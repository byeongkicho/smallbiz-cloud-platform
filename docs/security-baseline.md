# 보안 기준선 — checkov 정적 분석

> `checkov`(Prisma Cloud)를 Terraform 구성 전체에 돌린 결과와, **고친 것과 고치지 않은 것의 판단 근거**.
> 재현: `uvx checkov -d terraform --framework terraform --compact`

## 결과

| | 최초 실행 | 현재 |
|---|---:|---:|
| Passed | 81 | **87** |
| **Failed** | **17** | **0** |
| Skipped (사유 명시) | 0 | **11** |

**Failed 0은 "지적이 없었다"는 뜻이 아니다.** 17건 중 6건은 실제로 고쳤고, 11건은 코드에 `#checkov:skip=<ID>:<사유>`로 근거를 남기고 남겼다. 아래가 그 내역이다.

## ✅ 고친 것 (6건) — 비용 0, 기능 영향 없음

| 체크 | 내용 | 조치 |
|---|---|---|
| `CKV_AWS_161` | RDS IAM 인증 미사용 | `iam_database_authentication_enabled = true` — 비밀번호 외 인증 경로 확보 |
| `CKV_AWS_226` | 마이너 버전 자동 업그레이드 꺼짐 | `auto_minor_version_upgrade = true` — 보안 패치 자동 적용 |
| `CKV2_AWS_60` | 스냅샷에 태그 미승계 | `copy_tags_to_snapshot = true` — 비용 추적 태그가 스냅샷까지 |
| `CKV_AWS_382` | RDS SG 이그레스가 `0.0.0.0/0` | VPC CIDR로 축소. **RDS는 아웃바운드로 먼저 연결을 여는 일이 없다** — 관행적으로 붙던 규칙이었다 |
| `CKV_AWS_23` | SG와 규칙에 설명 없음 | 보안 그룹 자체와 이그레스 규칙에 `description` 추가 |
| `CKV2_AWS_12` | VPC 기본 보안 그룹이 열려 있음 | `aws_default_security_group`으로 **기존 default SG를 관리에 편입해 규칙을 전부 제거**. 새 SG를 만드는 게 아니라 방치돼 있던 것을 잠그는 것 |

> 기본 보안 그룹이 특히 중요하다. AWS가 VPC마다 자동 생성하고 기본값이 "자기 자신 발 모든 트래픽 + 모든 이그레스"인데, 아무도 명시적으로 붙이지 않아도 리소스가 실수로 물면 통제 밖 통신이 열린다. Terraform 코드에 등장하지 않으니 리뷰에서도 안 보인다.

## ⏭️ 남긴 것 (11건) — 근거

### 상시 과금이 붙는 것 — PoC 운영 패턴과 충돌

이 저장소는 `apply → 작업 → destroy` 사이클이 전제다([`cost-analysis.md`](cost-analysis.md)). 클러스터가 없는 동안에도 돈이 나가는 항목은 채택하지 않았다.

| 체크 | 내용 | 남긴 이유 |
|---|---|---|
| `CKV_AWS_58` | EKS Secrets 암호화(KMS) | KMS 키는 **상시 과금 + 삭제 대기 7~30일**. destroy해도 키가 남아 사이클마다 잔재가 쌓인다 |
| `CKV_AWS_37` | EKS 제어 플레인 전체 로깅 | CloudWatch Logs 수집·보관이 상시 과금 |
| `CKV_AWS_129` | RDS 로그 CloudWatch 전송 | 위와 동일 |
| `CKV_AWS_118` | RDS enhanced monitoring | 분당 지표 수집에 별도 과금 |
| `CKV2_AWS_11` | VPC Flow Logs | 수집·보관 과금. 트래픽이 적어 얻는 정보 대비 비용이 크다 |
| `CKV_AWS_157` | RDS Multi-AZ | 월 $19 → $38. 단일 AZ는 RTO를 감수한 의도적 선택 |

### 기능을 막는 것

| 체크 | 내용 | 남긴 이유 |
|---|---|---|
| `CKV_AWS_293` | RDS 삭제 방지 | **`deletion_protection`은 `destroy`를 막는다.** 이 저장소의 운영 패턴과 정면 충돌하고, 켜두면 "지웠다고 생각했는데 과금되는" 상황을 만든다 |
| `CKV_AWS_39` `CKV_AWS_38` | EKS 퍼블릭 엔드포인트 | 끄면 bastion/VPN 없이 `kubectl`이 불가능해 PoC 운영 자체가 막힌다. **프로덕션이라면 정답은 "끄기"가 아니라 사무실 고정 IP로 CIDR을 좁히는 것** |
| `CKV_AWS_130` (×2) | 퍼블릭 서브넷 자동 공인 IP | **EKS 퍼블릭 서브넷은 로드밸런서 배치에 퍼블릭 IP 자동 할당이 기능 요건**이다. 일반 서브넷에서는 끄는 게 맞지만 여기서는 끄면 ALB가 배치되지 않는다 |

## 🎯 통과한 것 중 기록해 둘 것

`terraform/bootstrap/`의 GitHub Actions OIDC 구성이 **관련 체크를 모두 통과했다.**

| 체크 | 내용 | 결과 |
|---|---|---|
| `CKV_AWS_393` | GitHub Actions OIDC 인가 정책이 안전한 클레임과 **클레임 순서**만 허용하는가 (IAM 역할) | **PASSED** |
| `CKV_AWS_358` | 동일 검사 (정책 문서) | **PASSED** |

`sub`를 와일드카드 없이 `repo:<owner>/<repo>:pull_request`와 `refs/heads/main` 두 값에 `StringEquals`로 고정한 설계가 이 검사의 요구와 일치한다. `StringLike` + `:*` 형태였다면 실패했을 항목이다.

## CI 연동 — 왜 soft-fail인가

`.github/workflows/terraform-validate.yaml`에 붙이되 **잡을 실패시키지 않는다**(`soft_fail: true`).

- checkov의 기본 정책은 **엔터프라이즈 프로덕션 기준**이다. PoC 저장소에 그대로 적용하면 위 표의 "의도적으로 안 하는 것"들 때문에 CI가 상시 빨강이 된다
- **상시 빨강인 게이트는 아무도 안 본다.** 신호가 죽는다
- 대신 결과를 잡 요약에 게시해 **변화를 눈에 보이게** 한다. 새 지적이 생기면 이 문서에 항목을 추가하거나 고치는 것이 절차다

## 한계

- 정적 분석은 **코드에 적힌 것만** 본다. 런타임 설정, IAM 정책의 실제 유효 권한, 컨테이너 이미지 취약점은 범위 밖이다
- `skip`은 검사를 끄는 것이지 위험이 사라지는 것이 아니다. 프로덕션으로 갈 때 **위 두 표를 그대로 체크리스트로 쓰는 것**이 이 문서의 용도다
