# Website

The Stokeback Mountain landing page. One self-contained `index.html` — all CSS,
JavaScript and the hand-drawn SVG art (the mountain, the two lads, the pixel
heart) live inline, no build step and no dependencies.

## Hosting

Served by **GitHub Pages** from this `docs/` folder via
[`.github/workflows/pages.yml`](../.github/workflows/pages.yml).

One-time setup: **Settings → Pages → Source: "GitHub Actions"**. After that,
every push to `main` that touches `docs/` redeploys automatically. You can also
run the workflow by hand from the Actions tab.

To preview locally, just open `index.html` in a browser, or:

```bash
python3 -m http.server -d docs 8000   # then visit http://localhost:8000
```

## The pitch form

`index.html` has one moving part: the "pitch an idea" form. It runs in one of
two modes, chosen by a single flag near the bottom of the inline script:

```js
var API_ENDPOINT = null;   // static hosting → open a prefilled GitHub issue
```

- **`null` (default, for GitHub Pages).** A pitch opens a **prefilled GitHub
  issue** in a new tab — the same issue queue the AI builds from. The dropdown
  maps onto the repo's real labels (`enhance` + `mode:*`, or `new-mode`); public
  pitches are deliberately **not** given the `auto` label, so nothing gets built
  unattended straight off the website — a human triages first.

- **A POST route (e.g. `'/api/idea'`).** On a dynamic host (Vercel, Netlify,
  a small server) set `API_ENDPOINT` to your endpoint and the form switches to a
  silent AJAX submit — no redirect. The expected request/response:

  ```
  POST <API_ENDPOINT>
  { "idea": "...", "name": "...", "mode": "infected", "website": "" }
  → 200  { "ok": true }
  → 4xx  { "ok": false, "error": "message shown to the user" }
  ```

  `website` is a honeypot — a real person never fills it, so treat any request
  with it set as spam and drop it.
