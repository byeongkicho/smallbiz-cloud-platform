terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # 원격 state. 버킷·테이블은 Terraform으로 만들지 않는다 — 상태를 보관할
  # 곳을 상태로 관리하면 닭-달걀이 된다. CLI로 부트스트랩했고 그 명령은
  # docs/operations.md에 기록했다.
  #
  # 버킷: 버전관리 + SSE(AES256) + 퍼블릭 액세스 전면 차단 + 비현행 버전 90일 만료
  # 잠금: DynamoDB(PAY_PER_REQUEST). Terraform 1.10+의 S3 네이티브 잠금
  #      (use_lockfile)을 쓰면 테이블이 필요 없지만, 로컬이 1.5.7에 묶여 있다
  #      (Homebrew 정식 formula가 BUSL 전환으로 1.5.7에서 중단됨). CI도 같은
  #      버전으로 고정해 스큐를 없앴다. 업그레이드는 README 로드맵 참조.
  backend "s3" {
    bucket         = "smallbiz-tfstate-apne2-35354da0"
    key            = "smallbiz-cloud-platform/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "smallbiz-tfstate-lock"
    encrypt        = true
  }
}
