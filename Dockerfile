FROM python:3.12-alpine

ENV TASK=go-task

RUN apk update && apk upgrade && apk add go-task git && rm -rf /var/cache/apk/*
RUN mkdir -p /app
COPY .task /app/.task
COPY Taskfile.yml README.md pyproject.toml uv.lock entrypoint.sh /app/
RUN cd /app && $TASK install
WORKDIR /code

ENTRYPOINT ["/app/entrypoint.sh"]
