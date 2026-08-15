# Evidence — 2026-04 apply/destroy cycle

이 문서는 README의 주장을 뒷받침하는 **1차 근거**다. 출처는 두 가지뿐이며 둘 다 사후 편집이 불가능하다:

1. **로컬 Terraform state 백업 5개** (`terraform/terraform.tfstate*`, 커밋하지 않음 — 계정 식별자 포함)
2. **AWS Cost Explorer 청구 데이터** (2026-08-15 조회)

계정 ID·클러스터 엔드포인트·VPC ID는 마스킹했다.

---

## 1. state serial 궤적

| 파일 | serial | 리소스 수 | 시각 (KST) |
|---|---:|---:|---|
| `terraform.tfstate.1775018265.backup` | 44 | 24 | 2026-04-01 13:37 |
| `terraform.tfstate.1775165186.backup` | 72 | 18 | 2026-04-03 06:26 |
| `terraform.tfstate.1775165194.backup` | 73 | 17 | 2026-04-03 06:26 |
| `terraform.tfstate.backup` | 74 | 16 | 2026-04-03 06:26 |
| `terraform.tfstate` | 93 | **0** | 2026-04-03 06:35 |

serial 93 / 리소스 0 = **destroy가 끝까지 완료됨**. 중단이나 부분 실패가 아니다.

## 2. 청구 데이터가 확정하는 것 (2026-04-01 ~ 04-03)

사용 유형별 실청구 (서울 `ap-northeast-2`):

| 사용 유형 | 수량 | 금액 |
|---|---:|---:|
| `APN2-AmazonEKS-Hours:perCluster` | 43.127 h | $4.3127 |
| **`APN2-AmazonEKS-Hours:extendedSupport`** | **43.127 h** | **$21.5633** |
| `APN2-BoxUsage:t3.medium` | 82.124 h | $4.2705 |
| `APN2-NatGateway-Hours` | 44.000 h | $2.5960 |
| `APN2-InstanceUsage:db.t3.micro` | **38.418 h** | $0.9989 |
| `APN2-PublicIPv4:InUseAddress` | 43.148 h | $0.2157 |
| `APN2-EBS:VolumeUsage.gp3` | 2.282 GB-mo | $0.2081 |
| `APN2-NatGateway-Bytes` | 1.691 GB | $0.0998 |
| `APN2-RDS:GP3-Storage` | 1.067 GB-mo | $0.1398 |
| 기타 (Regional 전송·GuardDuty·백업) | | $0.0779 |
| **합계** | | **$34.48** |

### 여기서 확정되는 사실

- **클러스터 가동 43.13시간.** 3~4시간 세션 의도가 43시간이 됐다 (생성 04-01 02:28Z → destroy 완료 04-02 21:35Z).
- **RDS는 실제로 생성되어 38.42시간 가동됐다.** state 백업 5개에는 잡히지 않았는데(93개 serial 중 5개만 보존), 청구 데이터에 `db.t3.micro` 38.418시간이 남아 있다. **state 부재를 미생성의 근거로 쓰면 안 된다는 사례.**
- 🔴 **ALB는 한 번도 생성되지 않았다.** ELB 계열 청구가 **0건**이고, 공인 IPv4도 43시간분 **1개**(NAT 게이트웨이용)만 과금됐다. ALB가 떴다면 AZ당 1개씩 최소 2개가 더 잡혔어야 한다. → `helm_release.alb_controller`는 `deployed`였지만 **컨트롤러가 Ingress를 실제 로드밸런서로 만들지는 못했다.** 원인 분석은 `../operations.md` 참조.
- 노드 82.12시간 = 2대 × 약 41시간.

## 3. EKS 버전과 extended support 할증

state에서:

- serial 44 (04-01 13:37): `aws_eks_cluster.main` **version 1.30**, `status ACTIVE`, `created_at 2026-04-01T02:28:11Z`
- serial 72 이후 (04-03 06:26): **version 1.31**
- → 같은 클러스터를 **1.30 → 1.31로 in-place 업그레이드**했다.

그런데 2026-04 기준 1.30·1.31은 **둘 다 표준 지원이 종료된 버전**이었다. 그 결과:

```
perCluster       43.127h × $0.10 = $ 4.31
extendedSupport  43.127h × $0.50 = $21.56   ← 순수 버전 지연 할증
                                    ------
EKS 합계                            $25.88
```

**청구서 $34.48 중 $21.56(63%)이 "버전을 안 올려서" 낸 돈이다.** 리소스를 하나도 더 쓰지 않고 발생한 비용이며, 표준 지원 버전을 썼다면 총액은 $12.92였다.

이 사이클 당시 코드의 버전 고정값은 세 곳이 서로 달랐다(`variables.tf`=1.29, `terraform.tfvars.example`=1.31, README=1.31, 실제 가동=1.30 → 1.31). 정정 내역은 `../../README.md`의 검증 수준 표와 커밋 이력 참조.

## 4. helm 릴리스 상태 변화

| state | `alb_controller` | `argocd` |
|---|---|---|
| serial 44 | `pending-install` (chart 1.7.1) | (없음) |
| serial 72 | `deployed` (1.7.1) | `deployed` (argo-cd 6.4.0) |
| serial 73 | `deployed` | (제거됨) |
| serial 74 | (제거됨) | — |

→ 두 차트 모두 최종적으로 `deployed`에 도달했다. **다만 "helm 설치 성공"과 "그 컨트롤러가 의도한 리소스를 만들었다"는 다른 명제다** — ALB 청구 0건이 그 차이를 보여준다.

## 5. 정리 상태

2026-08-15 기준 서울 리전 전수 조회 결과 **잔존 리소스 0건** (EKS·EC2·ELB·NAT·EIP·EBS·RDS·스냅샷·IAM OIDC 공급자·`smallbiz*` 역할 전부 없음). destroy는 고아 리소스를 남기지 않았다.

## 6. 이 문서를 만든 이유

이 저장소는 4월 이후 3.5개월간 방치돼 있었고, README는 apply 여부를 서술로만 주장하고 있었다. **주장과 근거를 분리해 두면 나중에 "무엇이 검증됐고 무엇이 아닌지"를 다시 판별할 수 있다.** 실제로 이 문서를 만드는 과정에서 두 가지가 뒤집혔다.

- state에 없어서 "RDS 미생성"으로 판단할 뻔했으나, **청구 데이터가 38.4시간 가동을 증명**했다
- helm이 `deployed`라서 "ALB 동작"으로 볼 뻔했으나, **ELB 청구 0건이 미생성을 증명**했다

둘 다 한 종류의 증거만 봤으면 반대로 결론 났을 것이다.
