import { beforeEach, describe, expect, it, vi } from "vitest";

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

let Hcaptcha;
let api;
let submit;

function fakeApi() {
  return {
    render: vi.fn(() => "widget-1"),
    execute: vi.fn((id, options) => {
      if (!options?.async) throw new Error("execute needs { async: true }");
      return Promise.resolve({ response: "token-1", key: "k" });
    }),
    reset: vi.fn(),
    remove: vi.fn(),
  };
}

function scripts() {
  return [...document.head.querySelectorAll("script")];
}

function onloadName(script) {
  return new URL(script.src).searchParams.get("onload");
}

function bootApi() {
  window.hcaptcha = api;
  window[onloadName(scripts()[0])]();
}

function mount({ id = "captcha", attrs = {}, method = "post" } = {}) {
  const form = document.createElement("form");
  form.method = method;
  const el = document.createElement("div");
  el.id = id;
  Object.assign(el.dataset, {
    sitekey: "site",
    src: "https://js.hcaptcha.com/1/api.js?render=explicit",
    ...attrs,
  });
  form.appendChild(el);
  document.body.appendChild(form);

  const handlers = {};
  const hook = Object.create(Hcaptcha);
  hook.el = el;
  hook.handleEvent = (name, fn) => (handlers[name] = fn);
  hook.mounted();
  return {
    hook,
    el,
    form,
    handlers,
    push: (payload = { id: el.id }) => handlers["hcaptcha:execute"](payload),
  };
}

const tokenField = (form) => form.querySelector('[name="h-captcha-response"]');

const pending = () => {
  let resolve;
  const promise = new Promise((r) => (resolve = r));
  return { promise, resolve };
};

async function withFakeTimers(run) {
  vi.useFakeTimers();
  try {
    await run();
  } finally {
    vi.useRealTimers();
  }
}

beforeEach(async () => {
  vi.restoreAllMocks();
  submit = vi.spyOn(HTMLFormElement.prototype, "submit").mockImplementation(() => {});
  document.head.innerHTML = "";
  document.body.innerHTML = "";
  delete window.hcaptcha;
  api = fakeApi();
  vi.resetModules();
  ({ Hcaptcha } = await import("../js/hcaptcha.js"));
});

describe("script loading", () => {
  it("adds one script with the page nonce and the language for two hooks", () => {
    const pageScript = document.createElement("script");
    pageScript.nonce = "n0nce";
    document.body.append(pageScript);
    mount({ id: "a", attrs: { src: "https://js.hcaptcha.com/1/api.js?render=explicit&hl=fr" } });
    mount({ id: "b" });

    expect(scripts()).toHaveLength(1);
    expect(scripts()[0].nonce).toBe("n0nce");
    expect(scripts()[0].src).toMatch(
      /^https:\/\/js\.hcaptcha\.com\/1\/api\.js\?render=explicit&hl=fr&onload=hcaptchaLiveViewOnload\d+$/,
    );
  });

  it("adds no nonce when the page has no script with one", () => {
    mount();

    expect(scripts()[0].nonce).toBe("");
  });

  it("renders every hook only after the onload callback", async () => {
    mount({ id: "a" });
    mount({ id: "b" });
    await flush();
    expect(api.render).not.toHaveBeenCalled();

    bootApi();
    await flush();

    expect(api.render).toHaveBeenCalledTimes(2);
    expect(api.render).toHaveBeenCalledWith(
      expect.any(HTMLElement),
      expect.objectContaining({ sitekey: "site", size: "invisible" }),
    );
  });

  it("reuses an existing window.hcaptcha and adds no script", async () => {
    window.hcaptcha = api;
    mount();
    await flush();

    expect(scripts()).toHaveLength(0);
    expect(api.render).toHaveBeenCalledTimes(1);
  });

  it("loads again after a failure", async () => {
    mount();
    scripts()[0].onerror();
    await flush();
    mount({ id: "b" });

    expect(scripts()).toHaveLength(1);
  });
});

