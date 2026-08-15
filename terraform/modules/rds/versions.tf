# 모듈은 자기가 쓰는 provider를 스스로 선언한다.
# 없으면 루트에서는 동작하지만 모듈 단독 검증(terraform init -backend=false)
# 때 최신 provider가 해석되어 루트와 다른 버전으로 검사된다.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
