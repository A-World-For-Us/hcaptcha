(function (w, d, cfg) {
  var loader =
    w.hcaptchaLoader ||
    (w.hcaptchaLoader = { started: false, ready: false, ok: false, queue: [], called: {} });

  function settle(ok) {
    var queue = loader.queue;
    loader.ready = true;
    loader.ok = ok;
    loader.queue = [];
    queue.forEach(function (fn) {
      fn(ok);
    });
  }

  function whenReady(fn) {
    if (loader.ready) fn(loader.ok);
    else loader.queue.push(fn);
  }

  function load() {
    loader.started = true;
    if (w.hcaptcha && w.hcaptcha.render) return settle(true);

    w.hcaptchaOnload = function () {
      settle(true);
    };
    var script = d.createElement("script");
    script.src = cfg.src;
    script.async = true;
    script.defer = true;
    if (cfg.nonce) script.nonce = cfg.nonce;
    script.onerror = function () {
      settle(false);
    };
    d.head.appendChild(script);
  }

  function params(el) {
    var params = {};
    ["sitekey", "theme", "type", "tabindex", "size", "badge", "callback"].forEach(function (key) {
      if (el.dataset[key] != null) params[key] = el.dataset[key];
    });
    return params;
  }

  function callOnload() {
    var name = cfg.onload;
    if (!name || loader.called[name]) return;
    loader.called[name] = true;
    if (typeof w[name] === "function") w[name]();
  }

  function render(el, options) {
    callOnload();
    return w.hcaptcha.render(el, options);
  }

  function setupCheckbox(el) {
    whenReady(function (ok) {
      if (ok) render(el, params(el));
    });
  }

  function setupInvisible(el) {
    var form = el.closest("form");
    if (!form) return;

    var running = false;
    var widgetId = null;

    function finish(submit) {
      running = false;
      if (submit) form.submit();
    }

    function release() {
      running = false;
      if (widgetId !== null) w.hcaptcha.reset(widgetId);
    }

    whenReady(function (ok) {
      if (!ok) return;
      var options = params(el);
      options.callback = function (token) {
        if (cfg.callback && typeof w[cfg.callback] === "function") w[cfg.callback](token);
        finish(true);
      };
      options["close-callback"] = function () {
        running = false;
      };
      options["chalexpired-callback"] = release;
      options["error-callback"] = function () {
        finish(true);
      };
      widgetId = render(el, options);
    });

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (running) return;
      running = true;
      whenReady(function (ok) {
        if (!ok || widgetId === null) return finish(true);
        try {
          w.hcaptcha.execute(widgetId);
        } catch (_error) {
          finish(true);
        }
      });
    });
  }

  var el = d.getElementById(cfg.id);
  if (el) {
    if (cfg.invisible) setupInvisible(el);
    else setupCheckbox(el);
  }
  if (!loader.started) load();
})(window, document, __CONFIG__);
