# web/ — the QQQ blend signal in the browser

A zero-dependency, zero-server reimplementation of `analysis/signal.jl` in plain
HTML/CSS/JS. **Drop your QQQ data file(s) onto the page and it prints today's
buy-hold / sell-wait call** for the adopted *either-on* blend — all computed in your
browser, nothing uploaded.

## Use it

1. Open **`web/index.html`** (double-click it — works straight from `file://`).
2. **Drop your QQQ CSV(s) onto the drop zone** (or click to choose). Use the file(s)
   from the project's `data/` folder — drop the long history file *and* any fresh
   overlapping pull; they're merged by date the same way `load_ticker` does it.
3. Read the signal card: the BUY/HOLD or SELL/WAIT call, the two filter states, and the
   ½-size `avg` exposure.

To refresh: get an updated data file (e.g. `julia analysis/fetch_data.jl` writes one into
`data/`, or export a new one), drop it in along with the history file, and the signal
updates. Needs ≥ ~1 year of daily bars (the 200-day averages have a 200-bar warm-up; the
full history gives the most accurate carried-forward state).

### Optional: auto-load when served
If you serve the folder over http (e.g. `python3 -m http.server --directory web`), the page
auto-loads a co-located **`qqq.csv`** on startup, so you can refresh by replacing that one
file. (`qqq.csv` is git-ignored; from `file://` the page just waits for a drop.)

## What's inside

- `index.html` — the page (inline CSS).
- `strategy.js` — the pure computation: CSV parse + date-merge, the indicators
  (SMA / TMA / CCI from OHLCV), the two component filters (`fastReentry`,
  `cciBandTmaSwitch`), and the blend. A faithful port of
  `analysis/src/{indicators,strategies}.jl`. No DOM — usable in Node too.
- `app.js` — UI glue (drag-drop, FileReader, rendering).
- `verify_node.js` — dev check: `node web/verify_node.js` runs `strategy.js` over the real
  `data/` files; its output matches `julia analysis/signal.jl` exactly (verified:
  same 6,864 bars, close, filter states, since-dates, and call).

Only the first 6 columns (Date, OHLC, Volume) are read; everything else in the file is
ignored, and every indicator is recomputed from price — identical to the Julia pipeline.
