(function (w, d, cfg) {
  var loader =
    w.hcaptchaLoader ||
    (w.hcaptchaLoader = { started: false, ready: false, ok: false, queue: [] });

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

  function setup(ok) {
    var el = d.getElementById(cfg.id);
    if (!ok || !el) return;

    if (cfg.onload && typeof w[cfg.onload] === "function") w[cfg.onload]();

    var options = params(el);
    if (!cfg.invisible) return w.hcaptcha.render(el, options);

    var form = el.closest("form");
    if (!form) return;

    var running = false;
    var widgetId;

    function finish(submit) {
      running = false;
      if (submit) form.submit();
    }

    options.callback = function (token) {
      if (cfg.callback && typeof w[cfg.callback] === "function") w[cfg.callback](token);
      finish(true);
    };
    options["close-callback"] = function () {
      finish(false);
    };
    options["error-callback"] = function () {
      finish(true);
    };

    widgetId = w.hcaptcha.render(el, options);

    form.addEventListener("submit", function (event) {
      event.preventDefault();
      if (running) return;
      running = true;
      try {
        w.hcaptcha.execute(widgetId);
      } catch (_error) {
        finish(true);
      }
    });
  }

  whenReady(setup);
  if (!loader.started) load();
})(window, document, __CONFIG__);
