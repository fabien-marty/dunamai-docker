# API -------------------------------------------------------------------------
# Information on using this utility.
# -----------------------------------------------------------------------------
#
# There are two main API functions exposed by this file:
# `hash_deps` and `unhash_deps`
# These are used in make rules to convert dependencies to dependencies on the
# hashes (contents) of those files, and then to convert references to the
# dependency hashes back to the original dependency files.
#
# combined.txt: $(call hash_deps,a.txt b.txt)
#    echo "Concatenating files"
#    cat $(call unhash_deps,$^) > $@
#
# It's also safe to only hash some dependencies (e.g. if you know that some
# will always have correct timestamps relative to the target) but still apply
# `unhash_deps` to all dependencies - e.g.:
#
# combined.txt: $(call hash_deps,a.txt) b.txt
#    echo "Concatenating files"
#    cat $(call unhash_deps,$^) > $@
#
# Note that these should not be used on PHONY dependencies, as it makes no
# sense - they are not files that can be hashed, and always cause a target that
# depends on them to be remade.
#
# There is configuration below to let you alter the behaviour of the utility,
# but the defaults are chosen so that the utility should work fine as is.
#
# To remove any hash files previously created by the utility, make the
# `hashdeps_clean` target.
#
# A common use case for makefile is compiling C or C++ code, and using GCC's
# automatic pre-requisite generation to e.g. rebuild when a header file
# changes - see:
# https://www.gnu.org/software/make/manual/html_node/Automatic-Prerequisites.html
# In order to support this, the api function `hash_deps_in_autogen_dep_file` is
# provided to convert an autogenerated dependency file to reference hashed
# dependencies. This should be called at the end of the recipe to generate the
# dependency file as it will modify its contents in place.
# Here's an example integrated into a dependency autogeneration rule for C
# object compilation:
#
# %.d: $(call hash_deps,%.c)
#    @echo Dependencies: $@ for $(call unhash_deps,$^)
#    @$(CC) -fPIC -MM -MP -MT $(@:%.d=%.o) $(call unhash_deps,$^) -MF $@
#    @$(call hash_deps_in_autogen_dep_file,$@)
#
# Note that this just blindly wraps all dependencies in the file with
# `hash_deps` - i.e. even any system headers that may be referenced there.
# For this reason, it's _strongly_ recommended you only use this when setting a
# `HASHDEPS_HASH_TREE_DIR` so all hashes go into a specified directory, and
# hashdeps doesn't end up trying to create files in system directories.
#
# You may want to write a function to do this more cleverly yourself (e.g.
# only hash files in a project directory, or exclude certain files).

# CONFIGURATION ---------------------------------------------------------------
# Users can override any of the following defaults e.g. by setting these
# variables _before_ including this file or passing values at the command line.
# -----------------------------------------------------------------------------

# The suffix used for files that contain the hashes of dependencies.
# Can be changed if desired, but _must_ be unique to files created by this
# utility. It _cannot_ be blank, and should include any starting `.`.
HASHDEPS_HASH_SUFFIX ?= .dephash

# Specify a directory to store hashes in rather than putting them alongside
# dependency files, which might otherwise undesirably pollute the source tree.
# Leave blank to just out hash files alongside dependency files.
# E.g. the following setting would store the hash for `source/file.txt` as
# `hashtree/source/file.txt.dephash`:
# HASHDEPS_HASH_TREE_DIR := hashtree
# This should be a relative path, and the directory will be created if it does
# not exist.
HASHDEPS_HASH_TREE_DIR ?= .hashes

# Set this variable to some non-whitespace value to disable any echoing by
# recipes in this utility.
# By default a message is echoed every time a hash file is checked and found to
# by up to date, or is regenerated.
HASHDEPS_QUIET ?= 1

# Set this to a non-whitespace value to disable all dependency hashing logic
# from this utility.
# Be careful about disabling this for a new build while hash files are present
# because then the hash files will be out of sync with the built targets.
# If you have previously built with hashdeps enabled, and are now going to
# build with it disabled, you _should_ make the `hashdeps_clean` target to
# remove any lingering hash files and prevent bad behaviour later if hashdeps
# is re-enabled.
HASHDEPS_DISABLE ?=

