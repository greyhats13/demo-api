# DevOps Assessment — Starter Repo

Welcome, and thanks for taking the time. This should take about **2 hours — please don't go over.** We're testing judgment under time pressure, not stamina.

> **You do NOT need an AWS account, and you should NOT deploy anything.** This is a code review and fix task — everything is done locally. You won't spend a cent or spin up any infrastructure.

## The situation

This repo runs a tiny stateless HTTP API on AWS (ECS Fargate behind an ALB). It **works** — but it was put together carelessly by someone in a hurry. Your job is to review it like a senior engineer reviewing a colleague's pull request: find what's wrong, fix what matters most, and clearly explain the rest.

## What's here

```
app/                  A trivial Flask service. Do NOT rewrite it.
Dockerfile            Builds and runs, but naively.
infra/                Terraform: ECR, VPC, ALB, ECS Fargate. Plans, but flawed.
.github/workflows/    A pipeline that "deploys" but is unsafe.
```

## What to do (top-down, by priority)

1. **`REVIEW.md` first (~30 min).** Write up the issues you'd flag in a PR: *what's wrong, why it matters, the fix,* and a priority (blocker / should-fix / nice-to-have). This is the most important deliverable.
2. **Fix the Dockerfile (~20 min).**
3. **Fix the highest-impact infra & pipeline issues (~50 min).** You won't have time for everything — fix what most reduces real risk, and leave the rest documented in `REVIEW.md`. Choosing well *is* the test.
4. **One paragraph (~10 min)** in `REVIEW.md`: how would you know this service is down, and how would you roll back a bad deploy?

## Show your work

So we can see your process (and because none of this needs a live cloud), please include in `REVIEW.md`:

- The output of `terraform fmt -check` and `terraform validate` after your changes (run from `infra/` — neither command needs AWS credentials).
- The `docker build` image size **before and after** your Dockerfile changes (`docker images`).
- A short note on anything you'd have done with more time.

You can verify all of your work locally with Docker and the Terraform CLI alone. No AWS account, no deployment.

## Submitting

Push your branch (or send a patch) plus `REVIEW.md`. In the follow-up interview we'll screen-share your work and ask you to walk through your reasoning live — and possibly make a small change on the spot — so make sure the decisions are genuinely yours.

Good luck — and remember, a focused fix of the three riskiest things with a clear writeup beats a rushed attempt to fix everything.
