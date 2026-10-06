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
  win.setTimeout = (fn, ms) => (ms ? timers.push({ fn, ms, live: true }) : setTimeout(fn));
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
        events.push({
          form: form.id,
          prevented: event.defaultPrevented,
          submitter: event.submitter,
        });
        if (!event.defaultPrevented) {
          sent.push({
            form: form.id,
            submitter: event.submitter,
            data: new win.FormData(form, event.submitter),
          });
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
      const cfg = {
        invisible: true,
        src: SRC,
        nonce: null,
        callback: null,
        onload: null,
        ...config,
      };
      win.eval(SOURCE.replace("__CONFIG__", JSON.stringify(cfg)));
    }
    hook();
  };
  const tick = () => new Promise((done) => setTimeout(done));
  const settle = async () => {
    await tick();
    await tick();
  };
  const loadApi = async () => {
    win.hcaptcha = api;
    win.hcaptchaElixirTemplateOnload();
    await settle();
  };
  const fail = async (fn) => {
    fn();
    await settle();
  };
  const scripts = () => [...win.document.head.querySelectorAll("script")];
  const submit = async (selector = "form") => {
    win.document.querySelector(selector).requestSubmit();
    await settle();
  };

  return {
    win,
    api,
    run,
    loadApi,
    fail,
    settle,
    scripts,
    submit,
    sent,
    events,
    timers,
    log,
    nativeSubmit,
  };
}

const FORM = `<form id="f"><div id="w1" class="h-captcha extra" data-sitekey="k" data-size="invisible"></div>
  <button id="go" name="go" value="1">Go</button></form>`;

describe("invisible widget", () => {
  it("listens on its own form only", async () => {
    const p = page(`${FORM}<form id="other"><button id="b2">x</button></form>`);
    p.run({ id: "w1" });
    await p.loadApi();

    await p.submit("#other");

    expect(p.events).toEqual([expect.objectContaining({ form: "other", prevented: false })]);
    expect(p.api.executes).toEqual([]);
  });

  it("waits for the API after an early submit, then executes once", async () => {
    const p = page(FORM);
    p.run({ id: "w1" });

    await p.submit();
    await p.submit();
    expect(p.api.executes).toEqual([]);
    expect(p.sent).toEqual([]);

    await p.loadApi();
    expect(p.api.executes).toEqual([1]);
    await p.submit();
    expect(p.api.executes).toEqual([1]);
  });

  it("renders with the data attributes, resets, calls the user callback and sends the form once", async () => {
    const p = page(FORM);
    const tokens = [];
    p.win.mine = (token) => tokens.push(token);
    p.run({ id: "w1", callback: "mine" });
    await p.loadApi();
    await p.submit();
    const { callback, "error-callback": error } = p.api.renders[0].options;

    expect(p.api.renders[0].options).toMatchObject({ sitekey: "k", size: "invisible" });
    callback("tok");
    error();

    expect(tokens).toEqual(["tok"]);
    expect(p.log).toEqual(["execute", "reset"]);
    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].data.get("h-captcha-response")).toBe("tok");
  });

  it("writes the token into the field hCaptcha created", async () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    await p.loadApi();
    const field = p.win.document.createElement("textarea");
    field.name = "h-captcha-response";
    p.win.document.getElementById("w1").appendChild(field);
    await p.submit();

    p.api.renders[0].options.callback("tok");

    expect(field.value).toBe("tok");
    expect(p.win.document.querySelectorAll('[name="h-captcha-response"]')).toHaveLength(1);
  });

  it("keeps the clicked button, on a form that has an input named submit", async () => {
    const p = page(FORM.replace("</form>", '<input name="submit" value="x"></form>'));
    p.run({ id: "w1" });
    await p.loadApi();
    p.win.document.getElementById("go").click();
    await p.settle();
    p.api.renders[0].options.callback("tok");

    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].submitter.id).toBe("go");
    expect(p.sent[0].data.get("go")).toBe("1");
  });

  it("falls back to submit() without requestSubmit", async () => {
    const p = page(FORM);
    p.win.HTMLFormElement.prototype.requestSubmit = undefined;
    p.run({ id: "w1" });
    await p.loadApi();
    p.win.document
      .getElementById("f")
      .dispatchEvent(new p.win.Event("submit", { cancelable: true }));
    await p.settle();
    p.api.renders[0].options.callback("tok");

    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].native).toBe(true);
  });

  it("shows other submit listeners only the final submit", async () => {
    const p = page(FORM);
    const form = p.win.document.getElementById("f");
    let onForm = 0;
    let onDocument = 0;
    form.addEventListener("submit", () => onForm++);
    p.win.document.addEventListener("submit", () => onDocument++);
    p.run({ id: "w1" });
    await p.loadApi();

    await p.submit();
    expect([onForm, onDocument]).toEqual([0, 0]);

    p.api.renders[0].options.callback("tok");
    expect([onForm, onDocument]).toEqual([1, 1]);
    expect(p.sent).toHaveLength(1);
  });

  it("releases the guard on close, on challenge expiry and on back-forward cache return", async () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    await p.loadApi();
    const options = p.api.renders[0].options;

    await p.submit();
    options["close-callback"]();
    await p.submit();
    options["chalexpired-callback"]();
    await p.submit();
    p.win.dispatchEvent(Object.assign(new p.win.Event("pageshow"), { persisted: true }));
    await p.submit();

    expect(p.api.executes).toHaveLength(4);
    expect(p.log.filter((entry) => entry === "reset")).toHaveLength(1);
    expect(p.sent).toEqual([]);
  });
});

