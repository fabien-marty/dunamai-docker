FROM python:3.12-alpine

RUN apk update && apk upgrade && apk add make git && rm -rf /var/cache/apk/*
RUN mkdir -p /app
COPY .hashes /app/.hashes
COPY Makefile README.md pyproject.toml uv.lock entrypoint.sh /app/
RUN cd /app && make install
WORKDIR /code

ENTRYPOINT ["/app/entrypoint.sh"]