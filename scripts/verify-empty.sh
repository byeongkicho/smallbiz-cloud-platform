#!/usr/bin/env bash
# verify-empty.sh — destroy 후 잔존 리소스가 없는지 확인한다.
#
# terraform destroy가 "Destroy complete"를 출력해도 그것만으로는 부족하다.
# 컨트롤러가 만든 리소스(ALB·k8s-* 보안그룹)는 state 밖에 있어서 Terraform이
# 모르고, 스냅샷·로그그룹은 destroy 대상이 아니다.
#
# 사용: ./scripts/verify-empty.sh   (0 = 깨끗, 1 = 잔존 있음)
#
# ⚠️ 이 스크립트로도 최종 판정은 못 한다. 다음날 Cost Explorer에서 해당
#    서비스가 $0인지 확인하는 것이 마지막 관문이다.

set -uo pipefail
REGION="${AWS_REGION:-ap-northeast-2}"
FOUND=0

check() {
  local label="$1"; shift
  local out
  out="$("$@" 2>/dev/null)" || out=""
  if [[ -n "${out// /}" && "$out" != "None" ]]; then
    printf '🔴 %-22s %s\n' "$label" "$out"
    FOUND=1
  else
    printf '✅ %-22s -\n' "$label"
  fi
}

echo "=== $REGION 잔존 리소스 점검 ==="

check "EKS 클러스터"    aws eks list-clusters --region "$REGION" --query 'clusters' --output text
check "EC2 인스턴스"    aws ec2 describe-instances --region "$REGION" \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' --output text
check "로드밸런서"      aws elbv2 describe-load-balancers --region "$REGION" \
  --query 'LoadBalancers[].LoadBalancerName' --output text
check "타깃그룹"        aws elbv2 describe-target-groups --region "$REGION" \
  --query 'TargetGroups[].TargetGroupName' --output text
check "NAT 게이트웨이"  aws ec2 describe-nat-gateways --region "$REGION" \
  --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text
check "미연결 EIP"      aws ec2 describe-addresses --region "$REGION" \
  --query 'Addresses[?AssociationId==null].PublicIp' --output text
check "미사용 EBS"      aws ec2 describe-volumes --region "$REGION" \
  --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text
check "EBS 스냅샷"      aws ec2 describe-snapshots --region "$REGION" --owner-ids self \
  --query 'Snapshots[].SnapshotId' --output text
check "RDS 인스턴스"    aws rds describe-db-instances --region "$REGION" \
  --query 'DBInstances[].DBInstanceIdentifier' --output text
check "RDS 수동 스냅샷" aws rds describe-db-snapshots --region "$REGION" --snapshot-type manual \
  --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
# default-* 서브넷그룹은 AWS가 계정/VPC마다 자동 생성하며 삭제 대상이 아니다.
# 오탐을 남겨두면 경고 전체를 무시하게 되므로 제외한다.
check "RDS 서브넷그룹"  aws rds describe-db-subnet-groups --region "$REGION" \
  --query 'DBSubnetGroups[?!starts_with(DBSubnetGroupName, `default`)].DBSubnetGroupName' --output text
check "프로젝트 VPC"    aws ec2 describe-vpcs --region "$REGION" \
  --filters Name=cidr,Values=10.0.0.0/16 --query 'Vpcs[].VpcId' --output text
check "유휴 ENI"        aws ec2 describe-network-interfaces --region "$REGION" \
  --filters Name=status,Values=available --query 'NetworkInterfaces[].NetworkInterfaceId' --output text
# 컨트롤러가 만든 SG는 k8s- 접두를 갖는다. default는 지울 수 없으므로 제외.
check "k8s-* 보안그룹"  aws ec2 describe-security-groups --region "$REGION" \
  --query 'SecurityGroups[?starts_with(GroupName, `k8s-`)].GroupId' --output text
check "EKS 로그그룹"    aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix /aws/eks/ --query 'logGroups[].logGroupName' --output text
check "IAM OIDC 공급자" aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[].Arn' --output text

echo
if [[ $FOUND -eq 0 ]]; then
  echo "✅ 잔존 없음. 단, 최종 판정은 다음날 Cost Explorer에서."
else
  echo "🔴 잔존 있음 — 위 항목을 수동 회수할 것. 순서는 docs/operations.md §7-1."
fi
exit $FOUND
