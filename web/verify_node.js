/* Verification harness: run strategy.js over the real data/ files in Node and print
 * the signal, so it can be diffed against `julia analysis/signal.jl`. Not used by the
 * web app. Usage:  node web/verify_node.js
 * With --dump: print the full history instead (one CSV line per bar — merged OHLCV,
 * indicators, positions) in the exact format of `julia web/verify_parity.jl`, which
 * diffs the two implementations bar-for-bar. */
const fs = require('fs'), path = require('path');
const S = require('./strategy.js');
const dir = path.join(__dirname, '..', 'data');
const files = fs.readdirSync(dir)
  .filter(f => f.startsWith('QQQ ') || f.startsWith('QQQ('))
  .map(f => ({ name: f, text: fs.readFileSync(path.join(dir, f), 'utf8') }));
const rows = S.mergeFiles(files);
if (process.argv.includes('--dump')) {
  // NB: end naturally (no process.exit) — exiting right after a large write to a
  // piped stdout truncates the output at the pipe buffer before it flushes.
  const a = S.analyze(rows);
  const f4 = x => isNaN(x) ? 'NaN' : x.toFixed(4);
  const f6 = x => isNaN(x) ? 'NaN' : x.toFixed(6);
  const out = [];
  for (let i = 0; i < rows.length; i++) {
    out.push([a.date[i], f4(rows[i].o), f4(rows[i].h), f4(rows[i].l), f4(rows[i].c),
              rows[i].v.toFixed(0), f6(a.s50[i]), f6(a.s200[i]), f6(a.c40[i]), f6(a.t200[i]),
              String(a.mom[i]), String(a.tr[i]), String(a.either[i]), String(a.avg[i])].join(','));
  }
  process.stdout.write(out.join('\n') + '\n');
} else {
  const g = S.computeSignal(rows);
  const r = (x, d = 0) => (x == null || isNaN(x)) ? 'NaN' : Number(x).toFixed(d);
  console.log(`merged ${g.rows} rows, ${g.firstDate} … ${g.asOf}`);
  console.log(`close ${r(g.close,2)}  SMA-50 ${r(g.sma50)} ${g.sma50>g.sma200?'>':'<'} SMA-200 ${r(g.sma200)}  CCI(40) ${r(g.cci40)}`);
  console.log(`Trend    (SMA fast-reentry):      ${g.trendIn?'IN ':'OUT'}  since ${g.trendSince}`);
  console.log(`Momentum (CCI40 -100/0 + TMA):    ${g.momIn?'IN ':'OUT'}  since ${g.momSince}  (CCI ${r(g.cci40)} vs exit ${g.momExit}, TMA-200 ${g.tmaDown?'DOWN':'UP'})`);
  console.log(`EITHER-ON: ${g.eitherLong?'BUY / HOLD (100% QQQ)':'SELL / WAIT (cash)'}  since ${g.eitherSince}`);
  console.log(`AVG (½):   ${Math.round(g.avgExposure*100)}% QQQ`);
}
