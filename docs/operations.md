# Operations Notes

> Real apply lessons captured here as encountered. **Work in progress.** Each entry follows: **symptom → diagnosis → fix → takeaway.**

Goal: turn this from a theoretical reference into a living incident log that proves the architecture has been operated, not just authored.

---

## Entry template

```markdown
### YYYY-MM-DD — Short title

**Symptom**
What I observed (error message, behavior, metric).

**Diagnosis**
What I checked, in what order, and what I found.

**Fix**
The exact change made.

**Takeaway**
What I'd watch for next time / what this reveals about the architecture.
```

---

## Entries

> _Adding entries from memory takes care — accuracy matters more than completeness here. New apply runs will produce new entries naturally._

### 📋 Pending — to be added

These were the apply runs (3월 24일 ~ 4월 3일) that produced this codebase. Specific issues and resolutions will be documented here as they're recalled or re-encountered. Likely candidates:

- IRSA / OIDC provider setup
- AWS Load Balancer Controller installation order
- Managed node group ready timing
- RDS subnet group / security group between AZs
- ArgoCD application sync namespace handling
- Terraform module destroy order

(Each will be replaced with a real entry following the template above.)

---

## Why this matters

For a portfolio audience: this document is more valuable than a perfect README. It demonstrates that the architecture has been **operated**, that I can articulate what went wrong and why, and that I'm honest about uncertainty.

For future-me: this is the runbook starting point. The next person to apply this — or the next time I do, on a different account — will find this here.
