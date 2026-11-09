(function () {
  "use strict";

  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  // ── SQL blocks: split sql/client_entitlements.sql on "-- [step:<id>]" markers ──
  function splitSteps(sql) {
    var steps = {};
    var parts = sql.split(/^-- \[step:([a-z_-]+)\]\s*$/m);
    for (var i = 1; i < parts.length; i += 2) steps[parts[i]] = parts[i + 1].trim();
    return steps;
  }

  function renderCode(el, code) {
    el.innerHTML =
      '<div class="code-bar"><span class="code-lang">SQL</span>' +
      '<button class="copy-btn" type="button">Copy</button></div>' +
      '<pre class="language-sql"><code class="language-sql"></code></pre>';
    var codeEl = el.querySelector("code");
    codeEl.textContent = code;
    if (window.Prism) Prism.highlightElement(codeEl);
    el.querySelector(".copy-btn").addEventListener("click", function () {
      var btn = this;
      copyText(code).then(function () {
        btn.textContent = "Copied!";
        btn.classList.add("copied");
        setTimeout(function () { btn.textContent = "Copy"; btn.classList.remove("copied"); }, 1800);
      });
    });
  }

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    document.execCommand("copy");
    document.body.removeChild(ta);
    return Promise.resolve();
  }

  var loadErr = '<div class="code-loading">Could not load content. If you opened this file directly, serve the folder over HTTP (e.g. <code>python3 -m http.server</code>).</div>';

  fetch("sql/client_entitlements.sql")
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
    .then(function (sql) {
      var steps = splitSteps(sql);
      document.querySelectorAll(".code-wrap[data-step]").forEach(function (el) {
        var code = steps[el.getAttribute("data-step")];
        if (code) renderCode(el, code);
      });
    })
    .catch(function () {
      document.querySelectorAll(".code-wrap[data-step]").forEach(function (el) { el.innerHTML = loadErr; });
    });

  // ── Result tables from data/sample_results.json ──
  function wrap(head, body) {
    return '<div class="table-scroll"><table class="results-table"><thead><tr>' +
      head.map(function (c) { return "<th>" + esc(c) + "</th>"; }).join("") +
      "</tr></thead><tbody>" + body + "</tbody></table></div>";
  }
  function n(v) { return Number(v).toLocaleString(); }
  function usd(v) { return "$" + Number(v).toLocaleString(); }
  function roleChip(r) {
    var base = r.split(" ")[0];
    var cls = /ADVISOR/.test(base) ? "role-admin" : /BRANCH/.test(base) ? "role-mgr" : /COMPLIANCE/.test(base) ? "role-comp" : "role-partner";
    return '<span class="role-chip ' + cls + '">' + esc(r) + "</span>";
  }
  function masked(v) { return /\*/.test(v) ? "partial" : "full"; }

  var render = {
    books: function (d) {
      return wrap(["Branch", "Advisor book", "Clients"], d.books.map(function (b) {
        return '<tr><td class="col-name">' + esc(b.branch) + '</td><td class="col-name">' + esc(b.advisor) + '</td><td class="num">' + b.clients + "</td></tr>";
      }).join("")) + '<p class="legend">Totals: ' + n(d.totals.clients) + " clients · " + n(d.totals.accounts) + " accounts · " + n(d.totals.holdings) + " holdings</p>";
    },
    visibility: function (d) {
      return wrap(["Role", "Clients visible", "Books visible"], d.visibility.map(function (v) {
        return "<tr" + (/covering/.test(v.role) ? ' class="flag"' : "") + "><td>" + roleChip(v.role) + '</td><td class="num"><strong>' + v.clients +
          '</strong></td><td class="col-name">' + esc(v.books) + "</td></tr>";
      }).join("")) + '<p class="legend">The highlighted row ran after a single <code>INSERT</code> into the mapping table, which was then removed with a <code>DELETE</code>.</p>';
    },
    masking: function (d) {
      return wrap(["Role", "Name", "Email", "Tax ID", "Net worth", "Account no."], d.masking.map(function (m) {
        if (m.hidden) return "<tr><td>" + roleChip(m.role) + '</td><td colspan="5" class="no">✕ Row not visible: client C0001 is in another advisor\'s book</td></tr>';
        var nwCls = m.role === "ENT_COMPLIANCE" ? "full" : "partial";
        return "<tr><td>" + roleChip(m.role) + "</td><td>" + esc(m.name) + '</td><td class="val ' + masked(m.email) + '">' + esc(m.email) +
          '</td><td class="val ' + masked(m.tax_id) + '">' + esc(m.tax_id) + '</td><td class="val ' + nwCls + '">' + usd(m.net_worth) +
          (nwCls === "partial" ? " <small>(band)</small>" : "") + '</td><td class="val ' + masked(m.account_number) + '">' + esc(m.account_number) + "</td></tr>";
      }).join("")) + '<div class="legend"><span class="l-full">Full value</span><span class="l-partial">Masked or banded</span></div>';
    },
    tag: function (d) {
      return wrap(["Role", "Client", "MOBILE_PHONE (tagged CONFIDENTIAL)"], d.tag.map(function (t) {
        return "<tr><td>" + roleChip(t.role) + '</td><td class="col-name">C0001</td><td class="val ' + (/RESTRICTED/.test(t.mobile_phone) ? "masked" : "full") + '">' + esc(t.mobile_phone) + "</td></tr>";
      }).join(""));
    },
    aggregation: function (d) {
      return '<div class="allowed-label" style="color:#B4232C">8a · Row-level query</div><div class="blocked">' + esc(d.aggregation.row_level) + "</div>" +
        '<div class="allowed-label">8b · Grouped query (allowed)</div>' +
        wrap(["Branch", "Segment", "Clients", "Avg AUM"], d.aggregation.grouped.map(function (g) {
          return '<tr><td class="col-name">' + esc(g.branch) + '</td><td class="col-name">' + esc(g.segment) + '</td><td class="num">' + g.clients +
            '</td><td class="num">' + usd(g.avg_aum) + "</td></tr>";
        }).join(""));
    },
    research: function (d) {
      return wrap(["Branch", "Sector", "Clients", "Market value"], d.research.rows.map(function (r) {
        return '<tr><td class="col-name">' + esc(r.branch) + '</td><td class="col-name">' + esc(r.sector) + '</td><td class="num">' + r.clients +
          '</td><td class="num">' + usd(r.market_value) + "</td></tr>";
      }).join("")) + '<div class="allowed-label" style="color:#B4232C">Partner reading ENT_CLIENTS directly</div><div class="blocked">' + esc(d.research.table_access) + "</div>";
    },
    aum: function (d) {
      var max = Math.max.apply(null, d.aum.map(function (a) { return a.aum; }));
      return wrap(["Role", "Clients", "Assets under management", ""], d.aum.map(function (a) {
        return "<tr><td>" + roleChip(a.role) + '</td><td class="num">' + a.clients + '</td><td class="num"><strong>' + usd(a.aum) +
          '</strong></td><td class="bar-cell"><div class="bar"><span style="width:' + (a.aum / max * 100).toFixed(1) + '%"></span></div></td></tr>';
      }).join(""));
    }
  };

  fetch("data/sample_results.json")
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (d) {
      document.querySelectorAll(".results[data-results]").forEach(function (el) {
        var fn = render[el.getAttribute("data-results")];
        if (fn) el.innerHTML = fn(d, el);
      });
    })
    .catch(function () {
      document.querySelectorAll(".results[data-results]").forEach(function (el) { el.innerHTML = loadErr; });
    });

  // ── Mobile Nav ──
  var btn = document.querySelector(".nav-hamburger");
  var links = document.querySelector(".nav-links");
  btn.addEventListener("click", function () {
    var open = links.classList.toggle("open");
    btn.classList.toggle("open", open);
    btn.setAttribute("aria-expanded", String(open));
  });
  links.querySelectorAll("a").forEach(function (a) {
    a.addEventListener("click", function () {
      links.classList.remove("open");
      btn.classList.remove("open");
      btn.setAttribute("aria-expanded", "false");
    });
  });

  // ── Nav Scroll Shadow ──
  var nav = document.getElementById("navbar");
  window.addEventListener("scroll", function () {
    nav.classList.toggle("scrolled", window.scrollY > 10);
  }, { passive: true });

  // ── Reveal on Scroll ──
  if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches && "IntersectionObserver" in window) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add("visible"); observer.unobserve(e.target); }
      });
    }, { threshold: 0.08, rootMargin: "0px 0px -40px 0px" });
    document.querySelectorAll(".reveal").forEach(function (el) { observer.observe(el); });
  } else {
    document.querySelectorAll(".reveal").forEach(function (el) { el.classList.add("visible"); });
  }
})();
