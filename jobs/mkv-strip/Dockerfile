FROM python:3.14-slim-trixie@sha256:cea0e6040540fb2b965b6e7fb5ffa00871e632eef63719f0ea54bca189ce14a6 AS base

SHELL ["/bin/sh", "-euxc"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

ENV MKV_STRIP_CONFIG=/etc/mkv-strip/config.json \
    PYTHONPATH=/app/src \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY src /app/src

FROM base AS test

COPY tests /app/tests

USER 1000:1000

RUN python3 -m unittest discover -s tests

FROM base AS runtime

USER 1000:1000

ENTRYPOINT ["python3", "-m", "mkv_strip"]
CMD ["--config", "/etc/mkv-strip/config.json"]
