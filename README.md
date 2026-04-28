# 🏢 Small Business Cloud Platform

> 소규모 기업의 비용 효율적이고 안정적인 클라우드 인프라 운영을 위한 포트폴리오 프로젝트
> A career-transition portfolio in production-style SMB cloud architecture.

## 💡 Why this project

A career-transition portfolio: from a social-work undergrad to infrastructure engineering, currently delivering daily L1 enterprise IT support through a global IT delivery chain. This repo is the production-grade end of that learning trajectory — built end-to-end on my own AWS account, `terraform apply`-ed and verified, then destroyed for cost control.

The "small business" framing matters. Most cloud architecture content assumes either FAANG-scale problems or hello-world demos. SMBs sit between: they need real availability, IaC, GitOps, and observability — but every line item must justify its monthly cost. This project is my answer to that gap.

What this project demonstrates:

- **Production patterns, not toy code** — IRSA, AWS Load Balancer Controller, ArgoCD GitOps, modular Terraform with separate `vpc` / `eks` / `rds` modules
- **Cost-conscious decisions, documented** — single-AZ NAT, `t3.micro` RDS, Spot-ready node groups, with explicit trade-offs in [`docs/cost-analysis.md`](docs/cost-analysis.md)
- **Repeatable infrastructure** — clean `terraform apply` from zero state to working cluster, then `terraform destroy` to control burn
- **Operations notes** (in progress) — real apply lessons captured for future-me and reviewers

## 📐 Architecture

```
User
  ↓
CloudFront (CDN)
  ↓
ALB (AWS Load Balancer Controller + Ingress)
  ↓
EKS Cluster (Kubernetes 1.31)
  ├── App Pods (Deployment + Service)
  ├── HPA (Horizontal Pod Autoscaler)
  └── Karpenter (Auto Node Provisioning)
  ↓
RDS MySQL 8.0 (Private Subnet)

+ S3 (static assets / backups)
+ CloudWatch + Container Insights (observability)
+ ArgoCD (GitOps CD)
+ GitHub Actions (CI)
+ Terraform (IaC)
```

## 🛠 Tech Stack

| Category | Technology |
|---|---|
| IaC | Terraform >= 1.5 |
| Container Orchestration | AWS EKS (Kubernetes 1.31) |
| Node Management | Karpenter |
| Ingress | AWS Load Balancer Controller |
| CI | GitHub Actions |
| CD | ArgoCD (GitOps) |
| Database | RDS MySQL 8.0 |
| Monitoring | CloudWatch Container Insights, Prometheus, Grafana |
| CDN | CloudFront |
| Region | ap-northeast-2 (Seoul) |

## 🎯 Design Decisions

### Why Kubernetes (EKS)?
- 서비스 확장 시 Pod 단위 스케일링으로 비용 효율적 대응
- Helm Chart 기반 표준화된 배포 → 운영 인력 최소화
- 멀티 클라우드 이식성 확보 (vendor lock-in 방지)

### Why Karpenter over Cluster Autoscaler?
- 노드 프로비저닝 속도 향상 (30초 이내)
- 인스턴스 타입 자동 선택으로 비용 최적화
- 2025~2026 기준 AWS 공식 권장 방식

### Why ArgoCD?
- GitOps: Git을 Single Source of Truth로 사용
- 배포 이력 추적 / 롤백 용이
- kubectl 직접 실행 대비 안정성 + 감사 추적 우수

### Cost Optimization (소규모 기업 관점)
- NAT Gateway: 단일 AZ (비용 절감, 프로덕션에서는 이중화 권장)
- Karpenter: 워크로드 기반 노드 자동 스케일링으로 유휴 비용 최소화
- RDS: db.t3.micro 시작 → 필요 시 스케일업
- Spot Instance 활용 가능 (Karpenter 설정)

## 📁 Project Structure

```
aws-portfolio/
├── README.md
├── terraform/
│   ├── main.tf              # Module composition
│   ├── provider.tf          # AWS + K8s + Helm providers
│   ├── variables.tf         # Input variables
│   ├── outputs.tf           # Output values
│   ├── versions.tf          # Provider version constraints
│   ├── terraform.tfvars     # Variable values
│   └── modules/
│       ├── vpc/             # VPC, Subnets, NAT, Routes
│       ├── eks/             # EKS Cluster, Node Group, OIDC, ALB Controller
│       └── rds/             # RDS PostgreSQL (Phase 2)
├── k8s/                     # Kubernetes manifests (Phase 2)
│   ├── app/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   └── hpa.yaml
│   └── argocd/
│       └── application.yaml
└── .github/
    └── workflows/
        └── ci.yaml          # GitHub Actions CI pipeline
```

## 🚀 Implementation Phases

### Phase 1 ✅ — Foundation
- [x] Terraform project structure
- [x] VPC (Public/Private Subnets, NAT, Routes)
- [x] EKS Cluster + Managed Node Group
- [x] AWS Load Balancer Controller
- [x] OIDC Provider (IRSA)

### Phase 2 ✅ — Application & Data
- [x] Sample app Deployment + Service + Ingress
- [x] HPA configuration
- [x] RDS MySQL 8.0
- [x] K8s Secrets (DB credentials)
- [x] ArgoCD installation & app registration

### Phase 3 📋 — Operations & Observability
- [ ] CloudWatch Container Insights
- [ ] Prometheus + Grafana (optional)
- [ ] GitHub Actions CI pipeline
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
