# dunamai-docker

[dunamai python CLI tool](https://github.com/mtkennerly/dunamai) packaged as a Docker image.

## What is it?

This is the [dunamai python CLI tool](https://github.com/mtkennerly/dunamai) packaged as a Docker image.

As well as being useful in certain contexts, it was also a perfect little project for playing with the new Python packages/projects manager: [uv](https://github.com/astral-sh/uv).

> [!WARNING]  
> VCS support is limited to `git`.

## Usage

The docker image full name is: `ghcr.io/fabien-marty/dunamai-docker`. Supported tags are:

- `latest`: for the latest version
- `1.22`: for the latest `1.22.x` version of `dunamai`

You have to mount your git clone in to `/code` in the container.

Example:

`docker run --pull always --rm -v $(pwd):/code ghcr.io/fabien-marty/dunamai-docker:1.22 from git --path /code`

## Dev

This repository is managed by a `Makefile`. Use `make help` to get available targets.