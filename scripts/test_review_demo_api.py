#!/usr/bin/env python3
"""Regression tests for the synthetic App Review TeslaMate API."""

from __future__ import annotations

import json
import os
import socketserver
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from datetime import datetime, timezone
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from generate_review_demo_api import CAR_ID, MARKER, generate


FIXED_NOW = datetime(2026, 7, 28, 12, 0, tzinfo=timezone.utc)


class QuietStaticHandler(SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        pass


class ReviewDemoHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def server_bind(self) -> None:
        socketserver.TCPServer.server_bind(self)
        self.server_name = "localhost"
        self.server_port = self.server_address[1]


class ReviewDemoAPITests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.output = self.root / "review-demo"
        generate(self.output, FIXED_NOW)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def payload(self, endpoint: str) -> Any:
        path = self.output / endpoint / "index.html"
        return json.loads(path.read_text(encoding="utf-8"))

    def json_endpoints(self) -> list[Path]:
        return sorted(
            path
            for path in self.output.rglob("index.html")
            if path != self.output / "index.html"
        )

    def test_generates_complete_parseable_api(self) -> None:
        self.assertTrue((self.output / MARKER).is_file())
        self.assertGreaterEqual(len(self.json_endpoints()), 35)
        for path in self.json_endpoints():
            with self.subTest(endpoint=path.relative_to(self.output)):
                json.loads(path.read_text(encoding="utf-8"))

        drives = self.payload(f"api/v1/cars/{CAR_ID}/drives")["data"]["drives"]
        charges = self.payload(f"api/v1/cars/{CAR_ID}/charges")["data"]["charges"]
        self.assertLess(len(drives), 200)
        self.assertLess(len(charges), 200)
        self.assertTrue(drives)
        self.assertTrue(charges)
        for drive in drives:
            self.assertTrue(
                (
                    self.output
                    / f"api/v1/cars/{CAR_ID}/drives/{drive['drive_id']}/index.html"
                ).is_file()
            )
        for charge in charges:
            self.assertTrue(
                (
                    self.output
                    / f"api/v1/cars/{CAR_ID}/charges/{charge['charge_id']}/index.html"
                ).is_file()
            )
        self.assertIsNone(
            self.payload(f"api/v1/cars/{CAR_ID}/charges/current")["data"]
        )

    def test_uses_recent_synthetic_data_without_sensitive_fields(self) -> None:
        newest_drive = self.payload(f"api/v1/cars/{CAR_ID}/drives")["data"][
            "drives"
        ][0]
        newest_date = datetime.fromisoformat(
            newest_drive["start_date"].replace("Z", "+00:00")
        )
        self.assertLess((FIXED_NOW - newest_date).total_seconds(), 3 * 24 * 60 * 60)

        serialized = "\n".join(
            path.read_text(encoding="utf-8") for path in self.json_endpoints()
        ).lower()
        for forbidden in (
            '"vin"',
            '"token"',
            '"password"',
            '"secret"',
            '"username"',
            "authorization",
            "bearer ",
            "http://",
            "@",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, serialized)
        self.assertIn('"demo":true', serialized)
        self.assertIn("synthetic read-only review data", serialized)

    def test_refuses_to_replace_unmarked_directory(self) -> None:
        unmarked = self.root / "do-not-replace"
        unmarked.mkdir()
        (unmarked / "owned.txt").write_text("keep", encoding="utf-8")

        with self.assertRaisesRegex(RuntimeError, "Refusing to replace"):
            generate(unmarked, FIXED_NOW)

        self.assertEqual((unmarked / "owned.txt").read_text(encoding="utf-8"), "keep")

    def test_static_server_passes_probe_and_rejects_writes(self) -> None:
        handler = partial(QuietStaticHandler, directory=str(self.root))
        server = ReviewDemoHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base_url = f"http://127.0.0.1:{server.server_port}/review-demo"
        try:
            environment = os.environ.copy()
            environment.update(
                {
                    "MATEDRIVE_INTEGRATION_BASE_URL": base_url,
                    "MATEDRIVE_INTEGRATION_REVIEW_MODE": "0",
                    "MATEDRIVE_INTEGRATION_ENV_FILE": str(
                        self.root / "missing-integration.env"
                    ),
                }
            )
            completed = subprocess.run(
                ["bash", "scripts/probe_teslamate_integration.sh"],
                cwd=Path(__file__).resolve().parent.parent,
                env=environment,
                text=True,
                capture_output=True,
                timeout=20,
                check=False,
            )
            self.assertEqual(
                completed.returncode,
                0,
                msg=f"{completed.stdout}\n{completed.stderr}",
            )
            self.assertIn("TeslaMate API preflight passed", completed.stdout)

            request = urllib.request.Request(
                f"{base_url}/api/v1/cars",
                data=b'{"data":"write"}',
                method="PUT",
                headers={"Content-Type": "application/json"},
            )
            with self.assertRaises(urllib.error.HTTPError) as error:
                urllib.request.urlopen(request, timeout=5)
            self.assertIn(error.exception.code, {405, 501})
            error.exception.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
