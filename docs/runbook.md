# 운영 런북 — 사이클 표준 절차

> 이 저장소는 `apply → 작업 → destroy` 사이클로 운영한다. 아래는 **그 사이클의 표준 절차**다.
>
> ⚠️ **[`operations.md`](operations.md)와 역할이 다르다.** 저기는 *무엇을 겪었나*(사후 기록), 여기는 *무엇을 할 것인가*(절차).
> 각 단계의 **근거는 전부 operations.md 의 해당 절**에 있고 여기서는 링크만 한다 — 사유를 두 벌로 두면 갈라진다.

## 왜 절차가 필요한가

이 사이클의 가장 큰 실패는 기술적 오류가 아니라 **종료 확인이었다.** 3~4시간을 의도했는데 클러스터가 **43.13시간** 돌았다([operations.md §8](operations.md)).

시간당 $0.34 구성에서 **세션 비용($1.4)과 한 달 방치 비용($247)의 차이는 176배**다. 관리 대상은 인스턴스 크기가 아니라 **끄는 절차**다.

---

## 1. apply 전 (pre-flight)

- [ ] **teardown 절차를 먼저 확인한다** — §3을 읽고 시작한다. 지우는 법을 모르는 채로 만들지 않는다
- [ ] **일일 예산 알람** 확인. ⚠️ 월 예산 알람은 **최대 24시간 지연**되어 트립와이어로 못 쓴다
- [ ] **종료 시각을 먼저 정한다.** 취침 2시간 전에 destroy 가 끝나는 시각에만 시작
- [ ] 타이머 2개(+2h / +3h)
- [ ] `terraform plan` 결과를 눈으로 확인 — CI 가 PR 에 게시한 plan 과 같은지

## 2. 운영 중

- [ ] `aws eks update-kubeconfig` 를 **destroy 직전에 다시 실행**할 것을 기억한다 → [§7-3](operations.md) (provider 가 module 출력에 의존)
- [ ] 리소스를 추가했으면 **state 에 들어갔는지 확인**한다 → [§3](operations.md) (state 엔 없는데 청구서엔 있었던 사례)

## 3. teardown — 순서가 있다

🔴 **순서를 지키지 않으면 VPC 삭제가 `DependencyViolation` 으로 실패한다.** 컨트롤러가 만든 ALB·타깃그룹·`k8s-*` 보안그룹은 **Terraform state 밖**에 있기 때문이다 → [§7-1](operations.md)

```bash
# 1) ArgoCD Application 먼저 — prune=true 라 앱 리소스(Ingress 포함)가 함께 정리된다.
#    이걸 먼저 하면 7-1 도 같이 해소된다.  → §7-2
kubectl delete -f k8s/argocd/application.yaml

# 2) 남은 Ingress 제거 후 ALB 소멸 대기 (보통 2~4분)
kubectl delete ingress --all --all-namespaces

# 3) provider 재구성 (클러스터가 먼저 사라지면 destroy 가 중단된다) → §7-3
aws eks update-kubeconfig --name smallbiz-platform-eks --region ap-northeast-2

# 4) destroy
terraform destroy
```

**복구**: `Kubernetes cluster unreachable` 로 중단되면 → `terraform state rm` 후 `terraform destroy -refresh=false`

## 4. 종료 판정 — 셋 다 만족해야 완료다

이게 이 런북의 핵심이다. **하나만 보면 "지웠다고 생각했는데 과금되는" 상태가 된다.**

| # | 확인 | 명령 | 통과 기준 |
|---|---|---|---|
| 1 | Terraform 상태 | `terraform state list` | 출력 0줄 |
| 2 | 주요 15종 조회 | `./scripts/verify-empty.sh` | 잔존 0건 (exit 0) |
| 3 | **청구 데이터** | 다음날 Cost Explorer | 해당 서비스 **$0** |

> 🔑 **3번을 빼면 안 된다.** 이 저장소에서 판정이 두 번 뒤집힌 것이 전부 "state 와 청구서가 어긋나서"였다 —
> state 에 `aws_db_instance` 가 없는데 RDS 가 **38.42시간 과금**됐고([§3](operations.md)),
> helm 이 `deployed` 인데 ALB 는 **ELB 청구 0건**으로 미생성이었다([§1](operations.md)).
> **증거는 두 종류를 교차 확인한다.**

## 5. 사이클 후

- [ ] 청구서를 역산해 [`cost-analysis.md`](cost-analysis.md) 갱신 — 예상과 다르면 그 차이가 다음 사이클의 재료다
- [ ] 새로 겪은 것은 [`operations.md`](operations.md) 에 추가. **틀렸던 것도 적는다**
- [ ] checkov 지적이 늘었으면 [`security-baseline.md`](security-baseline.md) 에 항목 추가 또는 수정

---

## 알려진 한계

- **루트 모듈이 인프라/애드온 2단으로 분리돼 있지 않다.** 그래서 §3의 순서를 사람이 지켜야 한다. 근본 해결은 모듈 분리이고, 현재는 **알려진 한계로 남겨둔 상태**다 → [§7-3](operations.md)
- `verify-empty.sh` 는 EC2·EKS·RDS·ELB·IAM OIDC·CloudWatch Logs 등 **15종만** 조회한다. 모든 AWS 서비스를 덮지 않으므로 §4-3(청구 확인)이 최종 관문이다 — 스크립트 주석에도 같은 취지가 적혀 있다
