"""Prepare deterministic CI files without credentials in Terraform configuration."""
import ipaddress
import json
import os
from pathlib import Path

config = json.loads(Path("ci/lab-config.json").read_text())
if "REPLACE" in json.dumps(config):
    raise SystemExit("Complete ci/lab-config.json before running cloud workflows.")
backend = config["backend"]
if backend.get("encrypt") is not True or backend.get("use_lockfile") is not True:
    raise SystemExit("Backend encryption and state locking must stay enabled.")
settings = config["terraform"]
network = ipaddress.ip_network(settings["admin_cidr"])
if network.version != 4 or network.prefixlen != 32 or not network.network_address.is_global:
    raise SystemExit("admin_cidr must be your public IPv4 address with /32.")
key = Path("ci/lab.pub")
if not key.exists() or not key.read_text().strip().startswith("ssh-rsa "):
    raise SystemExit("Copy your RSA public key to ci/lab.pub; never copy the private key.")
settings["ssh_public_key_path"] = "ci/lab.pub"
Path("ci.auto.tfvars.json").write_text(json.dumps(settings, indent=2) + "\n")
Path("ci-backend.json").write_text(json.dumps(backend, indent=2) + "\n")
if not Path("backend.tf").exists():
    Path("backend.tf").write_text(Path("backend.tf.example").read_text())
with open(os.environ["GITHUB_ENV"], "a") as output:
    # JSON strings must not be allowed to add arbitrary workflow environment lines.
    for name, value in {
        "ARM_SUBSCRIPTION_ID": settings["azure_subscription_id"],
        "LAB_NAME": settings["name"],
    }.items():
        if not isinstance(value, str) or "\n" in value or "\r" in value:
            raise SystemExit(f"Invalid {name}")
        output.write(f"{name}={value}\n")
