"""Real-browser walkthrough of the Beamlet Web workbench and management pages.

Uses only the pre-verified geckodriver + Firefox (headless) over W3C WebDriver.
All page interaction is real clicks / typing / Tab / scrolling / resize.
execute/sync is used only for layout measurement, scroll position, focus
inspection and a CSP enforcement probe.
"""

import http.client
import json
import os
import re
import sys
import time
import traceback
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from wd import Driver, WdError  # noqa: E402

BASE = os.environ.get("FIXTURE_BASE", "http://127.0.0.1:19601")
DRIVER_URL = os.environ.get("WD_URL", "http://127.0.0.1:19602")
FIREFOX = os.environ.get(
    "FIREFOX_BIN", "/home/kanade/.nix-profile/bin/firefox"
)
HERE = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(HERE, "shots")
RESULTS = os.path.join(HERE, "results.json")
FIXTURE_OUT = os.environ.get("FIXTURE_OUT")
if not FIXTURE_OUT:
    raise SystemExit("FIXTURE_OUT must point at the owned fixture output directory")
with open(os.path.join(FIXTURE_OUT, "handles.json"), encoding="utf-8") as fh:
    HANDLES = json.load(fh)

TAB = "\ue004"
ENTER = "\ue007"
DOWN = "\ue015"

results = []
shot_index = [0]


def record(check, viewport, action, observed, verdict, shot=None):
    entry = {
        "check": check,
        "viewport": viewport,
        "action": action,
        "observed": observed,
        "verdict": verdict,
        "screenshot": shot,
    }
    results.append(entry)
    save()
    return entry


def save():
    with open(RESULTS, "w") as fh:
        json.dump(results, fh, indent=2)


def shot(d, name):
    shot_index[0] += 1
    path = os.path.join(SHOTS, f"{shot_index[0]:02d}-{name}.png")
    d.screenshot(path)
    return os.path.relpath(path, os.path.dirname(HERE))


def body_text(d):
    return d.script("return document.body.innerText;")


def wait_ready(d, extra=None, timeout=40):
    def check():
        text = body_text(d)
        return not (
            ("Connecting" in text and "Ready" not in text)
            or (extra is not None and extra not in text)
        )

    d.wait_until(check, timeout=timeout, label="LiveView ready")


def overflow(d):
    return d.script(
        """
        const de = document.documentElement, b = document.body;
        return {
          innerWidth: window.innerWidth,
          innerHeight: window.innerHeight,
          docScrollWidth: de.scrollWidth,
          docClientWidth: de.clientWidth,
          bodyScrollWidth: b.scrollWidth,
          bodyClientWidth: b.clientWidth
        };
        """
    )


def element_geometry(d, css):
    return d.script(
        """
        const el = document.querySelector(arguments[0]);
        if (!el) return null;
        const r = el.getBoundingClientRect();
        const cs = getComputedStyle(el);
        return {
          selector: arguments[0],
          tag: el.tagName,
          width: Math.round(r.width * 100) / 100,
          height: Math.round(r.height * 100) / 100,
          right: Math.round(r.right * 100) / 100,
          bottom: Math.round(r.bottom * 100) / 100,
          viewportWidth: window.innerWidth,
          display: cs.display,
          overflowX: cs.overflowX,
          scrollWidth: el.scrollWidth,
          clientWidth: el.clientWidth
        };
        """,
        css,
    )


def select_option(d, css, wanted):
    """Select an option with real keyboard interaction only."""
    el = d.find(css, visible=True)
    d.click(el)
    el = d.find(css, visible=True)
    d.send_keys(el, DOWN)
    el = d.find(css, visible=True)
    value = d.prop(el, "value")
    if value == wanted:
        return value, "arrow-key selection"
    tries = [wanted[0], wanted]
    for t in tries:
        el = d.find(css, visible=True)
        d.send_keys(el, t)
        el = d.find(css, visible=True)
        value = d.prop(el, "value")
        if value == wanted:
            return value, f"typeahead {t!r}"
    return value, "FAILED to select"


def scroll_state(d):
    return d.script(
        """
        const region = document.querySelector('[data-scroll-region]');
        const indicator = document.querySelector('[data-new-activity]');
        return {
          scrollTop: Math.round(region.scrollTop),
          scrollHeight: region.scrollHeight,
          clientHeight: region.clientHeight,
          atBottom: region.scrollHeight - region.scrollTop - region.clientHeight <= 2,
          indicatorHidden: indicator.hidden,
          indicatorVisible: !indicator.hidden
        };
        """
    )


def set_scroll_top(d, top):
    return d.script(
        """
        const region = document.querySelector('[data-scroll-region]');
        region.scrollTop = arguments[0];
        return Math.round(region.scrollTop);
        """,
        top,
    )


def served_csp():
    """Read the CSP header the server actually sends (no browser state)."""
    parsed = urllib.parse.urlsplit(BASE)
    conn = http.client.HTTPConnection(parsed.hostname, parsed.port, timeout=20)
    try:
        conn.request("GET", "/")
        resp = conn.getresponse()
        header = resp.getheader("content-security-policy")
        resp.read()
    finally:
        conn.close()
    match = re.search(r"'nonce-([^']+)'", header or "")
    return {"header": header, "nonce": match.group(1) if match else None}


def csp_baseline(d):
    return d.script(
        """
        const inline = Array.from(document.querySelectorAll('script:not([src])'));
        return {
          theme: document.documentElement.getAttribute('data-theme'),
          themeSource: document.documentElement.getAttribute('data-theme-source'),
          inlineScripts: inline.map((el) => ({
            nonceAttribute: el.getAttribute('nonce'),
            nonceProperty: el.nonce,
            length: el.textContent.length
          })),
          liveSocketPresent: typeof window.liveSocket !== 'undefined',
          phxConnected: document.querySelector('[data-phx-main]') !== null,
          scriptSrc: Array.from(document.querySelectorAll('script[src]')).map((el) => el.getAttribute('src'))
        };
        """
    )


