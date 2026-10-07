import { defineConfig } from "@playwright/test";

const port = process.env.PORT || "4040";

export default defineConfig({
  testDir: ".",
  testMatch: "*.spec.js",
  timeout: 60_000,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: process.env.CI ? [["list"], ["github"]] : "list",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    launchOptions: {
      executablePath: process.env.CHROMIUM_PATH || undefined,
      args: ["--no-sandbox"],
    },
  },
  webServer: {
    command: "elixir server.exs",
    url: `http://127.0.0.1:${port}/health`,
    timeout: 600_000,
    reuseExistingServer: !process.env.CI,
    env: { PORT: port },
  },
});
