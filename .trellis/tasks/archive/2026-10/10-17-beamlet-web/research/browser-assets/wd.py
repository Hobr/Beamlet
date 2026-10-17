"""Minimal W3C WebDriver client (Python stdlib only) for the Beamlet browser walkthrough.

Only the pre-verified geckodriver + Firefox binary are used, over loopback HTTP.
No packages installed.
"""

import base64
import http.client
import json
import re
import time
import urllib.parse

ELEMENT_KEY = "element-6066-11e4-a52e-4f735466cecf"
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}
SESSION_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
ELEMENT_RE = re.compile(r"^[0-9a-f-]{1,64}$")


def loopback_parts(url):
    """Accept only http URLs pointing at a loopback geckodriver endpoint."""
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "http":
        raise ValueError(f"unsupported driver scheme: {parsed.scheme!r}")
    if parsed.hostname not in LOOPBACK_HOSTS:
        raise ValueError(f"driver host is not loopback: {parsed.hostname!r}")
    return parsed.hostname, int(parsed.port or 80)


def checked(kind, value):
    pattern = SESSION_RE if kind == "session" else ELEMENT_RE
    if not isinstance(value, str) or not pattern.match(value):
        raise ValueError(f"unexpected {kind} identifier: {value!r}")
    return value


class WdError(Exception):
    def __init__(self, method, path, code, payload):
        self.method = method
        self.path = path
        self.code = code
        self.payload = payload
        super().__init__(f"{method} {path} -> HTTP {code}: {payload}")


