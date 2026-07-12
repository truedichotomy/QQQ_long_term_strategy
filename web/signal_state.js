/* Detect a change in the either-on trade action. Recomputes the signal from the
 * data/ files (same loading as verify_node.js), compares against the last recorded
 * action in .github/signal-state.json, rewrites that state file, and emits GitHub
 * Actions outputs (flipped / action / either / prev / asof / close / avg).
 * Run by .github/workflows/update-signal.yml after the nightly data refresh; the
 * state file is committed alongside the data so re-runs never notify twice.
 * Usage:  node web/signal_state.js  */
const fs = require('fs'), path = require('path');
const S = require('./strategy.js');
const dir = path.join(__dirname, '..', 'data');
const files = fs.readdirSync(dir)
  .filter(f => f.startsWith('QQQ ') || f.startsWith('QQQ('))
  .map(f => ({ name: f, text: fs.readFileSync(path.join(dir, f), 'utf8') }));
const g = S.computeSignal(S.mergeFiles(files));
const state = {
  asOf: g.asOf,
  either: g.eitherLong ? 'BUY' : 'SELL',
  avg: Math.round(g.avgExposure * 100),
  close: Number(g.close.toFixed(2)),
};
const stateFile = path.join(__dirname, '..', '.github', 'signal-state.json');
let prev = null;
try { prev = JSON.parse(fs.readFileSync(stateFile, 'utf8')); } catch (e) {}
const flipped = !!prev && prev.either !== state.either;
fs.writeFileSync(stateFile, JSON.stringify(state, null, 2) + '\n');
const lines = [
  'flipped=' + flipped,
  'action=' + (state.either === 'BUY' ? 'BUY / HOLD — back into QQQ' : 'SELL / WAIT — move to cash'),
  'either=' + state.either,
  'prev=' + (prev ? prev.either : 'none'),
  'asof=' + state.asOf,
  'close=' + state.close,
  'avg=' + state.avg,
];
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, lines.join('\n') + '\n');
console.log((flipped ? 'FLIP ' + prev.either + ' → ' : 'no change: ') + state.either +
            ' as of ' + state.asOf + ' (close ' + state.close + ', avg ' + state.avg + '%)');
