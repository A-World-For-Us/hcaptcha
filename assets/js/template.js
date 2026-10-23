import {
  LOAD_TIMEOUT_MS,
  callGlobal,
  clearToken,
  loadApi,
  settleWithin,
  solve,
  withWatchdog,
  writeToken,
} from "./core.js";

const ONLOAD = "hcaptchaElixirTemplateOnload";

// __CONFIG__ is not defined here. lib/hcaptcha/template.ex replaces it with the JSON config.
async function run(config) {
  const apiLoaded = (window.hcaptchaElixirTemplate ??= loadApi({
    src: config.src,
    onload: ONLOAD,
    nonce: config.nonce,
  }).then(
    () => {
      callGlobal(config.onload);
      return true;
    },
    () => false,
  ));

  const container = document.getElementById(config.id);
  if (!container) return;

  const form = container.closest("form");
  if (config.invisible && !form) return;

  const { options, watch } = config.invisible
    ? withWatchdog(config.widget)
    : { options: config.widget };
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
    clearToken(form);
    sendForm(submitter);
  };

  const onSubmit = async (event) => {
    if (sending) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (busy) return;
    busy = true;
    const submitter = event.submitter ?? undefined;

    const ready = await settleWithin(apiLoaded, LOAD_TIMEOUT_MS, false);
    // The browser ignores requestSubmit while this submit event runs. Wait one task so the
    // send happens after it.
    await new Promise((resolve) => window.setTimeout(resolve));
    if (!ready || widgetId === undefined) return sendWithoutToken(submitter);

    const { token, dismissed } = await solve({ hcaptcha: window.hcaptcha, id: widgetId, watch });
    if (dismissed) {
      busy = false;
      return;
    }
    if (!token) return sendWithoutToken(submitter);

    callGlobal(config.callback, token);
    writeToken(form, token);
    sendForm(submitter);
  };

  form.addEventListener("submit", onSubmit, true);
  window.addEventListener("pageshow", (event) => {
    if (event.persisted) busy = false;
  });

  return render();
}

run(__CONFIG__);
