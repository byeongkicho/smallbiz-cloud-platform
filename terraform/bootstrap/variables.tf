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

variable "github_repository" {
  description = <<-EOT
    OIDC를 신뢰할 저장소, `owner/repo` 형식.

    이 값이 신뢰 정책의 `sub` 조건으로 들어간다. 여기가 틀리면 다른
    저장소의 워크플로가 이 계정의 역할을 수임할 수 있다.
  EOT
  type        = string
  default     = "byeongkicho/smallbiz-cloud-platform"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository는 'owner/repo' 형식이어야 한다."
  }
}

variable "state_bucket" {
  description = "루트 구성의 state가 있는 S3 버킷"
  type        = string
  default     = "smallbiz-tfstate-apne2-35354da0"
}

variable "state_lock_table" {
  description = "state 잠금 DynamoDB 테이블"
  type        = string
  default     = "smallbiz-tfstate-lock"
}
