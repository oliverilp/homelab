FROM python:3.13-slim-trixie

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

USER 1000:1000

ENTRYPOINT ["python3", "-m", "mkv_strip"]
CMD ["--config", "/etc/mkv-strip/config.json"]
