import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { JSDOM, VirtualConsole } from "jsdom";
import { describe, expect, it } from "vitest";

const SOURCE = readFileSync(resolve(process.cwd(), "lib/hcaptcha/template.js"), "utf8");
const SRC = "https://js.hcaptcha.com/1/api.js?render=explicit";

function page(body) {
  const dom = new JSDOM(`<!doctype html><body>${body}</body>`, {
    runScripts: "outside-only",
    virtualConsole: new VirtualConsole(),
  });
  const win = dom.window;
  const timers = [];
  win.setTimeout = (fn, ms) => timers.push({ fn, ms, live: true });
  win.clearTimeout = (id) => {
    if (timers[id - 1]) timers[id - 1].live = false;
  };

  const sent = [];
  const events = [];
  const hooked = new WeakSet();
  const hook = () => {
    win.document.querySelectorAll("form").forEach((form) => {
      if (hooked.has(form)) return;
      hooked.add(form);
      form.addEventListener("submit", (event) => {
        events.push({ form: form.id, prevented: event.defaultPrevented, submitter: event.submitter });
        if (!event.defaultPrevented) {
          sent.push({ form: form.id, submitter: event.submitter, data: new win.FormData(form, event.submitter) });
          event.preventDefault();
        }
      });
    });
  };
  const proto = win.HTMLFormElement.prototype;
  const nativeSubmit = proto.submit;
  proto.submit = function () {
    sent.push({ form: this.id, submitter: null, native: true, data: new win.FormData(this) });
  };

  const log = [];
  const api = {
    renders: [],
    executes: [],
    throwOn: null,
    render(el, options) {
      if (api.throwOn === el.id) throw new Error("bad param");
      api.renders.push({ el, options });
      return api.renders.length;
    },
    execute(id) {
      log.push("execute");
      api.executes.push(id);
    },
    reset(id) {
      log.push("reset");
    },
  };

  const run = (...configs) => {
    for (const config of configs) {
      const cfg = { invisible: true, src: SRC, nonce: null, callback: null, onload: null, ...config };
      win.eval(SOURCE.replace("__CONFIG__", JSON.stringify(cfg)));
    }
    hook();
  };
  const loadApi = () => {
    win.hcaptcha = api;
    win.hcaptchaElixirTemplateOnload();
  };
  const scripts = () => [...win.document.head.querySelectorAll("script")];
  const submit = (selector = "form") => win.document.querySelector(selector).requestSubmit();

  return { win, api, run, loadApi, scripts, submit, sent, events, timers, log, nativeSubmit };
}

const FORM = `<form id="f"><div id="w1" class="h-captcha extra" data-sitekey="k" data-size="invisible"></div>
  <button id="go" name="go" value="1">Go</button></form>`;

