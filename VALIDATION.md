# Validation status

- Terraform 1.16.0 was available on the preparation machine.
- Terraform formatting/parsing checks passed.
- Provider initialization succeeded after network permission was granted. Both the root and bootstrap configurations passed Terraform validation. Selected providers: AWS 6.68.0, AzureRM 4.81.0 and Google 7.46.1. Lockfiles are included.
- Both cloud startup templates rendered successfully with sample values, and the Grafana dashboard parsed as valid JSON.
- Shell execution was unavailable: WSL returned Access Denied and Git Bash could not start under the sandbox. The installer and rendered cloud scripts have not been executed or shell-validated.
- WSL access from this session returned Access Denied. Nothing was installed into your Ubuntu distribution.
- No account authentication, cloud plan, cloud deployment, startup-script execution, failover test or billing estimate was completed.
- Run the documented checks with your selected subscription/project, quotas and regions before using the lab. Static validation does not confirm cloud quotas, VM image availability, package installation, firewall reachability or runtime behaviour. Treat this as an implementation candidate, not a validated production deployment.
