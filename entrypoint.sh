#!/bin/sh

cd /app || exit 1
git config --global --add safe.directory '*'
exec ./.tmp/bin/uv run dunamai "$@"