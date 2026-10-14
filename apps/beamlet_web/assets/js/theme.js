// This separate, blocking same-origin bundle applies the theme before paint.
// Keeping it external lets the browser reject all untrusted inline scripts.
(() => {
  const key = "phx:theme"
  const media = window.matchMedia("(prefers-color-scheme: dark)")
  const normalize = value => ["light", "dark"].includes(value) ? value : "system"
  let preference = "system"
  try { preference = normalize(localStorage.getItem(key)) } catch (_) {}

  const resolved = () => preference === "system" ? (media.matches ? "dark" : "light") : preference
  const apply = () => {
    const theme = resolved()
    const root = document.documentElement
    root.dataset.theme = theme
    root.dataset.themePreference = preference
    root.classList.toggle("dark", theme === "dark")
    document.querySelectorAll("[data-phx-theme]").forEach(button => {
      button.setAttribute("aria-pressed", String(button.dataset.phxTheme === preference))
    })
    window.dispatchEvent(new CustomEvent("petal:scheme-changed", {
      detail: {preference, resolved: theme}
    }))
  }
  const set = value => {
    preference = normalize(value)
    try {
      if (preference === "system") localStorage.removeItem(key)
      else localStorage.setItem(key, preference)
    } catch (_) {}
    apply()
  }

  window.PetalColorScheme = {preference: () => preference, resolved, set}
  media.addEventListener("change", () => preference === "system" && apply())
  window.addEventListener("storage", event => {
    if (event.key === key || event.key === null) {
      preference = normalize(event.newValue)
      apply()
    }
  })
  window.addEventListener("phx:set-theme", event => {
    const control = event.target.closest("[data-phx-theme]")
    if (control) set(control.dataset.phxTheme)
  })
  window.addEventListener("phx:sync-theme", apply)
  document.addEventListener("DOMContentLoaded", apply)
  apply()
})()
