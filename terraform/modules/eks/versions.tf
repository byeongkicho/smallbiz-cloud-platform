# 모듈은 자기가 쓰는 provider를 스스로 선언한다.
#
# 이 파일이 없어서 CI가 실패했다(run 31860730402): 모듈 단독 검증에서
# helm provider가 최신 3.x로 해석됐고, 3.x는 `set { ... }` 블록을
# `set = [{ ... }]` 속성으로 바꾼 파괴적 변경을 담고 있다. 루트는
# `helm ~> 2.12`로 고정돼 있어 통과했으므로, 이 결함은 모듈을 다른
# 루트에서 재사용할 때에야 드러났을 것이다.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
