# Handoff — publishing sbm.dazrave.uk

The app is **built, deployed and running** on the game-server box. All that's
left is putting Cloudflare in front of it. That part is for whoever owns the
`dazrave.uk` zone (Anton).

## What's already done

- App runs on **CT212** as a systemd service `sbm-web`, listening on
  **`0.0.0.0:8099`**.
- Reachable on the LAN at **`http://192.168.0.212:8099`** (verified).
- Serves the cover page and accepts idea submissions to
  `/opt/sbm-web/submissions/incoming.jsonl`.

## What Anton needs to do

`sbm.dazrave.uk` already resolves to Cloudflare, so the DNS record exists — it
just has no working origin yet. Two ways to give it one; the tunnel is strongly
preferred for a home server.

### Preferred: Cloudflare Tunnel (no port-forward, hides the home IP)

1. Install `cloudflared` on CT212 (Debian 12):
   `pct exec 212 -- bash` then the standard cloudflared apt install.
2. `cloudflared tunnel login` → pick the `dazrave.uk` zone.
3. `cloudflared tunnel create sbm`
4. Route the hostname and point ingress at the app:
   ```yaml
   # /etc/cloudflared/config.yml
   tunnel: <tunnel-id>
   credentials-file: /root/.cloudflared/<tunnel-id>.json
   ingress:
     - hostname: sbm.dazrave.uk
       service: http://localhost:8099
     - service: http_status:404
   ```
5. `cloudflared tunnel route dns sbm sbm.dazrave.uk`
6. `systemctl enable --now cloudflared`

That's it — `https://sbm.dazrave.uk` serves the page, TLS handled by Cloudflare,
home IP never exposed.

### Alternative: proxy to the home IP

Point the (orange-clouded) `sbm` record at `67.208.53.120`, forward `443` on the
router to `192.168.0.212`, and terminate TLS on CT212 (an origin cert or a
Let's Encrypt cert via a small nginx/caddy in front of `:8099`). Exposes the
origin IP to anyone who unproxies it; the tunnel avoids that.

## Notes for whoever runs it

- The app only serves a static page and appends a line to a file — no database,
  no auth, no secrets. Safe to expose.
- Rate-limited to 6 submissions per IP per hour, with a honeypot for bots. It
  reads `CF-Connecting-IP`, so rate limits work correctly behind the tunnel.
- Redeploy after code changes: `web/deploy.sh` from the repo.
- Submissions are pulled for triage with `web/pull-ideas.sh`; see
  [`TRIAGE.md`](TRIAGE.md) for the enrich → gate → issue flow.
