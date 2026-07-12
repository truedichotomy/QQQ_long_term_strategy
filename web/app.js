/* app.js — UI for the QQQ blend signal. Ships with the QQQ history bundled (data.js) so it
 * shows a signal on open. A tab chooses the blend (either-on / avg). An "as of" date lets you
 * see what the call was on any past trading day. Uploading a newer file APPENDS to a local,
 * deduplicated database (localStorage). All client-side — no server, nothing uploaded.
 * Default bar mirrors signal.jl: before noon ET it reports the last completed session (today's
 * bar has barely formed); after noon it uses today's still-forming provisional bar. */
(function () {
  'use strict';
  var S = window.QQQStrategy;
  var $ = function (id) { return document.getElementById(id); };
  var drop = $('drop'), fileInput = $('file'), out = $('out'), statusEl = $('status'),
      resetBtn = $('reset'), tabsEl = $('tabs'), blendDescEl = $('blenddesc'),
      asofInput = $('asof'), latestBtn = $('latest');

  var BUNDLE = S.parseCSV(window.QQQ_DATA || '');
  var LS_KEY = 'qqq_uploads_v1', BLEND_KEY = 'qqq_blend';
  var mem = null, lastG = null, ANALYSIS = null, MIN_I = 0, asofIndex = 0;
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

  // The actionable bar, mirroring signal.jl: before noon ET, report the last completed session
  // rather than today's still-forming (provisional) bar; after noon, use today's provisional bar.
  function etNow() {
    try {
      var d = new Date();
      return { date: new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(d),
               hour: parseInt(new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', hour: '2-digit', hour12: false, hourCycle: 'h23' }).format(d), 10) || 0 };
    } catch (e) {
      var x = new Date(), m = x.getMonth() + 1, dd = x.getDate();
      return { date: x.getFullYear() + '-' + (m < 10 ? '0' : '') + m + '-' + (dd < 10 ? '0' : '') + dd, hour: x.getHours() };
    }
  }
  function defaultIndex() {
    var n = ANALYSIS.rows.length - 1, last = ANALYSIS.rows[n];
    if (last && last.partial && (n - 1) >= MIN_I) {
      var et = etNow();
      if (ANALYSIS.date[n] === et.date && et.hour < 12) return n - 1;   // before noon ET → last completed session
    }
    return n;
  }

  // Warn when the newest bar has gone stale (the nightly auto-update may be broken).
  // The widest normal gap is a long holiday weekend; beyond 5 days something is wrong.
  function staleWarn() {
    var last = ANALYSIS.date[ANALYSIS.rows.length - 1];
    var days = Math.round((new Date(etNow().date) - new Date(last)) / 864e5);
    return days > 5 ? ' <span class="prov">⚠ newest bar (' + esc(last) + ') is ' + days +
      ' days old — the nightly data update may be failing</span>' : '';
  }

  var fmtPct = function (r) { return (r >= 0 ? '+' : '−') + (100 * Math.abs(r)).toFixed(1) + '%'; };

  // Trade actions of the active blend over the 2 years up to bar `i`, newest first.
  // Each carries the segment outcome: QQQ's move from the action until the next one
  // (or until bar `i` for the most recent), and whether the call helped.
  function buildActions(a, i) {
    var s = blend === 'avg' ? a.avg : a.either;
    var asOf = a.date[i];
    var cutoff = (parseInt(asOf.slice(0, 4), 10) - 2) + asOf.slice(4);
    var ks = [];
    for (var k = 1; k <= i; k++) if (s[k] !== s[k - 1]) ks.push(k);
    ks = ks.filter(function (k) { return a.date[k] >= cutoff; });
    var acts = ks.map(function (k, j) {
      var to = j + 1 < ks.length ? ks[j + 1] : i;      // segment runs to the next action or as-of
      var ret = a.close[to] / a.close[k] - 1;
      var exp = s[k];
      var label, cls;
      if (blend === 'avg') {
        label = exp >= 1 ? '▲ 100% QQQ' : exp <= 0 ? '▼ 0% (cash)' : '◐ 50% QQQ';
        cls = exp >= 1 ? 'act-buy' : exp <= 0 ? 'act-sell' : 'act-half';
      } else {
        label = exp === 1 ? '▲ BUY' : '▼ SELL';
        cls = exp === 1 ? 'act-buy' : 'act-sell';
      }
      var outcome = 'QQQ ' + fmtPct(ret) +
        (exp >= 1 ? ' while in' : exp <= 0 ? (ret < 0 ? ' while out · avoided' : ' while out · missed') : ' at 50% exposure') +
        (j === ks.length - 1 ? ' (so far)' : '');
      var good = exp >= 1 ? (ret >= 0) : exp <= 0 ? (ret < 0) : null;   // did the call help?
      return { date: a.date[k], label: label, cls: cls, close: a.close[k],
               filters: 'T' + (a.tr[k] ? '✓' : '✗') + ' · M' + (a.mom[k] ? '✓' : '✗'),
               outcome: outcome, ocls: good == null ? 'seg-flat' : good ? 'seg-good' : 'seg-bad' };
    });
    return acts.reverse();
  }

  function renderActions(g) {
    var a = ANALYSIS, acts = buildActions(a, g.index);
    var head = '<div class="meta">Trade actions — past 2 years (' +
      (blend === 'avg' ? 'avg ½-size' : 'either-on') + '):</div>';
    if (!acts.length) {
      var st = blend === 'avg' ? (Math.round(g.avgExposure * 100) + '% QQQ') : (g.eitherLong ? 'in QQQ' : 'in cash');
      return head + '<div class="meta">no changes — ' + st + ' since ' +
        esc(blend === 'avg' ? g.avgSince : g.eitherSince) + '.</div>';
    }
    var rowsHtml = acts.map(function (x) {
      return '<tr><td>' + esc(x.date) + '</td><td class="' + x.cls + '">' + x.label + '</td><td>' +
        r(x.close, 2) + '</td><td class="filt">' + x.filters + '</td><td class="' + x.ocls + '">' +
        esc(x.outcome) + '</td></tr>';
    }).join('');
    return head +
      '<div class="tablewrap"><table class="acts"><thead><tr><th>Date</th><th>Action</th><th>QQQ close</th>' +
      '<th title="Trend · Momentum filter state after this change">Filters</th><th>Until next action</th></tr></thead>' +
      '<tbody>' + rowsHtml + '</tbody></table></div>';
  }

  function renderSignal(g) {
    var cls, action, sub, combine;
    if (blend === 'avg') {
      var pct = Math.round(g.avgExposure * 100);
      if (pct >= 100) { cls = 'buy'; action = '▲ HOLD'; sub = '— 100% in QQQ (both filters IN)'; }
      else if (pct <= 0) { cls = 'sell'; action = '▼ SELL / WAIT'; sub = '— 100% cash (both filters OUT)'; }
      else { cls = 'half'; action = '◐ HALF'; sub = '— 50% QQQ / 50% cash (one filter IN, one OUT)'; }
      combine = 'Avg ½-size: QQQ weight = (trend + momentum) ÷ 2 = <b>' + pct + '%</b> — at this exposure since ' +
        esc(g.avgSince) + '. (Either-on: ' + (g.eitherLong ? '100% QQQ' : 'cash') + '.)';
    } else {
      cls = g.eitherLong ? 'buy' : 'sell';
      action = g.eitherLong ? '▲ BUY / HOLD' : '▼ SELL / WAIT';
      sub = g.eitherLong ? '— stay 100% in QQQ' : '— move to cash and wait';
      combine = g.eitherLong
        ? 'Either-on is <b>long</b> because ' + (g.trendIn && g.momIn ? 'both filters are IN' : 'at least one filter is IN') +
          ' — you sit out only when <b>both</b> turn OUT. In QQQ since ' + esc(g.eitherSince) +
          '. (Avg ½-size: ' + Math.round(g.avgExposure * 100) + '%.)'
        : 'Either-on is <b>flat</b> because <b>both</b> filters are OUT — re-enter when either turns IN. In cash since ' +
          esc(g.eitherSince) + '.';
    }
    var trendDetail = 'SMA‑50 ' + ri(g.sma50) + (g.sma50 > g.sma200 ? ' &gt; ' : ' &lt; ') +
      'SMA‑200 ' + ri(g.sma200) + ' — ' + (g.sma50 > g.sma200 ? 'uptrend' : 'downtrend');
    var momDetail = 'CCI(40) ' + ri(g.cci40) + ' vs exit ' + g.momExit +
      ' · 200‑day triangular MA ' + (g.tmaDown ? 'falling' : 'rising');
    var rowsHtml = g.recent.map(function (x, i) {
      var hl = i === g.recent.length - 1;
      return '<tr' + (hl ? ' class="today"' : '') + '><td>' + esc(x.date) + (x.partial ? ' <span class="prov">⚠</span>' : '') + '</td><td>' +
        r(x.o, 2) + '</td><td>' + r(x.h, 2) + '</td><td>' + r(x.l, 2) + '</td><td>' +
        r(x.c, 2) + '</td><td>' + rv(x.v) + '</td></tr>';
    }).join('');
    out.innerHTML =
      '<div class="signal ' + cls + '">' +
        '<div><span class="sigaction">' + action + '</span><span class="sigsub">' + sub + '</span></div>' +
        '<div class="sigasof">' + (g.live ? 'live signal as of ' : 'historical signal as of ') +
          '<b>' + esc(g.asOf) + '</b> · QQQ close ' + r(g.close, 2) + ' · CCI(40) ' + ri(g.cci40) +
          (g.provisional ? ' <span class="prov">⚠ provisional (mid-session — not yet final)</span>' : '') +
          (g.heldForming ? ' <span class="prov">· today’s bar (' + esc(g.heldForming) + ') still forming — held until noon ET</span>' : '') +
          (g.live ? staleWarn() : '') + '</div>' +
        '<div class="brk">' +
          '<div class="brow"><span class="bn">Trend filter — SMA 50/200 fast‑reentry</span>' + chip(g.trendIn) +
            '<span class="bd">' + trendDetail + ' · since ' + esc(g.trendSince) + '</span></div>' +
          '<div class="brow"><span class="bn">Momentum filter — CCI(40) TMA‑trigger</span>' + chip(g.momIn) +
            '<span class="bd">' + momDetail + ' · since ' + esc(g.momSince) + '</span></div>' +
          '<div class="bcombine">' + combine + '</div>' +
        '</div>' +
      '</div>' +
      renderActions(g) +
      '<div class="meta">' + (g.live ? 'Last bars:' : 'Bars up to ' + esc(g.asOf) + ':') + '</div>' +
      '<div class="tablewrap"><table><thead><tr><th>Date</th><th>Open</th><th>High</th><th>Low</th><th>Close</th><th>Volume</th></tr></thead>' +
        '<tbody>' + rowsHtml + '</tbody></table></div>';
  }

  function applyBlend() {
    Array.prototype.forEach.call(tabsEl.children, function (b) {
      b.classList.toggle('active', b.getAttribute('data-blend') === blend); });
    blendDescEl.innerHTML = (blend === 'avg'
      ? 'Average of the two filters (0 / 50 / 100% invested) — smoothest ride, cushions fast crashes too, ~12 trades/yr.'
      : 'Long if <b>either</b> filter is in — highest return, ~3 trades/yr, simple all‑in/all‑out.') +
      ' <a class="stratlink" href="' + (blend === 'avg' ? 'blend_avg.html' : 'blend_either_on.html') +
      '">how this strategy works ▸</a>';
    if (lastG) renderSignal(lastG);
  }

  // Render the signal as of bar index `i` (clamped to the analyzable range).
  function renderAt(i) {
    if (!ANALYSIS) return;
    var n = ANALYSIS.rows.length - 1;
    i = Math.max(MIN_I, Math.min(i, n));
    asofIndex = i;
    lastG = S.signalAt(ANALYSIS, i);
    var di = defaultIndex();
    lastG.live = (i === n) || (i === di);                               // the current actionable call
    lastG.heldForming = (i === di && di < n) ? ANALYSIS.date[n] : null; // today's still-forming bar, held before noon
    if (asofInput.value !== lastG.asOf) asofInput.value = lastG.asOf;   // snap to the trading date
    latestBtn.classList.toggle('hidden', i === n);                     // offer "↻ latest" whenever not on the newest bar
    applyBlend();
  }

  function indexForDate(v) {                 // last bar on or before the picked date
    var dates = ANALYSIS.date;
    for (var k = dates.length - 1; k >= 0; k--) if (dates[k] <= v) return k;
    return 0;
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
    if (db.length < 201) { out.innerHTML = '<div class="err">Need at least ~201 daily bars; got ' + db.length + '.</div>'; setStatusBar(db, note); return; }
    ANALYSIS = S.analyze(db);
    MIN_I = S.firstValidIndex(ANALYSIS);
    asofInput.min = ANALYSIS.date[MIN_I];
    asofInput.max = ANALYSIS.date[db.length - 1];
    renderAt(defaultIndex());                 // default to the actionable bar (before noon ET: last completed session)
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

  Array.prototype.forEach.call(tabsEl.children, function (b) {
    b.addEventListener('click', function () {
      blend = b.getAttribute('data-blend');
      try { localStorage.setItem(BLEND_KEY, blend); } catch (e) {}
      applyBlend();
    });
  });
  asofInput.addEventListener('change', function () { if (asofInput.value) renderAt(indexForDate(asofInput.value)); });
  latestBtn.addEventListener('click', function () { renderAt(ANALYSIS.rows.length - 1); });
  ['dragenter', 'dragover'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) { e.preventDefault(); e.stopPropagation(); drop.classList.add('over'); }); });
  ['dragleave', 'drop'].forEach(function (ev) {
    drop.addEventListener(ev, function (e) { e.preventDefault(); e.stopPropagation(); drop.classList.remove('over'); }); });
  drop.addEventListener('drop', function (e) { readFiles(e.dataTransfer.files); });
  drop.addEventListener('click', function () { fileInput.click(); });
  fileInput.addEventListener('change', function () { readFiles(fileInput.files); fileInput.value = ''; });
  resetBtn.addEventListener('click', function () { lsClear(); refresh('<span class="new">Reset to bundled data.</span>'); });

  refresh();
  try { var qa = new URLSearchParams(location.search).get('asof'); if (qa && ANALYSIS) renderAt(indexForDate(qa)); } catch (e) {}
})();
