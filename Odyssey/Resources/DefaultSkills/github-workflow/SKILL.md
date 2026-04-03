---
name: github-workflow
description: Guidelines for using GitHub issues, PRs, reviews, releases, and projects via gh CLI.
category: Odyssey
triggers:
  - github
  - gh cli
  - create issue
  - open pr
  - pull request
  - code review
  - release
  - github project
---

# GitHub Workflow

You are working in a GitHub repository. Use the `gh` CLI (via Bash tool) to create durable, externally-visible work artifacts. Use PeerBus for real-time agent coordination.

## Prerequisites

Before using GitHub workflows, verify:
1. `gh auth status` — must succeed
2. Workspace has a GitHub remote

If either fails, skip GitHub workflows and work normally.

## When to Use GitHub

- **Issues** for durable artifacts that should survive the session: bugs, blockers, follow-up tasks, review requests, and delegated work that needs tracking.
- **PRs** for code changes that need review, visibility, or an audit trail.
- **Reviews** when another agent's code needs a quality gate or explicit handoff.
- **Releases** when shipping a milestone.
- **Projects** for tracking progress across multiple issues.
- Do NOT use GitHub for ephemeral coordination — that's PeerBus.

## Multi-Agent Conventions

- Delegated or decomposed code work → create an issue and link the implementation PR back to it.
- Durable blockers and must-fix defects → open issues with repro/context rather than leaving them only in chat or on the blackboard.
- Another agent's PR → review it. Never approve your own PR.
- Mention another agent in GitHub only when requesting a concrete action: review, handoff, follow-up, or decision.
- Use a short footer signature in issue bodies, PR descriptions, and substantive comments:
  `Posted by Odyssey agent: <AgentName>`
- When decomposing work, link parent and child issues so handoffs stay traceable.

## Safety Policy

- **Free:** create issue, create PR, comment, request review, list/view anything, check CI status.
- **Confirm with user first:** merge PR, close issue, delete branch, force push, create release.
- **Never:** force-push to main/master, delete repositories, modify branch protection rules.

## Issue Conventions

- Use labels: `agent-created`, `priority:{low,medium,high,critical}`, `type:{bug,feature,task}`.
- Durable defect issues should include repro steps, expected vs actual, severity, and supporting evidence when available.
- Tester and Reviewer should file issues for durable defects or must-fix findings, not minor nits or ephemeral observations.
- Close with a resolution summary, not just "done".
- Link related issues and PRs.
- For decomposed work, add parent/child references explicitly.

## PR Conventions

- Reference the issue number in PR description.
- Link the PR back to its issue and any related follow-up issues.
- Use draft PRs for work-in-progress.
- Check CI status before requesting review.
- When requesting another agent's action, mention them in the PR comment or review request and state the exact ask.
- Add the footer signature to the PR description.
- Keep PRs focused — one concern per PR.

## Release & Project Conventions

- Create releases with changelogs summarizing what changed.
- Use GitHub Projects to track issue progress through stages.
