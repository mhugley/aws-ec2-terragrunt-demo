# Private micro EC2 with Terraform, Terragrunt, and GitHub Actions

[![CI](https://github.com/mhugley/aws-ec2-terragrunt-demo/actions/workflows/ci.yml/badge.svg)](https://github.com/mhugley/aws-ec2-terragrunt-demo/actions/workflows/ci.yml)

One Amazon Linux 2023 ARM64 **t4g.micro** in the existing `personal-dev-vpc`, `us-east-1`. Terraform owns only the instance and its dedicated security group. Terragrunt supplies environment inputs and encrypted, versioned S3 state with native locking. Bootstrap provisions the state bucket and two narrowly scoped GitHub OIDC roles; the existing OIDC provider is reused.

## Cost and connectivity

On-demand Linux t4g.micro: **$0.0084/hour**, approximately $6.13/month at 730 hours. One 8 GiB gp3 root disk adds about $0.64/month: **~$6.77/month**, before tax and small S3/Actions charges. Estimate checked against AWS Pricing API on 2026-10-24; no free-tier credit assumed. Standard CPU credits prevent surplus CPU credit charges. No NAT, public IPv4, load balancer, detailed monitoring, or paid VPC endpoints are created.

The existing subnet has only a local route and no SSM endpoints. The instance therefore has **no interactive shell or internet access**. This demo verifies deployment, EC2 health, encryption, metadata security, and isolation through AWS APIs. Adding SSM or an application is a separate network design change.

## Workflows

- **CI**: Terraform/Terragrunt formatting, locked provider initialization, Terraform validation, TFLint, actionlint, plan-policy tests, and Trivy IaC scanning. No AWS credentials required.
- **Terraform plan**: same-repository PR plans with a read-only OIDC role, a refreshed PR comment, short-lived text-plan artifact, and cost/security guardrails. Fork PRs cannot obtain AWS credentials.
- **Deploy EC2**: manually select `plan`, `apply`, or `destroy` on `main`. Apply executes the exact fresh plan produced and checked in the same job. EC2 health and actual AWS configuration are verified after apply. Destroy requires `confirmation=destroy-ec2-demo` and verifies the state is empty of managed demo resources.
- **Drift detection**: weekly Monday 13:23 UTC and manual runs. Opens one drift issue, closes it on recovery, and never auto-applies.
- Dependabot updates Actions/provider dependencies weekly. Actions are pinned to commit SHAs; Terragrunt/actionlint downloads are checksum verified. CODEOWNERS, PR/issue templates, branch protection, and a main-only deployment environment support review.

All state-accessing workflows share a non-cancelling concurrency group and S3 locks. Jobs have timeouts, minimal token permissions, and short artifact retention. Plans/state are not committed; binary plans and state are never uploaded as artifacts. Terraform/Terragrunt versions and provider lock files are committed.

## Deploy or remove

```bash
# Plan only
gh workflow run deploy.yml --repo mhugley/aws-ec2-terragrunt-demo --ref main -f operation=plan
# Deploy, then verify health
gh workflow run deploy.yml --repo mhugley/aws-ec2-terragrunt-demo --ref main -f operation=apply
# Remove the instance and dedicated security group
gh workflow run deploy.yml --repo mhugley/aws-ec2-terragrunt-demo --ref main -f operation=destroy -f confirmation=destroy-ec2-demo
```

Deleting/stopping the instance outside Terraform causes drift. Use the destroy workflow to stop compute/storage charges; the small state bucket and OIDC roles remain for redeployment. Drift detection will report the declared instance as missing after an intentional destroy; disable that schedule if the demo is retired.

## Local use

Install Terraform 1.15.4 and Terragrunt 1.2.1, then authenticate AWS SSO:

```bash
export AWS_PROFILE=popeye
export AWS_REGION=us-east-1
aws sts get-caller-identity
cd live/dev/ec2
terragrunt init
terragrunt plan
```

The provider rejects the wrong AWS account. The module rejects a non-micro type, a mismatched VPC/subnet, and a non-ARM64 AMI. CI plan policy further forbids new resource types, public IPs, open ports, large/unencrypted disks, instance roles, and SSH keys. A trusted maintainer must update both IAM and source code to change the pinned AMI.

## Bootstrap / recovery

Bootstrap is administrator-only and is **never run by deployment Actions**. Its state lives in the same bucket under `bootstrap/terraform.tfstate`; Actions roles can access only `dev/ec2/`. The state bucket has deletion protection and 30-day old-version retention. It does not use a DynamoDB table or customer-managed KMS key.

For this first deployment bootstrap was applied locally with `AWS_PROFILE=popeye`, then its local state migrated to S3. To reproduce in a new account, update the account/network/repository identifiers, temporarily omit `bootstrap/backend.tf` for the first apply, then restore it and run `terraform init -migrate-state`. Never commit a local state file. For changes in this account:

```bash
AWS_PROFILE=popeye terraform -chdir=bootstrap init
AWS_PROFILE=popeye terraform -chdir=bootstrap plan
# Review the bootstrap plan before applying it as an administrator.
```

The deploy workflow does not auto-run on merge. Merge reviewed PRs, then dispatch an apply on main. Weekly drift flags pending changes as well as changes made outside Terraform. Emergency rollback: revert the change through a PR and apply a new plan, or dispatch destroy for this demo stack.
