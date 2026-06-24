/* app.js — UI for the QQQ blend signal. The page ships with the QQQ history bundled
 * (data.js), so it shows a signal the moment it opens. Uploading a newer file APPENDS to a
 * local database (localStorage), merged and deduplicated by date; the merged db persists
 * across reloads. Everything is client-side — no server, nothing uploaded. */
(function () {
  'use strict';
  var S = window.QQQStrategy;
  var drop = document.getElementById('drop'),
      fileInput = document.getElementById('file'),
      out = document.getElementById('out'),
      statusEl = document.getElementById('status'),
      resetBtn = document.getElementById('reset');

  var BUNDLE = S.parseCSV(window.QQQ_DATA || '');     // shipped default
  var LS_KEY = 'qqq_uploads_v1';
  var mem = null;                                     // in-memory fallback if localStorage is blocked

  function lsGet() { try { return localStorage.getItem(LS_KEY); } catch (e) { return mem; } }
  function lsSet(v) { try { localStorage.setItem(LS_KEY, v); } catch (e) { mem = v; } }
  function lsClear() { try { localStorage.removeItem(LS_KEY); } catch (e) {} mem = null; }
  function loadUploads() { return S.parseCSV(lsGet() || ''); }
  function database() { return S.mergeRows([BUNDLE, loadUploads()]); }  // uploads win on overlap

  var esc = function (s) { return String(s).replace(/[&<>]/g, function (c) {
    return c === '&' ? '&amp;' : c === '<' ? '&lt;' : '&gt;'; }); };
  var r = function (x, d) { d = d || 0; return (x == null || isNaN(x)) ? '–' : Number(x).toFixed(d); };
  var ri = function (x) { return (x == null || isNaN(x)) ? '–' : Math.round(x); };
  var rv = function (x) { return (x == null || isNaN(x)) ? '–' : Math.round(x).toLocaleString(); };

  function renderSignal(g) {
    var cls = g.eitherLong ? 'buy' : 'sell';
    var action = g.eitherLong ? '▲ BUY / HOLD' : '▼ SELL / WAIT';
    var sub = g.eitherLong ? '— stay 100% in QQQ' : '— move to cash and wait';
    var avgPct = Math.round(g.avgExposure * 100);
    var trendDetail = 'SMA‑50 ' + ri(g.sma50) + (g.sma50 > g.sma200 ? ' &gt; ' : ' &lt; ') +
      'SMA‑200 ' + ri(g.sma200) + ' — ' + (g.sma50 > g.sma200 ? 'uptrend' : 'downtrend');
    var momDetail = 'CCI(40) ' + ri(g.cci40) + ' vs exit ' + g.momExit +
      ' · 200‑day triangular MA ' + (g.tmaDown ? 'falling' : 'rising');
    var chip = function (on) { return on ? '<span class="chip in">IN</span>' : '<span class="chip out">OUT</span>'; };
    var combine = g.eitherLong
      ? 'Either‑on is <b>long</b> because ' + (g.trendIn && g.momIn ? 'both filters are IN' : 'at least one filter is IN') +
        ' — you sit out only when <b>both</b> turn OUT.'
      : 'Either‑on is <b>flat</b> because <b>both</b> filters are OUT — re‑enter when either turns IN.';
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
          '<div class="bcombine">' + combine + ' &nbsp;·&nbsp; <b>avg ½‑size</b> alternative: ' + avgPct + '% QQQ.</div>' +
        '</div>' +
      '</div>' +
      '<div class="meta">Last bars:</div>' +
      '<table><thead><tr><th>Date</th><th>Open</th><th>High</th><th>Low</th><th>Close</th><th>Volume</th></tr></thead>' +
        '<tbody>' + rowsHtml + '</tbody></table>';
  }

  function setStatus(html) { statusEl.innerHTML = html; }

  // Render the signal from the current database; `note` is an optional just-happened message.
  function refresh(note) {
    var db = database();
    try {
      renderSignal(S.computeSignal(db));
    } catch (e) {
      out.innerHTML = '<div class="err">' + esc(e.message || String(e)) + '</div>';
    }
    var up = loadUploads().length;
    var src = up > 0 ? 'bundled + ' + up.toLocaleString() + ' uploaded' : 'bundled';
    var range = db.length ? db[0].date + ' … ' + db[db.length - 1].date : '—';
    setStatus((note ? note + ' &nbsp; ' : '') +
      'Database: <b>' + db.length.toLocaleString() + '</b> bars (' + src + '), ' + range + '.');
    resetBtn.style.display = up > 0 ? '' : 'none';
  }

  function ingest(files) {                 // files: [{name, text}]
    var before = database();
    var beforeDates = {};
    before.forEach(function (x) { beforeDates[x.date] = 1; });
    var incoming = S.mergeFiles(files);
    if (!incoming.length) { refresh('<span class="new">No valid rows found in that file.</span>'); return; }
    var added = 0, updated = 0;
    incoming.forEach(function (x) { if (beforeDates[x.date]) updated++; else added++; });
    var uploads = S.mergeRows([loadUploads(), incoming]);   // accumulate, new wins
    lsSet(S.rowsToCSV(uploads));
    refresh('<span class="new">Merged ' + incoming.length.toLocaleString() + ' rows → ' +
      added.toLocaleString() + ' new day(s), ' + updated.toLocaleString() + ' updated.</span>');
  }

  function readFiles(list) {
    var arr = Array.prototype.slice.call(list);
    if (!arr.length) return;
    var pending = arr.length, results = [];
    arr.forEach(function (f, idx) {
      var fr = new FileReader();
      fr.onload = function () { results[idx] = { name: f.name, text: fr.result }; if (--pending === 0) ingest(results); };
      fr.onerror = function () { setStatus('<span class="new">Could not read ' + esc(f.name) + '</span>'); if (--pending === 0) ingest(results.filter(Boolean)); };
      fr.readAsText(f);
    });
  }

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
