/* app.js — UI for the QQQ blend signal. The page ships with the QQQ history bundled
 * (data.js), so it shows a signal the moment it opens. A tab chooses which blend to view —
 * either-on (all-in/all-out) or avg (½-size, 0/50/100%). Uploading a newer file APPENDS to a
 * local database (localStorage), merged and deduplicated by date. All client-side. */
(function () {
  'use strict';
  var S = window.QQQStrategy;
  var drop = document.getElementById('drop'),
      fileInput = document.getElementById('file'),
      out = document.getElementById('out'),
      statusEl = document.getElementById('status'),
      resetBtn = document.getElementById('reset'),
      tabsEl = document.getElementById('tabs'),
      blendDescEl = document.getElementById('blenddesc');

  var BUNDLE = S.parseCSV(window.QQQ_DATA || '');
  var LS_KEY = 'qqq_uploads_v1', BLEND_KEY = 'qqq_blend';
  var mem = null, lastG = null;
  var blend = (function () {
    try { var q = new URLSearchParams(location.search).get('blend'); if (q === 'avg' || q === 'either') return q; } catch (e) {}
    try { return localStorage.getItem(BLEND_KEY) || 'either'; } catch (e) { return 'either'; }
  })();
  if (blend !== 'avg' && blend !== 'either') blend = 'either';

  function lsGet() { try { return localStorage.getItem(LS_KEY); } catch (e) { return mem; } }
  function lsSet(v) { try { localStorage.setItem(LS_KEY, v); } catch (e) { mem = v; } }
  function lsClear() { try { localStorage.removeItem(LS_KEY); } catch (e) {} mem = null; }
  function loadUploads() { return S.parseCSV(lsGet() || ''); }
  function database() { return S.mergeRows([BUNDLE, loadUploads()]); }

  var esc = function (s) { return String(s).replace(/[&<>]/g, function (c) {
    return c === '&' ? '&amp;' : c === '<' ? '&lt;' : '&gt;'; }); };
  var r = function (x, d) { d = d || 0; return (x == null || isNaN(x)) ? '–' : Number(x).toFixed(d); };
  var ri = function (x) { return (x == null || isNaN(x)) ? '–' : Math.round(x); };
  var rv = function (x) { return (x == null || isNaN(x)) ? '–' : Math.round(x).toLocaleString(); };
  var chip = function (on) { return on ? '<span class="chip in">IN</span>' : '<span class="chip out">OUT</span>'; };

  function renderSignal(g) {
    var cls, action, sub, combine;
    if (blend === 'avg') {
      var pct = Math.round(g.avgExposure * 100);
      if (pct >= 100) { cls = 'buy'; action = '▲ HOLD'; sub = '— 100% in QQQ (both filters IN)'; }
      else if (pct <= 0) { cls = 'sell'; action = '▼ SELL / WAIT'; sub = '— 100% cash (both filters OUT)'; }
      else { cls = 'half'; action = '◐ HALF'; sub = '— 50% QQQ / 50% cash (one filter IN, one OUT)'; }
      combine = 'Avg ½-size: QQQ weight = (trend + momentum) ÷ 2 = <b>' + pct + '%</b> — at this exposure since ' +
        esc(g.avgSince) + '. (Either-on would be ' + (g.eitherLong ? '100% QQQ' : 'cash') + '.)';
    } else {
      cls = g.eitherLong ? 'buy' : 'sell';
      action = g.eitherLong ? '▲ BUY / HOLD' : '▼ SELL / WAIT';
      sub = g.eitherLong ? '— stay 100% in QQQ' : '— move to cash and wait';
      combine = g.eitherLong
        ? 'Either-on is <b>long</b> because ' + (g.trendIn && g.momIn ? 'both filters are IN' : 'at least one filter is IN') +
          ' — you sit out only when <b>both</b> turn OUT. In QQQ since ' + esc(g.eitherSince) +
          '. (Avg ½-size would be ' + Math.round(g.avgExposure * 100) + '%.)'
        : 'Either-on is <b>flat</b> because <b>both</b> filters are OUT — re-enter when either turns IN. In cash since ' +
          esc(g.eitherSince) + '.';
    }
    var trendDetail = 'SMA‑50 ' + ri(g.sma50) + (g.sma50 > g.sma200 ? ' &gt; ' : ' &lt; ') +
      'SMA‑200 ' + ri(g.sma200) + ' — ' + (g.sma50 > g.sma200 ? 'uptrend' : 'downtrend');
    var momDetail = 'CCI(40) ' + ri(g.cci40) + ' vs exit ' + g.momExit +
      ' · 200‑day triangular MA ' + (g.tmaDown ? 'falling' : 'rising');
    var rowsHtml = g.recent.map(function (x, i) {
      var today = i === g.recent.length - 1;
      return '<tr' + (today ? ' class="today"' : '') + '><td>' + esc(x.date) + '</td><td>' +
        r(x.o, 2) + '</td><td>' + r(x.h, 2) + '</td><td>' + r(x.l, 2) + '</td><td>' +
        r(x.c, 2) + '</td><td>' + rv(x.v) + '</td></tr>';
    }).join('');
    out.innerHTML =
      '<div class="signal ' + cls + '">' +
        '<div><span class="sigaction">' + action + '</span><span class="sigsub">' + sub + '</span></div>' +
        '<div class="sigasof">live signal as of <b>' + esc(g.asOf) + '</b> · QQQ close ' + r(g.close, 2) +
          ' · CCI(40) ' + ri(g.cci40) + '</div>' +
        '<div class="brk">' +
          '<div class="brow"><span class="bn">Trend filter — SMA 50/200 fast‑reentry</span>' + chip(g.trendIn) +
            '<span class="bd">' + trendDetail + ' · since ' + esc(g.trendSince) + '</span></div>' +
          '<div class="brow"><span class="bn">Momentum filter — CCI(40) TMA‑trigger</span>' + chip(g.momIn) +
            '<span class="bd">' + momDetail + ' · since ' + esc(g.momSince) + '</span></div>' +
          '<div class="bcombine">' + combine + '</div>' +
        '</div>' +
      '</div>' +
      '<div class="meta">Last bars:</div>' +
      '<table><thead><tr><th>Date</th><th>Open</th><th>High</th><th>Low</th><th>Close</th><th>Volume</th></tr></thead>' +
        '<tbody>' + rowsHtml + '</tbody></table>';
  }

  function applyBlend() {
    Array.prototype.forEach.call(tabsEl.children, function (b) {
      b.classList.toggle('active', b.getAttribute('data-blend') === blend); });
    blendDescEl.innerHTML = blend === 'avg'
      ? 'Average of the two filters (0 / 50 / 100% invested) — smoothest ride, cushions fast crashes too, ~12 trades/yr.'
      : 'Long if <b>either</b> filter is in — highest return, ~3 trades/yr, simple all‑in/all‑out.';
    if (lastG) renderSignal(lastG);
  }

  function setStatusBar(db, note) {
    var up = loadUploads().length;
    var src = up > 0 ? 'bundled + ' + up.toLocaleString() + ' uploaded' : 'bundled';
    var range = db.length ? db[0].date + ' … ' + db[db.length - 1].date : '—';
    statusEl.innerHTML = (note ? note + ' &nbsp; ' : '') +
      'Database: <b>' + db.length.toLocaleString() + '</b> bars (' + src + '), ' + range + '.';
    resetBtn.style.display = up > 0 ? '' : 'none';
  }

  function refresh(note) {
    var db = database();
    try { lastG = S.computeSignal(db); }
    catch (e) { lastG = null; out.innerHTML = '<div class="err">' + esc(e.message || String(e)) + '</div>'; setStatusBar(db, note); return; }
    applyBlend();
    setStatusBar(db, note);
  }

  function ingest(files) {
    var before = database(), beforeDates = {};
    before.forEach(function (x) { beforeDates[x.date] = 1; });
    var incoming = S.mergeFiles(files);
    if (!incoming.length) { refresh('<span class="new">No valid rows found in that file.</span>'); return; }
    var added = 0, updated = 0;
    incoming.forEach(function (x) { if (beforeDates[x.date]) updated++; else added++; });
    lsSet(S.rowsToCSV(S.mergeRows([loadUploads(), incoming])));
    refresh('<span class="new">Merged ' + incoming.length.toLocaleString() + ' rows → ' +
      added.toLocaleString() + ' new day(s), ' + updated.toLocaleString() + ' updated.</span>');
  }

  function readFiles(list) {
    var arr = Array.prototype.slice.call(list);
    if (!arr.length) return;
    var pending = arr.length, results = [];
    arr.forEach(function (f, idx) {
      var fr = new FileReader();
      fr.onload = function () { results[idx] = { name: f.name, text: fr.result }; if (--pending === 0) ingest(results.filter(Boolean)); };
      fr.onerror = function () { if (--pending === 0) ingest(results.filter(Boolean)); };
      fr.readAsText(f);
    });
  }

  // tabs
  Array.prototype.forEach.call(tabsEl.children, function (b) {
    b.addEventListener('click', function () {
      blend = b.getAttribute('data-blend');
      try { localStorage.setItem(BLEND_KEY, blend); } catch (e) {}
      applyBlend();
    });
  });
  // drag & drop / picker
  ['dragenter', 'dragover'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) { e.preventDefault(); e.stopPropagation(); drop.classList.add('over'); }); });
  ['dragleave', 'drop'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) { e.preventDefault(); e.stopPropagation(); drop.classList.remove('over'); }); });
  drop.addEventListener('drop', function (e) { readFiles(e.dataTransfer.files); });
  drop.addEventListener('click', function () { fileInput.click(); });
  fileInput.addEventListener('change', function () { readFiles(fileInput.files); fileInput.value = ''; });
  resetBtn.addEventListener('click', function () { lsClear(); refresh('<span class="new">Reset to bundled data.</span>'); });

  refresh();                                // show the signal immediately on open
})();
