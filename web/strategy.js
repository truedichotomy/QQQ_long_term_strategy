/* strategy.js — dependency-free reimplementation of the QQQ "either-on" blend signal,
 * a faithful port of analysis/src/{indicators,strategies}.jl. No DOM; runs in the
 * browser (window.QQQStrategy) and in Node (module.exports) so it can be unit-checked
 * against the Julia output. Only the 6 trusted columns (Date, OHLC, Volume) are read;
 * every indicator is computed here from price. */
(function (root) {
  'use strict';

  // ---------- CSV parsing (mirrors src/data.jl: quoted fields, ISO dates, comma volume) ----------
  function parseFields(line) {
    if (line.indexOf('"') !== -1) {            // quoted: extract every "..." field
      var out = [], re = /"([^"]*)"/g, m;
      while ((m = re.exec(line)) !== null) out.push(m[1]);
      return out;
    }
    return line.split(',');                     // fallback: plain CSV
  }

  function parseCSV(text) {
    var lines = String(text).split(/\r?\n/), rows = [];
    for (var i = 0; i < lines.length; i++) {
      var f = parseFields(lines[i]);
      if (f.length < 6) continue;
      var d = (f[0] || '').slice(0, 10);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) continue;        // skips header / blank / junk
      var c = parseFloat(f[4]);
      if (!isFinite(c)) continue;
      var v = parseFloat(String(f[5]).replace(/,/g, ''));  // strip thousands separators
      rows.push({ date: d, o: parseFloat(f[1]), h: parseFloat(f[2]),
                  l: parseFloat(f[3]), c: c, v: isFinite(v) ? v : 0 });
    }
    return rows;
  }

  // The filename's leading number is the pull's end-timestamp (mirrors _file_endts);
  // larger = more recent, used to break ties on overlapping dates. Fallback: max date.
  function fileEndTs(name, rows) {
    var m = /\((\d+)/.exec(name || '');
    if (m) return m[1];
    var mx = '';
    for (var i = 0; i < rows.length; i++) if (rows[i].date > mx) mx = rows[i].date;
    return mx.replace(/-/g, '') + '000000000';
  }

  // Merge one or more files by date (mirrors load_ticker/merge_markets): overlap of any
  // size is deduped; the row from the most recent pull (largest end-timestamp) wins.
  function mergeFiles(files) {  // files: [{name, text}]
    var parsed = files.map(function (f) {
      var rows = parseCSV(f.text);
      return { endts: fileEndTs(f.name, rows), rows: rows };
    }).filter(function (p) { return p.rows.length > 0; });
    parsed.sort(function (a, b) { return a.endts < b.endts ? -1 : a.endts > b.endts ? 1 : 0; });
    var byDate = {};
    parsed.forEach(function (p) { p.rows.forEach(function (r) { byDate[r.date] = r; }); });
    return Object.keys(byDate).sort().map(function (d) { return byDate[d]; });
  }

  // Merge several already-parsed row lists by date; later lists win on duplicate dates
  // (used to layer uploaded data on top of the bundled default). Dedupes, sorts by date.
  function mergeRows(arrays) {
    var byDate = {};
    arrays.forEach(function (rows) { (rows || []).forEach(function (r) { byDate[r.date] = r; }); });
    return Object.keys(byDate).sort().map(function (d) { return byDate[d]; });
  }

  // Serialize rows back to a compact CSV (for localStorage persistence).
  function rowsToCSV(rows) {
    return rows.map(function (r) {
      return r.date + ',' + r.o + ',' + r.h + ',' + r.l + ',' + r.c + ',' + r.v;
    }).join('\n');
  }

  // ---------- indicators (match src/indicators.jl exactly) ----------
  function sma(x, n) {
    var m = x.length, out = new Array(m).fill(NaN), acc = 0;
    if (n <= 0) return out;
    for (var i = 0; i < m; i++) {
      acc += x[i];
      if (i >= n) acc -= x[i - n];
      if (i >= n - 1) out[i] = acc / n;
    }
    return out;
  }

  function tma(x, n) {                          // SMA-of-SMA, NaN-warmup-safe (the Julia fix)
    if (n <= 1) return sma(x, Math.max(n, 1));
    var w1 = Math.floor(n / 2), w2 = n - w1 + 1;
    var inner = sma(x, w1), m = x.length, out = new Array(m).fill(NaN), f = -1;
    for (var i = 0; i < m; i++) { if (!isNaN(inner[i])) { f = i; break; } }
    if (f < 0) return out;
    var sub = sma(inner.slice(f), w2);
    for (var j = 0; j < sub.length; j++) out[f + j] = sub[j];
    return out;
  }

  function cci(high, low, close, n) {          // CCI on typical price (uses H/L/C)
    var m = close.length, out = new Array(m).fill(NaN);
    if (n <= 0) return out;
    var tp = new Array(m);
    for (var i = 0; i < m; i++) tp[i] = (high[i] + low[i] + close[i]) / 3;
    var s = sma(tp, n);
    for (var k = n - 1; k < m; k++) {
      var md = 0;
      for (var j = k - n + 1; j <= k; j++) md += Math.abs(tp[j] - s[k]);
      md /= n;
      out[k] = md === 0 ? 0 : (tp[k] - s[k]) / (0.015 * md);
    }
    return out;
  }

  // ---------- component filters (match src/strategies.jl) ----------
  function fastReentry(d, fast, slow, re, hold) {        // the trend filter
    fast = fast || 50; slow = slow || 200; re = re || 50; hold = (hold == null ? 10 : hold);
    var sf = sma(d.close, fast), ss = sma(d.close, slow), sr = sma(d.close, re);
    var m = d.close.length, out = new Array(m).fill(0), invested = false, last = -1e9;
    for (var i = 0; i < m; i++) {
      var can = (i - last) >= hold;
      if (invested) {
        if (can && !isNaN(sf[i]) && !isNaN(ss[i]) && sf[i] < ss[i]) { invested = false; last = i; }
      } else {
        var golden = !isNaN(sf[i]) && !isNaN(ss[i]) && sf[i] > ss[i];
        var recover = !isNaN(sr[i]) && d.close[i] > sr[i];
        if (can && (golden || recover)) { invested = true; last = i; }
      }
      out[i] = invested ? 1 : 0;
    }
    return out;
  }

  function cciBandTmaSwitch(d, o) {                       // the momentum filter
    o = o || {};
    var exitLo = o.exitLo == null ? -100 : o.exitLo, entryHi = o.entryHi == null ? 0 : o.entryHi,
        bearExit = o.bearExit == null ? 0 : o.bearExit, tmaN = o.tmaN || 200,
        lb = o.lb || 20, confirm = o.confirm == null ? 1 : o.confirm;
    var c = cci(d.high, d.low, d.close, 40), t = tma(d.close, tmaN);
    var m = d.close.length, out = new Array(m).fill(0), invested = true, run = 0;
    for (var i = 0; i < m; i++) {
      var bear = (i >= lb) && !isNaN(t[i]) && !isNaN(t[i - lb]) && (t[i] < t[i - lb]);
      var xlo = bear ? bearExit : exitLo;
      var cond = invested ? (!isNaN(c[i]) && c[i] < xlo) : (!isNaN(c[i]) && c[i] > entryHi);
      run = cond ? run + 1 : 0;
      if (run >= confirm) { invested = !invested; run = 0; }
      out[i] = invested ? 1 : 0;
    }
    return out;
  }

  function blendComponents(d) {
    return {
      momentum: cciBandTmaSwitch(d, { exitLo: -100, entryHi: 0, bearExit: 0, tmaN: 200, lb: 20, confirm: 1 }),
      trend: fastReentry(d, 50, 200, 50, 10)
    };
  }

  function lastChange(s) { var lc = 0; for (var i = 1; i < s.length; i++) if (s[i] !== s[i - 1]) lc = i; return lc; }

  // ---------- top level ----------
  function computeSignal(rows) {
    var n = rows.length;
    if (n < 201) throw new Error('Need at least ~201 daily bars for the 200-day averages; got ' + n + '.');
    var d = {
      date: rows.map(function (r) { return r.date; }), close: rows.map(function (r) { return r.c; }),
      high: rows.map(function (r) { return r.h; }), low: rows.map(function (r) { return r.l; }),
      open: rows.map(function (r) { return r.o; }), volume: rows.map(function (r) { return r.v; })
    };
    var s50 = sma(d.close, 50), s200 = sma(d.close, 200);
    var c40 = cci(d.high, d.low, d.close, 40), t200 = tma(d.close, 200);
    var comp = blendComponents(d), mom = comp.momentum, tr = comp.trend;
    var either = mom.map(function (v, i) { return Math.max(v, tr[i]); });
    var avg = mom.map(function (v, i) { return (v + tr[i]) / 2; });
    var i = n - 1, lb = 20;
    var bear = (i >= lb) && !isNaN(t200[i]) && !isNaN(t200[i - lb]) && (t200[i] < t200[i - lb]);
    return {
      rows: n, firstDate: d.date[0], asOf: d.date[i], close: d.close[i],
      sma50: s50[i], sma200: s200[i], cci40: c40[i], tmaDown: bear, momExit: bear ? 0 : -100,
      trendIn: tr[i] === 1, trendSince: d.date[lastChange(tr)],
      momIn: mom[i] === 1, momSince: d.date[lastChange(mom)],
      eitherLong: either[i] === 1, eitherSince: d.date[lastChange(either)],
      avgExposure: avg[i],
      recent: rows.slice(Math.max(0, n - 8))
    };
  }

  var API = {
    parseCSV: parseCSV, mergeFiles: mergeFiles, mergeRows: mergeRows, rowsToCSV: rowsToCSV,
    computeSignal: computeSignal, sma: sma, tma: tma, cci: cci, fastReentry: fastReentry,
    cciBandTmaSwitch: cciBandTmaSwitch, blendComponents: blendComponents
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  root.QQQStrategy = API;
})(typeof globalThis !== 'undefined' ? globalThis : this);