describe("invisible widget", () => {
  it("listens on its own form only", () => {
    const p = page(`${FORM}<form id="other"><button id="b2">x</button></form>`);
    p.run({ id: "w1" });
    p.loadApi();

    p.submit("#other");

    expect(p.events).toEqual([expect.objectContaining({ form: "other", prevented: false })]);
    expect(p.api.executes).toEqual([]);
  });

  it("waits for the API after an early submit, then executes once", () => {
    const p = page(FORM);
    p.run({ id: "w1" });

    p.submit();
    p.submit();
    expect(p.api.executes).toEqual([]);
    expect(p.sent).toEqual([]);

    p.loadApi();
    expect(p.api.executes).toEqual([1]);
    p.submit();
    expect(p.api.executes).toEqual([1]);
  });

  it("renders with the data attributes, resets, calls the user callback and sends the form once", () => {
    const p = page(FORM);
    const tokens = [];
    p.win.mine = (token) => tokens.push(token);
    p.run({ id: "w1", callback: "mine" });
    p.loadApi();
    p.submit();
    const { callback, "error-callback": error } = p.api.renders[0].options;

    expect(p.api.renders[0].options).toMatchObject({ sitekey: "k", size: "invisible" });
    callback("tok");
    error();

    expect(tokens).toEqual(["tok"]);
    expect(p.log).toEqual(["execute", "reset"]);
    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].data.get("h-captcha-response")).toBe("tok");
  });

  it("writes the token into the field hCaptcha created", () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    p.loadApi();
    const field = p.win.document.createElement("textarea");
    field.name = "h-captcha-response";
    p.win.document.getElementById("w1").appendChild(field);
    p.submit();

    p.api.renders[0].options.callback("tok");

    expect(field.value).toBe("tok");
    expect(p.win.document.querySelectorAll('[name="h-captcha-response"]')).toHaveLength(1);
  });

  it("keeps the clicked button, on a form that has an input named submit", () => {
    const p = page(FORM.replace("</form>", '<input name="submit" value="x"></form>'));
    p.run({ id: "w1" });
    p.loadApi();
    p.win.document.getElementById("go").click();
    p.api.renders[0].options.callback("tok");

    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].submitter.id).toBe("go");
    expect(p.sent[0].data.get("go")).toBe("1");
  });

  it("falls back to submit() without requestSubmit", () => {
    const p = page(FORM);
    p.win.HTMLFormElement.prototype.requestSubmit = undefined;
    p.run({ id: "w1" });
    p.loadApi();
    p.win.document.getElementById("f").dispatchEvent(new p.win.Event("submit", { cancelable: true }));
    p.api.renders[0].options.callback("tok");

    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].native).toBe(true);
  });

  it("shows other submit listeners only the final submit", () => {
    const p = page(FORM);
    const form = p.win.document.getElementById("f");
    let onForm = 0;
    let onDocument = 0;
    form.addEventListener("submit", () => onForm++);
    p.win.document.addEventListener("submit", () => onDocument++);
    p.run({ id: "w1" });
    p.loadApi();

    p.submit();
    expect([onForm, onDocument]).toEqual([0, 0]);

    p.api.renders[0].options.callback("tok");
    expect([onForm, onDocument]).toEqual([1, 1]);
    expect(p.sent).toHaveLength(1);
  });

  it("releases the guard on close, on challenge expiry and on back-forward cache return", () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    p.loadApi();
    const options = p.api.renders[0].options;

    p.submit();
    options["close-callback"]();
    p.submit();
    options["chalexpired-callback"]();
    p.submit();
    p.win.dispatchEvent(Object.assign(new p.win.Event("pageshow"), { persisted: true }));
    p.submit();

    expect(p.api.executes).toHaveLength(4);
    expect(p.log.filter((entry) => entry === "reset")).toHaveLength(1);
    expect(p.sent).toEqual([]);
  });
});

describe("loading", () => {
  it("sends the form without a token when the script fails to load, and later submits natively", () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    p.submit();

    p.scripts()[0].onerror();

    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].data.get("h-captcha-response")).toBeNull();
    expect(p.api.executes).toEqual([]);

    p.submit();
    expect(p.sent).toHaveLength(2);
  });

  it("sends the form when the script never calls back", () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    p.submit();

    expect(p.timers[0].ms).toBe(10000);
    p.timers[0].fn();

    expect(p.sent).toHaveLength(1);
  });

  it("does not block a second widget when a render throws", () => {
    const p = page(
      `${FORM}<form id="f2"><div id="w2" class="h-captcha" data-sitekey="k" data-size="invisible"></div></form>`,
    );
    p.api.throwOn = "w1";
    p.run({ id: "w1" }, { id: "w2" });
    p.submit("#f");
    p.submit("#f2");

    p.loadApi();

    expect(p.sent.map((entry) => entry.form)).toEqual(["f"]);
    expect(p.api.executes).toEqual([1]);
  });

  it("adds the API script once for two widgets, with the nonce", () => {
    const p = page(
      `${FORM}<form id="f2"><div id="w2" class="h-captcha" data-sitekey="k" data-size="invisible"></div></form>`,
    );
    p.run({ id: "w1", nonce: "abc" }, { id: "w2", nonce: "abc" });

    expect(p.scripts()).toHaveLength(1);
    expect(p.scripts()[0].nonce).toBe("abc");
    expect(p.scripts()[0].src).toBe(SRC);
  });

  it("calls a named onload function once for several widgets", () => {
    const p = page(
      `${FORM}<form id="f2"><div id="w2" class="h-captcha" data-sitekey="k" data-size="invisible"></div></form>`,
    );
    let calls = 0;
    p.win.mine = () => calls++;
    p.run({ id: "w1", onload: "mine" }, { id: "w2", onload: "mine" });
    p.loadApi();

    expect(calls).toBe(1);
  });
});

describe("checkbox widget", () => {
  it("renders explicitly with its data attributes and adds no submit listener", () => {
    const p = page(
      '<form id="f"><div id="w1" class="h-captcha" data-sitekey="k" data-theme="dark" data-callback="cb"></div></form>',
    );
    p.run({ id: "w1", invisible: false });
    p.loadApi();
    p.submit();

    expect(p.api.renders[0].options).toEqual({ sitekey: "k", theme: "dark", callback: "cb" });
    expect(p.events[0].prevented).toBe(false);
  });
});
