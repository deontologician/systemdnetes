# static/

Static assets served by the web server.

- `index.html` -- D3.js cluster dashboard that polls `/api/v1/cluster` every 3 seconds and renders node cards with CPU/memory utilization bars and pod tiles. Served at `GET /` via the `FileServer` effect.
