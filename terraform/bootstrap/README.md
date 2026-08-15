# bootstrap — CI가 AWS에 접근하는 방법

GitHub Actions가 이 계정에서 `terraform plan`을 돌릴 수 있게 하는 **최소 구성**이다.
관리하는 리소스는 4개뿐이고 전부 IAM이라 **비용이 0원**이다.

| 리소스 | 역할 |
|---|---|
| `aws_iam_openid_connect_provider.github` | GitHub의 OIDC 토큰을 이 계정이 신뢰하게 만든다 |
| `aws_iam_role.gha_terraform_plan` | 워크플로가 수임하는 역할 |
| `aws_iam_role_policy_attachment.read_only` | 관리형 `ReadOnlyAccess` |
| `aws_iam_role_policy.tfstate_access` | state 읽기 + 잠금(쓰기는 잠금 테이블에만) |

## 왜 계층을 나눴나

이 역할은 **CI가 루트 state를 읽을 때 쓰는 바로 그 역할**이다.
루트 구성과 같은 state에 넣으면, 역할을 잘못 건드린 PR이 머지되는 순간
CI가 자기 자신을 잠근다. 되돌리려면 다시 로컬 관리자 자격증명으로 내려와야 한다.

권한을 **부여하는** 계층과 **소비하는** 계층은 생애주기가 다르다. 그래서 state를 나눴다.

```
s3://smallbiz-tfstate-apne2-35354da0/
├── smallbiz-cloud-platform/terraform.tfstate    ← 루트 (VPC·EKS·RDS)
└── smallbiz-cloud-platform/bootstrap.tfstate    ← 이 디렉터리 (IAM·OIDC)
```

state를 담을 S3 버킷과 잠금 테이블 자체는 여전히 Terraform 밖에 있다(CLI 부트스트랩,
`docs/operations.md`). 그건 "state를 **담을 곳**"이고 이건 "state를 **읽을 권한**"이라 층이 다르다.

## 신뢰 정책 — 이 파일에서 가장 중요한 부분

```hcl
"token.actions.githubusercontent.com:sub" = [
  "repo:byeongkicho/smallbiz-cloud-platform:pull_request",
  "repo:byeongkicho/smallbiz-cloud-platform:ref:refs/heads/main",
]
```

- 조건은 `StringEquals`다. `StringLike` + `repo:owner/repo:*` 로 두면 그 저장소의
  **모든 ref·모든 environment**가 수임 가능해진다. 흔한 실수이고, 실수의 결과가 조용하다.
- `aud`는 `sts.amazonaws.com`으로 고정 — `configure-aws-credentials`가 요청하는 값과 같아야 한다.
- 태그 푸시, 다른 브랜치, `workflow_dispatch`의 다른 ref는 전부 **거부**된다.

## 권한을 어디까지 줬나 — 트레이드오프

**준 것**: 관리형 `ReadOnlyAccess` + state 잠금(DynamoDB 쓰기 3종).

`plan`은 실제 인프라를 읽어 코드와 대조해야 한다. 이 구성 하나가 VPC·EKS·IAM·RDS·EC2에
걸쳐 있어서, 최소권한 정책을 손으로 적으면 **plan이 권한 부족으로 깨지는 쪽이 훨씬 잦다**.
그 실패는 "코드가 틀렸다"와 구분이 안 되기 때문에 CI 신호를 오염시킨다.

**안 준 것**이 안전장치다:

- 쓰기 권한 없음 → 이 역할로는 **apply가 성공할 수 없다**.
- `s3:PutObject` 없음 → state를 읽고 잠글 수는 있어도 **덮어쓸 수 없다**.
  `plan`은 state를 갱신하지 않으므로(Terraform 0.15+) 기능에 지장이 없고,
  CI가 사고로 state를 망가뜨리는 경로가 닫힌다.

즉 범위는 넓지만 **방향이 한쪽**이다. 나중에 apply까지 CI로 옮긴다면 그때는
읽기 범위를 좁히는 것보다 **별도 역할을 만들어 환경 승인 게이트를 거는 것**이 순서다.

## 왜 액세스 키를 안 쓰나

대안은 `AWS_ACCESS_KEY_ID`를 저장소 Secrets에 넣는 것이었다. 하지 않은 이유:

- 공개 저장소에 **무기한 유효한** 자격증명이 존재하게 된다
- 유출되면 만료가 없어 사람이 회수할 때까지 계속 유효하다
- CloudTrail에서 어느 워크플로가 썼는지 구분되지 않는다

OIDC는 실행 1건당 단기 토큰을 발급하고, **어떤 저장소의 어떤 이벤트가** 수임했는지가
신뢰 정책과 CloudTrail 양쪽에 남는다.

## 적용

한 번만 실행하면 된다. 이후 CI가 알아서 이 역할을 쓴다.

```bash
cd terraform/bootstrap
terraform init
terraform plan     # 4 to add
terraform apply

# 출력된 ARN을 저장소 시크릿으로 등록 (계정 번호를 저장소에 커밋하지 않기 위해)
gh secret set AWS_ROLE_ARN --body "$(terraform output -raw gha_role_arn)"
```

## 한계 — 명시

- **`plan`만 한다.** apply는 여전히 로컬에서 사람이 실행한다.
- 부트스트랩 계층 자체는 **CI로 관리되지 않는다** — 여기를 CI에 맡기면 CI가 자기 권한을
  스스로 넓힐 수 있게 된다.
- fork에서 온 PR은 시크릿에 접근할 수 없어 이 워크플로가 실패한다.
  문법 검증은 자격증명이 필요 없는 `terraform-validate.yaml`이 계속 담당한다.
