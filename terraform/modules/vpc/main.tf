# ──────────────────────────────────────
# VPC
# ──────────────────────────────────────
resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:VPC Flow Logs는 CloudWatch 수집·보관에 상시 과금. PoC 사이클에서 미채택(docs/security-baseline.md)
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ──────────────────────────────────────
# Internet Gateway
# ──────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ──────────────────────────────────────
# Public Subnets
# ──────────────────────────────────────
resource "aws_subnet" "public" {
  # EKS 퍼블릭 서브넷은 로드밸런서와 노드가 퍼블릭 IP를 받아야 동작한다.
  # map_public_ip_on_launch=false로 두면 ALB 배치가 실패한다 — 끄는 것이
  # 정답인 일반 서브넷과 다르다. (checkov CKV_AWS_130)
  #checkov:skip=CKV_AWS_130:EKS ELB용 퍼블릭 서브넷 — 퍼블릭 IP 자동 할당이 기능 요건
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                            = "${var.project_name}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/role/elb"                        = "1"
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
  }
}

# ──────────────────────────────────────
# Private Subnets (EKS nodes)
# ──────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                                            = "${var.project_name}-private-${var.availability_zones[count.index]}"
    "kubernetes.io/role/internal-elb"               = "1"
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
    "karpenter.sh/discovery"                        = "${var.project_name}-eks"
  }
}

# ──────────────────────────────────────
# NAT Gateway (single AZ for cost saving)
# ──────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# ──────────────────────────────────────
# Route Tables
# ──────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ──────────────────────────────────────
# 기본 보안 그룹 — 규칙을 비워 둔다
#
# VPC를 만들면 AWS가 default SG를 자동 생성하는데, 기본값이 "자기 자신에서
# 오는 모든 트래픽 허용 + 모든 이그레스"다. 아무도 명시적으로 붙이지 않아도
# 리소스가 실수로 이걸 물면 통제 밖의 통신이 열린다.
# 이 리소스는 SG를 새로 만들지 않는다 — 기존 default SG를 Terraform 관리로
# 가져와 ingress/egress를 모두 제거한다. (checkov CKV2_AWS_12)
# ──────────────────────────────────────
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  # ingress·egress 블록을 비워 두면 모든 규칙이 제거된다

  tags = {
    Name = "${var.project_name}-default-sg-locked"
  }
}
