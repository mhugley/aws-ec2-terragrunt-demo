"""Fail closed on cost/security changes. Input is `terragrunt show -json plan`."""
import json
import sys

plan = json.load(open(sys.argv[1]))
mode = sys.argv[2] if len(sys.argv) > 2 else "apply"
errors = []
BUCKET = "mhugley-ec2-demo-data-283678155577-us-east-1"
S3_TYPES = {'aws_s3_bucket_public_access_block', 'aws_s3_bucket', 'aws_s3_bucket_ownership_controls', 'aws_s3_bucket_policy', 'aws_s3_bucket_lifecycle_configuration', 'aws_s3_bucket_versioning', 'aws_s3_bucket_server_side_encryption_configuration'}
allowed = {"aws_instance", "aws_security_group"} | S3_TYPES
counts = {kind: 0 for kind in allowed}
for change in plan.get("resource_changes", []):
    if change.get("mode") != "managed":
        continue
    if change["type"] not in allowed:
        errors.append(f"Unexpected resource type: {change['type']}")
    after = change["change"].get("after")
    if after is None:
        if mode != "destroy":
            errors.append(f"Deletion requires the explicit destroy workflow: {change['address']}")
        continue
    if change["type"] in counts:
        counts[change["type"]] += 1
    kind = change["type"]
    if kind in S3_TYPES:
        # Configuration resources reference a bucket ID that is unknown until creation.
        # The bucket resource name, IAM resource ARN, and companion resources are fixed.
        if after.get("bucket") not in (None, BUCKET):
            errors.append("Unexpected S3 bucket name")
        if kind == "aws_s3_bucket" and (after.get("bucket") != BUCKET or after.get("force_destroy") is not False):
            errors.append("Only the approved bucket without force-destroy is allowed")
        if kind == "aws_s3_bucket_public_access_block" and not all(after.get(k) is True for k in ("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets")):
            errors.append("S3 public access must be completely blocked")
        if kind == "aws_s3_bucket_ownership_controls" and after.get("rule", [{}])[0].get("object_ownership") != "BucketOwnerEnforced":
            errors.append("S3 ACLs must be disabled")
        if kind == "aws_s3_bucket_server_side_encryption_configuration":
            defaults = after.get("rule", [{}])[0].get("apply_server_side_encryption_by_default", [{}])[0]
            if defaults.get("sse_algorithm") != "AES256":
                errors.append("S3 must use SSE-S3 encryption")
        if kind == "aws_s3_bucket_versioning" and after.get("versioning_configuration", [{}])[0].get("status") != "Enabled":
            errors.append("S3 versioning must remain enabled")
        if kind == "aws_s3_bucket_policy":
            policy = json.loads(after.get("policy") or "{}")
            statements = policy.get("Statement", [])
            resources = {f"arn:aws:s3:::{BUCKET}", f"arn:aws:s3:::{BUCKET}/*"}
            if len(statements) != 1 or statements[0].get("Effect") != "Deny" or statements[0].get("Principal") != "*" or statements[0].get("Action") != "s3:*" or set(statements[0].get("Resource", [])) != resources or statements[0].get("Condition") != {"Bool": {"aws:SecureTransport": "false"}}:
                errors.append("S3 policy must only deny insecure transport, without granting public access")
    if change["type"] == "aws_instance":
        checks = {
            "micro only": after.get("instance_type") == "t4g.micro",
            "approved subnet": after.get("subnet_id") == "subnet-06218381657578b32",
            "no public IP": after.get("associate_public_ip_address") is False,
            "no SSH key": not after.get("key_name"),
            "no instance IAM role": not after.get("iam_instance_profile"),
            "standard CPU credits": after.get("credit_specification", [{}])[0].get("cpu_credits") == "standard",
            "IMDSv2": after.get("metadata_options", [{}])[0].get("http_tokens") == "required",
        }
        disks = after.get("root_block_device", [])
        checks["encrypted 8 GiB gp3 root"] = len(disks) == 1 and disks[0].get("encrypted") is True and disks[0].get("volume_size") == 8 and disks[0].get("volume_type") == "gp3"
        errors.extend(name for name, ok in checks.items() if not ok)
    if change["type"] == "aws_security_group":
        if after.get("vpc_id") != "vpc-0b57a3944dfc414b6" or after.get("ingress") or after.get("egress"):
            errors.append("Security group must remain isolated in the existing VPC")
if any(counts[k] for k in S3_TYPES) and mode != "destroy" and any(counts[k] != 1 for k in S3_TYPES):
    errors.append("The S3 bucket requires all seven security/lifecycle resources")
if any(count > 1 for count in counts.values()):
    errors.append("At most one resource of each approved type is allowed")
if errors:
    sys.exit("Plan guardrails failed: " + "; ".join(errors))
print("Plan guardrails passed: micro only, existing network, encryption, IMDSv2, no open ports; private encrypted S3.")
print("Estimated running cost: $0.0084/hour EC2 + $0.64/month gp3 (730h: ~$6.77/month), plus usage-based S3 storage/requests, tax, and Actions usage.")
