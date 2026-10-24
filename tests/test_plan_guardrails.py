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