describe("challenge", () => {
  it("writes the token, keeps the other fields and submits natively", async () => {
    const { form, push } = mount();
    form.insertAdjacentHTML(
      "afterbegin",
      '<input type="hidden" name="_csrf_token" value="csrf-1"><input name="submit" value="x">',
    );
    let sent;
    submit.mockImplementation(function () {
      sent = Object.fromEntries(new FormData(this));
    });
    bootApi();
    push();
    await flush();

    expect(api.execute).toHaveBeenCalledWith("widget-1", { async: true });
    expect(submit).toHaveBeenCalledTimes(1);
    expect(submit.mock.contexts[0]).toBe(form);
    expect(sent).toEqual({
      _csrf_token: "csrf-1",
      submit: "x",
      "h-captcha-response": "token-1",
    });
  });

  it("writes the token into the field hCaptcha created, after the reset", async () => {
    const { el, form, push } = mount();
    const textarea = document.createElement("textarea");
    textarea.name = "h-captcha-response";
    el.appendChild(textarea);
    api.reset.mockImplementation(() => (textarea.value = ""));
    let atSubmit;
    submit.mockImplementation(() => (atSubmit = textarea.value));
    bootApi();
    push();
    await flush();

    expect(form.querySelectorAll('[name="h-captcha-response"]')).toHaveLength(1);
    expect(atSubmit).toBe("token-1");
  });

  it("submits even when reset throws", async () => {
    api.reset.mockImplementation(() => {
      throw new Error("boom");
    });
    const { form, push } = mount();
    bootApi();
    push();
    await flush();

    expect(tokenField(form).value).toBe("token-1");
    expect(submit).toHaveBeenCalledTimes(1);
  });

  it.each([[{}], [{ id: "other" }]])("ignores the event payload %j", async (payload) => {
    const { handlers } = mount();
    bootApi();
    handlers["hcaptcha:execute"](payload);
    await flush();

    expect(api.execute).not.toHaveBeenCalled();
    expect(submit).not.toHaveBeenCalled();
  });

  it("runs one challenge at a time across hooks", async () => {
    api.execute.mockReturnValue(new Promise(() => {}));
    const a = mount({ id: "a" });
    const b = mount({ id: "b" });
    bootApi();
    a.push();
    b.push();
    a.push();
    await flush();

    expect(api.execute).toHaveBeenCalledTimes(1);
  });

  it.each(["challenge-closed", "challenge-expired"])(
    "does not submit on %s and frees the lock",
    async (code) => {
      api.execute.mockRejectedValueOnce(code);
      const a = mount({ id: "a" });
      const b = mount({ id: "b" });
      bootApi();
      a.push();
      await flush();

      expect(api.reset).toHaveBeenCalledWith("widget-1");
      expect(submit).not.toHaveBeenCalled();

      b.push();
      await flush();

      expect(api.execute).toHaveBeenCalledTimes(2);
      expect(tokenField(b.form).value).toBe("token-1");
      expect(submit).toHaveBeenCalledTimes(1);
    },
  );
});

