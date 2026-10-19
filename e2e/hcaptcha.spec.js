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

    await expect(page.locator("body")).toHaveText("missing_input_response", { timeout: 30_000 });
    expect(verifyPosts(tracked)).toHaveLength(1);
    expect(field(verifyPosts(tracked)[0], "h-captcha-response") ?? "").toBe("");
  });

  test("runs one execute and sends one request for a triple click", async ({ page }) => {
    const tracked = await trackPage(page);
    const executes = await countExecutes(page, 300);
    await page.goto("/invisible");
    await page.click("#submit-button", { clickCount: 3, delay: 20 });

    await expect(page.locator("body")).toHaveText("ok");
    expect(verifyPosts(tracked)).toHaveLength(1);
    expect(executes()).toBe(1);
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
