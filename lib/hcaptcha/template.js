(async (window, document, config) => {
  const DISMISSED = ["challenge-closed", "challenge-expired"];
  const CHALLENGE_TIMEOUT_MS = 20000;
  const LOAD_TIMEOUT_MS = 10000;
  const ONLOAD = "hcaptchaElixirTemplateOnload";

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
      window[ONLOAD] = () => resolve(apiReady());
      const script = document.createElement("script");
      script.src = `${config.src}&onload=${ONLOAD}`;
      script.onerror = () => resolve(false);
      if (config.nonce) script.nonce = config.nonce;
      document.head.append(script);
    });

  const apiLoaded = (window.hcaptchaElixirTemplate ??= loadApi().then((ready) => {
    if (ready) callGlobal(config.onload);
    return ready;
  }));

  const loadedWithin = (ms) =>
    new Promise((resolve) => {
      const timer = window.setTimeout(() => resolve(false), ms);
      apiLoaded.then((ready) => {
        window.clearTimeout(timer);
        resolve(ready);
      });
    });

  const container = document.getElementById(config.id);
  if (!container) return;

  const form = container.closest("form");
  if (config.invisible && !form) return;

  const options = config.widget;
  let widgetId;

  const render = async () => {
    if (!(await apiLoaded)) return;
    try {
      widgetId = window.hcaptcha.render(container, options);
    } catch (error) {
      window.reportError?.(error);
    }
  };

  if (!config.invisible) {
    options.callback = (token) => callGlobal(config.callback, token);
    return render();
  }

  let busy = false;
  let sending = false;
  let watchdog;
  options["open-callback"] = () => window.clearTimeout(watchdog);

  const resetWidget = () => {
    if (widgetId === undefined) return;
    try {
      window.hcaptcha.reset(widgetId);
    } catch {}
  };

  const responseField = () => form.querySelector('[name="h-captcha-response"]');

  const clearToken = () => {
    const field = responseField();
    if (field) field.value = "";
  };

  const writeToken = (token) => {
    let field = responseField();
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

  const sendWithoutToken = (submitter) => {
    clearToken();
    sendForm(submitter);
  };

  const challenge = async () => {
    let timer;
    const timeout = new Promise((resolve, reject) => {
      timer = window.setTimeout(() => reject("challenge-timeout"), CHALLENGE_TIMEOUT_MS);
    });
    watchdog = timer;
    try {
      return await Promise.race([window.hcaptcha.execute(widgetId, { async: true }), timeout]);
    } finally {
      window.clearTimeout(timer);
    }
  };

  const onSubmit = async (event) => {
    if (sending) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (busy) return;
    busy = true;
    const submitter = event.submitter ?? undefined;

    const ready = await loadedWithin(LOAD_TIMEOUT_MS);
    // The browser ignores requestSubmit while this submit event runs. Wait one task so the
    // send happens after it.
    await new Promise((resolve) => window.setTimeout(resolve));
    if (!ready || widgetId === undefined) return sendWithoutToken(submitter);

    let response;
    try {
      ({ response } = await challenge());
    } catch (error) {
      resetWidget();
      if (!DISMISSED.includes(error?.message ?? error)) return sendWithoutToken(submitter);
      busy = false;
      return;
    }

    callGlobal(config.callback, response);
    resetWidget();
    writeToken(response);
    sendForm(submitter);
  };

  form.addEventListener("submit", onSubmit, true);
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) busy = false;
  });

  return render();
})(window, document, __CONFIG__);
