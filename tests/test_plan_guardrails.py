import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check_plan.py"
BASE = {"resource_changes": [{"mode": "managed", "type": "aws_instance", "address": "aws_instance.demo", "change": {"actions": ["create"], "after": {
    "instance_type": "t4g.micro", "subnet_id": "subnet-06218381657578b32", "associate_public_ip_address": False,
    "credit_specification": [{"cpu_credits": "standard"}], "metadata_options": [{"http_tokens": "required"}],
    "root_block_device": [{"encrypted": True, "volume_size": 8, "volume_type": "gp3"}]
}}}]}
class Guardrails(unittest.TestCase):
    def run_plan(self, plan, mode="apply"):
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as f:
            json.dump(plan, f); f.flush()
            return subprocess.run([sys.executable, str(SCRIPT), f.name, mode], capture_output=True).returncode
    def test_micro_allowed(self):
        self.assertEqual(self.run_plan(BASE), 0)
    def test_larger_instance_rejected(self):
        plan = copy.deepcopy(BASE); plan["resource_changes"][0]["change"]["after"]["instance_type"] = "t4g.large"
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_public_address_rejected(self):
        plan = copy.deepcopy(BASE); plan["resource_changes"][0]["change"]["after"]["associate_public_ip_address"] = True
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_unencrypted_disk_rejected(self):
        plan = copy.deepcopy(BASE); plan["resource_changes"][0]["change"]["after"]["root_block_device"][0]["encrypted"] = False
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_unexpected_infrastructure_rejected(self):
        plan = copy.deepcopy(BASE); plan["resource_changes"][0]["type"] = "aws_nat_gateway"
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_destroy_must_be_explicit(self):
        plan = copy.deepcopy(BASE); plan["resource_changes"][0]["change"] = {"actions": ["delete"], "after": None}
        self.assertNotEqual(self.run_plan(plan), 0)
        self.assertEqual(self.run_plan(plan, "destroy"), 0)

    def test_multiple_instances_rejected(self):
        plan = copy.deepcopy(BASE); plan["resource_changes"].append(copy.deepcopy(plan["resource_changes"][0]))
        self.assertNotEqual(self.run_plan(plan), 0)

class S3Guardrails(unittest.TestCase):
    run_plan = Guardrails.run_plan
    def s3_plan(self):
        bucket = "mhugley-ec2-demo-data-283678155577-us-east-1"
        configs = {
            "aws_s3_bucket": {"bucket": bucket, "force_destroy": False},
            "aws_s3_bucket_public_access_block": {"bucket": None, "block_public_acls": True, "block_public_policy": True, "ignore_public_acls": True, "restrict_public_buckets": True},
            "aws_s3_bucket_ownership_controls": {"bucket": None, "rule": [{"object_ownership": "BucketOwnerEnforced"}]},
            "aws_s3_bucket_server_side_encryption_configuration": {"bucket": None, "rule": [{"apply_server_side_encryption_by_default": [{"sse_algorithm": "AES256"}]}]},
            "aws_s3_bucket_versioning": {"bucket": None, "versioning_configuration": [{"status": "Enabled"}]},
            "aws_s3_bucket_policy": {"bucket": None, "policy": json.dumps({"Version": "2012-10-17", "Statement": [{"Effect": "Deny", "Principal": "*", "Action": "s3:*", "Resource": [f"arn:aws:s3:::{bucket}", f"arn:aws:s3:::{bucket}/*"], "Condition": {"Bool": {"aws:SecureTransport": "false"}}}]})},
            "aws_s3_bucket_lifecycle_configuration": {"bucket": None},
        }
        return {"resource_changes": [{"mode": "managed", "type": kind, "address": f"module.data_bucket.{kind}.data", "change": {"actions": ["create"], "after": after}} for kind, after in configs.items()]}
    def test_secure_bucket_allowed(self):
        self.assertEqual(self.run_plan(self.s3_plan()), 0)
    def test_public_bucket_rejected(self):
        plan = self.s3_plan(); plan["resource_changes"][1]["change"]["after"]["block_public_policy"] = False
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_force_destroy_rejected(self):
        plan = self.s3_plan(); plan["resource_changes"][0]["change"]["after"]["force_destroy"] = True
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_other_bucket_rejected(self):
        plan = self.s3_plan(); plan["resource_changes"][0]["change"]["after"]["bucket"] = "unapproved-bucket"
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_public_policy_rejected(self):
        plan = self.s3_plan(); policy = json.loads(plan["resource_changes"][5]["change"]["after"]["policy"])
        policy["Statement"][0]["Effect"] = "Allow"
        plan["resource_changes"][5]["change"]["after"]["policy"] = json.dumps(policy)
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_encryption_change_rejected(self):
        plan = self.s3_plan(); plan["resource_changes"][3]["change"]["after"]["rule"][0]["apply_server_side_encryption_by_default"][0]["sse_algorithm"] = "aws:kms"
        self.assertNotEqual(self.run_plan(plan), 0)
    def test_suspended_versioning_rejected(self):
        plan = self.s3_plan(); plan["resource_changes"][4]["change"]["after"]["versioning_configuration"][0]["status"] = "Suspended"
        self.assertNotEqual(self.run_plan(plan), 0)

    def test_missing_public_access_block_rejected(self):
        plan = self.s3_plan(); del plan["resource_changes"][1]
        self.assertNotEqual(self.run_plan(plan), 0)
