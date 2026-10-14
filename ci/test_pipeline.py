"""Exercise plan verification without cloud access or credentials."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

VERIFY = Path(__file__).with_name("verify-plan.py").resolve()


class PlanVerificationTests(unittest.TestCase):
    def run_check(self, *, changes=None, confirmation="DEPLOY", tamper=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "ci").mkdir()
            (root / "reviewed-plan").mkdir()
            (root / "ci/lab-config.json").write_text(json.dumps({"terraform": {"name": "lab-test"}}))
            plan = b"test plan content; never an executable Terraform plan"
            manifest = {
                "commit": "abc123", "run_id": "123", "lab": "lab-test",
                "sha256": hashlib.sha256(plan).hexdigest(),
                "operation": "deploy", "created": int(time.time()),
            }
            manifest.update(changes or {})
            (root / "reviewed-plan/manifest.json").write_text(json.dumps(manifest))
            (root / "reviewed-plan/lab.tfplan").write_bytes(plan + (b"tampered" if tamper else b""))
            environment = dict(os.environ, GITHUB_SHA="abc123", PLAN_RUN_ID="123", CONFIRMATION=confirmation)
            return subprocess.run([sys.executable, str(VERIFY)], cwd=root, env=environment,
                                  capture_output=True, text=True)

    def test_valid_deploy(self):
        self.assertEqual(self.run_check().returncode, 0)

    def test_valid_destroy(self):
        self.assertEqual(self.run_check(changes={"operation": "destroy"}, confirmation="DESTROY").returncode, 0)

    def test_mismatched_identity(self):
        for field in ("commit", "run_id", "lab"):
            with self.subTest(field=field):
                self.assertNotEqual(self.run_check(changes={field: "wrong"}).returncode, 0)

    def test_expired_or_future_plan(self):
        for created in (int(time.time()) - 90000, int(time.time()) + 600):
            with self.subTest(created=created):
                self.assertNotEqual(self.run_check(changes={"created": created}).returncode, 0)

    def test_modified_plan(self):
        self.assertNotEqual(self.run_check(tamper=True).returncode, 0)

    def test_wrong_confirmation(self):
        self.assertNotEqual(self.run_check(confirmation="DESTROY").returncode, 0)

    def test_unknown_operation(self):
        self.assertNotEqual(self.run_check(changes={"operation": "unexpected"}).returncode, 0)


if __name__ == "__main__":
    unittest.main()
