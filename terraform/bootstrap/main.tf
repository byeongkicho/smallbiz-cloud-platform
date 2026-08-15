data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────────────────────────
# GitHub Actions OIDC 공급자
#
# 이걸 만드는 목적은 하나다: GitHub Actions에 **장기 액세스 키를 주지 않는 것**.
# 대안이었던 `AWS_ACCESS_KEY_ID`를 저장소 Secrets에 넣는 방식은
#   - 공개 저장소에 무기한 유효한 자격증명이 존재하게 되고
#   - 유출 시 만료가 없어 회수 전까지 계속 유효하며
#   - 어떤 워크플로가 썼는지 CloudTrail에서 구분되지 않는다.
# OIDC는 실행 1건당 15분~1시간짜리 토큰을 발급하고, 어떤 저장소·어떤 이벤트가
# 수임했는지가 신뢰 정책과 CloudTrail 양쪽에 남는다.
# ──────────────────────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # `aud` 클레임. configure-aws-credentials가 요청하는 기본값과 같아야 한다.
  client_id_list = ["sts.amazonaws.com"]

  # thumbprint_list는 의도적으로 비워 둔다 — AWS provider가 현재 루트 CA를
  # 조회해 채운다. 값을 하드코딩하면 GitHub이 인증서를 교체하는 날
  # (2023-06에 실제로 있었다) CI가 통째로 죽는다.
}

# ──────────────────────────────────────────────────────────────
# 신뢰 정책 — 누가 이 역할을 수임할 수 있는가
#
# 🔴 여기가 이 파일에서 가장 중요한 부분이다.
# `sub`를 한정하지 않으면(예: `repo:owner/repo:*`) 누구든 그 저장소를 포크해
# 워크플로를 돌리는 것으로는 안 되지만, 저장소 안의 **어떤 ref·어떤 환경**이든
# 수임할 수 있게 된다. 여기서는 두 경우만 허용한다:
#   - pull_request 이벤트 (plan을 보여주는 용도)
#   - main 브랜치 push  (머지 후 재확인)
# 태그·다른 브랜치·environment는 전부 거부된다.
# ──────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "gha_assume_role" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringEquals이지 StringLike가 아니다 — 와일드카드를 쓸 수 없게 한다.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:pull_request",
        "repo:${var.github_repository}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "gha_terraform_plan" {
  name        = "${var.project_name}-gha-terraform-plan"
  description = "GitHub Actions가 terraform plan을 실행할 때 수임하는 역할 (plan 전용, apply 불가)"

  assume_role_policy   = data.aws_iam_policy_document.gha_assume_role.json
  max_session_duration = 3600
}

# ──────────────────────────────────────────────────────────────
# 권한 ①: 리소스 읽기
#
# plan은 실제 인프라를 읽어 코드와 대조해야 하므로 광범위한 Describe/List/Get이
# 필요하다. 이 구성 하나만 해도 VPC·EKS·IAM·RDS·EC2에 걸쳐 있어, 최소권한 정책을
# 손으로 쓰면 plan이 권한 부족으로 깨지는 쪽이 훨씬 잦다.
#
# 그래서 관리형 ReadOnlyAccess를 쓰되, **쓰기 권한을 한 줄도 주지 않는 것**으로
# 안전성을 확보한다. 이 역할로는 apply가 성공할 수 없다.
# 트레이드오프는 이 디렉터리의 README.md에 기록.
# ──────────────────────────────────────────────────────────────
resource "aws_iam_role_policy_attachment" "read_only" {
  role       = aws_iam_role.gha_terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ──────────────────────────────────────────────────────────────
# 권한 ②: state 백엔드
#
# ReadOnlyAccess가 S3 읽기와 DynamoDB 읽기는 이미 포함하지만, **잠금은 쓰기**다
# (PutItem/DeleteItem). 그 부분만 명시적으로 준다.
#
# 🔴 s3:PutObject는 주지 않는다. plan은 state를 갱신하지 않기 때문이다
# (Terraform 0.15+). 결과적으로 이 역할은 state를 읽고 잠글 수는 있어도
# **덮어쓸 수 없다** — CI가 사고로 state를 망가뜨리는 경로가 닫힌다.
# ──────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "tfstate_access" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }

  statement {
    sid       = "ReadStateObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/*"]
  }

  statement {
    sid    = "StateLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.state_lock_table}",
    ]
  }
}

resource "aws_iam_role_policy" "tfstate_access" {
  name   = "tfstate-backend-access"
  role   = aws_iam_role.gha_terraform_plan.id
  policy = data.aws_iam_policy_document.tfstate_access.json
}
