"""Fail closed on cost/security changes. Input is `terragrunt show -json plan`."""
import json
import sys

plan = json.load(open(sys.argv[1]))
mode = sys.argv[2] if len(sys.argv) > 2 else "apply"
errors = []
allowed = {"aws_instance", "aws_security_group"}
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
if any(count > 1 for count in counts.values()):
    errors.append("At most one instance and one security group are allowed")
if errors:
    sys.exit("Plan guardrails failed: " + "; ".join(errors))
print("Plan guardrails passed: micro only, existing network, encryption, IMDSv2, no open ports.")
print("Estimated running cost: $0.0084/hour EC2 + $0.64/month gp3 (730h: ~$6.77/month), excluding tax and small S3/Actions usage.")
