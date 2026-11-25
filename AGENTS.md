# Agent Instructions

This repository uses a private reusable AI workflow through the `.ai-template` submodule.

If `.ai/README.md` is not available, run `./scripts/setup-ai-workflow.sh` first. If the private workflow cannot be loaded, stop rather than inventing replacement workflow rules.

After setup, `.ai/` is the source of truth for workflow, policies, skills, review rules, Git rules, and automation instructions.

Read `.ai/README.md` first. For end-to-end goals follow `.ai/skills/execute-goal.md`.

Project-specific context is tracked in `.ai/` as an overlay and must not be overwritten by reusable workflow updates.

## Durly repository

Native macOS battery-care application. Read `docs/product-requirements.md`, `.ai/project/scope.md`, `.ai/project/decisions.md` and `.ai/docs/project-requirements.md` before changes. Use SwiftPM and Command Line Tools, no full Xcode, Codex or Cursor. CI must use Linux runners only; native compilation and device tests run locally. Never enable unverified hardware writes. Respect readiness and issue dependency gates.
