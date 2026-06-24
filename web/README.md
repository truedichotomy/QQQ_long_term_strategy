# web/ — the QQQ blend signal in the browser

A zero-dependency, zero-server reimplementation of `analysis/signal.jl` in plain
HTML/CSS/JS. **The QQQ history is bundled in, so it shows today's buy-hold / sell-wait
call the moment you open it** — and you can drop in newer data to keep it current.
Everything runs in your browser; nothing is uploaded.

## Use it

1. Open **`web/index.html`** (double-click — works straight from `file://`). It immediately
   shows the current signal computed from the bundled data, with the two filter states and the
   last-bars table. A **tab at the top switches the view between the two blends** — *Either-on*
   (all-in / all-out) and *Avg ½-size* (0 / 50 / 100% exposure). (Deep-link with
   `index.html?blend=avg`; the choice is remembered.)
2. **To update:** drop a newer QQQ CSV onto the "update" zone (or click to choose). New bars
   are **merged into a local database and deduplicated by date** (on an overlapping date the
   uploaded value wins). The merged database is **saved in your browser** (`localStorage`) and
   reused on the next visit, so each upload accumulates. *Reset to bundled data* clears it.

You can drop the file(s) from the project's `data/` folder, or a fresh export
(`julia analysis/fetch_data.jl` writes one into `data/`). Multiple files dropped at once are
merged together first (newest pull wins), then merged into the database.

## Keeping the bundle current (maintainer)

The bundled history lives in **`web/data.js`** (generated, not hand-edited). After updating
the project's `data/` folder, regenerate it:

```bash
node web/build_data.js     # rebuilds web/data.js from data/
```

End users never need this — they just drop a file in the page. It's only to refresh the
*default* bundled data shipped with the app.

## What's inside

- `index.html` — the page (inline CSS).
- `data.js` — the bundled QQQ history (`window.QQQ_DATA`, a compact CSV string). Generated.
- `strategy.js` — the pure computation: CSV parse, date-merge/dedupe (`mergeFiles`,
  `mergeRows`), the indicators (SMA / TMA / CCI from OHLCV), the two component filters
  (`fastReentry`, `cciBandTmaSwitch`), and the blend. A faithful port of
  `analysis/src/{indicators,strategies}.jl`. No DOM — runs in Node too.
- `app.js` — UI glue: render-on-load from the bundle, drag-drop upload, `localStorage`
  database (merge + dedupe + persist), status line, reset.
- `build_data.js` — regenerates `data.js` from `data/`.
- `verify_node.js` — dev check: `node web/verify_node.js` runs `strategy.js` over the real
  `data/` files; its output matches `julia analysis/signal.jl` exactly.

Only the first 6 columns (Date, OHLC, Volume) are read; everything else is ignored and every
indicator is recomputed from price — identical to the Julia pipeline. **Verified:** the JS
port and the bundle both reproduce the Julia signal exactly (same 6,864 bars, close, filter
states, since-dates, and call).