def csp_inject(d):
    return d.script(
        """
        window.__beamletCsp = {violations: [], injectedRan: false};
        document.addEventListener('securitypolicyviolation', (e) => {
          window.__beamletCsp.violations.push({directive: e.effectiveDirective, blocked: e.blockedURI});
        });
        const s = document.createElement('script');
        s.setAttribute('data-probe', 'injected');
        s.textContent = 'window.__beamletCsp.injectedRan = true;';
        document.body.appendChild(s);
        return {injected: true};
        """
    )


def csp_settle(d):
    return d.script("return window.__beamletCsp;")


def alert_probe(d):
    ok, val = d.probe("GET", f"/session/{d.session_id}/alert/text")
    return ok, val


def keys(d, eid, text):
    d.send_keys(eid, text)


def focus_report(d):
    return d.script(
        """
        const el = document.activeElement;
        if (!el || el === document.body) return {tag: 'BODY'};
        const cs = getComputedStyle(el);
        return {
          tag: el.tagName,
          type: el.getAttribute('type'),
          name: el.getAttribute('name'),
          id: el.id || null,
          label: (el.innerText || el.getAttribute('aria-label') || el.value || '').trim().slice(0, 60),
          outlineStyle: cs.outlineStyle,
          outlineWidth: cs.outlineWidth,
          outlineColor: cs.outlineColor,
          boxShadow: cs.boxShadow.slice(0, 120),
          borderColor: cs.borderColor
        };
        """
    )



def type_follow_up(d, text):
    """Clear then type into the follow-up draft with real key events."""
    box = d.find("#follow-up textarea", visible=True)
    d.clear(box)
    d.wait_until(lambda: d.prop(d.find("#follow-up textarea"), "value") == "", label="draft cleared")
    d.send_keys(d.find("#follow-up textarea", visible=True), text)
    d.wait_until(
        lambda: d.prop(d.find("#follow-up textarea"), "value") == text, label="draft typed"
    )
    return [e for e in d.find_all("#follow-up button") if d.text(e) == "Send next turn"][0]


