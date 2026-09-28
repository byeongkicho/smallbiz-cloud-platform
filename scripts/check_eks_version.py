#!/usr/bin/env python3
"""EKS 버전 수명주기 검사 — PR 마다 CI(terraform-validate)에서 돈다. AWS 자격증명이 필요 없다.

왜 있나
  2026-04 사이클의 청구액 63%가 확장 지원 할증이었다. 1.30 으로 만든 클러스터가
  생성 시점에 이미 표준 지원이 끝나 있었고, 제어 플레인이 시간당 $0.10 이 아니라 $0.60 이었다.
  이 값은 사람이 기억해서 관리하면 뚫린다 → PR 단계에서 코드로 막는다.

무엇을 보나
  1. terraform/variables.tf 의 eks_cluster_version 기본값과 terraform.tfvars.example 의 값이 같은가
     (2026-04 에는 같은 값이 네 곳에서 서로 달랐다)
  2. 그 버전의 표준 지원 종료일까지 남은 날
     - 표에 없는 버전          → 실패 (모르면 통과시키지 않는다)
     - 이미 지났다             → 실패 (생성 즉시 확장 지원 요금)
     - 30일 미만               → 실패 (upgrade_policy=STANDARD 면 곧 AWS 가 자동 업그레이드한다.
                                       코드가 뒤처지면 plan 이 다운그레이드를 시도해 실패한다)
     - 90일 미만               → 경고 (다음 버전 계획을 세울 때)
  3. 모듈의 upgrade_support_type 기본값이 STANDARD 인가 (EXTENDED 로 바뀌면 경고)

종료일 출처
  https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  「Amazon EKS Kubernetes release calendar」 표, 2026-09-28 확인. 날짜는 UTC 기준이고
  확장 지원 과금은 그날 UTC 0시부터 시작한다. 새 버전이 나오면 이 표에 추가할 것.

사용
  python3 scripts/check_eks_version.py
  CHECK_DATE=2026-11-15 python3 scripts/check_eks_version.py   # 날짜를 바꿔 분기 확인
"""

import os
import re
import sys
from datetime import date, datetime, timezone
from pathlib import Path

END_OF_STANDARD_SUPPORT = {
    "1.31": "2025-11-26",
    "1.32": "2026-03-23",
    "1.33": "2026-07-29",
    "1.34": "2026-12-02",
    "1.35": "2027-03-27",
    "1.36": "2027-08-02",
}
FAIL_DAYS = 30
WARN_DAYS = 90

ROOT = Path(__file__).resolve().parent.parent
GITHUB = os.environ.get("GITHUB_ACTIONS") == "true"


def annotate(level: str, msg: str) -> None:
    # GitHub Actions 에서는 PR 화면에 주석으로 뜨게 한다
    print(f"::{level}::{msg}" if GITHUB else f"[{level}] {msg}")


def read_default(path: Path, var: str) -> str | None:
    text = path.read_text(encoding="utf-8")
    m = re.search(r'variable\s+"' + re.escape(var) + r'"\s*\{.*?\n\s*default\s*=\s*"([^"]+)"', text, re.S)
    return m.group(1) if m else None


def read_tfvars(path: Path, var: str) -> str | None:
    if not path.exists():
        return None
    m = re.search(r'^\s*' + re.escape(var) + r'\s*=\s*"([^"]+)"', path.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else None


def main() -> int:
    today = date.fromisoformat(os.environ["CHECK_DATE"]) if os.environ.get("CHECK_DATE") \
        else datetime.now(timezone.utc).date()
    failed = False

    version = read_default(ROOT / "terraform/variables.tf", "eks_cluster_version")
    if not version:
        annotate("error", "terraform/variables.tf 에서 eks_cluster_version 기본값을 찾지 못했다 — 검사를 할 수 없다")
        return 1

    example = read_tfvars(ROOT / "terraform/terraform.tfvars.example", "eks_cluster_version")
    if example and example != version:
        annotate("error", f"버전 불일치: variables.tf={version} / terraform.tfvars.example={example}")
        failed = True

    end = END_OF_STANDARD_SUPPORT.get(version)
    if not end:
        annotate("error", f"EKS {version} 은 종료일 표에 없다 — 모르는 버전은 통과시키지 않는다. "
                          "AWS 릴리스 캘린더를 확인해 표에 추가할 것")
        return 1

    days = (date.fromisoformat(end) - today).days
    head = f"EKS {version} 표준 지원 종료 {end} (UTC) · 기준일 {today} · 남은 날 {days}일"
    if days < 0:
        annotate("error", f"{head} — 이미 확장 지원 구간이다. 이 버전으로 만들면 제어 플레인이 시간당 $0.60 이다")
        failed = True
    elif days < FAIL_DAYS:
        annotate("error", f"{head} — {FAIL_DAYS}일 미만. STANDARD 정책이면 곧 자동 업그레이드되어 "
                          "코드가 실제 클러스터보다 뒤처진다. 버전을 먼저 올릴 것")
        failed = True
    elif days < WARN_DAYS:
        annotate("warning", f"{head} — {WARN_DAYS}일 미만. 다음 버전으로 올릴 계획을 세울 때다")
    else:
        print(f"[ok] {head}")

    policy = read_default(ROOT / "terraform/modules/eks/variables.tf", "upgrade_support_type")
    if policy != "STANDARD":
        annotate("warning", f"upgrade_support_type 기본값이 {policy!r} 다 — EXTENDED 면 표준 지원 종료 후 확장 지원 요금이 붙는다")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
