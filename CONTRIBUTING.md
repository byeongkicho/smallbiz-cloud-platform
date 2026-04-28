# Contributing

Thanks for your interest. This is a personal portfolio project, but issues, corrections, and small suggestions are welcome.

## Reporting issues

Please open a GitHub Issue with:

- **Component** — `terraform/`, `k8s/`, `docs/`, or other
- **Expected vs. actual** behavior
- **Environment** — Terraform version, `kubectl` version, AWS region if relevant
- Logs / error output where helpful (redact any account IDs, ARNs, IPs)

## Suggesting improvements

- For docs typos, clarifications, or small fixes — pull requests are welcome directly.
- For architectural changes (new modules, big refactors, Phase 3 components) — please open an issue first to align on scope.

## Code style

- **Terraform**: `terraform fmt -recursive` before committing. `terraform validate` should pass.
- **YAML**: 2-space indent, no trailing whitespace, namespace declared explicitly.
- **Markdown**: clear headers, complete sentences, runnable examples.

## What this project is, and isn't

**Is**: a single-developer learning portfolio focused on small-business-friendly cloud architecture, used as a visible artifact during job search.

**Isn't**: a managed open-source project with a release cadence or production support guarantees. Don't deploy this as-is to production without a security review and your own backend state setup.

## Local setup

See [README.md](README.md) "Setup Secrets" and "Quick Start" sections.

## Disclosure

This project was built with substantial help from AI pair-programming tools (primarily Claude Code). Architectural decisions, debugging, and final responsibility for what's committed belong to the human author. Each commit message documents the human author and may include an AI co-author trailer.