describe("loading", () => {
  it("sends the form without a token when the script fails to load, and later submits natively", async () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    await p.submit();

    await p.fail(() => p.scripts()[0].onerror());

    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].data.get("h-captcha-response")).toBeNull();
    expect(p.api.executes).toEqual([]);

    await p.submit();
    expect(p.sent).toHaveLength(2);
  });

  it("sends the form after the event has finished dispatching when the script already failed", async () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    await p.fail(() => p.scripts()[0].onerror());

    p.win.document.querySelector("form").requestSubmit();
    for (let turn = 0; turn < 5; turn++) await Promise.resolve();
    expect(p.sent).toEqual([]);

    await p.settle();
    expect(p.sent).toHaveLength(1);
  });

  it("sends the form without a token when the challenge neither answers nor opens in 10 seconds", async () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    await p.loadApi();
    await p.submit();

    expect(p.timers.at(-1).ms).toBe(10000);
    await p.fail(() => p.timers.at(-1).fn());

    expect(p.sent).toHaveLength(1);
    expect(p.sent[0].data.get("h-captcha-response")).toBeNull();
  });

  it("keeps waiting when the challenge window is open", async () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    await p.loadApi();
    await p.submit();
    p.api.renders[0].options["open-callback"]();
    await p.fail(() => p.timers.at(-1).fn());

    expect(p.sent).toEqual([]);
  });

  it("sends the form when the script never calls back", async () => {
    const p = page(FORM);
    p.run({ id: "w1" });
    await p.submit();

    expect(p.timers[0].ms).toBe(10000);
    await p.fail(() => p.timers[0].fn());

    expect(p.sent).toHaveLength(1);
  });

  it("does not block a second widget when a render throws", async () => {
    const p = page(
      `${FORM}<form id="f2"><div id="w2" class="h-captcha" data-sitekey="k" data-size="invisible"></div></form>`,
    );
    p.api.throwOn = "w1";
    p.run({ id: "w1" }, { id: "w2" });
    await p.submit("#f");
    await p.submit("#f2");

    await p.loadApi();

    expect(p.sent.map((entry) => entry.form)).toEqual(["f"]);
    expect(p.api.executes).toEqual([1]);
  });

  it("adds the API script once for two widgets, with the nonce", async () => {
    const p = page(
      `${FORM}<form id="f2"><div id="w2" class="h-captcha" data-sitekey="k" data-size="invisible"></div></form>`,
    );
    p.run({ id: "w1", nonce: "abc" }, { id: "w2", nonce: "abc" });

    expect(p.scripts()).toHaveLength(1);
    expect(p.scripts()[0].nonce).toBe("abc");
    expect(p.scripts()[0].src).toBe(SRC);
  });

  it("calls a named onload function once for several widgets", async () => {
    const p = page(
      `${FORM}<form id="f2"><div id="w2" class="h-captcha" data-sitekey="k" data-size="invisible"></div></form>`,
    );
    let calls = 0;
    p.win.mine = () => calls++;
    p.run({ id: "w1", onload: "mine" }, { id: "w2", onload: "mine" });
    await p.loadApi();

    expect(calls).toBe(1);
  });
});

describe("checkbox widget", () => {
  it("renders explicitly with its data attributes and adds no submit listener", async () => {
    const p = page(
      '<form id="f"><div id="w1" class="h-captcha" data-sitekey="k" data-theme="dark" data-callback="cb"></div></form>',
    );
    p.run({ id: "w1", invisible: false });
    await p.loadApi();
    await p.submit();

    expect(p.api.renders[0].options).toEqual({ sitekey: "k", theme: "dark", callback: "cb" });
    expect(p.events[0].prevented).toBe(false);
  });
});