# The default use case for this utility is when there are dependencies that
# end up with modification times newer than the targets that depend on them,
# and the user wants to prevent wasted rebuilding when it's not needed.
# You should use this if you can guarantee that:
# - hash files always have modification time older than the targets that
#   depend on them (i.e. hash files are always stored with target files).
# - dependencies will only ever end up with newer timestamps - never will a
#   dependency file be modified and then set to have a modification time of
#   earlier than that of the hash file previously generated.
#
# Set this to a non-empty value to force the hash to always be generated and
# checked for a dependency. This is useful if you can make no guarantees about
# timestamps of files - e.g. perhaps a target can end up with a timestamp
# newer than a dependency while actually the target still needs regenerating.
# The default case has the added benefit that it's faster since make will check
# the modification time of the hash file to decide if it should re-make the
# target, rather than forcefully always re-making (and so re-calculating the
# hashes to check) the hash files.
#
# In either case, it's assumed that the hash file is stored with the target
# and it is always correct that the target was made with the dependency
# contents matching the hash. This must be true because the hash is created as
# part of creating the target.
# The target somehow changing, but the hash and dependency content still
# matching is not considered at all as a case to handle.
HASHDEPS_FORCE_HASH ?= 1

# The default value here should always be fine, but is configurable in case.
# When forcing hash file generation, this is the modification time that is set
# on the hash file if the hash has not changed, to prevent the target from
# being re-made in case the hash file is now newer.
# We can't access the modification times of all targets that are being made
# that depend on the hashed dependency, so we have to guess at a time in the
# past that will be older than the target's modification time.
# This is passed to `touch -d` so can be a datestamp or something relative like
# 'HASHDEPS_HASH_FILE_TIMESTAMP := "5 years ago"'
# (note that this is passed to the shell as-is so quotes are important).
# This does nothing if `HASHDEPS_FORCE_HASH` is not set, and cannot be blank if
# `HASHDEPS_FORCE_HASH` is not set
HASHDEPS_HASH_FILE_TIMESTAMP ?= "5 years ago"

# This is the program used to create a hash of a file.
# It must:
# - accept a filename to provide the hash of as a positional argument
# - output the hash to stdout with no preceeding text - either as the only
#   output or optionally followed by a space and then anything else.
# Example other programs that can be used are `sha1sum` and `sha256sum`.
# `md5sum` is the default because it's widely available, should be the fastest,
# provides a small hash to check, and there's no concern here about someone
# crafting collisions since nothing here is meant to  be cryptographically
# secure in any way.
HASHDEPS_HASH_CMD ?= md5sum

# INTERNALS -------------------------------------------------------------------
# Users _must not_ change anything below this line!
# -----------------------------------------------------------------------------

# Do any sanity checks on variables up front.
ifeq ($(strip $(HASHDEPS_HASH_SUFFIX)),)
$(error The suffix for dependency hash files (HASHDEPS_HASH_SUFFIX) cannot\
		be blank)
endif

ifneq ($(strip $(HASHDEPS_FORCE_HASH)),)
ifeq ($(strip $(HASHDEPS_HASH_FILE_TIMESTAMP)),)
$(error The timestamp to set on hash files when the hash is unchanged\
		(HASHDEPS_HASH_FILE_TIMESTAMP) cannot be blank when configured to\
		force hash file generation (HASHDEPS_FORCE_HASH))
endif
endif

# Either actually echo or just use true, which 'does nothing, successfully'.
ifeq ($(strip $(HASHDEPS_QUIET)),)
HASHDEPS_ECHO := echo
else
HASHDEPS_ECHO := true
endif

# Only if the value is non-empty, make sure it ends in a forward slash so
# another directory or filename can be appended correctly.
HASHDEPS_HASH_TREE_SANITISED := \
	$(addsuffix /,$(strip $(HASHDEPS_HASH_TREE_DIR)))

# If we are changing the modification times of hash files, need to always run
# the rules for them since that's where the times are set. Do that by making
# them depend on the special `FORCE` target to force them to be run.
HASHDEPS_MAYBE_FORCE_DEP := $(if $(HASHDEPS_FORCE_HASH),HASHDEPS_FORCE_TARGET,)

