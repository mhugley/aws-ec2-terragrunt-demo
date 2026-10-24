# Security

Never commit credentials, state files, binary plans, or secrets. GitHub Actions uses AWS OIDC with repository-bound subjects; no AWS access keys are stored in GitHub. The plan role cannot modify EC2 or write Terraform state (only the lock object). The deployment role is limited to this project's tagged resources, the approved AMI/subnet, and a micro instance. Bootstrap IAM and state resources are outside the deployment role's permissions.

Only main may deploy through the dev environment. Same-repository PRs can receive a read-only cloud plan; fork PRs receive credential-free CI only. A collaborator who can modify and execute a same-repository PR can read demo state, so grant write access only to trusted people. State contains infrastructure identifiers and can become sensitive if the module changes.

The EC2 instance has no public IP, no SSH key, no instance role, no ingress/egress rules, IMDSv2, and encrypted root storage. Existing networking is read only. Network reachability/SSM is intentionally unavailable in the current subnet. Pin upgrades and review dependency PRs before merging.

For a security issue, contact the repository owner privately. Do not disclose credentials in issues.

The data bucket blocks public access and ACLs, uses SSE-S3, versioning, and a deny-HTTP policy. Workflow S3 permissions reference only its exact ARN, without direct object permissions. Nonempty bucket deletion is deliberately blocked by force_destroy=false. Bootstrap IAM remains administrator-managed.
