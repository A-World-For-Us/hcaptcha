(async (window, document, config) => {
  const WIDGET_KEYS = ["sitekey", "theme", "type", "tabindex", "size", "badge", "callback"];
  const TIMEOUT_MS = 10000;

  const apiReady = () => Boolean(window.hcaptcha?.render);

  const callGlobal = (name, ...args) => {
    if (typeof window[name] !== "function") return;
    try {
      window[name](...args);
    } catch {}
  };

  const loadApi = () =>
    new Promise((resolve) => {
      if (apiReady()) return resolve(true);
      window.hcaptchaElixirTemplateOnload = () => resolve(apiReady());
      window.setTimeout(() => resolve(false), TIMEOUT_MS);
      const script = document.createElement("script");
      script.src = config.src;
      script.onerror = () => resolve(false);
      if (config.nonce) script.nonce = config.nonce;
      document.head.append(script);
    });

  const apiLoaded = (window.hcaptchaElixirTemplate ??= loadApi().then((ready) => {
    if (ready) callGlobal(config.onload);
    return ready;
  }));

  const container = document.getElementById(config.id);
  if (!container) return;

  const form = container.closest("form");
  if (config.invisible && !form) return;

  const options = Object.fromEntries(
    Object.entries(container.dataset).filter(([key]) => WIDGET_KEYS.includes(key)),
  );
  let widgetId;

  const render = async () => {
    if (!(await apiLoaded)) return;
    try {
      widgetId = window.hcaptcha.render(container, options);
    } catch {}
  };

  if (!config.invisible) return render();

  const formPrototype = window.HTMLFormElement.prototype;
  let running = false;
  let sending = false;
  let opened = false;
  let submitter;
  let watchdog;

  const stop = () => {
    window.clearTimeout(watchdog);
    running = false;
    submitter = undefined;
  };

  const resetWidget = () => {
    if (widgetId === undefined) return;
    try {
      window.hcaptcha.reset(widgetId);
    } catch {}
  };

  const writeToken = (token) => {
    let field = form.querySelector('[name="h-captcha-response"]');
    if (!field) {
      field = Object.assign(document.createElement("input"), {
        type: "hidden",
        name: "h-captcha-response",
      });
      form.append(field);
    }
    field.value = token;
  };

  const sendForm = (button) => {
    sending = true;
    try {
      formPrototype.requestSubmit.call(form, button);
    } catch {
      formPrototype.submit.call(form);
    } finally {
      sending = false;
    }
  };

  const finish = (token) => {
    if (!running) return;
    const button = submitter;
    stop();
    resetWidget();
    if (token) writeToken(token);
    sendForm(button);
  };

  options.callback = (token) => {
    callGlobal(config.callback, token);
    finish(token);
  };
  options["open-callback"] = () => {
    opened = true;
  };
  options["close-callback"] = stop;
  options["chalexpired-callback"] = () => {
    if (!running) return;
    stop();
    resetWidget();
  };
  options["error-callback"] = () => finish();

  const onSubmit = async (event) => {
    if (sending) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (running) return;

    running = true;
    submitter = event.submitter ?? undefined;
    const ready = await apiLoaded;
    // The browser ignores requestSubmit while this submit event runs. Wait one task so the
    // send happens after it.
    await new Promise((resolve) => window.setTimeout(resolve));
    if (!running) return;
    if (!ready || widgetId === undefined) return finish();

    opened = false;
    watchdog = window.setTimeout(() => {
      if (!opened) finish();
    }, TIMEOUT_MS);
    try {
      window.hcaptcha.execute(widgetId);
    } catch {
      finish();
    }
  };

  form.addEventListener("submit", onSubmit, true);
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) stop();
  });

  return render();
})(window, document, __CONFIG__);