# Function to convert a normal dependency to a hashed dependency.
# Takes one argument - a space separated list of dependencies to convert.
define hash_deps
    $(if $(HASHDEPS_DISABLE),\
		$(1),\
		$(patsubst %,\
			$(HASHDEPS_HASH_TREE_SANITISED)%$(HASHDEPS_HASH_SUFFIX),\
			$(1)))
endef

# Function that undoes the transformations above, so lets you access the
# true dependency files in recipes.
# Takes one argument - a space separated list of dependencies to convert.
define unhash_deps
    $(if $(HASHDEPS_DISABLE),\
		$(1),\
		$(patsubst $(HASHDEPS_HASH_TREE_SANITISED)%$(HASHDEPS_HASH_SUFFIX),\
			%,\
			$(1)))
endef

# Make will delete files created by pattern rules by default - prevent this.
.PRECIOUS: %$(HASHDEPS_HASH_SUFFIX)

# Check if the file hash in the file is still accurate. If not, write an
# updated hash.
# The dependency used as the input file is guaranteed to exist by make.
$(HASHDEPS_HASH_TREE_SANITISED)%$(HASHDEPS_HASH_SUFFIX): % $(HASHDEPS_MAYBE_FORCE_DEP)
	@mkdir -p $(dir $@)
	@curr_hash=$$($(HASHDEPS_HASH_CMD) "$<" | cut -f 1 -d " ") && \
		{ [ -f "$@" ] && \
			[ "$$(cat "$@" | tr -d '[:space:]')" = "$${curr_hash}" ] && \
			$(if $(HASHDEPS_FORCE_HASH),\
				touch -d $(HASHDEPS_HASH_FILE_TIMESTAMP) "$@" &&,) \
			$(HASHDEPS_ECHO) "Hash file still up to date: $@" ;} || \
		{ $(HASHDEPS_ECHO) "Updating hash file: $@" && \
			echo -n "$${curr_hash}" > "$@" ; }

# A 'clean' target that removes any generated hash files.
# Delete any files with the unique hash file suffix, either anywhere in the
# current directory or in the HASH_TREE_DIR if set.
# Purposely echo the clean command so users can see what is being deleted.
HASHDEPS_CLEAN_DIR := \
	$(if $(HASHDEPS_HASH_TREE_SANITISED),$(HASHDEPS_HASH_TREE_SANITISED),.)
HASHDEPS_CLEAN_CMD := \
	find $(HASHDEPS_CLEAN_DIR) -name "*$(HASHDEPS_HASH_SUFFIX)" -delete
.PHONY: hashdeps_clean
hashdeps_clean:
	@$(HASHDEPS_ECHO) "Removing all dependency file hashes"
	$(HASHDEPS_CLEAN_CMD)

# An empty phony target that can be set as a dependency to force rebuilding.
.PHONY: HASHDEPS_FORCE_TARGET
HASHDEPS_FORCE_TARGET:

# Function to convert an auto-generated dependency file to one that references
# the hashes of the dependencies in the file.
# Takes one argument - the autogenerated dependency file.
# This is a bit of sed magic - adapted from an example rule to concatenate
# lines that end with a `\` - number 39 here:
# http://www.catonmat.net/blog/sed-one-liners-explained-part-one/
# It appends lines to the search string while they end in `\`, then for that
# whole multiline search string it wraps everything (non-empty) after the `:`
# (so all the dependencies of a target) with a call to `hash_deps`.
# This is perhaps a bit too far reaching for some use cases (e.g. if there
# are system files in the dependencies this will depend on hashes of them)
# so should probably only be used when hashes are stored in a separate tree
# with `HASHDEPS_HASH_TREE_DIR`.
define hash_deps_in_autogen_dep_file
    $(if $(HASHDEPS_DISABLE),\
		,\
		sed -i -e \
			':a; /\\$$/N; s/\\$$/\\/; ta; s/:\(.\+\)/: $$(call hash_deps,\1)/'\
			$(1))
endef
