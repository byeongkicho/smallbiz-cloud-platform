variable "project_name" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "upgrade_support_type" {
  description = "EKS 업그레이드 정책. STANDARD = 표준 지원 종료 시 자동 업그레이드(확장 지원 요금 없음) / EXTENDED = 확장 지원 진입(요금 6배)"
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXTENDED"], var.upgrade_support_type)
    error_message = "upgrade_support_type 은 STANDARD 또는 EXTENDED 여야 한다."
  }
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "node_instance_types" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}
