# ──────────────────────────────────────
# General
# ──────────────────────────────────────
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "smallbiz-platform"
}

variable "environment" {
  description = "Environment (dev / staging / prod)"
  type        = string
  default     = "dev"
}

# ──────────────────────────────────────
# VPC
# ──────────────────────────────────────
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to use (min 2 for EKS)"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (EKS nodes)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ──────────────────────────────────────
# EKS
# ──────────────────────────────────────
variable "eks_cluster_version" {
  description = <<-EOT
    Kubernetes version for EKS.

    1.34를 쓰는 이유: 표준 지원 종료가 2026-12-02로 아직 남아 있다.
    표준 지원이 끝난 버전은 확장 지원 요금이 붙어 제어 플레인이
    시간당 $0.10 → $0.60 (6배)이 된다.

    2026-04 사이클에서 이 값이 실제로 문제가 됐다 — 클러스터가 1.30/1.31로
    43시간 돌았고, 청구서 $34.48 중 $21.56(63%)이 확장 지원 할증이었다.
    리소스를 더 쓴 것이 아니라 버전을 안 올려서 낸 돈이다.
    근거: docs/evidence/2026-04-apply-cycle.md
  EOT
  type        = string
  default     = "1.34"
}

variable "eks_node_instance_types" {
  description = "Instance types for the managed node group (Karpenter는 미구현 — README 로드맵 참조)"
  type        = list(string)
  default     = ["t3.medium", "t3.large"]
}

# ──────────────────────────────────────
# RDS (Phase 2)
# ──────────────────────────────────────
variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Database admin username"
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "db_password" {
  description = "Database admin password"
  type        = string
  sensitive   = true
}
