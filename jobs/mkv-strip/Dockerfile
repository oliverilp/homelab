FROM python:3.14-slim-trixie@sha256:a7fb1e634c4a578f9e0bd6327f11a3cde11b7a9395f48e24360c0988bcc5c2bc AS base

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
