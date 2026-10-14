import assert from "node:assert/strict"
import {createRequire} from "node:module"

// Optional browser check: install Playwright outside this project, or provide
// PLAYWRIGHT_MODULE pointing at an existing playwright/playwright-core package.
const require = createRequire(import.meta.url)
const {firefox} = require(process.env.PLAYWRIGHT_MODULE || "playwright")
const baseURL = process.env.BEAMLET_URL || "http://localhost:4000"
const browser = await firefox.launch({headless: true})
const context = await browser.newContext({colorScheme: "dark", viewport: {width: 1280, height: 900}})
const errors = []
context.on("page", page => page.on("pageerror", error => errors.push(error.message)))
const page = await context.newPage()
const waitTheme = (target, theme, preference) => target.waitForFunction(
  ({theme, preference}) => document.documentElement.dataset.theme === theme &&
    document.documentElement.dataset.themePreference === preference,
  {theme, preference}
)

try {
  assert.equal((await page.goto(baseURL)).status(), 200)
  await waitTheme(page, "dark", "system")
  assert.equal(await page.locator("[data-phx-theme=system]").getAttribute("aria-pressed"), "true")
  const darkBackground = await page.evaluate(() => getComputedStyle(document.body).backgroundColor)

  // Click an icon, not just its button: event delegation must find the control.
  await page.locator("[data-phx-theme=light] span").click()
  await waitTheme(page, "light", "light")
  assert.equal(await page.evaluate(() => localStorage.getItem("phx:theme")), "light")
  assert.notEqual(await page.evaluate(() => getComputedStyle(document.body).backgroundColor), darkBackground)
  await page.reload()
  await waitTheme(page, "light", "light")

  const otherTab = await context.newPage()
  await otherTab.goto(baseURL)
  await waitTheme(otherTab, "light", "light")
  await page.locator("[data-phx-theme=dark]").click()
  await waitTheme(otherTab, "dark", "dark")
  await page.locator("[data-phx-theme=system]").click()
  await waitTheme(otherTab, "dark", "system")
  assert.equal(await page.evaluate(() => localStorage.getItem("phx:theme")), null)
  await page.emulateMedia({colorScheme: "light"})
  await waitTheme(page, "light", "system")
  await otherTab.close()

  // Navigate from a controller page to LiveView, then exercise real DOM hooks.
  await page.getByRole("link", {name: "Explore components"}).click()
  await page.waitForURL(`${baseURL}/components`)
  await page.waitForFunction(() => window.liveSocket?.isConnected())
  await page.getByRole("button", {name: "Preview greeting"}).click()
  await page.locator("#flash-error").waitFor({state: "visible"})
  await page.getByLabel("Name", {exact: true}).fill("<script>")
  await page.getByRole("button", {name: "Preview greeting"}).click()
  await page.getByText("Hello, <script>!").waitFor({state: "visible"})
  assert.equal(await page.locator("#flash-error").count(), 0)
  // A LiveView patch must not reset the selected theme's accessibility state.
  assert.equal(await page.locator("[data-phx-theme=system]").getAttribute("aria-pressed"), "true")

  await page.getByRole("button", {name: /Actions$/}).click()
  await page.getByRole("menuitem", {name: "Show notification"}).click()
  await page.locator("#flash-info").waitFor({state: "visible"})
  await page.locator("#flash-info").getByRole("button", {name: "close", exact: true}).click()
  await page.locator("#flash-info").waitFor({state: "hidden"})

  await page.getByRole("button", {name: "Open dialog"}).click()
  await page.getByRole("dialog").waitFor({state: "visible"})
  await page.keyboard.press("Escape")
  await page.locator("#preview-dialog").waitFor({state: "detached"})
  await page.getByRole("button", {name: "Open dialog"}).click()
  await page.getByRole("dialog").waitFor({state: "visible"})
  await page.getByRole("button", {name: "Done", exact: true}).click()
  await page.locator("#preview-dialog").waitFor({state: "detached"})

  await page.setViewportSize({width: 375, height: 812})
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true)
  await page.locator("[data-phx-theme=dark]").click()
  await waitTheme(page, "dark", "dark")
  assert.equal(await page.locator("#client-error").isVisible(), false)
  assert.equal(await page.locator("#server-error").isVisible(), false)
  assert.deepEqual(errors, [])
  console.log("Browser smoke passed: themes, persistence, cross-tab sync, system changes, LiveView form/menu/dialog, mobile layout, no JS errors.")
} finally {
  await context.close()
  await browser.close()
}
