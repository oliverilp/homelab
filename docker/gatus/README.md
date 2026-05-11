# Gatus Docker Monitoring

Docker Compose bundle for running Gatus outside the homelab, exposed through Cloudflare Tunnel.

## Services

- `gatus`: status dashboard with SQLite persistence in `./data/data.db`
- `cloudflared`: remotely managed Cloudflare Tunnel connector
- `watchtower`: updates only the `gatus` and `cloudflared` containers

No alert providers are configured.

SQLite stores up to 263520 check results per endpoint, which is about 183 days at the configured 1-minute interval. Up to 1000 status events are retained per endpoint.

Gatus stores every health check result. Consecutive failure thresholds apply to alerting, not raw SQLite history, and no alert providers are configured here.

## Cloudflare Tunnel

Create a remotely managed tunnel in Cloudflare Zero Trust, then add a public hostname such as `status.oliverilp.ee`.

Use this service URL for the public hostname:

```text
http://gatus:8080
```

Because `cloudflared` runs in Docker, `localhost:8080` would point at the `cloudflared` container itself, not the Gatus container.

## Deploy

```bash
cp .env.example .env
```

Put the Cloudflare tunnel token in `.env`, then start it:

```bash
docker compose up -d
```

Gatus is also bound to `127.0.0.1:8080` on the Docker host for local debugging. Public access should go through Cloudflare Tunnel.

## Updates

Watchtower runs in label-only mode and only `gatus` plus `cloudflared` have the update label enabled. The default schedule checks weekly on Sunday at 04:00 in `TZ`.

Updates briefly restart the affected container. `cloudflared` updates can make the dashboard unavailable through Cloudflare for a moment, while Gatus updates pause checks during the short restart. SQLite history is persisted in `./data/data.db`.

## Monitored Endpoints

This config includes only routes attached to `traefik-public-gateway`:

- `https://auth.oliverilp.ee`
- `https://photos.oliverilp.ee`
- `https://linkwarden.oliverilp.ee`
- `https://memos.oliverilp.ee`
- `https://speedtest.oliverilp.ee`
- `https://crunchyroll.ee`
- `https://manga.crunchyroll.ee`

Routes on `traefik-internal-gateway` are intentionally excluded because that gateway targets `10.1.20.51`, which this external Docker host cannot reach without a VPN.
