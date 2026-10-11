#!/usr/bin/env python3
"""Offline A/B runner for a built Flutter web artifact.

This runner serves one existing build under /duoyi/, creates fresh Playwright
contexts for each A/B, viewport, and locale combination, and blocks outbound
network requests. The only external-origin requests it can fulfill are the
known Flutter CanvasKit JS/WASM files, read from that same build directory.
"""

from __future__ import annotations

import argparse
import datetime as dt
import functools
import hashlib
import http.server
import json
import pathlib
import re
import threading
import time
from urllib.parse import unquote, urlsplit, urlunsplit

from playwright.sync_api import Error as PlaywrightError
from playwright.sync_api import sync_playwright


APP_PATH = "/duoyi/"
LOCALE_PREF_KEY = "flutter.duoyi_locale_v1"
DEJAVU_TTF_NAMES = {"dejavusans.ttf"}
FONT_SUFFIXES = {".ttf", ".otf", ".woff", ".woff2"}
CANVASKIT_HOST = "www.gstatic.com"
CANVASKIT_PATH_PREFIX = "/flutter-canvaskit/"
CANVASKIT_CONTENT_TYPES = {
    "canvaskit.js": "application/javascript",
    "canvaskit.wasm": "application/wasm",
    "chromium/canvaskit.js": "application/javascript",
    "chromium/canvaskit.wasm": "application/wasm",
}
VIEWPORTS = (
    {"name": "mobile-390x844", "width": 390, "height": 844},
    {"name": "desktop-1440x900", "width": 1440, "height": 900},
)
LOCALES = (
    {"name": "zh", "browser": "zh-CN", "preference": "zh"},
    {"name": "en", "browser": "en-US", "preference": "en"},
)
ARMS = (
    {
        "name": "A-block-local-dejavu",
        "allow_dejavu": False,
        "description": "Abort the local DejaVuSans.ttf request.",
    },
    {
        "name": "B-allow-local-dejavu",
        "allow_dejavu": True,
        "description": "Allow the local DejaVuSans.ttf request and record its GET response status and SHA-256.",
    },
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_url(raw_url: str) -> str:
    """Drop query and fragment values from recorded request URLs."""
    parsed = urlsplit(raw_url)
    hostname = parsed.hostname or ""
    if ":" in hostname and not hostname.startswith("["):
        hostname = f"[{hostname}]"
    netloc = hostname
    if parsed.port is not None:
        netloc = f"{netloc}:{parsed.port}"
    return urlunsplit((parsed.scheme, netloc, parsed.path, "", ""))


def is_font_request(request, parsed_url=None) -> bool:
    parsed_url = parsed_url or urlsplit(request.url)
    suffix = pathlib.PurePosixPath(unquote(parsed_url.path)).suffix.lower()
    return request.resource_type == "font" or suffix in FONT_SUFFIXES


def is_dejavu_ttf_request(request, parsed_url=None) -> bool:
    parsed_url = parsed_url or urlsplit(request.url)
    filename = pathlib.PurePosixPath(unquote(parsed_url.path)).name.lower()
    return filename in DEJAVU_TTF_NAMES


def is_gstatic_canvaskit_request(request, parsed_url=None) -> bool:
    parsed_url = parsed_url or urlsplit(request.url)
    if (
        parsed_url.scheme != "https"
        or parsed_url.hostname != CANVASKIT_HOST
        or parsed_url.port not in (None, 443)
        or parsed_url.query
        or parsed_url.username
        or parsed_url.password
        or request.method not in ("GET", "HEAD")
    ):
        return False
    return parsed_url.path.startswith(CANVASKIT_PATH_PREFIX)


def local_canvaskit_file(build_dir: pathlib.Path, request_path: str):
    """Resolve an allowed gstatic CanvasKit path inside this build only."""
    match = re.fullmatch(
        r"/flutter-canvaskit/[^/]+/(.+)",
        request_path,
    )
    if not match:
        return None, None

    relative_asset = pathlib.PurePosixPath(match.group(1))
    relative_key = relative_asset.as_posix()
    content_type = CANVASKIT_CONTENT_TYPES.get(relative_key)
    if content_type is None or ".." in relative_asset.parts:
        return None, None

    candidate = (build_dir / "canvaskit").joinpath(*relative_asset.parts)
    candidate = candidate.resolve()
    if not candidate.is_relative_to(build_dir) or not candidate.is_file():
        return None, None
    return candidate, content_type


class BuildHandler(http.server.SimpleHTTPRequestHandler):
    """Read-only static handler that exposes only the build at /duoyi/."""

    def __init__(self, *args, root: pathlib.Path, **kwargs):
        self.root = root
        super().__init__(*args, directory=str(root), **kwargs)

    def log_message(self, _format, *_args):
        return

    def do_GET(self):
        path = unquote(urlsplit(self.path).path)
        if path == APP_PATH[:-1]:
            self.send_response(301)
            self.send_header("Location", APP_PATH)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path != APP_PATH[:-1] and not path.startswith(APP_PATH):
            self.send_error(404, "Only /duoyi/ is served")
            return
        super().do_GET()

    def do_HEAD(self):
        path = unquote(urlsplit(self.path).path)
        if path == APP_PATH[:-1]:
            self.send_response(301)
            self.send_header("Location", APP_PATH)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if path != APP_PATH[:-1] and not path.startswith(APP_PATH):
            self.send_error(404, "Only /duoyi/ is served")
            return
        super().do_HEAD()

    def translate_path(self, path: str) -> str:
        request_path = unquote(urlsplit(path).path)
        if request_path in (APP_PATH[:-1], APP_PATH):
            relative_parts = ("index.html",)
        elif request_path.startswith(APP_PATH):
            relative = request_path[len(APP_PATH) :]
            relative_parts = pathlib.PurePosixPath(relative).parts
        else:
            relative_parts = (".offline-font-ab-not-served",)

        candidate = self.root.joinpath(*relative_parts).resolve()
        if not candidate.is_relative_to(self.root):
            return str(self.root / ".offline-font-ab-not-served")
        return str(candidate)


class LoopbackBuildServer:
    def __init__(self, build_dir: pathlib.Path):
        handler = functools.partial(BuildHandler, root=build_dir)
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(
            target=self.server.serve_forever,
            name="offline-font-ab-static-server",
            daemon=True,
        )
        self.thread.start()
        port = self.server.server_address[1]
        self.port = port
        self.base_url = f"http://127.0.0.1:{port}{APP_PATH}"

    def close(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)


def add_locale_preference(context, locale_preference: str):
    # SharedPreferences web stores JSON-encoded values under the flutter. prefix.
    # This writes only the app's device-level locale choice; it does not create
    # an account, auth token, server configuration, or other persisted state.
    key_literal = json.dumps(LOCALE_PREF_KEY)
    value_literal = json.dumps(json.dumps(locale_preference))
    context.add_init_script(
        "(() => { try { localStorage.setItem("
        f"{key_literal}, {value_literal}"
        "); } catch (_) {} })();"
    )


def install_network_policy(context, page, scenario, build_dir, server, arm):
    policy_blocked = set()

    def record_font_request(request, action, expected_by_policy):
        scenario["fontRequests"].append(
            {
                "method": request.method,
                "url": safe_url(request.url),
                "resourceType": request.resource_type,
                "action": action,
                "expectedByOfflinePolicy": expected_by_policy,
            }
        )

    def route_request(route):
        request = route.request
        parsed = urlsplit(request.url)
        request_key = (request.method, request.url)

        if is_gstatic_canvaskit_request(request, parsed):
            local_path, content_type = local_canvaskit_file(
                build_dir,
                unquote(parsed.path),
            )
            substitution = {
                "url": safe_url(request.url),
                "method": request.method,
                "status": None,
                "localPath": str(local_path) if local_path else None,
                "sha256": None,
                "bytes": None,
            }
            if local_path is None:
                substitution["action"] = "blocked-local-candidate-missing"
                scenario["canvasKitSubstitutions"].append(substitution)
                scenario["errors"].append(
                    {
                        "type": "canvaskit-local-file-missing",
                        "url": safe_url(request.url),
                        "message": "CanvasKit CDN request had no matching file inside --build-dir.",
                    }
                )
                scenario["blockedRequests"].append(
                    {
                        "method": request.method,
                        "url": safe_url(request.url),
                        "reason": "CanvasKit local candidate missing; external fetch blocked",
                    }
                )
                policy_blocked.add(request_key)
                route.abort("blockedbyclient")
                return

            try:
                body = local_path.read_bytes()
                substitution.update(
                    {
                        "action": "fulfilled-from-same-build",
                        "status": 200,
                        "sha256": sha256_bytes(body),
                        "bytes": len(body),
                    }
                )
                scenario["canvasKitSubstitutions"].append(substitution)
                route.fulfill(
                    status=200,
                    content_type=content_type,
                    headers={
                        "Access-Control-Allow-Origin": "*",
                        "Cache-Control": "no-store",
                    },
                    body=body if request.method == "GET" else b"",
                )
            except Exception as error:  # Keep evidence even if a bundle read fails.
                substitution["action"] = "local-fulfill-error"
                if not any(
                    item is substitution
                    for item in scenario["canvasKitSubstitutions"]
                ):
                    scenario["canvasKitSubstitutions"].append(substitution)
                scenario["errors"].append(
                    {
                        "type": "canvaskit-local-fulfill",
                        "url": safe_url(request.url),
                        "message": str(error),
                    }
                )
                policy_blocked.add(request_key)
                route.abort("blockedbyclient")
            return

        is_loopback_build_read = (
            parsed.scheme == "http"
            and parsed.hostname == "127.0.0.1"
            and parsed.port == server.port
            and (
                parsed.path in (APP_PATH[:-1], APP_PATH)
                or parsed.path.startswith(APP_PATH)
            )
        ) and request.method in ("GET", "HEAD")

        if is_loopback_build_read:
            is_dejavu = is_dejavu_ttf_request(request, parsed)
            if is_font_request(request, parsed):
                if is_dejavu and not arm["allow_dejavu"]:
                    action = "blocked-local-dejavu-in-A"
                    expected = True
                else:
                    action = "allowed-loopback-build-read"
                    expected = False
                record_font_request(request, action, expected)

            if is_dejavu and not arm["allow_dejavu"]:
                scenario["blockedRequests"].append(
                    {
                        "method": request.method,
                        "url": safe_url(request.url),
                        "reason": "A arm blocks the local DejaVu TTF",
                    }
                )
                policy_blocked.add(request_key)
                route.abort("blockedbyclient")
                return
            route.continue_()
            return

        if is_font_request(request, parsed):
            record_font_request(
                request,
                "blocked-outbound-request",
                True,
            )
        scenario["blockedRequests"].append(
            {
                "method": request.method,
                "url": safe_url(request.url),
                "reason": "Offline policy allows only loopback /duoyi/ GET/HEAD and same-build CanvasKit fulfillments",
            }
        )
        policy_blocked.add(request_key)
        route.abort("blockedbyclient")

    context.route("**/*", route_request)

    def on_response(response):
        request = response.request
        parsed = urlsplit(response.url)
        if response.status >= 400:
            scenario["errors"].append(
                {
                    "type": "http-response",
                    "status": response.status,
                    "url": safe_url(response.url),
                }
            )
        if (
            arm["allow_dejavu"]
            and request.method == "GET"
            and is_dejavu_ttf_request(request, parsed)
            and parsed.scheme == "http"
            and parsed.hostname == "127.0.0.1"
            and parsed.port == server.port
            and parsed.path.startswith(APP_PATH)
        ):
            try:
                body = response.body()
                scenario["fontAssetResponses"].append(
                    {
                        "method": request.method,
                        "url": safe_url(response.url),
                        "status": response.status,
                        "bytes": len(body),
                        "sha256": sha256_bytes(body),
                    }
                )
            except PlaywrightError as error:
                scenario["errors"].append(
                    {
                        "type": "dejavu-response-body",
                        "url": safe_url(response.url),
                        "message": str(error),
                    }
                )

    def on_request_failed(request):
        expected = (request.method, request.url) in policy_blocked
        scenario["errors"].append(
            {
                "type": "request-failed",
                "url": safe_url(request.url),
                "method": request.method,
                "failure": request.failure,
                "expectedByOfflinePolicy": expected,
            }
        )

    page.on("response", on_response)
    page.on("requestfailed", on_request_failed)
    page.on(
        "pageerror",
        lambda error: scenario["errors"].append(
            {"type": "page-error", "message": str(error)}
        ),
    )
    page.on(
        "console",
        lambda message: scenario["errors"].append(
            {"type": "console-error", "message": message.text}
        )
        if message.type == "error"
        else None,
    )

    if hasattr(page, "route_web_socket"):
        # The static home-screen probe has no WebSocket need. Close any attempted
        # socket so it cannot become a route around HTTP request interception.
        page.route_web_socket(
            "**/*",
            lambda socket_route: socket_route.close(
                code=1008,
                reason="Offline font A/B policy",
            ),
        )


def collect_page_state(page):
    return page.evaluate(
        """() => {
          const allElements = (root) => [...root.querySelectorAll('*')].flatMap(element => [
            element,
            ...(element.shadowRoot ? allElements(element.shadowRoot) : []),
          ]);
          const canvases = allElements(document).filter(element => element.tagName === 'CANVAS');
          return {
            title: document.title,
            readyState: document.readyState,
            url: location.href,
            baseHref: document.querySelector('base')?.getAttribute('href') ?? null,
            viewport: { width: innerWidth, height: innerHeight },
            flutterViewCount: document.querySelectorAll('flutter-view').length,
            glassPaneCount: document.querySelectorAll('flt-glass-pane').length,
            canvasCount: canvases.length,
            canvasRects: canvases.slice(0, 4).map(canvas => {
              const rect = canvas.getBoundingClientRect();
              return { width: Math.round(rect.width), height: Math.round(rect.height) };
            }),
            bodyText: (document.body?.innerText ?? '').trim().slice(0, 1000),
            fontStatus: document.fonts?.status ?? null,
          };
        }"""
    )


def run_scenario(browser, server, build_dir, output_dir, arm, viewport, locale, settle_ms, timeout_ms):
    scenario_id = f"{arm['name']}-{locale['name']}-{viewport['name']}"
    screenshot_path = output_dir / f"{scenario_id}.png"
    scenario = {
        "id": scenario_id,
        "arm": arm["name"],
        "armDescription": arm["description"],
        "locale": locale,
        "viewport": {
            "width": viewport["width"],
            "height": viewport["height"],
        },
        "responseStatus": None,
        "elapsedMs": None,
        "state": None,
        "readiness": {},
        "blockedRequests": [],
        "canvasKitSubstitutions": [],
        "fontRequests": [],
        "fontAssetResponses": [],
        "errors": [],
        "screenshot": str(screenshot_path),
    }

    context = browser.new_context(
        viewport={"width": viewport["width"], "height": viewport["height"]},
        device_scale_factor=1,
        locale=locale["browser"],
        color_scheme="light",
        service_workers="block",
    )
    add_locale_preference(context, locale["preference"])
    page = context.new_page()
    install_network_policy(context, page, scenario, build_dir, server, arm)

    started = time.monotonic()
    try:
        response = page.goto(
            server.base_url,
            wait_until="load",
            timeout=timeout_ms,
        )
        scenario["responseStatus"] = response.status if response else None
    except PlaywrightError as error:
        scenario["errors"].append(
            {"type": "navigation", "message": str(error)}
        )

    try:
        page.wait_for_timeout(settle_ms)
        scenario["state"] = collect_page_state(page)
    except PlaywrightError as error:
        scenario["errors"].append(
            {"type": "page-state", "message": str(error)}
        )

    state = scenario["state"] or {}
    scenario["readiness"] = {
        "appHttp200": scenario["responseStatus"] == 200,
        "documentComplete": state.get("readyState") == "complete",
        "flutterViewMounted": state.get("flutterViewCount", 0) > 0,
        "canvasMounted": state.get("canvasCount", 0) > 0,
        "baseHrefUsesDuoyiPath": state.get("baseHref") == APP_PATH,
        "sameBuildCanvasKitFulfillments": len(
            [
                item
                for item in scenario["canvasKitSubstitutions"]
                if item.get("action") == "fulfilled-from-same-build"
            ]
        ),
        "localDejaVuGetResponses": len(
            [
                item
                for item in scenario["fontAssetResponses"]
                if item.get("method") == "GET"
            ]
        ),
    }
    scenario["elapsedMs"] = round((time.monotonic() - started) * 1000)

    try:
        page.screenshot(
            path=str(screenshot_path),
            full_page=False,
            animations="disabled",
        )
    except PlaywrightError as error:
        scenario["screenshot"] = None
        scenario["errors"].append(
            {"type": "screenshot", "message": str(error)}
        )
    finally:
        context.close()
    return scenario


def write_json(path: pathlib.Path, value):
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--build-dir",
        required=True,
        type=pathlib.Path,
        help="Flutter web output root containing index.html and canvaskit/.",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=pathlib.Path,
        help="Evidence directory for readiness/errors/font JSON and screenshots.",
    )
    parser.add_argument(
        "--settle-ms",
        type=int,
        default=7000,
        help="Wait after navigation before state capture (default: 7000).",
    )
    parser.add_argument(
        "--timeout-ms",
        type=int,
        default=60000,
        help="Navigation timeout per fresh browser context (default: 60000).",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    build_dir = args.build_dir.expanduser().resolve(strict=True)
    if not build_dir.is_dir():
        raise SystemExit(f"--build-dir is not a directory: {build_dir}")
    index_html = build_dir / "index.html"
    if not index_html.is_file():
        raise SystemExit(f"--build-dir must contain index.html: {build_dir}")

    output_dir = args.output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    run_record = {
        "startedAtUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "buildDir": str(build_dir),
        "buildIndexSha256": sha256_bytes(index_html.read_bytes()),
        "outputDir": str(output_dir),
        "appPath": APP_PATH,
        "localePreference": {
            "key": LOCALE_PREF_KEY,
            "values": [locale["preference"] for locale in LOCALES],
            "scope": "only the app's device-level locale; no account/auth state",
        },
        "networkPolicy": {
            "allow": "loopback /duoyi/ GET/HEAD and exact CanvasKit CDN assets fulfilled from this --build-dir",
            "block": "all other outbound requests and all non-read methods",
            "canvasKitLocalRoot": str(build_dir / "canvaskit"),
        },
        "scenarios": [],
        "fatalErrors": [],
    }

    server = None
    try:
        server = LoopbackBuildServer(build_dir)
        run_record["baseUrl"] = server.base_url
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                headless=True,
                args=[
                    "--no-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-background-networking",
                    "--disable-component-update",
                    "--disable-sync",
                    "--metrics-recording-only",
                    "--no-first-run",
                    "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1",
                ],
            )
            try:
                for arm in ARMS:
                    for locale in LOCALES:
                        for viewport in VIEWPORTS:
                            scenario = run_scenario(
                                browser,
                                server,
                                build_dir,
                                output_dir,
                                arm,
                                viewport,
                                locale,
                                args.settle_ms,
                                args.timeout_ms,
                            )
                            run_record["scenarios"].append(scenario)
            finally:
                browser.close()
    except Exception as error:
        run_record["fatalErrors"].append(
            {"type": type(error).__name__, "message": str(error)}
        )
    finally:
        if server is not None:
            server.close()
        run_record["finishedAtUtc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        write_json(output_dir / "offline-font-ab-readiness.json", run_record)
        write_json(
            output_dir / "offline-font-ab-errors.json",
            {
                "fatalErrors": run_record["fatalErrors"],
                "scenarios": [
                    {
                        "id": item["id"],
                        "errors": item["errors"],
                        "blockedRequests": item["blockedRequests"],
                    }
                    for item in run_record["scenarios"]
                ],
            },
        )
        write_json(
            output_dir / "offline-font-ab-font-requests.json",
            {
                "scenarios": [
                    {
                        "id": item["id"],
                        "arm": item["arm"],
                        "fontRequests": item["fontRequests"],
                        "fontAssetResponses": item["fontAssetResponses"],
                    }
                    for item in run_record["scenarios"]
                ],
            },
        )

    return 1 if run_record["fatalErrors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
