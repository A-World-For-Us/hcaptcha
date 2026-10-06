(async (w, d, cfg) => {
  const KEYS = ["sitekey", "theme", "type", "tabindex", "size", "badge", "callback"];
  const usable = () => Boolean(w.hcaptcha?.render);

  const load = () =>
    new Promise((resolve) => {
      if (usable()) return resolve(true);
      w.hcaptchaElixirTemplateOnload = () => resolve(usable());
      w.setTimeout(() => resolve(false), 10000);
      const script = d.createElement("script");
      script.src = cfg.src;
      script.onerror = () => resolve(false);
      if (cfg.nonce) script.nonce = cfg.nonce;
      d.head.append(script);
    });

  const loaded = (w.hcaptchaElixirTemplate ??= load().then((ok) => {
    try {
      if (ok && cfg.onload) w[cfg.onload]?.();
    } catch {}
    return ok;
  }));

  const el = d.getElementById(cfg.id);
  const form = el?.closest("form");
  if (!el || (cfg.invisible && !form)) return;

  const options = Object.fromEntries(
    Object.entries(el.dataset).filter(([key]) => KEYS.includes(key)),
  );
  let widgetId;

  if (cfg.invisible) {
    const proto = w.HTMLFormElement.prototype;
    let running = false;
    let sending = false;
    let submitter;
    let opened = false;
    let watchdog;

    const abort = () => {
      w.clearTimeout(watchdog);
      running = false;
      submitter = undefined;
    };

    const reset = () => {
      try {
        if (widgetId !== undefined) w.hcaptcha.reset(widgetId);
      } catch {}
    };

    const send = () => {
      const button = submitter;
      submitter = undefined;
      sending = true;
      try {
        try {
          proto.requestSubmit.call(form, button);
        } catch {
          proto.submit.call(form);
        }
      } finally {
        sending = false;
      }
    };

    const finish = (token) => {
      if (!running) return;
      w.clearTimeout(watchdog);
      running = false;
      reset();
      if (token) {
        let field = form.querySelector('[name="h-captcha-response"]');
        if (!field) {
          field = Object.assign(d.createElement("input"), {
            type: "hidden",
            name: "h-captcha-response",
          });
          form.append(field);
        }
        field.value = token;
      }
      send();
    };

    options.callback = (token) => {
      try {
        if (typeof w[cfg.callback] === "function") w[cfg.callback](token);
      } finally {
        finish(token);
      }
    };
    options["open-callback"] = () => {
      opened = true;
    };
    options["close-callback"] = abort;
    options["chalexpired-callback"] = () => {
      if (!running) return;
      abort();
      reset();
    };
    options["error-callback"] = () => finish();

    form.addEventListener(
      "submit",
      async (event) => {
        if (sending) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        if (running) return;
        running = true;
        submitter = event.submitter ?? undefined;
        // The browser ignores requestSubmit while this submit event runs. Wait one task so the
        // send happens after it.
        const ok = await loaded;
        await new Promise((resolve) => w.setTimeout(resolve));
        if (!running) return;
        try {
          if (!ok || widgetId === undefined) throw new Error("hCaptcha is not available");
          opened = false;
          watchdog = w.setTimeout(() => {
            if (!opened) finish();
          }, 10000);
          w.hcaptcha.execute(widgetId);
        } catch {
          finish();
        }
      },
      true,
    );

    w.addEventListener("pageshow", (event) => {
      if (event.persisted) abort();
    });
  }

  if (await loaded) {
    try {
      widgetId = w.hcaptcha.render(el, options);
    } catch {}
  }
})(window, document, __CONFIG__);
