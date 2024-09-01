FROM python:3.12-alpine

RUN apk update && apk upgrade && apk add make && rm -rf /var/cache/apk/*
RUN mkdir -p /app
WORKDIR /app
COPY .hashes /app/.hashes
COPY Makefile README.md pyproject.toml uv.lock /app/
RUN make install

ENTRYPOINT ["/app/.tmp/bin/uv", "run", "dunamai"]