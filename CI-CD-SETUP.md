# GitHub Actions CI/CD setup

This configuration extends your Windows/WSL multi-cloud lab. GitHub-hosted Ubuntu runners execute the pipeline in the cloud. Your laptop is needed only for editing files and the initial account/identity setup.

## Pipeline behaviour

```text
Push / pull request --> Terraform formatting and validation (no cloud credentials)

Manual "Plan cloud changes" --> Sign in through OIDC --> Read current state
                            --> Save deploy OR destroy plan --> Review plan

Manual "Apply reviewed plan" + run ID + DEPLOY/DESTROY
    --> Verify successful source run, same main commit, plan checksum and age
    --> Sign in through OIDC --> Apply exactly the saved plan --> Show outputs
```

No push automatically creates billable resources. Deployment and teardown both use a reviewed plan. A saved destroy plan is applied with `terraform apply`; it is not replanned at execution time. Changes to the demo application templates also go through Terraform and can replace VMs; review replacement actions carefully. This pipeline does not yet build container images or deploy an independent application release.

Files: `validate.yml` runs CI; `plan.yml` creates plans; `apply.yml` deploys or tears down; `identity.yml` helps set up federation. The shared action establishes the cloud session. `ci/prepare.py` generates configuration, and `ci/verify-plan.py` verifies a selected plan before cloud authentication.

## 1. Create the repository

Create a **private GitHub repository** whose default branch is `main`. Put the contents of `multicloud-student-lab` at its root, including the hidden `.github` directory. Do not upload the enclosing ZIP or place the lab inside another folder. These cloud workflows deliberately skip public repositories because saved Terraform plans can contain sensitive state values.

From WSL, after reviewing `.gitignore`:

```bash
cd ~/projects/multicloud-student-lab
git init -b main
git add .
git status
git commit -m "Add multi-cloud Terraform lab and CI/CD"
git remote add origin https://github.com/YOUR-OWNER/YOUR-REPOSITORY.git
git push -u origin main
```

Use your existing GitHub sign-in method. Never add Terraform state, private SSH keys, service-account JSON keys or local credential folders. The existing provider lockfiles should be committed. The workflow uses Terraform 1.16.0 to match the prepared project.