describe("failures submit without a token", () => {
  it.each([
    ["another error", () => api.execute.mockRejectedValueOnce("network-error"), bootApi],
    ["a script load error", () => {}, () => scripts()[0].onerror()],
    [
      "an API without render",
      () => {},
      () => {
        window.hcaptcha = {};
        window[onloadName(scripts()[0])]();
      },
    ],
  ])("after %s", async (_name, arrange, trigger) => {
    arrange();
    const { form, push } = mount();
    trigger();
    push();
    await flush();

    expect(tokenField(form).value).toBe("");
    expect(submit).toHaveBeenCalledTimes(1);
  });

  it("after a render failure, and logs it", async () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    api.render.mockImplementation(() => {
      throw new Error("missing sitekey");
    });
    const { form, push } = mount();
    bootApi();
    push();
    await flush();

    expect(error).toHaveBeenCalled();
    expect(api.execute).not.toHaveBeenCalled();
    expect(tokenField(form).value).toBe("");
    expect(submit).toHaveBeenCalledTimes(1);
  });

  it("clears a token left in the form from an earlier send", async () => {
    const { form, push } = mount();
    form.insertAdjacentHTML(
      "beforeend",
      '<input type="hidden" name="h-captcha-response" value="old-token">',
    );
    scripts()[0].onerror();
    push();
    await flush();

    expect(tokenField(form).value).toBe("");
    expect(submit).toHaveBeenCalledTimes(1);
  });

  it("after 10 s, and still renders the widget when the script loads late", () =>
    withFakeTimers(async () => {
      const { push } = mount();
      push();
      await vi.advanceTimersByTimeAsync(10000);
      expect(submit).toHaveBeenCalledTimes(1);
      expect(api.render).not.toHaveBeenCalled();

      bootApi();
      await vi.advanceTimersByTimeAsync(0);
      expect(api.render).toHaveBeenCalledTimes(1);
    }));

  it("after 10 s without the onload callback", () =>
    withFakeTimers(async () => {
      const { form, push } = mount();
      push();
      await vi.advanceTimersByTimeAsync(9999);
      expect(submit).not.toHaveBeenCalled();

      await vi.advanceTimersByTimeAsync(1);
      expect(submit).toHaveBeenCalledTimes(1);
      expect(tokenField(form).value).toBe("");
    }));

  it("after 20 s when the challenge never opens", () =>
    withFakeTimers(async () => {
      api.execute.mockReturnValue(new Promise(() => {}));
      const { form, push } = mount();
      bootApi();
      await vi.advanceTimersByTimeAsync(0);
      push();
      await vi.advanceTimersByTimeAsync(19999);
      expect(submit).not.toHaveBeenCalled();

      await vi.advanceTimersByTimeAsync(1);
      expect(submit).toHaveBeenCalledTimes(1);
      expect(tokenField(form).value).toBe("");
      expect(api.reset).toHaveBeenCalledWith("widget-1");
    }));

  it("not once the challenge is open", () =>
    withFakeTimers(async () => {
      const execute = pending();
      api.execute.mockReturnValue(execute.promise);
      const { form, push } = mount();
      bootApi();
      await vi.advanceTimersByTimeAsync(0);
      push();
      await vi.advanceTimersByTimeAsync(0);
      api.render.mock.calls[0][1]["open-callback"]();
      await vi.advanceTimersByTimeAsync(10 * 60 * 1000);
      expect(submit).not.toHaveBeenCalled();

      execute.resolve({ response: "late-token" });
      await vi.advanceTimersByTimeAsync(0);
      expect(tokenField(form).value).toBe("late-token");
      expect(submit).toHaveBeenCalledTimes(1);
    }));
});

describe("teardown", () => {
  it("removes the widget when destroyed", async () => {
    const { hook } = mount();
    bootApi();
    await flush();
    hook.destroyed();
    await flush();

    expect(api.remove).toHaveBeenCalledWith("widget-1");
  });

  it("does not render when destroyed before the API loads", async () => {
    const { hook } = mount();
    hook.destroyed();
    bootApi();
    await flush();

    expect(api.render).not.toHaveBeenCalled();
  });
});

describe("mount", () => {
  it("logs an error and does nothing without a form", () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const el = document.createElement("div");
    el.id = "lonely";
    document.body.appendChild(el);
    const hook = Object.create(Hcaptcha);
    hook.el = el;
    hook.handleEvent = vi.fn();
    hook.mounted();

    expect(error).toHaveBeenCalledWith(expect.stringContaining("#lonely"));
    expect(hook.handleEvent).not.toHaveBeenCalled();
    expect(scripts()).toHaveLength(0);
  });

  it("logs an error and does not mount when the form method is not post", () => {
    const error = vi.spyOn(console, "error").mockImplementation(() => {});
    const { handlers } = mount({ id: "login", method: "get" });

    expect(error).toHaveBeenCalledWith(expect.stringContaining("#login"));
    expect(handlers).toEqual({});
    expect(scripts()).toHaveLength(0);
  });
});
