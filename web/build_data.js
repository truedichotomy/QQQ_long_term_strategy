/* Regenerate web/data.js — the QQQ history bundled into the web app so it shows a signal
 * on open. Re-run after updating the project's data/ folder:   node web/build_data.js   */
const fs = require('fs'), p = require('path');
const S = require('./strategy.js');
const dir = p.join(__dirname, '..', 'data');
const files = fs.readdirSync(dir)
  .filter(function (f) { return f.indexOf('QQQ ') === 0 || f.indexOf('QQQ(') === 0; })
  .map(function (f) { return { name: f, text: fs.readFileSync(p.join(dir, f), 'utf8') }; });
const rows = S.mergeFiles(files);
// provisional (mid-session) dates carry a 7th "P" column in the archive — mark them in the bundle
const provisional = {};
files.forEach(function (file) {
  file.text.split(/\r?\n/).forEach(function (line) {
    var m = [], re = /"([^"]*)"/g, mm;
    while ((mm = re.exec(line)) !== null) m.push(mm[1]);
    if (m.length >= 7 && m[6] === 'P') provisional[m[0].slice(0, 10)] = 1;
  });
});
// 2-decimal OHLC + integer volume, so this is byte-identical to the Julia writer
// (analysis/src/fetch.jl write_web_bundle), which signal.jl/fetch_data.jl also use.
const f2 = function (x) { return Number(x).toFixed(2); };
const csv = rows.map(function (r) {
  var base = r.date + ',' + f2(r.o) + ',' + f2(r.h) + ',' + f2(r.l) + ',' + f2(r.c) + ',' + Math.round(r.v);
  return provisional[r.date] ? base + ',P' : base;
}).join('\n');
// The 3-month T-bill yield (cash earns it in the performance stats): raw `Date,Yield` lines from
// the last one on or before the first QQQ bar onward — the same slice the Julia writer emits.
const tpath = p.join(dir, 'rates', 'TBILL_3M.csv');
let tline = '';
if (fs.existsSync(tpath)) {
  const tb = fs.readFileSync(tpath, 'utf8').split(/\r?\n/).slice(1).filter(Boolean);
  let k = -1;
  tb.forEach(function (l, j) { if (l.slice(0, 10) <= rows[0].date) k = j; });
  tline = 'window.TBILL_DATA=' + JSON.stringify(tb.slice(Math.max(k, 0)).join('\n')) + ';\n';
}
fs.writeFileSync(p.join(__dirname, 'data.js'),
  '/* Bundled QQQ daily OHLCV (merged from data/) so the page shows a signal on open, plus the\n' +
  '   3-month T-bill yield (data/rates/TBILL_3M.csv, %) that cash earns in the performance stats.\n' +
  '   Generated — refresh with: julia analysis/fetch_data.jl (or node web/build_data.js). Do not hand-edit. */\n' +
  'window.QQQ_DATA=' + JSON.stringify(csv) + ';\n' + tline);
console.log('wrote web/data.js: ' + rows.length + ' rows, ' + rows[0].date + ' … ' + rows[rows.length - 1].date +
  (tline ? ' + T-bill yields' : ''));
