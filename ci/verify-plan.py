"""Reject mismatched, modified or expired plans before obtaining cloud credentials."""
import hashlib
import json
import os
import time
from pathlib import Path

manifest = json.loads(Path("reviewed-plan/manifest.json").read_text())
config = json.loads(Path("ci/lab-config.json").read_text())
expected = {
    "commit": os.environ["GITHUB_SHA"],
    "run_id": os.environ["PLAN_RUN_ID"],
    "lab": config["terraform"]["name"],
    "sha256": hashlib.sha256(Path("reviewed-plan/lab.tfplan").read_bytes()).hexdigest(),
}
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(f"Plan mismatch: {key}. Generate a new plan.")
if manifest.get("operation") not in ("deploy", "destroy"):
    raise SystemExit("Unrecognised operation")
if os.environ["CONFIRMATION"] != manifest["operation"].upper():
    raise SystemExit("Confirmation must be DEPLOY or DESTROY, matching the plan.")
if not 0 <= time.time() - manifest["created"] <= 86400:
    raise SystemExit("Plan has expired. Generate and review a new plan.")
print("Plan identity, checksum, age and requested operation verified.")
