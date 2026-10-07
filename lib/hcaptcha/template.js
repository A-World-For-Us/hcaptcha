(async (window, document, config) => {
  const WIDGET_KEYS = ["sitekey", "theme", "type", "tabindex", "size", "badge"];
  const DISMISSED = ["challenge-closed", "challenge-expired"];
  const TIMEOUT_MS = 10000;

  const apiReady = () => Boolean(window.hcaptcha?.render);

  const callGlobal = (name, ...args) => {
    if (typeof window[name] !== "function") return;
    try {
      window[name](...args);
    } catch (error) {
      window.reportError?.(error);
    }
  };

  const loadApi = () =>
    new Promise((resolve) => {
      if (apiReady()) return resolve(true);
      const timer = window.setTimeout(() => resolve(false), TIMEOUT_MS);
      const settle = (ready) => {
        window.clearTimeout(timer);
        resolve(ready);
      };
      window.hcaptchaElixirTemplateOnload = () => settle(apiReady());
      const script = document.createElement("script");
      script.src = config.src;
      script.onerror = () => settle(false);
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

  if (!config.invisible) {
    options.callback = (token) => callGlobal(config.callback, token);
    return render();
  }

  let busy = false;
  let sending = false;
  let flow = 0;
  let watchdog;

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

  const sendForm = (submitter) => {
    const formPrototype = window.HTMLFormElement.prototype;
    busy = false;
    sending = true;
    try {
      formPrototype.requestSubmit.call(form, submitter);
    } catch {
      formPrototype.submit.call(form);
    } finally {
      sending = false;
    }
  };

  options["open-callback"] = () => window.clearTimeout(watchdog);

  const challenge = () => {
    const timeout = new Promise((resolve, reject) => {
      watchdog = window.setTimeout(() => reject("challenge-timeout"), TIMEOUT_MS);
    });
    return Promise.race([window.hcaptcha.execute(widgetId, { async: true }), timeout]);
  };

  const cancel = () => {
    window.clearTimeout(watchdog);
    flow += 1;
    busy = false;
  };

  const onSubmit = async (event) => {
    if (sending) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (busy) return;
    busy = true;
    const current = ++flow;
    const submitter = event.submitter ?? undefined;

    await apiLoaded;
    // The browser ignores requestSubmit while this submit event runs. Wait one task so the
    // send happens after it.
    await new Promise((resolve) => window.setTimeout(resolve));
    if (current !== flow) return;
    if (widgetId === undefined) return sendForm(submitter);

    let response;
    try {
      ({ response } = await challenge());
    } catch (error) {
      if (current !== flow) return;
      window.clearTimeout(watchdog);
      resetWidget();
      if (!DISMISSED.includes(error?.message ?? error)) return sendForm(submitter);
      busy = false;
      return;
    }
    if (current !== flow) return;
    window.clearTimeout(watchdog);

    callGlobal(config.callback, response);
    resetWidget();
    writeToken(response);
    sendForm(submitter);
  };

  form.addEventListener("submit", onSubmit, true);
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) cancel();
  });

  return render();
})(window, document, __CONFIG__);
