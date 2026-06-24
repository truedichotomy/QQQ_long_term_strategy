/* Verification harness: run strategy.js over the real data/ files in Node and print
 * the signal, so it can be diffed against `julia analysis/signal.jl`. Not used by the
 * web app. Usage:  node web/verify_node.js  */
const fs = require('fs'), path = require('path');
const S = require('./strategy.js');
const dir = path.join(__dirname, '..', 'data');
const files = fs.readdirSync(dir)
  .filter(f => f.startsWith('QQQ ') || f.startsWith('QQQ('))
  .map(f => ({ name: f, text: fs.readFileSync(path.join(dir, f), 'utf8') }));
const rows = S.mergeFiles(files);
const g = S.computeSignal(rows);
const r = (x, d = 0) => (x == null || isNaN(x)) ? 'NaN' : Number(x).toFixed(d);
console.log(`merged ${g.rows} rows, ${g.firstDate} … ${g.asOf}`);
console.log(`close ${r(g.close,2)}  SMA-50 ${r(g.sma50)} ${g.sma50>g.sma200?'>':'<'} SMA-200 ${r(g.sma200)}  CCI(40) ${r(g.cci40)}`);
console.log(`Trend    (SMA fast-reentry):      ${g.trendIn?'IN ':'OUT'}  since ${g.trendSince}`);
console.log(`Momentum (CCI40 -100/0 + TMA):    ${g.momIn?'IN ':'OUT'}  since ${g.momSince}  (CCI ${r(g.cci40)} vs exit ${g.momExit}, TMA-200 ${g.tmaDown?'DOWN':'UP'})`);
console.log(`EITHER-ON: ${g.eitherLong?'BUY / HOLD (100% QQQ)':'SELL / WAIT (cash)'}  since ${g.eitherSince}`);
console.log(`AVG (½):   ${Math.round(g.avgExposure*100)}% QQQ`);
