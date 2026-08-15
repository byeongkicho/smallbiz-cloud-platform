# Operations — 실제로 겪은 것

2026-04-01 ~ 04-03 apply/destroy 사이클과 2026-08-15 사후 분석에서 나온 것들.
**겪은 것과 겪지 않은 것을 나눠 적는다** — §1~5·§7은 실제 관측, §6은 아직 겪지 않은 알려진 위험이다.

---

## 1. helm이 `deployed`인데 ALB가 안 만들어졌다

**증상**: `helm_release.alb_controller`의 status가 `deployed`. 컨트롤러 파드도 Ready. 그런데 Ingress를 만들어도 ALB가 생기지 않았다.

**진단이 늦어진 이유**: helm은 **차트가 설치됐는지**만 본다. 컨트롤러가 **자기 일을 할 수 있는지**는 보지 않는다. 그래서 Terraform 출력만 보면 전부 초록이었다.

**확증**: 4개월 뒤 Cost Explorer를 열어보니 **ELB 계열 청구가 0건**이었다. 공인 IPv4도 43시간분 1개(NAT용)만 과금됐다 — ALB가 떴다면 AZ당 1개씩 최소 2개가 더 잡혔어야 한다. 로드밸런서는 한 번도 존재하지 않았다.

**근본 원인**: IRSA 역할에 `ElasticLoadBalancingFullAccess` 관리형 정책만 붙어 있었다. AWS Load Balancer Controller는 서브넷을 자동 탐색하기 위해 `ec2:DescribeSubnets`·`ec2:DescribeSecurityGroups`·`ec2:DescribeVpcs`와 `iam:CreateServiceLinkedRole`이 필요한데 그 정책엔 EC2 권한이 없다. 컨트롤러는 기동엔 성공하고 **첫 Ingress 조정 시점에 실패**한다.

**조치**: 공식 [`iam_policy.json`](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json)을 저장소에 vendoring하고 `aws_iam_policy`로 교체 (예정 — 재검증 시).

**교훈**: **설치 성공은 동작 검증이 아니다.** 컨트롤러류는 "설치됨"과 "권한이 있어 실제로 리소스를 만듦" 사이에 간극이 있고, 그 간극은 첫 조정(reconcile) 때만 드러난다.

---

## 2. 청구서의 63%가 "버전을 안 올려서" 낸 돈이었다

**증상**: 43시간 돌린 클러스터 청구가 $34.48. 시간당 $0.10 × 43h = $4.3을 예상했는데 EKS만 $25.88이었다.

**진단**: 사용 유형을 쪼개보니

```
APN2-AmazonEKS-Hours:perCluster        43.127h × $0.10 = $ 4.31
APN2-AmazonEKS-Hours:extendedSupport   43.127h × $0.50 = $21.56
```

**근본 원인**: 클러스터가 1.30으로 생성돼 1.31로 업그레이드됐는데, 2026-04 기준 **두 버전 모두 표준 지원이 끝난 상태**였다. 표준 지원 종료 후에는 확장 지원 요금이 붙어 제어 플레인이 시간당 $0.10 → $0.60이 된다.

**게다가 코드의 버전 고정값이 4곳에서 서로 달랐다**: `variables.tf`=1.29(이제는 생성 자체가 불가) / `terraform.tfvars.example`=1.31 / README=1.31 / 실제 가동=1.30→1.31.

**조치**: 전부 `1.34`로 통일하고, 선택 근거(표준 지원 종료일)를 `variables.tf`의 변수 description에 적었다. 숫자만 남기면 6개월 뒤에 왜 그 값인지 아무도 모른다.

**교훈**: 관리형 서비스의 **버전 지연은 기능 문제가 아니라 청구 문제**다. 그리고 같은 값이 여러 파일에 흩어져 있으면 반드시 어긋난다.

---

## 3. state에 없는데 청구서엔 있었다 (RDS)

**증상**: 보존된 state 백업 5개 어디에도 `aws_db_instance`가 없다. "RDS는 코드만 있고 만들어진 적 없다"고 결론 낼 뻔했다.

**반증**: 청구 데이터에 `APN2-InstanceUsage:db.t3.micro` **38.418시간**이 있었다. RDS는 실제로 생성되어 클러스터와 거의 같은 기간 돌았다.

**원인**: state 백업은 **쓰기 시점의 스냅샷**이고, 이 사이클은 serial 93까지 갔는데 남아 있는 건 5개(44·72·73·74·93)뿐이다. RDS가 존재하던 구간의 스냅샷이 보존되지 않았을 뿐이다.

**교훈**: **state 부재는 미생성의 증거가 아니다.** 인프라가 존재했는지는 청구·CloudTrail 같은 독립 소스로 교차 확인해야 한다. §1과 정반대 방향의 오판이 될 뻔했다 — 한쪽은 "있다고 착각", 한쪽은 "없다고 착각".

---

## 4. ArgoCD가 설치됐지만 아무것도 동기화하지 않았다

**증상**: `helm_release.argocd` = `deployed`. Phase 2 체크박스에 "ArgoCD installation & app registration ✅"라고 적어뒀다.

**실제**: `k8s/argocd/application.yaml`의 `repoURL`이 `https://github.com/placeholder/aws-portfolio.git`이었다. 존재하지 않는 저장소를 가리키고 있었으므로 **동기화가 일어날 수 없었다.** 저장소를 push한 뒤 URL을 바꾸는 걸 잊었고, ArgoCD UI를 열어 상태를 확인하지 않았기 때문에 4개월 동안 몰랐다.

