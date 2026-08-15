terraform {
  # 루트 구성과 같은 버전에 고정한다. 로컬 1.5.7 · CI 1.5.7.
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # 부트스트랩은 루트 구성과 **다른 state**를 쓴다.
  #
  # 이유: 여기서 만드는 IAM 역할이 CI가 루트 state를 읽을 때 쓰는 바로 그
  # 역할이다. 같은 state에 넣으면 역할을 잘못 수정한 plan이 머지되는 순간
  # CI가 자기 자신을 잠근다 — 복구하려면 다시 로컬 자격증명으로 내려와야 한다.
  # 권한을 부여하는 계층과 권한을 소비하는 계층은 생애주기가 달라야 한다.
  #
  # 버킷 자체는 여전히 Terraform 밖이다(CLI 부트스트랩, docs/operations.md).
  # 그건 "state를 담을 곳"이고, 이건 "state를 읽을 권한"이라 층이 다르다.
  backend "s3" {
    bucket         = "smallbiz-tfstate-apne2-35354da0"
    key            = "smallbiz-cloud-platform/bootstrap.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "smallbiz-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = var.project_name
      Layer     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}