In GitHub Settings > Environments, create `lab` and restrict deployment branches to **main only**. Environment availability depends on your GitHub plan and repository visibility. If environments are unavailable in your private repository, these workflows require a compatible plan; do not make plan artifacts public as a workaround. The separate manual Apply workflow provides the review step without requiring an environment reviewer feature. You may additionally require a reviewer where available. See [GitHub environment availability](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

Protect main with pull-request review/status checks where your plan supports it. Only trusted collaborators should have write access: they can edit Terraform and trigger manual workflows.

## 2. Preserve your existing lab configuration and state

First complete the WSL authentication and S3 bootstrap steps in README.md. CI does not create the state bucket or federation identities. For an already deployed lab, migrate its existing state to the configured S3 key before switching to CI. A new empty state key would attempt to create duplicate resources.

Edit `ci/lab-config.json`. Copy the exact values from your deployed `terraform.tfvars` and `backend.hcl`, including regions, sizes, lab name, routing method and your public admin IP. Copy only your **public** key:

```bash
cp ~/.ssh/multicloud-lab.pub ci/lab.pub
```

Commit `ci/lab.pub`, the completed JSON configuration and any lockfile updates. The private key stays in WSL; GitHub runners do not SSH into the VMs. `admin_cidr` stays your own public IPv4 /32, not a runner IP. The runners provision through cloud APIs.

If you later change settings, update this JSON, review and merge the commit, then create a new plan. Keep WSL's local tfvars consistent if you also operate Terraform locally. Do not run local Terraform changes while applying a CI plan.

## 3. Discover your exact GitHub federation identity

Run Actions > Inspect federation identity > Run workflow on main. It does not access a cloud account. Copy its `sub`, `repository_id` and `repository_owner_id` output. It prints selected identity claims, never the bearer token.

Use the exact `sub` shown, including the `lab` environment. Do not blindly copy older tutorials: newer GitHub repositories can include immutable numeric IDs in subjects, such as `repo:OWNER@OWNER_ID/REPO@REPO_ID:environment:lab`. Older repositories may use `repo:OWNER/REPO:environment:lab`. Custom subjects can differ again. See [GitHub OIDC reference](https://docs.github.com/en/actions/reference/security/oidc).

## 4. AWS: create a federated role

In the AWS IAM console:

1. Add an OpenID Connect identity provider with URL `https://token.actions.githubusercontent.com` and audience `sts.amazonaws.com`, or reuse that provider if it already exists.
2. Create an IAM role named `github-multicloud-lab` using the trust template in `ci/aws-trust-policy.json.example`. Replace ACCOUNT_ID and EXACT_SUB_FROM_IDENTITY_WORKFLOW. Keep the subject exact; do not use a repository wildcard.
3. Attach an inline permissions policy based on `ci/aws-permissions-policy.json.example`. Replace STATE_BUCKET and adjust both object paths if you changed the backend key.
4. Copy the role ARN for the GitHub variable below.

The sample EC2 permission is intentionally broad within an isolated student AWS account, covering the networking and VM operations in this lab. It is not a production least-privilege policy and must not be used as-is in a shared account. S3 access is scoped to the existing lab state and lock objects. It does not grant state-bucket creation or IAM administration. The same role handles planning and applying in this starter pipeline.

The workflow requests a one-hour temporary session. Official reference: [AWS credential action](https://github.com/aws-actions/configure-aws-credentials).

## 5. Azure: create an application and federated credential

In Microsoft Entra ID > App registrations, create `github-multicloud-lab`. Record its Application (client) ID and Directory (tenant) ID. Under Certificates & secrets > Federated credentials, add a credential with:

| Field | Value |
|---|---|
| Issuer | `https://token.actions.githubusercontent.com` |
| Subject | Exact `sub` from the identity workflow |
| Audience | `api://AzureADTokenExchange` |
| Name | `github-lab` |

Use the custom issuer/subject option if the GitHub wizard generates a different subject. Assign the application's service principal Contributor on the **isolated student subscription**, because the existing Terraform creates a resource group. For a shared subscription, pre-create the group and refactor the Terraform before restricting its role to that group.

Register Microsoft.Compute and Microsoft.Network once using your WSL admin session (README commands). CI disables automatic provider registration. AzureRM reads GitHub OIDC directly using ARM_USE_OIDC, so this workflow does not need an Azure client secret or a separate Azure CLI login. References: [AzureRM authentication](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) and [Azure federation subjects](https://learn.microsoft.com/entra/workload-id/workload-identities-github-immutable-subjects).

## 6. GCP: service account and workload identity federation

In the selected GCP project, enable Compute Engine, IAM, IAM Service Account Credentials, Security Token Service and Service Usage APIs. Create a service account named `github-multicloud-lab` with these project roles for the isolated lab:

- Compute Admin (`roles/compute.admin`).
- Service Usage Admin (`roles/serviceusage.serviceUsageAdmin`) because this Terraform manages the Compute API service.
- Service Usage Consumer (`roles/serviceusage.serviceUsageConsumer`).

Create a workload identity pool `github-lab` and an OIDC provider `github` with issuer `https://token.actions.githubusercontent.com`. Use the provider's default audience unless you deliberately configure another audience in both the provider and auth action.

Attribute mappings:

```text
google.subject          = assertion.sub
attribute.repository_id = assertion.repository_id
attribute.ref           = assertion.ref
```

Restrict the provider with an attribute condition, replacing both placeholders:

```text
assertion.repository_id == 'YOUR_NUMERIC_REPOSITORY_ID' && assertion.ref == 'refs/heads/main' && assertion.sub == 'YOUR_EXACT_SUB'
```

On the deployment service account, grant Workload Identity User (`roles/iam.workloadIdentityUser`) to this principal set, using the project **number**, not project ID:

```text
principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-lab/attribute.repository_id/REPOSITORY_ID
```

Save the provider resource name and service-account email for GitHub. Federation configuration requires an administrator initially; the deployment account itself does not need permission to manage its own trust. See [GCP GitHub authentication](https://github.com/google-github-actions/auth) and [deployment federation configuration](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines).

## 7. Add GitHub configuration variables

Under repository Settings > Secrets and variables > Actions > Variables, add:

| Variable | Example / source |
|---|---|
| AWS_ROLE_ARN | `arn:aws:iam::123456789012:role/github-multicloud-lab` |
| AWS_REGION | State-bucket region, e.g. `us-east-1` |
| AZURE_CLIENT_ID | Entra application client ID |
| AZURE_TENANT_ID | Entra directory ID |
| GCP_WORKLOAD_IDENTITY_PROVIDER | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-lab/providers/github` |
| GCP_SERVICE_ACCOUNT | `github-multicloud-lab@PROJECT_ID.iam.gserviceaccount.com` |

These are identifiers, not passwords. The Azure subscription ID and GCP project ID come from `ci/lab-config.json`. **No AWS access key, Azure client secret, GCP JSON key or SSH private key is needed in GitHub.** The cloud providers issue temporary credentials to the trusted workflow identity.

## 8. First deployment

1. Push the completed configuration. Confirm Validate Terraform succeeds.
2. Run Plan cloud changes on main, select `deploy`, and enter your exact lab name.
3. Review the Terraform log and downloaded `plan.txt`. Confirm the account IDs, regions, costs and any resource replacements are expected. Record the run ID from the summary.
4. Run Apply reviewed plan on the **same main commit**, paste the plan run ID and enter `DEPLOY`.
5. Wait for completion, inspect outputs and run the application's health/failover checks from README.md. Terraform success alone does not prove startup scripts or monitoring are healthy.

The plan must be from a successful manual plan workflow, match the current main commit and lab, and be less than 24 hours old. Artifacts are retained for one day. If you merge another commit, generate a new plan. A changed remote state causes Terraform to reject a stale saved plan; generate and review a new one rather than bypassing locking.

Only the plan directory is uploaded, not credentials or the `.terraform` directory. Nonetheless Terraform plans can contain sensitive values; repository and artifact access must stay restricted. Authentication is repeated in each job; credentials are not passed in the artifact. Action versions are specified by release tags; pin audited commit SHAs before production use.

## 9. Teardown and cost control

Run Plan cloud changes with operation `destroy` and the exact lab name. Review its deletion list. Then run Apply reviewed plan with that run ID and `DESTROY`. This removes the root lab resources, not the separately bootstrapped S3 bucket or the manually created federation identities.

No scheduled destroy is configured. You control when the student lab is removed. GitHub-hosted runner minutes/storage can also have limits or charges; check your GitHub allowance.

## 10. Common errors

| Error | Fix |
|---|---|
| Cloud jobs skipped | Run main in a private repository |
| AWS role cannot be assumed | Exact subject, audience and role ARN; trust provider exists |
| Azure no matching federated credential | Exact subject and `api://AzureADTokenExchange` audience |
| GCP impersonation denied | Provider condition, numeric project/repository IDs and service-account IAM binding |
| Missing configuration | Complete JSON, copy RSA public key, set all six variables |
| Provider registration denied | Register Azure providers from admin WSL session |
| State AccessDenied | Exact S3 key, bucket permissions and lockfile delete permission |
| Source run mismatch / stale plan | New successful plan from current main; use that run ID |
| Quota or SKU unavailable | Select supported regions/sizes and generate a new plan |
| Destroy fails midway | Inspect remaining state/resources, renew plan, retry; never delete state to hide the error |

These files are prepared locally. They have not been connected to your repository or run against your cloud accounts.
