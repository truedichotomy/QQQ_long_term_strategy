/* app.js — UI glue for the QQQ blend signal. Reads dropped/selected CSV file(s) with
 * the FileReader API (fully client-side), computes the signal via strategy.js, and renders
 * a signal card. No network, no upload. Also auto-loads a co-located `qqq.csv` when the
 * page is served over http(s) (skipped on file:// to avoid CORS noise). */
(function () {
  'use strict';
  var drop = document.getElementById('drop'),
      fileInput = document.getElementById('file'),
      out = document.getElementById('out');

  var esc = function (s) { return String(s).replace(/[&<>]/g, function (c) {
    return c === '&' ? '&amp;' : c === '<' ? '&lt;' : '&gt;'; }); };
  var r = function (x, d) { d = d || 0; return (x == null || isNaN(x)) ? '–' : Number(x).toFixed(d); };
  var ri = function (x) { return (x == null || isNaN(x)) ? '–' : Math.round(x); };

  function render(g) {
    var cls, action, sub;
    if (g.eitherLong) { cls = 'buy'; action = '▲ BUY / HOLD'; sub = '— stay 100% in QQQ'; }
    else { cls = 'sell'; action = '▼ SELL / WAIT'; sub = '— move to cash and wait'; }

    var avgPct = Math.round(g.avgExposure * 100);
    var trendDetail = 'SMA‑50 ' + ri(g.sma50) + (g.sma50 > g.sma200 ? ' &gt; ' : ' &lt; ') +
      'SMA‑200 ' + ri(g.sma200) + ' — ' + (g.sma50 > g.sma200 ? 'uptrend' : 'downtrend');
    var momDetail = 'CCI(40) ' + ri(g.cci40) + ' vs exit ' + g.momExit +
      ' · 200‑day triangular MA ' + (g.tmaDown ? 'falling' : 'rising');
    var chip = function (on) { return on
      ? '<span class="chip in">IN</span>' : '<span class="chip out">OUT</span>'; };
    var combine = g.eitherLong
      ? 'Either‑on is <b>long</b> because ' + (g.trendIn && g.momIn ? 'both filters are IN'
          : 'at least one filter is IN') + ' — you sit out only when <b>both</b> turn OUT.'
      : 'Either‑on is <b>flat</b> because <b>both</b> filters are OUT — re‑enter when either turns IN.';

    var rowsHtml = g.recent.map(function (x, i) {
      var today = i === g.recent.length - 1;
      return '<tr' + (today ? ' class="today"' : '') + '><td>' + esc(x.date) + '</td><td>' +
        r(x.o, 2) + '</td><td>' + r(x.h, 2) + '</td><td>' + r(x.l, 2) + '</td><td>' +
        r(x.c, 2) + '</td><td>' + ri(x.v).toLocaleString() + '</td></tr>';
    }).join('');

    out.innerHTML =
      '<div class="signal ' + cls + '">' +
        '<div><span class="sigaction">' + action + '</span><span class="sigsub">' + sub + '</span></div>' +
        '<div class="sigasof">live signal as of <b>' + esc(g.asOf) + '</b> · QQQ close ' + r(g.close, 2) +
          ' · CCI(40) ' + ri(g.cci40) + '</div>' +
        '<div class="brk">' +
          '<div class="brow"><span class="bn">Trend filter — SMA 50/200 fast‑reentry</span>' +
            chip(g.trendIn) + '<span class="bd">' + trendDetail + ' · since ' + esc(g.trendSince) + '</span></div>' +
          '<div class="brow"><span class="bn">Momentum filter — CCI(40) TMA‑trigger</span>' +
            chip(g.momIn) + '<span class="bd">' + momDetail + ' · since ' + esc(g.momSince) + '</span></div>' +
          '<div class="bcombine">' + combine +
            ' &nbsp;·&nbsp; <b>avg ½‑size</b> alternative: ' + avgPct + '% QQQ.</div>' +
        '</div>' +
      '</div>' +
      '<div class="meta">' + g.rows.toLocaleString() + ' daily bars merged, ' +
        esc(g.firstDate) + ' … ' + esc(g.asOf) + '. Last bars:</div>' +
      '<table><thead><tr><th>Date</th><th>Open</th><th>High</th><th>Low</th><th>Close</th><th>Volume</th></tr></thead>' +
        '<tbody>' + rowsHtml + '</tbody></table>' +
      '<button class="reload" id="again">↻ load a different file</button>';

    document.getElementById('again').onclick = function () { fileInput.value = ''; fileInput.click(); };
  }

  function showError(msg) {
    out.innerHTML = '<div class="err">' + esc(msg) + '</div>';
  }

  function process(files) {        // files: [{name, text}]
    try {
      var rows = QQQStrategy.mergeFiles(files);
      if (!rows.length) { showError('No usable rows found. Expected a CSV with Date,Open,High,Low,Close,Volume columns.'); return; }
      render(QQQStrategy.computeSignal(rows));
    } catch (e) { showError(e.message || String(e)); }
  }

  function readFileList(list) {
    var arr = Array.prototype.slice.call(list).filter(function (f) { return /\.csv$/i.test(f.name) || f.type.indexOf('csv') !== -1 || true; });
    if (!arr.length) return;
    var pending = arr.length, results = [];
    arr.forEach(function (f, idx) {
      var fr = new FileReader();
      fr.onload = function () {
        results[idx] = { name: f.name, text: fr.result };
        if (--pending === 0) process(results);
      };
      fr.onerror = function () { showError('Could not read ' + f.name); };
      fr.readAsText(f);
    });
  }

  // drag & drop
  ['dragenter', 'dragover'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) { e.preventDefault(); e.stopPropagation(); drop.classList.add('over'); });
  });
  ['dragleave', 'drop'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) { e.preventDefault(); e.stopPropagation(); drop.classList.remove('over'); });
  });
  drop.addEventListener('drop', function (e) { readFileList(e.dataTransfer.files); });
  drop.addEventListener('click', function () { fileInput.click(); });
  fileInput.addEventListener('change', function () { readFileList(fileInput.files); });

  // optional auto-load when served (not file://): co-located qqq.csv
  if (location.protocol !== 'file:') {
    fetch('qqq.csv').then(function (resp) {
      if (!resp.ok) throw 0;
      return resp.text();
    }).then(function (text) {
      process([{ name: 'qqq.csv', text: text }]);
    }).catch(function () { /* no co-located file; wait for a drop */ });
  }
})();
