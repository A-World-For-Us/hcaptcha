import { expect, test } from "@playwright/test";

const TEST_TOKEN = "10000000-aaaa-bbbb-cccc-000000000001";
const TEST_SITEKEY = "10000000-ffff-ffff-ffff-000000000001";

async function trackPage(page) {
  const posts = [];
  const violations = [];

  page.on("request", (request) => {
    if (request.method() === "POST" && new URL(request.url()).hostname === "127.0.0.1") {
      posts.push({ path: new URL(request.url()).pathname, body: request.postData() ?? "" });
    }
  });
  await page.exposeFunction("reportCspViolation", (text) => violations.push(text));
  await page.addInitScript(() => {
    document.addEventListener("securitypolicyviolation", (event) => {
      window.reportCspViolation(`${event.violatedDirective} ${event.blockedURI}`);
    });
  });

  return { posts, violations };
}

async function countExecutes(page, delayMs = 0) {
  let count = 0;
  await page.exposeFunction("reportExecute", () => count++);
  await page.addInitScript((delay) => {
    let api;
    Object.defineProperty(window, "hcaptcha", {
      configurable: true,
      get: () => api,
      set: (value) => {
        api = value;
        const execute = value.execute.bind(value);
        value.execute = async (...args) => {
          window.reportExecute();
          await new Promise((resolve) => setTimeout(resolve, delay));
          return execute(...args);
        };
      },
    });
  }, delayMs);
  return () => count;
}

const verifyPosts = (tracked) => tracked.posts.filter((post) => post.path === "/verify");
const field = (post, name) => new URLSearchParams(post.body).get(name);

async function openLogin(page) {
  await page.goto("/");
  await page.waitForFunction(() => window.liveSocket?.isConnected());
  await expect(page.locator("#captcha")).toHaveAttribute("data-sitekey", TEST_SITEKEY);
}

const invisiblePages = [
  { name: "template", open: (page) => page.goto("/invisible"), fill: async () => {} },
  {
    name: "LiveView component",
    open: openLogin,
    fill: (page) => page.fill("#email", "a@example.com"),
  },
];

const blocked = [
  { name: "the hCaptcha script is blocked", pattern: /https:\/\/js\.hcaptcha\.com\// },
  {
    name: "only the other hCaptcha hosts are blocked",
    pattern: /^https:\/\/(?!js\.hcaptcha\.com\/)[^/]*hcaptcha\.com\//,
    timeout: 30_000,
  },
];

for (const { name, open, fill } of invisiblePages) {
  test.describe(`${name}, invisible`, () => {
    test("runs one execute and sends one request for a triple click", async ({ page }) => {
      const tracked = await trackPage(page);
      const executes = await countExecutes(page, 1500);
      await open(page);
      await fill(page);
      await page.click("#submit-button", { clickCount: 3, delay: 20 });

      await expect(page.locator("body")).toHaveText("ok");
      expect(verifyPosts(tracked)).toHaveLength(1);
      expect(executes()).toBe(1);
    });

    for (const { name: blockedName, pattern, timeout } of blocked) {
      test(`posts without a token when ${blockedName}`, async ({ page }) => {
        const tracked = await trackPage(page);
        await page.route(pattern, (route) => route.abort());
        await open(page);
        await fill(page);
        await page.click("#submit-button");

        await expect(page.locator("body")).toHaveText("missing_input_response", { timeout });
        expect(verifyPosts(tracked)).toHaveLength(1);
        expect(field(verifyPosts(tracked)[0], "h-captcha-response") ?? "").toBe("");
      });
    }
  });
}

test.describe("invisible widget", () => {
  test("verifies the test token without a CSP violation", async ({ page }) => {
    const tracked = await trackPage(page);
    await page.goto("/invisible");
    await page.click("#submit-button");

    await expect(page.locator("body")).toHaveText("ok");
    expect(verifyPosts(tracked)).toHaveLength(1);
    expect(field(verifyPosts(tracked)[0], "h-captcha-response")).toBe(TEST_TOKEN);
    expect(field(verifyPosts(tracked)[0], "name")).toBe("x");
    expect(tracked.violations).toEqual([]);
  });

  test("submits an unrelated form once with no captcha", async ({ page }) => {
    const tracked = await trackPage(page);
    await page.goto("/invisible");
    await page.click("#other-button");

    await expect(page.locator("body")).toHaveText("other-ok");
    expect(tracked.posts.map((post) => post.path)).toEqual(["/other"]);
    expect(tracked.posts[0].body).not.toContain("h-captcha-response");
  });
});

test.describe("checkbox widget", () => {
  test("verifies the test token after the box is ticked", async ({ page }) => {
    const tracked = await trackPage(page);
    await page.goto("/checkbox");
    await page.frameLocator("iframe[title*='checkbox']").locator("#checkbox").click();
    await expect(page.locator("[name='h-captcha-response']").first()).not.toHaveValue("");
    await page.click("#submit-button");

    await expect(page.locator("body")).toHaveText("ok");
    expect(field(verifyPosts(tracked)[0], "h-captcha-response")).toBe(TEST_TOKEN);
    expect(tracked.violations).toEqual([]);
  });
});

test.describe("LiveView component", () => {
  test("posts the test token with the CSRF token after a native submit", async ({ page }) => {
    const tracked = await trackPage(page);
    await openLogin(page);
    await page.fill("#email", "a@example.com");
    await page.click("#submit-button");

    await expect(page.locator("body")).toHaveText("ok");
    expect(verifyPosts(tracked)).toHaveLength(1);
    const body = new URLSearchParams(verifyPosts(tracked)[0].body);
    expect(body.get("h-captcha-response")).toBe(TEST_TOKEN);
    expect(body.get("_csrf_token")).toBeTruthy();
    expect(tracked.violations).toEqual([]);
  });

  test("ignores a server event without the widget id", async ({ page }) => {
    const tracked = await trackPage(page);
    const executes = await countExecutes(page);
    await openLogin(page);
    await page.evaluate(() => window.dispatchEvent(new CustomEvent("phx:hcaptcha:execute")));
    await page.waitForTimeout(1500);

    expect(executes()).toBe(0);
    expect(tracked.posts).toEqual([]);
  });
});

test.describe("hCaptcha API", () => {
  test("rejects a closed challenge with the string challenge-closed", async ({ page }) => {
    await page.goto("/health");
    const rejection = await page.evaluate(async (sitekey) => {
      const loaded = new Promise((resolve) => (window.probeLoaded = resolve));
      const script = document.createElement("script");
      script.src = "https://js.hcaptcha.com/1/api.js?render=explicit&onload=probeLoaded";
      document.head.appendChild(script);
      await loaded;

      const el = document.createElement("div");
      document.body.appendChild(el);
      const id = window.hcaptcha.render(el, { sitekey, size: "invisible" });
      const pending = window.hcaptcha.execute(id, { async: true });
      window.hcaptcha.close(id);

      try {
        await pending;
      } catch (error) {
        return { type: typeof error, value: String(error) };
      }
    }, TEST_SITEKEY);

    expect(rejection).toEqual({ type: "string", value: "challenge-closed" });
  });
});
