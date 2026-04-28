# Cost Analysis

> SMB-focused infrastructure must justify every line item. This document breaks down monthly cost for the current architecture (Phase 1 + 2), the deliberate trade-offs taken to reduce cost, and disciplined-PoC operating patterns that bring monthly burn well below steady-state.

## Region & assumptions

- Region: `ap-northeast-2` (Seoul)
- Pricing reference: AWS public pricing as of 2026-Q2 (USD)
- All figures **estimates** — actual cost depends on traffic, data transfer, and ongoing storage growth.

## Steady-state monthly estimate (24×7 operation)

| Component | Spec | Est. monthly |
|---|---|---:|
| EKS control plane | 1 cluster (always-on) | $73 |
| EC2 worker nodes | 2 × `t3.medium` (managed node group) | ~$60 |
| NAT Gateway | **single AZ** (cost trade-off) | ~$32 |
| ALB | 1 (low traffic baseline) | ~$16 |
| RDS | `db.t3.micro` MySQL 8.0, single-AZ, 20GB gp3 | ~$12 |
| EBS volumes | gp3 for nodes + RDS storage | ~$5 |
| Data transfer / misc | NAT + ALB egress at low traffic | ~$10 |
| **Total** | | **~$210 / month** |

> This is the "always running" cost. The PoC operating pattern below brings the realized monthly cost to **~$30–50** for active learning and demo purposes.

## Deliberate cost trade-offs (with risk acknowledged)

| Decision | Saving (vs reference) | Acknowledged risk |
|---|---|---|
| **Single NAT Gateway** instead of AZ-per-NAT | ~$32 / month | If the AZ housing the NAT fails, all private-subnet egress drops. Acceptable for PoC; production would dual-AZ. |
| **`t3.medium` nodes** instead of `t3.large` baseline | ~$60 / month | Less headroom; HPA + Karpenter (Phase 3) compensate. |
| **`db.t3.micro` RDS** instead of `db.t3.small` | ~$12 / month | Limited memory; suitable for SMB workloads, scale up when CPU/memory pressure observed. |
| **Single-AZ RDS** instead of Multi-AZ | ~$12 / month | RTO is restore-from-snapshot rather than auto-failover. Acceptable for non-mission-critical workloads. |
| **`.terraform.lock.hcl` committed**; no remote backend yet | $0 (saves S3+DynamoDB cost) | Single-developer assumption. Move to S3 + DynamoDB lock once team grows. |

## Disciplined PoC operating pattern (recommended for portfolio learning)

Rather than running the full architecture 24×7 (~$210/month), this pattern uses on-demand cycles:

```
Daily learning session
  ├─ terraform apply              (~3–5 min wait)
  ├─ kubectl / argocd / app work  (1–4 hours active)
  └─ terraform destroy            (~5–10 min wait)
```

### Monthly cost under this pattern

- Active hours: assume 8 sessions × 3h = ~24h/month of cluster running
- EKS control plane: 24h × $0.10 = $2.40
- EC2 nodes: ~$2 (Spot-ready setup further reduces this)
- NAT Gateway hourly cost during active hours: ~$1
- ALB during active hours: <$1
- RDS: deletion + snapshot pattern, ~$3 for snapshots + minimal active hours
- Data transfer: minimal at this duty cycle, <$5
- **Estimated total: ~$15–25 / month** in this learning mode

### What enables this pattern

- **Modular Terraform** — `terraform destroy` cleanly removes all resources (modules: `vpc`, `eks`, `rds`)
- **Stateless app pattern** — namespace + manifests can be re-applied via ArgoCD on each new cluster
- **External state intentionally not yet centralized** — single-developer PoC; remote backend recommended for shared work

## Hidden / often-missed costs to watch

- **NAT Gateway data processing** ($0.045/GB) — adds up fast under chatty workloads. VPC endpoints for S3/ECR mitigate.
- **EKS control plane is always-on once `apply`** — $0.10/hour billing starts immediately. Always pair `apply` with a `destroy` plan.
- **EBS snapshots** linger after `destroy` if not explicitly cleaned (RDS snapshot retention in particular).
- **Unused ALB** if you forgot a Service of type LoadBalancer or an Ingress without target — still billed monthly.
- **Data transfer between AZs** — ~$0.01/GB; minor at small scale but can dominate at high traffic.

## Monitoring cost (planned for Phase 3)

- AWS Budgets alert at 50% / 80% / 100% of monthly target ($30 PoC, $250 steady)
- Cost Explorer "Service" + "Tag" grouping (`project=smallbiz-platform`, `environment=dev`)
- (Optional) Karpenter consolidation policy → idle nodes auto-removed

## Key takeaways

1. **The architecture itself is SMB-affordable** at ~$210/month if always-on; the trade-offs above keep it that way.
2. **Disciplined PoC operation** (apply / work / destroy) brings learning cost down by ~10×.
3. **NAT, EKS control plane, ALB** are the recurring fixed costs — these are the items where cost-conscious decisions matter most.
4. **Multi-AZ everything** doubles fixed-cost lines; intentional single-AZ in dev with planned dual-AZ in production is a defensible SMB pattern.

## Future cost optimizations (Phase 3 candidates)

- **Karpenter** with consolidation + Spot — typically 50–70% savings on EC2 vs. managed node group at small scale
- **VPC endpoints** for S3 / ECR / STS — eliminates NAT data charges for these services
- **Fargate** for some workloads — eliminates EC2 management overhead, useful for sporadic workloads
- **CloudFront in front of ALB** — caches static assets, reducing ALB processed GB
