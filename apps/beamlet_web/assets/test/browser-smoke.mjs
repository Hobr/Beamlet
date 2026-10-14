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
const violations = []
await context.exposeBinding("recordCSPViolation", (_source, violation) => violations.push(violation))
await context.addInitScript(() => {
  window.cspViolationCount = 0
  document.addEventListener("securitypolicyviolation", event => {
    window.cspViolationCount++
    window.recordCSPViolation({directive: event.effectiveDirective, blockedURI: event.blockedURI})
  })
})
context.on("page", page => page.on("pageerror", error => errors.push(error.message)))
const page = await context.newPage()
// Older Playwright Firefox waitForFunction uses page-side eval, which a strict
// production CSP correctly rejects. Poll from Node instead of weakening CSP.
const waitUntil = async predicate => {
  const deadline = Date.now() + 15000
  while (Date.now() < deadline) {
    if (await predicate()) return
    await new Promise(resolve => setTimeout(resolve, 50))
  }
  assert.fail("Timed out waiting for browser state")
}
const waitTheme = (target, theme, preference) => waitUntil(async () =>
  await target.locator("html").getAttribute("data-theme") === theme &&
  await target.locator("html").getAttribute("data-theme-preference") === preference
)

try {
  const response = await page.goto(baseURL)
  assert.equal(response.status(), 200)
  const policy = response.headers()["content-security-policy"]
  const scriptPolicy = policy.split(";").map(value => value.trim())
    .find(value => value.startsWith("script-src "))
  assert.ok(scriptPolicy.includes("'self'"))
  assert.ok(!scriptPolicy.includes("'unsafe-inline'"))
  assert.ok(policy.includes("script-src-attr 'none'"))
  if (process.env.BEAMLET_DEV_TOOLS) {
    // Tidewave deliberately enables eval and embedding for contextual testing.
    assert.ok(scriptPolicy.includes("'unsafe-eval'"))
    assert.ok(scriptPolicy.includes("https://tidewave.ai"))
    assert.ok(scriptPolicy.includes("http://127.0.0.1:4007"))
  } else {
    assert.ok(!policy.includes("unsafe-eval"))
    assert.ok(!policy.includes("127.0.0.1:4007"))
    assert.ok(!policy.includes("tidewave.ai"))
    assert.ok(policy.includes("frame-ancestors 'none'"))
  }
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
  await waitUntil(() => page.evaluate(() => window.liveSocket?.isConnected()))
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
  if (process.env.BEAMLET_DEV_TOOLS) {
    await waitUntil(() => page.evaluate(() => window.liveReloader?.socket.isConnected()))
    assert.equal(await page.locator('script[src$="/assets/live_debugger/client.js"]').count(), 1)
    await page.setViewportSize({width: 1280, height: 900})
    assert.equal((await page.goto(`${baseURL}/dev/dashboard`)).status(), 200)
    await page.locator("[data-phx-main].phx-connected").waitFor()
  }

  // Normal application and development tools must work without CSP violations.
  assert.deepEqual(errors, [])
  assert.deepEqual(violations, [])

  // Check enforcement, not merely the presence of a response header.
  await page.evaluate(() => {
    const script = document.createElement("script")
    script.textContent = "window.untrustedInlineExecuted = true"
    document.head.append(script)
    script.remove()

    const button = document.createElement("button")
    button.setAttribute("onclick", "window.untrustedHandlerExecuted = true")
    document.body.append(button)
    button.click()
    button.remove()
  })
  await waitUntil(() => page.evaluate(() => window.cspViolationCount >= 2))
  assert.equal(await page.evaluate(() => window.untrustedInlineExecuted === true), false)
  assert.equal(await page.evaluate(() => window.untrustedHandlerExecuted === true), false)
  assert.ok(violations.some(event => event.directive === "script-src-elem" && event.blockedURI === "inline"))
  assert.ok(violations.some(event => event.directive === "script-src-attr" && event.blockedURI === "inline"))
  console.log("Browser smoke passed: themes, LiveView form/menu/dialog, mobile layout, development tools when enabled, CSP enforcement, no unexpected JS/CSP errors.")
} finally {
  await context.close()
  await browser.close()
}
