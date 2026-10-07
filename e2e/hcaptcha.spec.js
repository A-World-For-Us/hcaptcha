import { expect, test } from "@playwright/test";

const TEST_TOKEN = "10000000-aaaa-bbbb-cccc-000000000001";

async function trackPage(page) {
  const posts = [];
  const violations = [];

  page.on("request", (request) => {
    if (request.method() === "POST" && new URL(request.url()).hostname === "127.0.0.1") {
      posts.push({ path: new URL(request.url()).pathname, body: request.postData() ?? "" });
    }
  });
  page.on("console", (message) => {
    if (/content security policy|refused to/i.test(message.text())) violations.push(message.text());
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
  const calls = [];
  await page.exposeFunction("reportExecute", () => calls.push(1));
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
  return calls;
}

const verifyPosts = (tracked) => tracked.posts.filter((post) => post.path === "/verify");
const tokenOf = (post) => new URLSearchParams(post.body).get("h-captcha-response");

test.describe("invisible widget", () => {
  test("verifies the test token without a CSP violation", async ({ page }) => {
    const tracked = await trackPage(page);
    await page.goto("/invisible");
    await page.click("#submit-button");

    await expect(page.locator("body")).toHaveText("ok");
    expect(verifyPosts(tracked)).toHaveLength(1);
    expect(tokenOf(verifyPosts(tracked)[0])).toBe(TEST_TOKEN);
    expect(new URLSearchParams(verifyPosts(tracked)[0].body).get("name")).toBe("x");
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

  test("posts without a token when the hCaptcha script is blocked", async ({ page }) => {
    const tracked = await trackPage(page);
    await page.route(/https:\/\/js\.hcaptcha\.com\//, (route) => route.abort());
    await page.goto("/invisible");
    await page.click("#submit-button");

    await expect(page.locator("body")).toHaveText("missing_input_response");
    expect(verifyPosts(tracked)).toHaveLength(1);
    expect(verifyPosts(tracked)[0].body).not.toContain("h-captcha-response");
  });

  test("posts without a token when only the other hCaptcha hosts are blocked", async ({ page }) => {
    const tracked = await trackPage(page);
    await page.route(/^https:\/\/(?!js\.hcaptcha\.com\/)[^/]*hcaptcha\.com\//, (route) =>
      route.abort(),
    );
    await page.goto("/invisible");
    await page.click("#submit-button");

    await expect(page.locator("body")).toHaveText("missing_input_response", { timeout: 15_000 });
    expect(verifyPosts(tracked)).toHaveLength(1);
    expect(tokenOf(verifyPosts(tracked)[0]) ?? "").toBe("");
  });

  test("runs one execute and sends one request for a triple click", async ({ page }) => {
    const tracked = await trackPage(page);
    const calls = await countExecutes(page, 1500);
    await page.goto("/invisible");
    await page.click("#submit-button", { clickCount: 3, delay: 20 });

    await expect(page.locator("body")).toHaveText("ok");
    expect(verifyPosts(tracked)).toHaveLength(1);
    expect(calls).toHaveLength(1);
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
    expect(tokenOf(verifyPosts(tracked)[0])).toBe(TEST_TOKEN);
    expect(tracked.violations).toEqual([]);
  });
});
