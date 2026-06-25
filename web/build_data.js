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
fs.writeFileSync(p.join(__dirname, 'data.js'),
  '/* Bundled QQQ daily OHLCV (merged from data/) so the page shows a signal on open.\n' +
  '   Generated — refresh with: julia analysis/fetch_data.jl (or node web/build_data.js). Do not hand-edit. */\n' +
  'window.QQQ_DATA=' + JSON.stringify(csv) + ';\n');
console.log('wrote web/data.js: ' + rows.length + ' rows, ' + rows[0].date + ' … ' + rows[rows.length - 1].date);
