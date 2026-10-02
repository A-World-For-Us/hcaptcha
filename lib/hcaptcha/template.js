(function (w, d, cfg) {
  var TIMEOUT_MS = 10000;
  var loader =
    w.hcaptchaElixirTemplate ||
    (w.hcaptchaElixirTemplate = { started: false, ready: false, ok: false, queue: [], called: {} });

  function settle(ok) {
    if (loader.ready) return;
    w.clearTimeout(loader.timer);
    loader.ready = true;
    loader.ok = ok;
    var queue = loader.queue;
    loader.queue = [];
    queue.forEach(function (fn) {
      try {
        fn(ok);
      } catch (_error) {
        // one failing widget must not block the others
      }
    });
  }

  function whenReady(fn) {
    if (loader.ready) fn(loader.ok);
    else loader.queue.push(fn);
  }

  function apiReady() {
    return !!(w.hcaptcha && w.hcaptcha.render);
  }

  function load() {
    loader.started = true;
    if (apiReady()) return settle(true);

    w.hcaptchaElixirTemplateOnload = function () {
      settle(apiReady());
    };
    loader.timer = w.setTimeout(function () {
      settle(false);
    }, TIMEOUT_MS);

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
    try {
      if (typeof w[name] === "function") w[name]();
      loader.called[name] = true;
    } catch (_error) {
      // a failing user function must not stop the widget
    }
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

    var proto = w.HTMLFormElement.prototype;
    var running = false;
    var sending = false;
    var submitter = null;
    var widgetId = null;

    function resetWidget() {
      if (widgetId === null) return;
      try {
        w.hcaptcha.reset(widgetId);
      } catch (_error) {
        // the form can still be sent
      }
    }

    function writeToken(token) {
      var field = form.querySelector('[name="h-captcha-response"]');
      if (!field) {
        field = d.createElement("input");
        field.type = "hidden";
        field.name = "h-captcha-response";
        form.appendChild(field);
      }
      field.value = token;
    }

    function send() {
      var button = submitter;
      submitter = null;
      sending = true;
      try {
        if (typeof proto.requestSubmit === "function") {
          try {
            proto.requestSubmit.call(form, button || undefined);
          } catch (_error) {
            proto.submit.call(form);
          }
        } else {
          proto.submit.call(form);
        }
      } finally {
        sending = false;
      }
    }

    function finish(submit, token) {
      if (!running) return;
      running = false;
      resetWidget();
      if (!submit) return;
      if (token) writeToken(token);
      send();
    }

    function release() {
      if (!running) return;
      running = false;
      submitter = null;
      resetWidget();
    }

    whenReady(function (ok) {
      if (!ok) return;
      var options = params(el);
      options.callback = function (token) {
        try {
          if (cfg.callback && typeof w[cfg.callback] === "function") w[cfg.callback](token);
        } finally {
          finish(true, token);
        }
      };
      options["close-callback"] = function () {
        running = false;
        submitter = null;
      };
      options["chalexpired-callback"] = release;
      options["error-callback"] = function () {
        finish(true);
      };
      widgetId = render(el, options);
    });

    form.addEventListener(
      "submit",
      function (event) {
        if (sending) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        if (running) return;
        running = true;
        submitter = event.submitter || null;
        whenReady(function (ok) {
          if (!running) return;
          if (!ok || widgetId === null) return finish(true);
          try {
            w.hcaptcha.execute(widgetId);
          } catch (_error) {
            finish(true);
          }
        });
      },
      true,
    );

    w.addEventListener("pageshow", function (event) {
      if (event.persisted) {
        running = false;
        submitter = null;
      }
    });
  }

  var el = d.getElementById(cfg.id);
  if (el) {
    if (cfg.invisible) setupInvisible(el);
    else setupCheckbox(el);
  }
  if (!loader.started) load();
})(window, document, __CONFIG__);
