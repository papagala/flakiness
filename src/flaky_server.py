#!/usr/bin/env python3
"""A tiny, dependency-free HTTP server that fails a configurable percentage of
requests. Built to exercise gateway/mesh retry behaviour (e.g. Envoy Gateway)
against KServe Deployments, InferenceServices and InferenceGraphs.

Health/readiness GETs always return 200 so probes pass; any POST is subject to
the configured failure percentage. Every decision is logged to stdout so retries
are visible via `kubectl logs` / `stern`.
"""
import argparse
import json
import os
import random
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# GET paths that must always succeed (liveness / readiness / model-ready checks).
HEALTH_PREFIXES = (
    "/healthz",
    "/readyz",
    "/livez",
    "/v1/models/",          # KServe v1 model readiness: GET /v1/models/<name>
    "/v2/health/",          # KServe v2 (Open Inference Protocol) health
    "/v2/models/",          # KServe v2 model metadata / ready
)


def build_handler(percentage: float, fail_status: int, model_name: str):
    class Handler(BaseHTTPRequestHandler):
        # Silence the default noisy per-request logging; we log our own line.
        def log_message(self, *_args):
            pass

        def _write(self, status: int, payload: dict, flaky_result: str = ""):
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            if flaky_result:
                self.send_header("X-Flaky-Result", flaky_result)
            self.end_headers()
            self.wfile.write(body)

        def _log(self, msg: str):
            print(f"[flaky] {msg}", flush=True)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path == "/" or path.startswith(HEALTH_PREFIXES):
                self._write(200, {"status": "ok", "model": model_name})
                return
            # Unknown GET: still healthy, keeps probes forgiving.
            self._write(200, {"status": "ok", "model": model_name})

        def do_POST(self):
            path = self.path.split("?", 1)[0]
            length = int(self.headers.get("Content-Length", 0) or 0)
            if length:
                self.rfile.read(length)  # drain body

            roll = random.random() * 100.0
            if roll < percentage:
                self._log(f"POST {path} -> {fail_status} (roll={roll:.1f} < {percentage:g})")
                self._write(
                    fail_status,
                    {"error": "flaky failure injected", "model": model_name},
                    flaky_result="fail",
                )
                return

            self._log(f"POST {path} -> 200 (roll={roll:.1f} >= {percentage:g})")
            if "/v2/" in path:
                payload = {
                    "model_name": model_name,
                    "outputs": [
                        {"name": "output-0", "datatype": "FP32",
                         "shape": [1], "data": [0.85]}
                    ],
                }
            else:
                payload = {"predictions": [{"model": model_name, "score": 0.85}]}
            self._write(200, payload, flaky_result="ok")

    return Handler


def _env_int(name: str, default: int) -> int:
    val = os.environ.get(name)
    return int(val) if val not in (None, "") else default


def main(argv=None):
    parser = argparse.ArgumentParser(description="Configurable flaky HTTP inference server.")
    parser.add_argument(
        "--percentage-of-failures", type=float,
        default=float(_env_int("PERCENTAGE_OF_FAILURES", 20)),
        help="Percent of POST requests to fail, 0-100 (env: PERCENTAGE_OF_FAILURES, default 20).",
    )
    parser.add_argument(
        "--port", type=int, default=_env_int("PORT", 8080),
        help="Port to listen on (env: PORT, default 8080).",
    )
    parser.add_argument(
        "--fail-status", type=int, default=_env_int("FAIL_STATUS", 503),
        help="HTTP status returned on failure (env: FAIL_STATUS, default 503).",
    )
    parser.add_argument(
        "--model-name", default=os.environ.get("MODEL_NAME", "flaky"),
        help="Model name reported in responses/paths (env: MODEL_NAME, default 'flaky').",
    )
    args = parser.parse_args(argv)

    pct = max(0.0, min(100.0, args.percentage_of_failures))
    handler = build_handler(pct, args.fail_status, args.model_name)
    server = ThreadingHTTPServer(("0.0.0.0", args.port), handler)
    print(
        f"[flaky] listening on :{args.port} "
        f"percentage-of-failures={pct:g} fail-status={args.fail_status} "
        f"model-name={args.model_name}",
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("[flaky] shutting down", flush=True)
        server.shutdown()
        return 0


if __name__ == "__main__":
    sys.exit(main())
