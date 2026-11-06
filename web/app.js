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

  // The panel window: either-on trades ~3×/yr so it gets 5 years; avg trades
  // ~12×/yr so 2 years keeps the table a similar length.
  function actionYears() { return blend === 'avg' ? 2 : 5; }

  // Trade actions of the active blend over the window up to bar `i`, newest first.
  // Each carries the segment outcome: QQQ's move from the action until the next one
  // (or until bar `i` for the most recent), and whether the call helped.
  function buildActions(a, i) {
    var s = blend === 'avg' ? a.avg : a.either;
    var asOf = a.date[i];
    var cutoff = (parseInt(asOf.slice(0, 4), 10) - actionYears()) + asOf.slice(4);
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

  // Net result of the active blend vs buy-and-hold over the panel window ending at
  // bar `i`, replicating src/engine.jl: the signal is lagged one trading day, a 5 bps
  // cost is charged on turnover, and cash earns the 3-month T-bill yield in effect at the
  // prior close while out of the market (flat 4%/yr only if the bundle carries no rates).
  var COST = 5e-4;
  var TBILL = (function () {                            // bundled yields (%), ascending dates
    var dt = [], y = [];
    (window.TBILL_DATA || '').split('\n').forEach(function (l) {
      var f = l.split(','); if (f.length >= 2 && f[0]) { dt.push(f[0]); y.push(parseFloat(f[1])); }
    });
    return { date: dt, yld: y };
  })();
  // Annualized cash rate on each of the ascending `dates`: the last yield on or before the
  // date, floored at 0 (mirrors rate_on in src/data.jl).
  function cashRates(dates) {
    var out = new Array(dates.length), j = 0, m = TBILL.date.length;
    for (var k = 0; k < dates.length; k++) {
      if (!m) { out[k] = 0.04; continue; }
      while (j < m - 1 && TBILL.date[j + 1] <= dates[k]) j++;
      out[k] = Math.max(TBILL.yld[j], 0) / 100;
    }
    return out;
  }
  function windowStats(a, i) {
    var s = blend === 'avg' ? a.avg : a.either;
    var cash = a.cash || (a.cash = cashRates(a.date));
    var asOf = a.date[i];
    var cutoff = (parseInt(asOf.slice(0, 4), 10) - actionYears()) + asOf.slice(4);
    var k0 = 0; while (k0 < i && a.date[k0] < cutoff) k0++;
    if (i - k0 < 40) return null;                       // window too short to annualize
    var eq = 1;
    for (var t = k0 + 1; t <= i; t++) {
      var r = a.close[t] / a.close[t - 1] - 1;
      var rf = Math.pow(1 + cash[t - 1], 1 / 252) - 1;  // yield set at the prior close
      var p = s[t - 1], pp = t >= 2 ? s[t - 2] : 0;     // lagged position & turnover
      eq *= (1 + p * r + (1 - p) * rf) * (1 - COST * Math.abs(p - pp));
    }
    var years = (new Date(asOf) - new Date(a.date[k0])) / 864e5 / 365.25;
    return { years: years, cashNow: cash[i], tbill: TBILL.date.length > 0,
             overlay: Math.pow(eq, 1 / years) - 1,
             bh: Math.pow(a.close[i] / a.close[k0], 1 / years) - 1 };
  }

  function renderActions(g) {
    var a = ANALYSIS, acts = buildActions(a, g.index);
    var head = '<div class="meta">Trade actions — past ' + actionYears() + ' years (' +
      (blend === 'avg' ? 'avg ½-size' : 'either-on') + '):</div>';
    var st = windowStats(a, g.index);
    if (st) {
      head += '<div class="actstat">Net result: <b class="' + (st.overlay >= st.bh ? 'seg-good' : 'seg-bad') + '">' +
        fmtPct(st.overlay) + '/yr</b> vs buy‑and‑hold <b>' + fmtPct(st.bh) + '/yr</b> over the past ' +
        st.years.toFixed(1) + ' yrs <span class="statnote">(annualized; signal lagged a day, 0.05% trade cost, cash earns ' +
        (st.tbill ? 'the 3-month T-bill yield while out — ' + (100 * st.cashNow).toFixed(2) + '% now' : '4%/yr while out') + ')</span></div>';
    }
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

  // ── Filter-history charts: each filter's inputs and thresholds over a window ending at
  //    the as-of bar, so the reader can see how the current state came about. Drawn as
  //    plain SVG at the container's pixel width; a shared crosshair drives one readout
  //    (which shows the as-of bar when idle, so no value is hover-only). ──
  var CH_KEY = 'qqq_chart_range', CH_RANGES = [['6M', 0.5], ['1Y', 1], ['2Y', 2], ['5Y', 5]];
  var chartRange = (function () {
    try { var v = localStorage.getItem(CH_KEY); if (CH_RANGES.some(function (x) { return x[0] === v; })) return v; } catch (e) {}
    return '1Y';
  })();
  var CC = { close: '#2a78d6', s50: '#eb6834', s200: '#1baf7a', cci: '#2a78d6', entry: '#0a7f3f', exit: '#c1121f',
             out: 'rgba(193,18,31,0.09)', outBlend: 'rgba(193,18,31,0.24)', grid: '#eceef0', axis: '#c7ccd2', xh: '#1f2937' };
  var PAD = { l: 44, r: 8, t: 8, b: 22 }, MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  var CHG = null, chartW = 0;                         // geometry of the last render (crosshair)

  function tmaDown(a, t) { return t >= 20 && !isNaN(a.t200[t]) && !isNaN(a.t200[t - 20]) && a.t200[t] < a.t200[t - 20]; }
  function momExitAt(a, t) { return tmaDown(a, t) ? 0 : -100; }
  function niceStep(span, n) {
    var raw = span / n, p = Math.pow(10, Math.floor(Math.log(raw) / Math.LN10)), f = raw / p;
    return (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * p;
  }

  function chartSvg(o) {   // o: id, label, W, H, k0, i, lo, hi, shades [{state (1=IN), fill}], refs [{fn,color}], lines [{v,color}], years
    var a = ANALYSIS, W = o.W, H = o.H, pw = W - PAD.l - PAD.r, ph = H - PAD.t - PAD.b, n = Math.max(o.i - o.k0, 1);
    var x = function (t) { return PAD.l + (t - o.k0) / n * pw; };
    var y = function (v) { return PAD.t + (1 - (v - o.lo) / (o.hi - o.lo)) * ph; };
    var f1 = function (v) { return v.toFixed(1); };
    var path = function (fn, step) {                   // pen lifts over NaN; `step` draws a stair
      var d = '', pen = false, pv = NaN;
      for (var t = o.k0; t <= o.i; t++) {
        var v = fn(t);
        if (isNaN(v)) { pen = false; continue; }
        if (pen && step && v !== pv) d += 'L' + f1(x(t)) + ' ' + f1(y(pv));
        d += (pen ? 'L' : 'M') + f1(x(t)) + ' ' + f1(y(v)); pen = true; pv = v;
      }
      return d;
    };
    var s = '<svg class="fc" id="' + o.id + '" tabindex="0" role="img" aria-label="' + o.label + '" viewBox="0 0 ' +
            W + ' ' + H + '" width="' + W + '" height="' + H + '">';
    var half = pw / n / 2, t;
    o.shades.forEach(function (sh) {                                 // OUT spans, layered in order
      for (var t = o.k0; t <= o.i; t++) {
        if (sh.state[t] !== 0) continue;
        var u = t; while (u < o.i && sh.state[u + 1] === 0) u++;
        var xa = Math.max(PAD.l, x(t) - half), xb = Math.min(PAD.l + pw, x(u) + half);
        s += '<rect x="' + f1(xa) + '" y="' + PAD.t + '" width="' + f1(Math.max(xb - xa, 1)) + '" height="' + ph + '" fill="' + sh.fill + '"/>';
        t = u;
      }
    });
    var step = niceStep(o.hi - o.lo, 4);                             // y grid + labels
    for (var k = Math.ceil(o.lo / step); k * step <= o.hi; k++) {
      var yy = f1(y(k * step));
      s += '<line x1="' + PAD.l + '" x2="' + (PAD.l + pw) + '" y1="' + yy + '" y2="' + yy + '" stroke="' + CC.grid + '"/>' +
           '<text class="tk" x="' + (PAD.l - 6) + '" y="' + yy + '" dy="3.5" text-anchor="end">' + Math.round(k * step) + '</text>';
    }
    s += '<line x1="' + PAD.l + '" x2="' + (PAD.l + pw) + '" y1="' + (PAD.t + ph) + '" y2="' + (PAD.t + ph) + '" stroke="' + CC.axis + '"/>';
    var mstep = o.years <= 1 ? (pw < 420 ? 2 : 1) : o.years <= 2 ? (pw < 420 ? 6 : 3) : 12;   // x ticks at month starts
    for (t = o.k0 + 1; t <= o.i; t++) {
      var ym = a.date[t].slice(0, 7), mo = +ym.slice(5, 7) - 1;
      if (ym === a.date[t - 1].slice(0, 7) || mo % mstep) continue;
      var xx = f1(x(t));
      s += '<line x1="' + xx + '" x2="' + xx + '" y1="' + (PAD.t + ph) + '" y2="' + (PAD.t + ph + 4) + '" stroke="' + CC.axis + '"/>' +
           '<text class="tk" x="' + xx + '" y="' + (H - 6) + '" text-anchor="middle">' + (mo === 0 || mstep === 12 ? ym.slice(0, 4) : MON[mo]) + '</text>';
    }
    o.refs.forEach(function (rf) {
      s += '<path d="' + path(rf.fn, true) + '" fill="none" stroke="' + rf.color + '" stroke-width="1.5" stroke-dasharray="5 4"/>';
    });
    o.lines.forEach(function (ln) {
      s += '<path d="' + path(function (t) { return ln.v[t]; }) + '" fill="none" stroke="' + ln.color +
           '" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>';
    });
    s += '<line class="xh" x1="0" x2="0" y1="' + PAD.t + '" y2="' + (PAD.t + ph) + '" stroke="' + CC.xh + '" stroke-width="1" visibility="hidden"/>';
    CHG = { k0: o.k0, i: o.i, n: n, pw: pw, W: W };
    return s + '</svg>';
  }

  function readoutHtml(t) {
    var a = ANALYSIS;
    return '<b>' + esc(a.date[t]) + '</b> · QQQ close <b>' + r(a.close[t], 2) + '</b> · SMA‑50 ' + ri(a.s50[t]) +
      ' · SMA‑200 ' + ri(a.s200[t]) + ' · trend ' + chip(a.tr[t] === 1) + '<br>CCI(40) <b>' + ri(a.c40[t]) +
      '</b> · exits below ' + momExitAt(a, t) + ', re‑enters above 0 · momentum ' + chip(a.mom[t] === 1) +
      (blend === 'either' ? ' → either‑on ' + chip(a.either[t] === 1) : '');
  }

  function renderCharts(g) {
    var a = ANALYSIS, i = g.index, yrs = CH_RANGES.filter(function (x) { return x[0] === chartRange; })[0][1];
    var start = new Date(new Date(a.date[i]).getTime() - yrs * 365.25 * 864e5).toISOString().slice(0, 10);
    var k0 = i; while (k0 > 0 && a.date[k0 - 1] >= start) k0--;
    if (i - k0 < 10) return '';
    chartW = out.clientWidth || 700;
    var W = Math.max(300, chartW), lo = Infinity, hi = -Infinity, clo = -100, chi = 0;
    for (var t = k0; t <= i; t++) {
      [a.close[t], a.s50[t], a.s200[t]].forEach(function (v) { if (!isNaN(v)) { lo = Math.min(lo, v); hi = Math.max(hi, v); } });
      if (!isNaN(a.c40[t])) { clo = Math.min(clo, a.c40[t]); chi = Math.max(chi, a.c40[t]); }
    }
    var pad = (hi - lo) * 0.05, cpad = (chi - clo) * 0.06;
    // on the either-on tab, a darker band marks when the blend itself is OUT (both filters out → cash)
    var eo = blend === 'either', blendShade = eo ? [{ state: a.either, fill: CC.outBlend }] : [];
    var blendKey = eo ? '<span><i class="box dark"></i>either‑on OUT (in cash)</span>' : '';
    var btns = CH_RANGES.map(function (x) {
      return '<button data-range="' + x[0] + '"' + (x[0] === chartRange ? ' class="active"' : '') + '>' + x[0] + '</button>';
    }).join('');
    return '<div class="fcharts">' +
      '<div class="fchead"><span class="meta">Filter history — the inputs behind each filter, up to ' + esc(a.date[i]) +
        ':</span><span class="rng" id="fcrange">' + btns + '</span></div>' +
      '<div class="fcread" id="fcread">' + readoutHtml(i) + '</div>' +
      '<div class="fctitle">Trend filter — QQQ close vs its 50‑ and 200‑day averages</div>' +
      '<div class="fclegend"><span><i style="border-color:' + CC.close + '"></i>QQQ close</span><span><i style="border-color:' +
        CC.s50 + '"></i>SMA‑50</span><span><i style="border-color:' + CC.s200 + '"></i>SMA‑200</span><span><i class="box"></i>trend filter OUT</span>' +
        blendKey + '</div>' +
      chartSvg({ id: 'fc-trend', label: 'QQQ close with 50- and 200-day moving averages', W: W, H: 200, k0: k0, i: i,
                 lo: lo - pad, hi: hi + pad, shades: [{ state: a.tr, fill: CC.out }].concat(blendShade), refs: [], years: yrs,
                 lines: [{ v: a.s200, color: CC.s200 }, { v: a.s50, color: CC.s50 }, { v: a.close, color: CC.close }] }) +
      '<div class="fcnote">OUT after a death cross (SMA‑50 falls below SMA‑200); back IN when the close reclaims SMA‑50 ' +
        'or on a golden cross, at least 10 trading days after the last switch.</div>' +
      '<div class="fctitle">Momentum filter — CCI(40) and its thresholds</div>' +
      '<div class="fclegend"><span><i style="border-color:' + CC.cci + '"></i>CCI(40)</span><span><i class="dash" style="border-color:' +
        CC.entry + '"></i>re‑entry (0)</span><span><i class="dash" style="border-color:' + CC.exit +
        '"></i>exit (−100, or 0 while the 200‑day triangular MA falls)</span><span><i class="box"></i>momentum filter OUT</span>' +
        blendKey + '</div>' +
      chartSvg({ id: 'fc-mom', label: 'CCI(40) with its entry and exit thresholds', W: W, H: 170, k0: k0, i: i,
                 lo: clo - cpad, hi: chi + cpad, shades: [{ state: a.mom, fill: CC.out }].concat(blendShade), years: yrs,
                 lines: [{ v: a.c40, color: CC.cci }],
                 refs: [{ fn: function () { return 0; }, color: CC.entry }, { fn: function (t) { return momExitAt(a, t); }, color: CC.exit }] }) +
      '<div class="fcnote">OUT when CCI(40) closes below the red exit line; back IN when it closes above 0. ' +
        'Shading marks each filter’s state at that close — trades are acted on the next session.' +
        (eo ? ' Darker red: both filters OUT, so the either‑on blend is in cash.' : '') + '</div>' +
    '</div>';
  }

  // Crosshair: pointer or arrow keys on either chart move one hairline across both and
  // update the readout; leaving (or Esc) returns it to the as-of bar.
  function wireCharts() {
    var svgs = ['fc-trend', 'fc-mom'].map($).filter(Boolean), read = $('fcread');
    if (!CHG || !svgs.length || !read) return;
    var cur = CHG.i;
    var show = function (t) {
      cur = Math.max(CHG.k0, Math.min(CHG.i, t));
      var xx = (PAD.l + (cur - CHG.k0) / CHG.n * CHG.pw).toFixed(1);
      svgs.forEach(function (sv) {
        var l = sv.querySelector('.xh'); if (!l) return;
        l.setAttribute('x1', xx); l.setAttribute('x2', xx); l.setAttribute('visibility', 'visible');
      });
      read.innerHTML = readoutHtml(cur);
    };
    var hide = function () {
      svgs.forEach(function (sv) { var l = sv.querySelector('.xh'); if (l) l.setAttribute('visibility', 'hidden'); });
      cur = CHG.i; read.innerHTML = readoutHtml(CHG.i);
    };
    svgs.forEach(function (sv) {
      sv.addEventListener('pointermove', function (e) {
        var rc = sv.getBoundingClientRect(), px = (e.clientX - rc.left) * (CHG.W / rc.width);
        show(Math.round(CHG.k0 + (px - PAD.l) / CHG.pw * CHG.n));
      });
      sv.addEventListener('pointerleave', hide);
      sv.addEventListener('blur', hide);
      sv.addEventListener('keydown', function (e) {
        var step = e.shiftKey ? 21 : 1;
        if (e.key === 'ArrowLeft') { show(cur - step); e.preventDefault(); }
        else if (e.key === 'ArrowRight') { show(cur + step); e.preventDefault(); }
        else if (e.key === 'Escape') hide();
      });
    });
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
    var rowsHtml = g.recent.slice().reverse().map(function (x, i) {   // newest bar on top
      var hl = i === 0;
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
      renderCharts(g) +
      renderActions(g) +
      '<div class="meta">' + (g.live ? 'QQQ last bars:' : 'QQQ bars up to ' + esc(g.asOf) + ':') + '</div>' +
      '<div class="tablewrap"><table><thead><tr><th>Date</th><th>Open</th><th>High</th><th>Low</th><th>Close</th><th>Volume</th></tr></thead>' +
        '<tbody>' + rowsHtml + '</tbody></table></div>';
    wireCharts();
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
  out.addEventListener('click', function (e) {               // chart range buttons (re-rendered each time)
    var b = e.target.closest && e.target.closest('#fcrange button');
    if (!b || !lastG) return;
    chartRange = b.getAttribute('data-range');
    try { localStorage.setItem(CH_KEY, chartRange); } catch (err) {}
    renderSignal(lastG);
  });
  var rsz = null;                                            // redraw the charts at the new width
  window.addEventListener('resize', function () {
    clearTimeout(rsz);
    rsz = setTimeout(function () { if (lastG && out.clientWidth !== chartW) renderSignal(lastG); }, 150);
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
