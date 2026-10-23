export const FIELD_NAME = "h-captcha-response";
export const CHALLENGE_TIMEOUT_MS = 20000;
export const LOAD_TIMEOUT_MS = 10000;

const DISMISSED = ["challenge-closed", "challenge-expired"];

export const apiReady = () => typeof window.hcaptcha?.render === "function";

const errorCode = (error) => (typeof error === "string" ? error : error?.message);

export function callGlobal(name, ...args) {
  if (typeof window[name] !== "function") return;
  try {
    window[name](...args);
  } catch (error) {
    window.reportError?.(error);
  }
}

export function loadApi({ src, onload, nonce }) {
  return new Promise((resolve, reject) => {
    if (apiReady()) return resolve(window.hcaptcha);

    const script = document.createElement("script");

    const settle = (error) => {
      if (!error && apiReady()) return resolve(window.hcaptcha);
      script.remove();
      reject(error ?? new Error("hCaptcha API has no render function"));
    };

    window[onload] = () => settle();

    script.src = `${src}&onload=${onload}`;
    script.async = true;
    if (nonce) script.nonce = nonce;
    script.onerror = () => settle(new Error("hCaptcha script failed to load"));
    document.head.append(script);
  });
}

export async function settleWithin(promise, ms, fallback) {
  let timer;
  const timeout = new Promise((resolve) => {
    timer = window.setTimeout(() => resolve(fallback), ms);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    window.clearTimeout(timer);
  }
}

export function withWatchdog(options) {
  const watch = { timer: undefined };
  return {
    options: { ...options, "open-callback": () => window.clearTimeout(watch.timer) },
    watch,
  };
}

export async function solve({ hcaptcha, id, watch }) {
  const timeout = new Promise((_, reject) => {
    watch.timer = window.setTimeout(() => reject("challenge-timeout"), CHALLENGE_TIMEOUT_MS);
  });
  let token = "";
  let dismissed = false;
  try {
    ({ response: token } = await Promise.race([hcaptcha.execute(id, { async: true }), timeout]));
  } catch (error) {
    dismissed = DISMISSED.includes(errorCode(error));
  } finally {
    window.clearTimeout(watch.timer);
  }
  try {
    hcaptcha.reset(id);
  } catch {}
  return { token, dismissed };
}

const responseField = (form) => form.querySelector(`[name="${FIELD_NAME}"]`);

export function writeToken(form, token) {
  let field = responseField(form);
  if (!field) {
    field = Object.assign(document.createElement("input"), { type: "hidden", name: FIELD_NAME });
    form.append(field);
  }
  field.value = token;
}

export function clearToken(form) {
  const field = responseField(form);
  if (field) field.value = "";
}
