# Accelerator-HPC-Toolkit

A skill for coding agents (Claude Code, Codex, Cursor, Gemini CLI and any tool that reads the open Agent Skills
format) that takes a new BSC MareNostrum 5 user from "I have an account" to a verified first job, then to real GPU
and CPU-array jobs, with the guardrails a shared, budgeted machine needs.

It exists because the hardest part of a supercomputer for a startup is not the science. It is the first two
weeks: keys, transfer nodes, queues, quotas, containers with no internet, and the twenty small rules nobody
writes down. Every rule in this toolkit was paid for by a real failure during one startup's first two
allocations (about 500 submissions, 21,000 tasks, 7,000 GPU-hours, June to October 2026). The evidence is in
`skills/mn5-first-job/references/lessons.md`.

## Install

The skill is the folder `skills/mn5-first-job/`. Copy it where your agent reads skills:

| Agent | Where |
|---|---|
| Claude Code (all projects) | `~/.claude/skills/mn5-first-job/` |
| Claude Code (one project) | `<project>/.claude/skills/mn5-first-job/` |
| Codex / Cursor / others | the tool's skills directory, same folder |

```
git clone https://github.com/Harry-Pack2Earth/Accelerator-HPC-Toolkit.git
cp -r Accelerator-HPC-Toolkit/skills/mn5-first-job ~/.claude/skills/
```

Then, in a working folder of your own, tell the agent: "Use the mn5-first-job skill. My cluster username is
`<username>`." The agent runs the preflight, the smoke job, and takes it from there.

## What you need before starting

- A BSC account (username in the welcome email) and an SSH key uploaded in the BSC accounts portal.
- `ssh` and `rsync` on the laptop. Windows: an Ubuntu (WSL2) terminal. macOS: `brew install rsync`.
- For GPU images: Docker Desktop (Apple Silicon: enable Rosetta) or Apptainer on Linux/WSL2.

## Layout

```
skills/mn5-first-job/
  SKILL.md                 the procedure and the guardrails (the agent reads this first)
  scripts/                 preflight, smoke loop, push/pull, submit, status, cost, image and wheel builds
  templates/               sbatch files (smoke, image smoke, single GPU, multi-GPU, CPU array), container.def
  references/              lessons.md, bsc-marenostrum5.md, software-three-doors.md, troubleshooting.md, budget-and-queues.md
TESTING.md                 what has been verified on which machine, and what has not
```

## Status

See `TESTING.md`. Dry-run paths are tested. Cluster and per-OS build paths are marked verified only once run.

## Scope

MareNostrum 5 at BSC. Site specifics live in one file (`references/bsc-marenostrum5.md`) so another EuroHPC
site can be added without touching the procedure.

## Credits and licence

Built by Pack2Earth from its allocations on MareNostrum 5 through the BSC AI Factory accelerator pilot and
EuroHPC AI Factories Playground Access, and offered to the next cohorts. Apache-2.0: fork it, fix it, ship it.