class Driver:
    def __init__(self, url):
        self.host, self.port = loopback_parts(url)
        self.session_id = None

    # ---------- transport ----------
    def _cmd(self, method, path, body=None, timeout=180):
        if not path.startswith("/"):
            raise ValueError(f"bad driver path: {path!r}")
        payload = json.dumps(body).encode() if body is not None else None
        conn = http.client.HTTPConnection(self.host, self.port, timeout=timeout)
        try:
            conn.request(
                method,
                path,
                body=payload,
                headers={"content-type": "application/json; charset=utf-8"},
            )
            resp = conn.getresponse()
            raw = resp.read().decode()
        finally:
            conn.close()
        if resp.status >= 400:
            raise WdError(method, path, resp.status, raw[:4000])
        return json.loads(raw)["value"]

    def probe(self, method, path, body=None):
        """Same as _cmd but returns (ok, value_or_error) instead of raising."""
        try:
            return True, self._cmd(method, path, body)
        except WdError as exc:
            return False, str(exc)

    # ---------- session ----------
    def start(self, firefox_binary, extra_args=None):
        args = ["-headless"] + list(extra_args or [])
        value = self._cmd(
            "POST",
            "/session",
            {
                "capabilities": {
                    "alwaysMatch": {
                        "browserName": "firefox",
                        "acceptInsecureCerts": True,
                        "pageLoadStrategy": "normal",
                        "moz:firefoxOptions": {
                            "binary": firefox_binary,
                            "args": args,
                            "prefs": {
                                "dom.disable_beforeunload": True,
                                "browser.tabs.warnOnClose": False,
                            },
                        },
                    }
                }
            },
        )
        self.session_id = value["sessionId"]
        return value["capabilities"]

    def quit(self):
        if self.session_id:
            ok, val = self.probe("DELETE", f"/session/{checked('session', self.session_id)}")
            self.session_id = None
            return ok, val
        return True, "no session"

    def _s(self, path):
        return f"/session/{checked('session', self.session_id)}{path}"

    def _e(self, eid, suffix):
        return f"/element/{checked('element', eid)}/{suffix}"

    # ---------- navigation / page ----------
    def navigate(self, url):
        return self._cmd("POST", self._s("/url"), {"url": url})

    def current_url(self):
        return self._cmd("GET", self._s("/url"))

    def title(self):
        return self._cmd("GET", self._s("/title"))

    def source(self):
        return self._cmd("GET", self._s("/source"))

    def window_rect(self, **kw):
        return self._cmd("POST", self._s("/window/rect"), kw)

    def screenshot(self, path):
        b64 = self._cmd("GET", self._s("/screenshot"))
        with open(path, "wb") as fh:
            fh.write(base64.b64decode(b64))
        return path

    # ---------- elements ----------
    def find(self, css, timeout=15.0, visible=False):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            ok, val = self.probe(
                "POST", self._s("/element"), {"using": "css selector", "value": css}
            )
            if ok and isinstance(val, dict):
                eid = val.get(ELEMENT_KEY)
                if isinstance(eid, str) and (not visible or self.displayed(eid)):
                    return eid
                last = "element present but not displayed"
            else:
                last = val
            time.sleep(0.25)
        raise TimeoutError(f"find({css!r}) failed: {last}")

    def find_all(self, css):
        val = self._cmd(
            "POST", self._s("/elements"), {"using": "css selector", "value": css}
        )
        return [e.get(ELEMENT_KEY) for e in val if isinstance(e, dict)]

    def find_absent(self, css, timeout=15.0):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if not self.find_all(css):
                return True
            time.sleep(0.2)
        return False

    def click(self, eid):
        return self._cmd("POST", self._s(self._e(eid, "click")), {})

    def send_keys(self, eid, text):
        value = list(text)
        return self._cmd(
            "POST", self._s(self._e(eid, "value")), {"text": text, "value": value}
        )

    def clear(self, eid):
        return self._cmd("POST", self._s(self._e(eid, "clear")), {})

    def text(self, eid):
        return self._cmd("GET", self._s(self._e(eid, "text")))

    def attr(self, eid, name):
        return self._cmd("GET", self._s(self._e(eid, f"attribute/{name}")))

    def prop(self, eid, name):
        return self._cmd("GET", self._s(self._e(eid, f"property/{name}")))

    def rect(self, eid):
        return self._cmd("GET", self._s(self._e(eid, "rect")))

    def displayed(self, eid):
        return self._cmd("GET", self._s(self._e(eid, "displayed")))

    def enabled(self, eid):
        return self._cmd("GET", self._s(self._e(eid, "enabled")))

    def tag(self, eid):
        return self._cmd("GET", self._s(self._e(eid, "name")))

    def active_element(self):
        return self._cmd("GET", self._s("/element/active")).get(ELEMENT_KEY)

    # ---------- script ----------
    def script(self, js, *args):
        converted = []
        for a in args:
            if isinstance(a, str) and a.startswith("wd:eid:"):
                converted.append({ELEMENT_KEY: a[len("wd:eid:") :]})
            else:
                converted.append(a)
        return self._cmd("POST", self._s("/execute/sync"), {"script": js, "args": converted})

    def eid(self, element_id):
        return "wd:eid:" + element_id

    # ---------- logs (may be unsupported by geckodriver) ----------
    def logs(self, kind="browser"):
        attempts = []
        path = self._s("/log")
        ok, val = self.probe("POST", path, {"type": kind})
        attempts.append(("POST /log", ok, val))
        if ok:
            return attempts
        ok, val = self.probe(
            "GET", self._s("/log?type=" + urllib.parse.quote(kind, safe=""))
        )
        attempts.append(("GET /log", ok, val))
        return attempts

    # ---------- waiting ----------
    def wait_until(self, predicate, timeout=20.0, interval=0.25, label="condition"):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            try:
                result = predicate()
                if result:
                    return result
                last = result
            except (WdError, TimeoutError) as exc:
                last = str(exc)
            time.sleep(interval)
        raise TimeoutError(f"wait_until({label}) timed out; last={last!r}")

    def wait_body(self, needle, timeout=20.0):
        return self.wait_until(
            lambda: needle in self.script("return document.body.innerText;"),
            timeout=timeout,
            label=f"body contains {needle!r}",
        )
