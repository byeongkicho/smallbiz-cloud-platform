# 🏢 Small Business Cloud Platform

[![Terraform Validate](https://github.com/byeongkicho/smallbiz-cloud-platform/actions/workflows/terraform-validate.yaml/badge.svg)](https://github.com/byeongkicho/smallbiz-cloud-platform/actions/workflows/terraform-validate.yaml)
[![Terraform Plan](https://github.com/byeongkicho/smallbiz-cloud-platform/actions/workflows/terraform-plan.yaml/badge.svg)](https://github.com/byeongkicho/smallbiz-cloud-platform/actions/workflows/terraform-plan.yaml)

> 소규모 기업의 비용 효율적이고 안정적인 클라우드 인프라 운영을 위한 포트폴리오 프로젝트
> A career-transition portfolio in production-style SMB cloud architecture.

## ✅ 검증 수준 — 무엇이 실제로 확인됐나

이 저장소의 모든 주장은 두 가지 1차 근거로만 뒷받침한다: **Terraform state 백업**과 **AWS 청구 데이터**. 근거 원문은 [`docs/evidence/2026-04-apply-cycle.md`](docs/evidence/2026-04-apply-cycle.md).

| 구성요소 | 코드 | apply 검증 | 근거 |
|---|:-:|:-:|---|
| VPC / 서브넷 / 단일 NAT | ✅ | **✅** | state serial 44 · NAT 44.0h 청구 |
| EKS 클러스터 | ✅ | **✅** | 43.13h 청구 · 1.30 생성 후 1.31로 in-place 업그레이드 |
| 관리형 노드그룹 (t3.medium × 2) | ✅ | **✅** | 82.12h 청구 |
| OIDC 공급자 / IRSA | ✅ | **✅** | state |
| RDS MySQL (db.t3.micro) | ✅ | **✅** | **38.42h 청구** (state 백업엔 미포착 — §아래) |
| AWS Load Balancer Controller | ✅ | **설치만** | helm `deployed`. 그러나 **ALB는 생성되지 않았다** — ELB 청구 0건 |
| ArgoCD | ✅ | **설치만** | helm `deployed`. `repoURL`이 placeholder여서 **동기화된 적 없음** |
| HPA | ✅ | ❌ | metrics-server 미설치 |
| Karpenter · CloudFront · S3 · Container Insights | ❌ | — | **코드 0줄.** 아래 로드맵 참조 |

**두 번 뒤집힌 판정이 이 표를 만든 이유다.** state에 `aws_db_instance`가 없어 "RDS 미생성"으로 결론 낼 뻔했으나 청구 데이터가 38.4시간 가동을 증명했고, 반대로 helm이 `deployed`라 "ALB 동작"으로 볼 뻔했으나 ELB 청구 0건이 미생성을 증명했다. **한 종류의 증거만 봤으면 양쪽 다 반대로 적혔을 것이다.**

## 💡 Why this project

A career-transition portfolio: from a social-work undergrad to infrastructure engineering, currently delivering daily L1 enterprise IT support through a global IT delivery chain.

2026-04-01 ~ 04-03에 개인 AWS 계정에서 실제로 `terraform apply` → `terraform destroy`까지 수행했다 (state serial 44 → 93, 리소스 24 → 0). 클러스터 가동 **43.13시간**, 총 청구 **$34.48**. 검증된 범위와 그렇지 않은 범위는 위 표에 그대로 적었다.

The "small business" framing matters. Most cloud architecture content assumes either FAANG-scale problems or hello-world demos. SMBs sit between: they need real availability, IaC, GitOps, and observability — but every line item must justify its monthly cost.

What this project demonstrates:

- **모듈 단위 Terraform** — `vpc` / `eks` / `rds` 분리, IRSA(OIDC), 관리형 노드그룹
- **비용 판단을 문서로** — 단일 AZ NAT, `db.t3.micro`, 그리고 🔴 **청구서 $34.48 중 $21.56(63%)이 EKS 확장 지원 할증**이었다는 실측. 리소스를 더 쓴 게 아니라 **버전을 안 올려서 낸 돈**이다 ([`docs/cost-analysis.md`](docs/cost-analysis.md))
- **destroy까지가 인프라 코드** — serial 93 / 리소스 0으로 완결, 잔존 고아 리소스 0건
- **틀린 것을 틀렸다고 적기** — [`docs/operations.md`](docs/operations.md)

## 📐 Architecture — 실제로 코드가 있는 것만

```
User
  ↓
ALB (AWS Load Balancer Controller + Ingress)   ⚠️ 컨트롤러는 설치됨, ALB 생성은 미검증
  ↓
EKS Cluster (Kubernetes 1.34)
  ├── App Pods (Deployment + Service)
  └── HPA                                       ⚠️ metrics-server 미설치라 미동작
  ↓
RDS MySQL (Private Subnet, db.t3.micro)

+ ArgoCD (설치됨 / 동기화 미검증)
+ GitHub Actions (fmt · validate)
+ Terraform (IaC)
```

**로드맵 (코드 없음 — 다이어그램에 그리지 않는다)**: CloudFront + S3 · Karpenter · CloudWatch Container Insights · Multi-AZ NAT

> 관측성(Prometheus / Grafana / 알림 / SLO)은 이 저장소가 아니라 **실제 운영 중인 서비스**에 있다 → [Gluten-Free_Korea `terraform/` · `monitoring/`](https://github.com/byeongkicho/Gluten-Free_Korea/tree/main/terraform) — 자체 제작 익스포터(지표 15종) → Grafana Cloud → 10패널 대시보드 + 알림 5룰, 전부 Terraform 관리.

## 🛠 Tech Stack

| Category | Technology | 상태 |
|---|---|---|
| IaC | Terraform >= 1.5 | **검증** |
| Container Orchestration | AWS EKS (Kubernetes 1.34) | **검증** |
| Node Management | 관리형 노드그룹 (t3.medium × 2) | **검증** |
| Ingress | AWS Load Balancer Controller | 설치만 |
| CD | ArgoCD (GitOps) | 설치만 |
| Database | RDS MySQL (db.t3.micro) | **검증** |
| CI | GitHub Actions (fmt · validate) | 코드만 |
| Region | ap-northeast-2 (Seoul) | — |
| ~~Karpenter · CloudFront · Container Insights~~ | — | **미구현** |

## 🎯 Design Decisions

### Why Kubernetes (EKS)?
- 서비스 확장 시 Pod 단위 스케일링으로 비용 효율적 대응
- Helm Chart 기반 표준화된 배포 → 운영 인력 최소화
- 멀티 클라우드 이식성 확보 (vendor lock-in 방지)

### Why Karpenter over Cluster Autoscaler? — ⚠️ 로드맵 근거 (미구현)
> 아래는 **선택의 근거이지 구현의 서술이 아니다.** 현재 노드는 관리형 노드그룹(t3.medium × 2 고정)이고 Karpenter 코드는 0줄이다.
- 노드 프로비저닝 속도 향상
- 인스턴스 타입 자동 선택으로 비용 최적화
- 도입 시 `modules/vpc`에 이미 넣어둔 `karpenter.sh/discovery` 서브넷 태그를 사용하게 된다 (태그만 선반영된 상태)

### Why ArgoCD?
- GitOps: Git을 Single Source of Truth로 사용
- 배포 이력 추적 / 롤백 용이
- kubectl 직접 실행 대비 안정성 + 감사 추적 우수

### Cost Optimization (소규모 기업 관점)
- **EKS 버전을 표준 지원 구간에 유지** — 43시간 사이클에서 확장 지원 할증이 $21.56 나왔다. 아키텍처를 바꾸지 않고 총액을 63% 줄일 수 있는 유일한 항목이었고, 실측 전까지는 이게 최대 비용 요인인 줄 몰랐다
- NAT Gateway: 단일 AZ (비용 절감, 프로덕션에서는 이중화 권장)
- RDS: db.t3.micro 시작 → 필요 시 스케일업
- **apply/destroy 사이클로 운영** — 상시 가동 시 월 $210+ 추정. 다만 4월에 3~4시간 의도가 43시간이 됐다. **비용 관리의 실제 대상은 시간당 단가가 아니라 종료 확인이다**
- (로드맵) Karpenter · Spot — 미구현

## 📁 Project Structure

```
aws-portfolio/
├── README.md
├── LICENSE                              # MIT
├── CONTRIBUTING.md
├── .gitignore
├── docs/
│   ├── cost-analysis.md                 # 실청구 역산 단가 · 확장지원 할증 분석
│   ├── security-baseline.md             # checkov 결과 + 고친 것/남긴 것의 근거
│   ├── operations.md                    # 실제로 겪은 장애와 원인
│   └── evidence/                        # state·청구 데이터 기반 1차 근거
├── terraform/
│   ├── main.tf                          # Module composition
│   ├── provider.tf                      # AWS + Kubernetes + Helm providers
│   ├── variables.tf                     # Input variables
│   ├── outputs.tf                       # Output values
│   ├── versions.tf                      # Provider version constraints
│   ├── terraform.tfvars.example         # Copy to terraform.tfvars (gitignored)
│   ├── bootstrap/                       # CI가 AWS에 접근하는 층 (OIDC + plan 전용 역할)
│   │   ├── main.tf                      #   state를 루트와 분리 — 권한 부여/소비 계층 분리
│   │   └── README.md                    #   신뢰 정책·권한 범위·트레이드오프
│   └── modules/
│       ├── vpc/                         # VPC, Subnets, NAT, Routes
│       ├── eks/                         # EKS Cluster, Node Group, OIDC, ALB Controller
│       └── rds/                         # RDS MySQL 8.0
├── k8s/
│   ├── app/
│   │   ├── namespace.yaml
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── hpa.yaml
│   │   └── secret.yaml.example          # Copy to secret.yaml (gitignored)
│   └── argocd/
│       └── application.yaml
└── .github/
    └── workflows/
        ├── terraform-validate.yaml      # PR-time fmt + validate (no AWS creds needed)
        └── terraform-plan.yaml          # PR-time plan (OIDC 수임 · 원격 state · 읽기 전용)
```

## 🔄 CI/CD — PR에서 계획을 먼저 본다

워크플로가 두 층이다. **자격증명이 필요 없는 검사를 앞에** 두는 것이 의도다.

| 워크플로 | AWS 접근 | 잡는 것 |
|---|---|---|
| `terraform-validate.yaml` | 없음 | fmt·문법·모듈 유효성. fork PR에서도 돈다 |
| `terraform-plan.yaml` | **OIDC 단기 토큰** | 실제 계정과 코드의 차이 (`plan` 결과를 잡 요약에 게시) |

**저장소에 장기 AWS 액세스 키가 없다.** GitHub OIDC 공급자를 신뢰하고, 워크플로는 실행
1건당 단기 토큰으로 IAM 역할을 수임한다. 신뢰 정책의 `sub`는 이 저장소의
`pull_request`와 `refs/heads/main` **두 값에만** `StringEquals`로 묶여 있다.

역할은 **읽기 + state 잠금만** 가능하다. `s3:PutObject`가 없어 state를 덮어쓸 수 없고,
쓰기 권한이 없어 **apply가 성공할 수 없다**. 설계 근거와 한계는
[`terraform/bootstrap/README.md`](terraform/bootstrap/README.md).

## 🚀 Implementation Phases

### Phase 1 ✅ — Foundation
- [x] Terraform project structure
- [x] VPC (Public/Private Subnets, NAT, Routes) — **apply 검증**
- [x] EKS Cluster + Managed Node Group — **apply 검증** (43.13h 가동)
- [x] OIDC Provider (IRSA) — **apply 검증**
- [x] AWS Load Balancer Controller — helm `deployed`까지만. **ALB 생성 실패** (원인은 [operations.md](docs/operations.md))

### Phase 2 — Application & Data
- [x] RDS MySQL — **apply 검증** (38.42h 가동)
- [x] Sample app Deployment + Service + Ingress (매니페스트 작성)
- [x] K8s Secrets (DB credentials) — `secret.yaml`은 gitignore
- [x] ArgoCD **설치** — helm `deployed`
- [ ] ArgoCD **Application 동기화** — `repoURL`이 placeholder여서 한 번도 동작한 적 없음 (수정 완료, 재검증 필요)
- [ ] HPA 동작 — metrics-server 미설치

### Phase 3 📋 — Operations & Observability
- [x] GitHub Actions CI 실제 실행 — 첫 실행이 결함 2건 검출 (fmt 위반 · 하위 모듈 `required_providers` 누락)
- [x] Terraform 원격 state (S3 + DynamoDB 잠금)
- [x] **GitHub OIDC + PR 단위 `plan`** — 장기 액세스 키 없이 CI가 역할 수임, plan 결과를 잡 요약에 게시
- [x] **checkov 정적 분석 (soft-fail) + [`security-baseline.md`](docs/security-baseline.md)** — 지적 17건 → **0건**(7건 수정 · 11건은 사유를 코드와 문서에 남기고 의도적으로 유지)
- [ ] CloudWatch Container Insights
- [ ] Karpenter (replace managed node group)
- [ ] CloudFront + S3

## 🔐 Setup Secrets (before first apply)

`terraform.tfvars` and `k8s/app/secret.yaml` are gitignored. Copy from the `.example` files and fill in real values:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp k8s/app/secret.yaml.example k8s/app/secret.yaml
# Edit both files to set a strong db_password (must match in both files)
```

## 🏁 Quick Start

```bash
cd terraform

# Initialize
terraform init

# Preview changes
terraform plan

# Apply (creates real AWS resources — costs apply!)
terraform apply

# Connect kubectl to EKS
aws eks update-kubeconfig --name smallbiz-platform-eks --region ap-northeast-2

# Verify
kubectl get nodes
kubectl get pods -A

# Destroy when done (important for cost!)
terraform destroy
```

## 💡 Future Enhancements
- Karpenter로 Managed Node Group 완전 교체
- Spot Instance 활용한 추가 비용 절감
- Multi-AZ NAT Gateway (고가용성)
- Crossplane을 통한 인프라 추상화
- Internal Developer Platform (IDP) 구축

## 📝 License
Portfolio project by Byeongki Cho