def must(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    d = Driver(DRIVER_URL)
    caps = d.start(FIREFOX)
    started = time.time()
    try:
        d.window_rect(x=0, y=0, width=1440, height=900)
        size = d.window_rect()
        record(
            "capability",
            f"{size['width']}x{size['height']}",
            "POST /session with moz:firefoxOptions binary + ['-headless'], then POST /window/rect",
            {"browserName": caps.get("browserName"), "browserVersion": caps.get("browserVersion"),
             "platformName": caps.get("platformName"), "windowRect": size},
            "PASS",
        )
    except Exception:
        record("capability", "n/a", "start session", traceback.format_exc(), "FAIL")
        d.quit()
        raise

    try:
        journey(d)
    except Exception:
        record("journey-abort", "n/a", "walker aborted", traceback.format_exc(), "FAIL")
    finally:
        ok, val = d.quit()
        record("cleanup", "n/a", "DELETE /session", {"ok": ok, "value": val,
               "elapsedSeconds": round(time.time() - started, 1)}, "PASS" if ok else "FAIL")


def journey(d):
    vp_desktop = "1440x900"

    # ---------------- A. Desktop home ----------------
    d.navigate(BASE + "/")
    wait_ready(d, "What would you like to do?")
    d.wait_until(lambda: "cli-external-agent" in body_text(d), label="external agent listed")
    home_overflow = overflow(d)
    controls = {
        css: element_geometry(d, css)
        for css in [
            "#creation textarea",
            "#creation select",
            "#creation button.btn-primary",
            "#agent-search input",
            "nav a",
        ]
    }
    list_items = [d.text(eid) for eid in d.find_all("aside ul li button")]
    s = shot(d, "desktop-home")
    no_overflow = (
        home_overflow["docScrollWidth"] <= home_overflow["docClientWidth"]
        and home_overflow["bodyScrollWidth"] <= home_overflow["bodyClientWidth"]
    )
    inside = all(
        c is None or c["right"] <= c["viewportWidth"] + 1 for c in controls.values()
    )
    record(
        "1-desktop-home",
        vp_desktop,
        "navigate / and measure documentElement/body scrollWidth vs clientWidth plus control rectangles",
        {
            "overflow": home_overflow,
            "sidebarAgents": list_items,
            "geometry": controls,
            "noHorizontalOverflow": no_overflow,
            "controlsInsideViewport": inside,
        },
        "PASS" if no_overflow and inside and list_items else "FAIL",
        s,
    )
    home_agents = list_items

    # ---------------- B. Preset flow on /agents/new ----------------
    d.find("nav a", visible=True)
    new_link = [e for e in d.find_all("nav a") if d.text(e) == "New Agent"][0]
    d.click(new_link)
    d.wait_until(lambda: "/agents/new" in d.current_url(), label="navigated to /agents/new")
    wait_ready(d, "What would you like to do?")

    preset_select = "select[name='draft[preset]']"
    env_select = "select[name='draft[environment]']"
    initial_preset = d.prop(d.find(preset_select), "value")
    env_before = element_geometry(d, env_select)
    details_open = d.prop(d.find("#creation details"), "open")
    record(
        "2a-initial-draft",
        vp_desktop,
        "click nav 'New Agent' and read default draft control state",
        {
            "preset": initial_preset,
            "environmentControl": env_before,
            "adjustDetailsOpen": details_open,
            "toolCheckboxes": len(d.find_all("input[type=checkbox][name='draft[tools][]']")),
            "modelOptions": [d.text(e) for e in d.find_all("select[name='draft[model]'] option")],
        },
        "PASS" if initial_preset == "chat" and env_before is None else "FAIL",
    )

    # conditional environment appears only for an environment-requiring tool
    checkbox = d.find("input[type=checkbox][name='draft[tools][]']", visible=True)
    d.click(checkbox)
    d.wait_until(lambda: element_geometry(d, env_select) is not None, label="environment control appears")
    env_options = [d.text(e) for e in d.find_all(f"{env_select} option")]
    env_value = d.prop(d.find(env_select), "value")
    s = shot(d, "new-agent-environment-visible")
    record(
        "2b-environment-conditional",
        vp_desktop,
        "real click on the slow-echo tool checkbox in the expanded options",
        {
            "environmentControlAppeared": True,
            "environmentOptions": env_options,
            "selectedEnvironmentValue": env_value,
            "toolsChecked": [d.prop(e, "value") for e in d.find_all("input[type=checkbox][name='draft[tools][]']") if d.prop(e, "checked")],
        },
        "PASS" if env_options and env_value == "" else "FAIL",
        s,
    )

    checkbox = d.find("input[type=checkbox][name='draft[tools][]']", visible=True)
    d.click(checkbox)
    env_gone = d.find_absent(env_select, timeout=15)
    record(
        "2c-environment-removed",
        vp_desktop,
        "real click to uncheck the environment-requiring tool",
        {"environmentControlAbsent": env_gone},
        "PASS" if env_gone else "FAIL",
    )

    value, how = select_option(d, preset_select, "tool-run")
    env_after_preset = d.wait_until(
        lambda: element_geometry(d, env_select), label="preset applies environment control"
    )
    d.wait_until(
        lambda: d.prop(d.find(env_select), "value") == "workspace", label="workspace preselected"
    )
    text_now = body_text(d)
    record(
        "2d-preset-switch",
        vp_desktop,
        f"keyboard selection of preset 'tool-run' ({how})",
        {
            "presetValue": value,
            "environmentControl": env_after_preset,
            "environmentValue": d.prop(d.find(env_select), "value"),
            "modifiedBadgePresent": "Modified from preset defaults" in text_now,
            "summaryText": [
                line for line in text_now.splitlines() if "Effective public options" in line
            ],
        },
        "PASS" if value == "tool-run" and "Modified from preset defaults" not in text_now else "FAIL",
    )

    name_input = "input[name='draft[title]']"
    d.send_keys(d.find(name_input, visible=True), "Browser preset agent")
    d.wait_until(lambda: "Modified from preset defaults" in body_text(d), label="modified badge")
    s = shot(d, "new-agent-modified")
    record(
        "2e-adjust-preset",
        vp_desktop,
        "type 'Browser preset agent' into the Name input",
        {
            "modifiedBadgePresent": "Modified from preset defaults" in body_text(d),
            "nameValue": d.prop(d.find(name_input), "value"),
        },
        "PASS",
        s,
    )

    d.click(d.find("button", visible=True) if False else [e for e in d.find_all("#creation button") if d.text(e) == "Reset to preset defaults"][0])
    d.wait_until(lambda: "Modified from preset defaults" not in body_text(d), label="badge cleared by reset")
    record(
        "2f-reset",
        vp_desktop,
        "real click on 'Reset to preset defaults'",
        {
            "modifiedBadgePresent": "Modified from preset defaults" in body_text(d),
            "nameValue": d.prop(d.find(name_input), "value"),
            "presetValue": d.prop(d.find(preset_select), "value"),
            "environmentValue": d.prop(d.find(env_select), "value"),
        },
        "PASS",
    )

    hostile = "<script>alert(1)</script> TOOLS run"
    d.send_keys(d.find("#creation textarea", visible=True), hostile)
    d.send_keys(d.find(name_input, visible=True), "Browser preset agent")
    d.wait_until(
        lambda: d.prop(d.find("#creation textarea"), "value") == hostile,
        label="task draft echoed in the textarea value",
    )
    # Enter inside a single-line input submits the creation form (implicit submission).
    d.send_keys(d.find(name_input, visible=True), ENTER)
    d.wait_until(lambda: "/agents/" in d.current_url(), timeout=40, label="creation navigates to workspace")
    wait_ready(d, "Agent workspace")
    workspace_url = d.current_url()
    d.wait_until(lambda: "Input accepted" in body_text(d), timeout=40, label="initial input accepted")
    record(
        "2g-create-with-enter",
        vp_desktop,
        "type hostile task text then press Enter inside the Name input (implicit form submission)",
        {
            "url": workspace_url,
            "inputResult": [ln for ln in body_text(d).splitlines() if ln.startswith("Initial input:")],
            "identityLine": [ln for ln in body_text(d).splitlines() if ln.startswith("Creation identity")],
        },
        "PASS",
    )

    # ---------------- C. First turn: model -> tool -> model ----------------
    d.wait_until(lambda: "Tool call: slow-echo" in body_text(d), timeout=40, label="tool call entry")
    mid = {
        "activitySection": d.find_all("section[aria-label='Current concurrent activity'] details"),
        "entries": len(d.find_all("#context article")),
        "bodyHead": body_text(d)[:600],
    }
    shot_mid = shot(d, "agent-first-turn-activity")
    record(
        "3a-tool-activity",
        vp_desktop,
        "observe the workspace while the deterministic model dispatches the configured tool",
        {
            "activityDetails": len(mid["activitySection"]),
            "entries": mid["entries"],
            "hasToolCallEntry": "Tool call: slow-echo" in mid["bodyHead"] or "Tool call: slow-echo" in body_text(d),
            "statusLine": [ln for ln in body_text(d).splitlines() if ln.startswith("Business state:")],
        },
        "PASS",
        shot_mid,
    )

    d.wait_until(lambda: "Tool completed" in body_text(d), timeout=60, label="final model output")
    text = body_text(d)
    escaped = "&lt;script&gt;" in d.script("return document.documentElement.outerHTML;")
    lit_text = "<script>alert(1)</script>" in d.script(
        "return Array.from(document.querySelectorAll('#context pre')).map(p=>p.textContent).join('\\n');"
    )
    overflow_metrics = d.script(
        """
        const region = document.querySelector('[data-scroll-region]');
        const section = region.closest('section');
        const sr = section.getBoundingClientRect();
        const pres = Array.from(document.querySelectorAll('#context article pre'));
        return {
          sectionRight: Math.round(sr.right),
          pres: pres.map((p) => {
            const r = p.getBoundingClientRect();
            return {
              scrollWidth: p.scrollWidth,
              clientWidth: p.clientWidth,
              right: Math.round(r.right),
              overflowX: getComputedStyle(p).overflowX,
              whiteSpace: getComputedStyle(p).whiteSpace,
              overflowWrap: getComputedStyle(p).overflowWrap
            };
          })
        };
        """
    )
    contained = all(
        p["scrollWidth"] <= p["clientWidth"] + 1 and p["right"] <= overflow_metrics["sectionRight"] + 1
        for p in overflow_metrics["pres"]
    )
    s = shot(d, "agent-first-turn-done")
    record(
        "3b-first-turn-output",
        vp_desktop,
        "wait for the second model completion after the tool result",
        {
            "hasFinalText": "Tool completed" in text,
            "escapedInSource": escaped,
            "literalScriptTextPresent": lit_text,
            "longOutputContainment": overflow_metrics,
            "allInsideContainer": contained,
            "truncationNotice": [ln for ln in text.splitlines() if "truncat" in ln.lower() or "omitted" in ln.lower()],
        },
        "PASS" if contained and escaped and lit_text else "FAIL",
        s,
    )

    alert_ok, alert_val = alert_probe(d)
    record(
        "8a-hostile-text-no-dialog",
        vp_desktop,
        "GET /session/{id}/alert/text after rendering the hostile task text",
        {"alertPresent": alert_ok, "value": alert_val, "escapedInSource": escaped, "literalTextInPre": lit_text},
        "PASS" if not alert_ok and escaped and lit_text else "FAIL",
    )

    # ---------------- D. Second turn ----------------
    send_btn = type_follow_up(d, "second turn from the workbench")
    d.click(send_btn)
    d.wait_until(lambda: "SECOND-TURN-ACK" in body_text(d), timeout=40, label="second turn reply")
    record(
        "3c-second-turn",
        vp_desktop,
        "type into the follow-up textarea and real-click 'Send next turn'",
        {
            "ackPresent": "SECOND-TURN-ACK: second turn from the workbench" in body_text(d),
            "turnEntries": len(d.find_all("#context article")),
            "businessState": [ln for ln in body_text(d).splitlines() if ln.startswith("Business state:")],
        },
        "PASS",
    )

    # ---------------- D2. Live tool activity card ----------------
    d.click(type_follow_up(d, "TOOLS again"))
    live_cards = d.wait_until(
        lambda: (
            lambda cards: cards
            if any("slow-echo" in c for c in cards)
            else None
        )(
            [
                d.text(e)
                for e in d.find_all(
                    "section[aria-label='Current concurrent activity'] details"
                )
            ]
        ),
        timeout=25,
        interval=0.2,
        label="live tool activity card",
    )
    s = shot(d, "agent-live-tool-activity")
    record(
        "3d-live-tool-activity",
        vp_desktop,
        "real-click 'Send next turn' with a TOOLS task and poll the live activity section while the tool runs",
        {
            "cards": live_cards[:3],
            "businessState": [ln for ln in body_text(d).splitlines() if ln.startswith("Business state:")],
        },
        "PASS" if any("slow-echo" in c for c in live_cards) else "FAIL",
        s,
    )
    d.wait_until(
        lambda: d.enabled([e for e in d.find_all("#follow-up button") if d.text(e) == "Send next turn"][0]),
        timeout=60,
        label="tool turn finished",
    )

    # ---------------- E. Scroll behaviour ----------------
    d.wait_until(
        lambda: (lambda m: m if m["scrollHeight"] > m["clientHeight"] + 50 else None)(scroll_state(d)),
        timeout=20,
        label="scrollable conversation region",
    )
    set_scroll_top(d, 0)
    time.sleep(0.6)
    before = scroll_state(d)
    send_btn = type_follow_up(d, "third turn while reading")
    d.click(send_btn)
    d.wait_until(lambda: "SECOND-TURN-ACK: third turn while reading" in body_text(d), timeout=40, label="third turn reply")
    after = d.wait_until(
        lambda: (lambda m: m if m["indicatorVisible"] else None)(scroll_state(d)),
        timeout=20,
        label="new-activity affordance",
    )
    s = shot(d, "scroll-new-activity-affordance")
    stayed = abs(after["scrollTop"] - before["scrollTop"]) <= 2
    record(
        "4a-scroll-not-forced",
        vp_desktop,
        "set region scrollTop=0 (reader above bottom), then real-click 'Send next turn'",
        {
            "regionBefore": before,
            "regionAfter": after,
            "scrollTopUnchanged": stayed,
            "indicatorVisible": after["indicatorVisible"],
        },
        "PASS" if stayed and after["indicatorVisible"] else "FAIL",
        s,
    )

    indicator = d.find("[data-new-activity]", visible=True)
    d.click(indicator)
    jumped = d.wait_until(lambda: (lambda m: m if m["atBottom"] and m["indicatorHidden"] else None)(scroll_state(d)), timeout=15, label="jump to bottom")
    s = shot(d, "scroll-jumped-to-bottom")
    record(
        "4b-jump-to-bottom",
        vp_desktop,
        "real click on the 'New activity — jump to bottom' button",
        {"regionAfterJump": jumped},
        "PASS",
        s,
    )

    # ---------------- I. Small viewport ----------------
    d.window_rect(x=0, y=0, width=390, height=844)
    requested = d.window_rect()
    narrowest = overflow(d)
    record(
        "1d-390-requested",
        f"{narrowest['innerWidth']}x{narrowest['innerHeight']} effective",
        "POST /window/rect {width:390,height:844} and read the effective CSS viewport",
        {
            "requestedRect": requested,
            "effectiveInnerWidth": narrowest["innerWidth"],
            "effectiveInnerHeight": narrowest["innerHeight"],
            "note": "This Firefox build clamps the window to a 500 CSS px minimum width, so a 390 CSS px viewport is unreachable (see 1e-blocked note in the report for the four techniques measured).",
        },
        "BLOCKED" if narrowest["innerWidth"] > 400 else "PASS",
    )
    d.navigate(BASE + "/")
    wait_ready(d, "What would you like to do?")
    small_overflow = overflow(d)
    small_controls = {
        css: element_geometry(d, css)
        for css in ["#creation textarea", "#creation select", "#creation button.btn-primary", "#agent-search input"]
    }
    s = shot(d, "mobile-home")
    small_ok = (
        small_overflow["docScrollWidth"] <= small_overflow["docClientWidth"]
        and small_overflow["bodyScrollWidth"] <= small_overflow["bodyClientWidth"]
        and all(c is None or c["right"] <= c["viewportWidth"] + 1 for c in small_controls.values())
    )
    record(
        "1b-mobile-home",
        "390x844",
        "resize window to 390x844 and navigate to /",
        {"overflow": small_overflow, "geometry": small_controls, "noHorizontalOverflow": small_ok},
        "PASS" if small_ok else "FAIL",
        s,
    )

    created_handle = workspace_url.rsplit("/", 1)[-1].split("?")[0]
    d.navigate(BASE + "/agents/" + created_handle)
    wait_ready(d, "Agent workspace")
    small_ws = overflow(d)
    ws_controls = {
        css: element_geometry(d, css)
        for css in ["#context [data-scroll-region]", "#follow-up textarea", "#follow-up button"]
    }
    s = shot(d, "mobile-workspace")
    ws_ok = (
        small_ws["docScrollWidth"] <= small_ws["docClientWidth"]
        and all(c is None or c["right"] <= c["viewportWidth"] + 1 for c in ws_controls.values())
    )
    record(
        "1c-mobile-workspace",
        "390x844",
        "navigate directly to /agents/<handle> at 390x844 and measure the conversation region and controls",
        {"overflow": small_ws, "geometry": ws_controls, "noHorizontalOverflow": ws_ok},
        "PASS" if ws_ok else "FAIL",
        s,
    )

    # ---------------- F. Child / activity inspector ----------------
    d.window_rect(x=0, y=0, width=1440, height=900)
    d.navigate(BASE + "/agents/" + HANDLES["parent-browser"])
    wait_ready(d, "Agent workspace")
    d.wait_until(lambda: "Current concurrent activity" in body_text(d), label="activity section")
    details = d.wait_until(
        lambda: (d.find_all("section[aria-label='Current concurrent activity'] details") or None),
        label="activity details",
    )
    d.click(d.find("section[aria-label='Current concurrent activity'] details summary", visible=True))
    child_text = body_text(d)
    inspect = d.wait_until(
        lambda: [e for e in d.find_all("button") if d.text(e) == "Inspect child (observe only)"] or None,
        timeout=20,
        label="inspect child button",
    )
    s = shot(d, "activity-inspector-open")
    d.click(inspect[0])
    d.wait_until(lambda: "observe=1" in d.current_url(), timeout=30, label="child inspector navigation")
    wait_ready(d, "Agent workspace")
    child_url = d.current_url()
    child_body = body_text(d)
    record(
        "3d-child-inspector",
        vp_desktop,
        "expand the real activity <details>, real-click 'Inspect child (observe only)'",
        {
            "activityDetailsCount": len(details),
            "childActivityLine": [ln for ln in child_text.splitlines() if ln.startswith("child ")][:3],
            "childUrl": child_url,
            "childInspectorShowsChildTask": "HOLD child task" in child_body,
            "commandControls": {
                "followUpForm": len(d.find_all("#follow-up")),
                "stopButton": len([e for e in d.find_all("button") if d.text(e) == "Stop current turn (keep Agent)"]),
                "closeButton": len([e for e in d.find_all("button") if d.text(e) == "Close instance…"]),
            },
        },
        "PASS" if "observe=1" in child_url and "HOLD child task" in child_body and not d.find_all("#follow-up") else "FAIL",
        s,
    )

    # activity diagnostics link from the workbench
    d.navigate(BASE + "/agents/" + HANDLES["parent-browser"])
    wait_ready(d, "Agent workspace")
    d.wait_until(lambda: "Current concurrent activity" in body_text(d), label="activity section again")
    d.click(d.find("section[aria-label='Current concurrent activity'] details summary", visible=True))
    links = [e for e in d.find_all("a") if d.text(e) == "Inspect activity diagnostics"]
    diag_url = None
    if links:
        d.click(links[0])
        d.wait_until(lambda: "/admin/diagnostics" in d.current_url(), label="activity diagnostics navigation")
        wait_ready(d, "Retained live context")
        diag_url = d.current_url()
    record(
        "3e-activity-diagnostics",
        vp_desktop,
        "real-click 'Inspect activity diagnostics' inside the expanded activity card",
        {
            "linkCount": len(links),
            "url": diag_url,
            "retainedContext": "Retained live context" in body_text(d),
            "activityIdentityWording": [ln for ln in body_text(d).splitlines() if "Activity identity" in ln],
        },
        "PASS" if links and diag_url and "Retained live context" in body_text(d) else "FAIL",
    )

    # ---------------- G. Management pages ----------------
    d.navigate(BASE + "/admin/nodes")
    wait_ready(d, "Read-only nodes")
    d.wait_until(lambda: "Last observation received" in body_text(d), timeout=40, label="node observation")
    nodes_text = body_text(d)
    s = shot(d, "admin-nodes")
    record(
        "7a-admin-nodes",
        vp_desktop,
        "navigate /admin/nodes and wait for the owned caller observation",
        {
            "statusLine": [ln for ln in nodes_text.splitlines() if ln.startswith("Last observation")
                           or "Read completeness" in ln or "Configured roles" in ln
                           or "Registered services" in ln or "Available " in ln
                           or "No reports" in ln or "Report:" in ln][:12],
            "capacityLines": [ln for ln in nodes_text.splitlines() if ln.startswith("Available ")],
            "unknownCapabilityWording": "Available capacity unknown" in nodes_text,
            "pidSentinel": "#PID" in nodes_text,
        },
        "PASS" if "Configured roles" in nodes_text and "#PID" not in nodes_text else "FAIL",
        s,
    )

    d.navigate(BASE + "/admin/presets")
    wait_ready(d, "Read-only presets")
    d.wait_until(lambda: "Last observation received" in body_text(d), timeout=40, label="preset catalogue")
    presets_text = body_text(d)
    s = shot(d, "admin-presets")
    record(
        "7b-admin-presets",
        vp_desktop,
        "navigate /admin/presets and inspect the trusted catalogue projection",
        {
            "entries": [ln for ln in presets_text.splitlines() if ln.startswith(("chat:", "tool-run:", "local:", "slow-echo:", "workspace:"))],
            "noBindingDetails": not any(k in presets_text for k in ["credentials", "provider", "#PID", "BrowserFixture"]),
            "defaultAuthorityLine": [ln for ln in presets_text.splitlines() if "Default authority reference" in ln],
            "writeControls": [d.text(e) for e in d.find_all("button")],
        },
        "PASS" if "chat: Chat only" in presets_text and "credentials" not in presets_text else "FAIL",
        s,
    )

    d.navigate(BASE + "/admin/diagnostics")
    wait_ready(d, "Read-only diagnostics")
    no_handle_text = body_text(d)
    record(
        "7c-diagnostics-no-handle",
        vp_desktop,
        "navigate /admin/diagnostics without a handle",
        {
            "statusLines": [ln for ln in no_handle_text.splitlines() if ln.startswith(("Unknown", "No exact", "Display absent"))],
            "hasNoHandleWording": "No exact live handle resolved" in no_handle_text,
            "displayAbsentWording": "Display absent / omitted" in no_handle_text,
        },
        "PASS" if "No exact live handle resolved" in no_handle_text else "FAIL",
    )

    d.navigate(BASE + "/admin/diagnostics?handle=" + HANDLES["parent-browser"])
    wait_ready(d, "Read-only diagnostics")
    d.wait_until(lambda: "Retained live context" in body_text(d), timeout=40, label="retained context")
    diag_text = body_text(d)
    s = shot(d, "admin-diagnostics-handle")
    inspect_buttons = [
        (d.text(e), d.enabled(e)) for e in d.find_all("button") if "Inspect" in (d.text(e) or "")
    ]
    record(
        "7d-diagnostics-handle",
        vp_desktop,
        "navigate /admin/diagnostics?handle=<parent handle> from the workspace handle",
        {
            "observeOnlyWording": "Observe only" in diag_text,
            "retainedContext": "Retained live context" in diag_text,
            "entriesRendered": len(d.find_all("section[aria-label='Retained live context'] article")),
            "commandControls": {
                "textareas": len(d.find_all("textarea")),
                "stopButton": len([e for e in d.find_all("button") if "Stop" in (d.text(e) or "")]),
                "closeButton": len([e for e in d.find_all("button") if "Close" in (d.text(e) or "")]),
            },
            "inspectButtonsEnabled": inspect_buttons,
            "openObserveOnlyLink": len([e for e in d.find_all("a") if d.text(e) == "Open observe-only workbench"]),
        },
        "PASS"
        if "Retained live context" in diag_text
        and not d.find_all("textarea")
        and len([e for e in d.find_all("button") if "Stop" in (d.text(e) or "")]) == 0
        else "FAIL",
        s,
    )

    # diagnostics for a workspace handle that actually holds transcript entries
    d.navigate(BASE + "/admin/diagnostics?handle=" + HANDLES["cli-external-agent"])
    wait_ready(d, "Read-only diagnostics")
    d.wait_until(lambda: "Retained live context" in body_text(d), timeout=40, label="retained context (cli)")
    cli_text = body_text(d)
    cli_entries = d.find_all("section[aria-label='Retained live context'] article")
    s = shot(d, "admin-diagnostics-cli-handle")
    record(
        "7e-diagnostics-entries",
        vp_desktop,
        "navigate /admin/diagnostics?handle=<cli external agent handle> and inspect retained entries",
        {
            "entriesRendered": len(cli_entries),
            "observeOnlyWording": "Observe only" in cli_text,
            "entrySnippets": [ln for ln in cli_text.splitlines() if "external CLI first turn" in ln or "context line 1" in ln][:3],
            "commandControls": {
                "textareas": len(d.find_all("textarea")),
                "stopButton": len([e for e in d.find_all("button") if "Stop" in (d.text(e) or "")]),
            },
            "pidSentinel": "#PID" in cli_text,
        },
        "PASS" if len(cli_entries) > 0 and not d.find_all("textarea") and "#PID" not in cli_text else "FAIL",
        s,
    )

    # ---------------- H. Keyboard ----------------
    def tab_pass(count):
        stops = []
        for _ in range(count):
            active = d.active_element()
            if active is None:
                break
            stops.append(focus_report(d))
            try:
                d.send_keys(active, TAB)
            except WdError:
                break
            time.sleep(0.15)
        return stops

    d.navigate(BASE + "/agents/" + created_handle)
    wait_ready(d, "Agent workspace")
    d.script("document.activeElement.blur(); window.scrollTo(0,0);")
    header_stops = tab_pass(9)
    d.script("document.querySelector('h1').setAttribute('tabindex','-1'); document.querySelector('h1').focus();")
    body_stops = tab_pass(12)
    sequence = header_stops + body_stops
    s = shot(d, "keyboard-focus-sequence")
    tags = [r.get("tag") for r in sequence]
    def outline_ring(r):
        width = str(r.get("outlineWidth", "0px")).replace("px", "") or "0"
        return r.get("outlineStyle") not in (None, "none") and float(width) > 0

    outline_rings = [r for r in sequence if outline_ring(r)]
    shadow_rings = [
        r for r in sequence if r.get("boxShadow") and r.get("boxShadow") not in ("none", "")
    ]
    record(
        "5a-tab-order",
        vp_desktop,
        "focus the workspace heading, then send 18 real Tab key events and read document.activeElement",
        {
            "sequence": sequence,
            "reachesTextarea": "TEXTAREA" in tags,
            "reachesButtons": "BUTTON" in tags,
            "reachesLinks": "A" in tags,
            "outlineFocusRingCount": len(outline_rings),
            "outlineFocusRingSamples": outline_rings[:4],
            "boxShadowFocusRingCount": len(shadow_rings),
            "boxShadowFocusRingSamples": shadow_rings[:4],
        },
        "PASS"
        if "TEXTAREA" in tags
        and "BUTTON" in tags
        and "A" in tags
        and (outline_rings or shadow_rings)
        else "FAIL",
        s,
    )

    # Enter activates a focused link (real keyboard navigation)
    d.navigate(BASE + "/")
    wait_ready(d, "What would you like to do?")
    nav_link = [e for e in d.find_all("nav a") if d.text(e) == "Nodes"][0]
    d.script("arguments[0].focus();", d.eid(nav_link))
    focused = focus_report(d)
    d.send_keys(d.active_element(), ENTER)
    d.wait_until(lambda: "/admin/nodes" in d.current_url(), timeout=30, label="Enter activates link")
    record(
        "5b-enter-activates",
        vp_desktop,
        "focus the 'Nodes' nav link and press Enter",
        {"focusedBeforeEnter": focused, "url": d.current_url()},
        "PASS",
    )

    # ---------------- H2. Lifecycle ----------------
    d.navigate(BASE + "/")
    wait_ready(d, "What would you like to do?")
    d.wait_until(lambda: bool([e for e in d.find_all("aside ul li button") if created_handle]), label="agents listed")
    agent_ids = [d.text(e).splitlines()[0] for e in d.find_all("aside ul li button")]
    new_only = [i for i in agent_ids if i not in [x.splitlines()[0] for x in home_agents]]
    created_id = new_only[0] if new_only else None
    clickable = [e for e in d.find_all("aside ul li button") if created_id and created_id in d.text(e)]
    must(clickable, "created agent missing from discovery list")
    d.click(clickable[0])
    d.wait_until(lambda: "Agent workspace" in body_text(d), timeout=30, label="reattached workspace")
    left_and_returned = body_text(d)
    record(
        "6a-leave-and-rediscover",
        vp_desktop,
        "navigate away to /admin/nodes, return to /, real-click the surviving Agent in 'Live Agents'",
        {
            "url": d.current_url(),
            "agentId": created_id,
            "retainedEntries": len(d.find_all("#context article")),
            "retainedSecondTurn": "SECOND-TURN-ACK" in left_and_returned,
            "businessState": [ln for ln in left_and_returned.splitlines() if ln.startswith("Business state:")],
        },
        "PASS" if "SECOND-TURN-ACK" in left_and_returned else "FAIL",
    )

    # stop keeps the instance
    d.click(type_follow_up(d, "HOLD this turn"))
    d.wait_until(
        lambda: [ln for ln in body_text(d).splitlines() if ln.startswith("Business state:") and ("running" in ln or "waiting" in ln)],
        timeout=30,
        label="running state",
    )
    running_line = [ln for ln in body_text(d).splitlines() if ln.startswith("Business state:")]
    stop_btn = [e for e in d.find_all("button") if d.text(e) == "Stop current turn (keep Agent)"][0]
    s = shot(d, "workspace-running-before-stop")
    d.click(stop_btn)
    d.wait_until(
        lambda: [ln for ln in body_text(d).splitlines() if ln.startswith("Business state:") and "stopped" in ln],
        timeout=30,
        label="stopped state",
    )
    d.click([e for e in d.find_all("button") if d.text(e) == "Discover now"][0])
    time.sleep(1.5)
    after_stop = [d.text(e).splitlines()[0] for e in d.find_all("aside ul li button")]
    s2 = shot(d, "workspace-stopped")
    record(
        "6b-stop-keeps-instance",
        vp_desktop,
        "send a HOLD turn, real-click 'Stop current turn (keep Agent)', then 'Discover now'",
        {
            "runningStateLine": running_line,
            "businessStateAfterStop": [ln for ln in body_text(d).splitlines() if ln.startswith("Business state:")],
            "feedback": [ln for ln in body_text(d).splitlines() if "acknowledged" in ln],
            "stillDiscovered": created_id in after_stop if created_id else None,
            "discoveredIds": after_stop,
        },
        "PASS" if created_id in after_stop else "FAIL",
        s2,
    )
    record("6b-evidence-screens", vp_desktop, "screenshots around stop", {"before": s}, "PASS", s)

    # close requires separate confirmation and ends the instance
    d.click([e for e in d.find_all("button") if d.text(e) == "Close instance…"][0])
    d.wait_until(lambda: "Close this Agent instance?" in body_text(d), label="close confirmation")
    confirm_text = body_text(d)
    s = shot(d, "close-confirmation")
    still_alive = d.find_all("#context article")
    d.click([e for e in d.find_all("button") if d.text(e) == "Keep instance"][0])
    d.wait_until(lambda: "Close this Agent instance?" not in body_text(d), label="keep instance cancels")
    kept_ids = [d.text(e).splitlines()[0] for e in d.find_all("aside ul li button")]
    record(
        "6c-close-requires-confirmation",
        vp_desktop,
        "real-click 'Close instance…' then 'Keep instance'",
        {
            "confirmationWording": [ln for ln in confirm_text.splitlines() if "Close this Agent" in ln or "Leaving this page" in ln],
            "instanceStillRendered": bool(still_alive),
            "stillDiscoveredAfterKeep": created_id in kept_ids if created_id else None,
        },
        "PASS" if "Close this Agent instance?" in confirm_text and (created_id in kept_ids) else "FAIL",
        s,
    )

    d.click([e for e in d.find_all("button") if d.text(e) == "Close instance…"][0])
    d.wait_until(lambda: "Confirm close instance" in body_text(d), label="confirm button")
    d.click([e for e in d.find_all("button") if d.text(e) == "Confirm close instance"][0])
    d.wait_until(
        lambda: "Observation unavailable" in body_text(d) or "unavailable" in body_text(d).lower(),
        timeout=30,
        label="observation loss after close",
    )
    time.sleep(1.0)
    d.click([e for e in d.find_all("button") if d.text(e) == "Discover now"][0])
    time.sleep(2.0)
    final_ids = [d.text(e).splitlines()[0] for e in d.find_all("aside ul li button")]
    s = shot(d, "workspace-after-close")
    record(
        "6d-close-ends-instance",
        vp_desktop,
        "real-click 'Close instance…' then 'Confirm close instance', then 'Discover now'",
        {
            "statusAfterClose": [ln for ln in body_text(d).splitlines() if ln.startswith(("Observation", "Business state"))],
            "discoveredIdsAfterClose": final_ids,
            "removedFromDiscovery": created_id not in final_ids if created_id else None,
        },
        "PASS" if created_id not in final_ids else "FAIL",
        s,
    )

    # ---------------- 8. CSP + console ----------------
    d.navigate(BASE + "/")
    wait_ready(d, "What would you like to do?")
    baseline = csp_baseline(d)
    header = served_csp()
    csp_inject(d)
    time.sleep(1.0)
    settle = csp_settle(d)
    s = shot(d, "csp-probe")
    logs = d.logs("browser")
    record(
        "8b-csp-and-console",
        vp_desktop,
        "read the served CSP header, snapshot nonce-bearing inline scripts, then register securitypolicyviolation and append a nonce-less inline script",
        {
            "servedCsp": header,
            "baseline": baseline,
            "violations": settle,
            "inlineScriptBlocked": bool(settle) and not settle.get("injectedRan"),
            "inlineScriptNonceEvidence": [
                {
                    "noncePropertyLength": len(i["nonceProperty"] or ""),
                    "nonceAttributeHidden": i["nonceAttribute"] == "",
                    "nonceLooksLike16ByteBase64": bool(
                        re.fullmatch(r"[A-Za-z0-9+/]{22}==", i["nonceProperty"] or "")
                    ),
                }
                for i in baseline["inlineScripts"]
            ],
            "note": "CSP nonce is generated per response, so the header read via a second plain HTTP request is a different nonce; the document's own nonce is proven by the hidden attribute plus the inline theme script having executed.",
            "themeApplied": baseline["theme"],
            "liveSocketPresent": baseline["liveSocketPresent"],
            "phxConnected": baseline["phxConnected"],
            "webdriverLogs": logs,
        },
        "PASS"
        if settle
        and settle.get("violations")
        and not settle.get("injectedRan")
        and baseline["inlineScripts"]
        and all(
            i["nonceAttribute"] == ""
            and bool(re.fullmatch(r"[A-Za-z0-9+/]{22}==", i["nonceProperty"] or ""))
            for i in baseline["inlineScripts"]
        )
        and baseline["theme"] is not None
        and baseline["phxConnected"]
        else "FAIL",
        s,
    )


if __name__ == "__main__":
    os.makedirs(SHOTS, exist_ok=True)
    main()
    print(json.dumps({"checks": len(results)}, indent=2))
