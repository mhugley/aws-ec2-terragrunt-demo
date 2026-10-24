#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root/live/dev/ec2"
id="$(terragrunt output -raw instance_id)"
aws ec2 wait instance-status-ok --instance-ids "$id"
aws ec2 describe-instances --instance-ids "$id" --output json > "$root/outputs.json"
python3 - "$root/outputs.json" <<'CHECK'
import json, sys
instances = [i for r in json.load(open(sys.argv[1]))['Reservations'] for i in r['Instances']]
assert len(instances) == 1
instance = instances[0]
assert instance['State']['Name'] == 'running'
assert instance['InstanceType'] == 't4g.micro'
assert instance['VpcId'] == 'vpc-0b57a3944dfc414b6'
assert instance['SubnetId'] == 'subnet-06218381657578b32'
assert not instance.get('PublicIpAddress')
assert instance['MetadataOptions']['HttpTokens'] == 'required'
print('EC2 health and configuration checks passed:', instance['InstanceId'])
CHECK
sg="$(terragrunt output -raw security_group_id)"
aws ec2 describe-security-groups --group-ids "$sg" --query 'SecurityGroups[0]' --output json | python3 -c 'import json,sys; s=json.load(sys.stdin); assert not s["IpPermissions"] and not s["IpPermissionsEgress"]; print("Security group isolation verified")'
volume="$(aws ec2 describe-instances --instance-ids "$id" --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)"
aws ec2 describe-volumes --volume-ids "$volume" --output json | python3 -c 'import json,sys; v=json.load(sys.stdin)["Volumes"][0]; assert v["Encrypted"] and v["Size"] == 8 and v["VolumeType"] == "gp3"; print("Encrypted 8 GiB gp3 root verified")'
[[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || echo "EC2 health checks passed: **$id** (private t4g.micro)." >> "$GITHUB_STEP_SUMMARY"