**조치**: 실제 저장소 URL로 수정. 다만 **동기화가 실제로 도는지는 재검증 전까지 "미검증"으로 표기**한다.

**교훈**: GitOps는 "설치했다"가 아니라 **"커밋이 클러스터에 반영되는 왕복을 한 번이라도 봤다"**가 검증 기준이다.

---

## 5. CI를 처음 켜자 결함 2건이 나왔다

워크플로 파일은 2026-04부터 저장소에 있었지만 **실행 이력이 0회**였다. 2026-08-15에 처음 돌렸고, 세 번 만에 초록이 됐다.

| 실행 | 결과 | 걸린 것 |
|---|---|---|
| #1 | ❌ | `terraform fmt -check` — `modules/vpc/main.tf`의 tags 정렬 (exit 3) |
| #2 | ❌ | `Validate sub-modules` — helm provider 파괴적 변경 |
| #3 | ✅ | — |

**#2가 진짜 발견이다.** `modules/{vpc,eks,rds}` 어디에도 `required_providers`가 없었다. 루트는 `helm ~> 2.12`로 고정돼 있어 통과하지만, 모듈을 단독으로 `terraform init -backend=false` 하면 provider가 **최신으로 해석된다.** helm 3.x는 `set { ... }` 블록을 `set = [{ ... }]` 속성으로 바꿨고, `modules/eks/main.tf`의 `helm_release` 3곳이 전부 깨졌다.

루트에서만 쓰는 동안은 절대 드러나지 않는다. **모듈을 다른 루트에서 재사용하는 순간 터진다.** 각 모듈이 자기가 쓰는 provider를 스스로 선언하도록 고쳤다.

**교훈**: 검증을 안 돌리면 통과한 것이 아니라 **판정이 없는 것**이다. 4개월간 초록도 빨강도 아니었을 뿐이다.

---

## 6. 아직 겪지 않았지만 대비해야 하는 것 (재검증 시)

⚠️ **아래는 관측된 사고가 아니다.** 2026-04 destroy는 깨끗하게 끝났고(serial 93 / 리소스 0, 잔존 고아 리소스 0건) 아래 상황은 발생하지 않았다. 다만 §1을 고쳐 ALB가 **실제로 생성되면** 그때부터 유효해지는 위험이라 미리 적어둔다.

### 6-1. 컨트롤러가 만든 ALB는 Terraform state 밖에 있다

AWS Load Balancer Controller가 Ingress를 보고 만든 ALB·타깃그룹·`k8s-*` 보안그룹은 Terraform이 모른다. `terraform destroy`가 EKS를 먼저 지우면 컨트롤러가 사라져 ALB가 고아가 되고, 그 ENI/SG가 VPC에 남아 `DependencyViolation`으로 VPC 삭제가 실패한다.

**순서**:
```bash
kubectl delete ingress --all --all-namespaces
# ALB가 사라질 때까지 대기 (보통 2~4분)
terraform destroy
```

### 6-2. ArgoCD Application finalizer

`application.yaml`에 `resources-finalizer.argocd.argoproj.io`가 있다. ArgoCD를 먼저 지우면 finalizer를 처리할 컨트롤러가 없어 Application과 네임스페이스가 `Terminating`에 정체한다.
`syncPolicy.automated.prune = true`이므로 **Application을 먼저 지우면 앱 리소스(Ingress 포함)가 함께 정리되고, 그 결과 6-1도 같이 해소된다.**

### 6-3. helm/kubernetes provider가 module 출력에 의존

`provider.tf`가 `module.eks.cluster_endpoint`로 provider를 구성한다. destroy 중 클러스터가 먼저 사라지면 `Kubernetes cluster unreachable`로 중단된다.
- 예방: destroy 직전 `aws eks update-kubeconfig` 재실행
- 복구: `terraform state rm` 후 `terraform destroy -refresh=false`
- 근본 해결: 루트 모듈을 인프라 / 애드온 2단으로 분리 — **알려진 한계로 남겨둔다**

### 6-4. destroy 완료 판정 기준

셋 다 만족해야 완료다: `terraform state list`가 비었다 · 리전 전수 조회에서 잔존 0건 · **다음날 Cost Explorer에서 해당 서비스 $0**.

---

## 7. 이 사이클의 가장 큰 실패 — 종료 확인

3~4시간 세션을 의도했는데 **클러스터가 43.13시간 돌았다**. 비용 자체는 $34로 감당 가능한 범위였지만, 비율로 보면 계획 대비 10배 이상이다.

시간당 $0.34 구성에서 **세션 비용($1.4)과 한 달 방치 비용($247)의 차이는 176배**다. 즉 이 프로젝트에서 관리해야 할 대상은 인스턴스 크기나 단가 선택이 아니라 **끄는 것을 잊지 않는 절차**다.

다음 사이클의 방어:
- apply **전에** teardown/verify 스크립트 작성
- 일일 예산 알람(월 예산은 최대 24시간 지연되어 트립와이어로 못 쓴다)
- 폰 타이머 2개(+2h/+3h)
- 취침 2시간 전에 destroy가 끝나는 시각에만 시작
