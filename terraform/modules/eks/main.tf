# ──────────────────────────────────────
# EKS Cluster IAM Role
# ──────────────────────────────────────
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# ──────────────────────────────────────
# EKS Cluster
# ──────────────────────────────────────
resource "aws_eks_cluster" "main" {
  # 아래 4건은 checkov가 지적하지만 이 저장소에서는 의도적으로 두었다.
  # 항목별 근거는 docs/security-baseline.md.
  #checkov:skip=CKV_AWS_58:EKS Secrets 암호화용 KMS 키는 상시 과금 + 삭제 대기 7~30일이라 apply/destroy 반복과 맞지 않는다
  #checkov:skip=CKV_AWS_37:제어 플레인 전체 로그를 CloudWatch로 보내면 수집·보관이 상시 과금된다
  #checkov:skip=CKV_AWS_39:퍼블릭 엔드포인트를 끄면 bastion/VPN 없이 kubectl이 불가능해 PoC 운영 자체가 막힌다
  #checkov:skip=CKV_AWS_38:위와 같은 이유. 프로덕션이라면 사무실 고정 IP로 CIDR을 좁히는 것이 정답이다
  name     = "${var.project_name}-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Enable IRSA (IAM Roles for Service Accounts)
  # This is auto-enabled for clusters >= 1.13

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]

  tags = {
    Name = "${var.project_name}-eks"
  }
}

# ──────────────────────────────────────
# EKS Node Group (managed — initial bootstrap)
# Karpenter will take over after bootstrap
# ──────────────────────────────────────
resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node.name
}

resource "aws_eks_node_group" "bootstrap" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-bootstrap"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = var.node_instance_types
  version         = var.cluster_version

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "general"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]

  tags = {
    Name = "${var.project_name}-bootstrap-node"
  }
}

# ──────────────────────────────────────
# OIDC Provider (for IRSA — Karpenter, ALB Controller 등)
# ──────────────────────────────────────
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-eks-oidc"
  }
}

# ──────────────────────────────────────
# AWS Load Balancer Controller (via Helm)
# ──────────────────────────────────────
resource "aws_iam_role" "alb_controller" {
  name = "${var.project_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      # sub 와 aud 를 함께 고정한다.
      #
      # sub 만 걸면 이 클러스터의 OIDC 공급자가 발급한 토큰 중 대상(aud)이
      # 다른 것까지 수임에 쓰일 수 있다. 서비스 계정 토큰은 용도별로 다른
      # audience 로 발급될 수 있으므로, STS 용으로 발급된 토큰만 받도록
      # aud = sts.amazonaws.com 을 명시한다.
      #
      # 같은 기준을 GitHub Actions OIDC(terraform/bootstrap)에도 적용했다.
      # 한쪽에만 적용하면 그 자체가 리뷰에서 질문거리가 된다.
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# ──────────────────────────────────────────────────────────────
# ALB Controller IAM 정책 — 공식 정책을 저장소에 vendoring
#
# 🔴 이 리소스가 존재하는 이유는 2026-04 사이클의 실패 때문이다.
# 당시 이 역할에는 관리형 `ElasticLoadBalancingFullAccess`만 붙어 있었다.
# 이름만 보면 충분해 보이지만 그 정책에는 **EC2 조회 권한이 없다.**
# 컨트롤러는 서브넷을 자동 탐색하기 위해 ec2:DescribeSubnets /
# DescribeSecurityGroups / DescribeVpcs 와 iam:CreateServiceLinkedRole 이
# 필요한데, 이것들이 빠져 있으면 **파드는 정상 기동하고 helm은 `deployed`를
# 보고한 뒤, 첫 Ingress 조정 시점에서야 조용히 실패한다.**
# 그 결과 ALB가 한 번도 만들어지지 않았고, 4개월 뒤 ELB 청구가 0건인 것을
# 보고서야 알았다. 상세: docs/operations.md §1
#
# 정책 본문은 컨트롤러 프로젝트가 배포하는 공식 파일을 그대로 vendoring했다.
#   출처: kubernetes-sigs/aws-load-balancer-controller
#         v2.7.1/docs/install/iam_policy.json  (helm 차트 1.7.1의 appVersion)
# 손으로 추린 최소 권한 대신 공식 정책을 쓰는 이유는, 이 컨트롤러의 권한
# 요구가 버전마다 바뀌고 누락 시 위처럼 조용히 실패하기 때문이다.
# 차트 버전을 올릴 때 이 JSON도 같은 태그에서 다시 받아야 한다.
# ──────────────────────────────────────────────────────────────
resource "aws_iam_policy" "alb_controller" {
  name        = "${var.project_name}-alb-controller-policy"
  description = "Official AWS Load Balancer Controller policy (vendored from v2.7.1)"
  policy      = file("${path.module}/policies/alb-controller-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  policy_arn = aws_iam_policy.alb_controller.arn
  role       = aws_iam_role.alb_controller.name
}

# metrics-server — HPA 의 전제이자 ArgoCD 헬스 판정의 전제다.
#
# 이것이 없으면 HPA 가 `ScalingActive=False` (FailedGetResourceMetric) 로 남고,
# ArgoCD 는 그 HPA 를 Degraded 로 판정한다. 즉 파드가 2/2 Running 이고 앱이
# 정상 응답해도 **Application 은 영구 Synced/Degraded** 다.
# k8s/app/hpa.yaml 이 Application 의 동기화 경로(path: k8s/app) 안에 있으므로 해당된다.
#
# kind 실측(2026-08-18): 제거 → 11초 만에 Healthy→Degraded / 재설치 → 47초 만에 복귀.
# EKS 는 metrics-server 가 기본 탑재가 아니다(Auto Mode 제외) → 명시적으로 설치한다.
#
# ⚠️ `--kubelet-insecure-tls` 를 넣지 말 것. 그건 kind 노드의 자체서명 kubelet 인증서
#    때문에 필요한 로컬 전용 플래그이고, EKS 에 넣으면 TLS 검증을 스스로 끄는 것이 된다.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.1"

  set {
    name  = "replicas"
    value = "1"
  }

  depends_on = [aws_eks_node_group.bootstrap]
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "region"
    value = "ap-northeast-2"
  }

  depends_on = [aws_eks_node_group.bootstrap]
}
