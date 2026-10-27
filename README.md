# Accelerator-HPC-Toolkit

A skill for your coding agent that takes you from "I have a MareNostrum 5 account" to your first verified
job on the supercomputer, then to real GPU and CPU jobs, with the guardrails a shared, budgeted machine needs.
You do not need to know SLURM, containers or the terminal: the agent does the cluster work, you approve and read.

It exists because the hardest part of a supercomputer for a startup is not the science. It is the first two
weeks: keys, transfer nodes, queues, quotas, containers with no internet, and the twenty small rules nobody
writes down. The rules here come from one startup's first two allocations (about 500 submissions, 21,000
tasks, 7,000 GPU-hours, June to October 2026) and from building this toolkit against the live machine. Each
rule carries what actually happened (`skills/mn5-first-job/references/lessons.md`).

## The lazy path

Open Claude Code in an empty folder and paste:

> Install the skill from https://github.com/Harry-Pack2Earth/Accelerator-HPC-Toolkit and get my first job
> running on MareNostrum 5. My cluster username is `abc123456`.

It will do everything below except the two things only you can do: upload your SSH key in the BSC portal
(if you have not, it stops and tells you exactly how) and say yes before anything real is submitted. The
first tiny test job goes on its own: it costs under half a CPU-hour and proves the whole path.

**If you are the agent reading this:** the folder you were opened in is the working folder. `git clone` this
repository into it; `mkdir -p ~/.claude/skills && cp -r Accelerator-HPC-Toolkit/skills/mn5-first-job ~/.claude/skills/`
(so the skill is there for later sessions); then open `Accelerator-HPC-Toolkit/skills/mn5-first-job/SKILL.md`
and follow it from Step 0, running the scripts from the clone by absolute path, with the working folder as
your current directory (`cluster.env`, `build/`, `pulled/` land there). Steps 0 and 1 need no answers from
the human; ask the skill's opening questions before Step 2. Do not improvise around the skill; it encodes
rules that each cost someone a day.

## 1. Before you start (15 minutes, once)

1. **A BSC account.** Your username is in the welcome email from BSC (it looks like `abc123456`).
2. **An SSH key uploaded to BSC.** On your laptop, in a terminal (macOS: Terminal; Windows: see step 3 first):
   ```
   ssh-keygen -t ed25519
   ```
   press Enter at every question, then show the public key with `cat ~/.ssh/id_ed25519.pub`, copy that whole
   line, and paste it in the BSC accounts portal: https://hpcaccounts.bsc.es → SSH KEYS → ADD NEW SSH KEY.
   The upload replaces any key already there, so include every key you still want.
3. **A laptop with the basic tools.**
   - macOS: nothing to install (`ssh` and `rsync` are built in; GNU rsync via `brew install rsync` is a plus).
   - Windows: install Ubuntu under WSL2 once: in PowerShell as administrator run `wsl --install`, reboot,
     open "Ubuntu" from the Start menu, then `sudo apt-get install -y rsync python3-pip`. Do everything that
     follows inside that Ubuntu window, including installing your agent.
   - Linux: `sudo apt-get install -y rsync python3-pip` (or your distribution's equivalent).
4. **A coding agent.** This toolkit was built and tested with Claude Code (https://claude.com/claude-code).
   The skill folder follows the open Agent Skills format, so other agents that read that format can use it
   too, but only Claude Code has been exercised.
5. For GPU work later: Docker Desktop on macOS (or colima), Apptainer on Linux / WSL2. Not needed for the
   first job.

## 2. Install the skill (2 minutes)

In a terminal:
```
git clone https://github.com/Harry-Pack2Earth/Accelerator-HPC-Toolkit.git
mkdir -p ~/.claude/skills
cp -r Accelerator-HPC-Toolkit/skills/mn5-first-job ~/.claude/skills/
```
That is the whole install: Claude Code reads every folder under `~/.claude/skills/` that holds a `SKILL.md`.
(To install for one project only, copy it to `<project>/.claude/skills/` instead.) Other agents: copy the
same folder to wherever that tool reads skills.

Updating later: `git pull` in the cloned folder and repeat the `cp -r`.

## 3. Your first job (about 10 minutes)

Make an empty folder for your cluster work and start your agent in it:
```
mkdir ~/mn5 && cd ~/mn5
claude
```
Then say, in your own words:

> Use the mn5-first-job skill. My cluster username is `abc123456`. Get my first job running on
> MareNostrum 5 and show me the result.

What happens next, all driven by the agent:
1. **Preflight.** It checks your laptop, proves the key login works (if not, it tells you exactly what to fix),
   reads your project, queues, quota and budget from the cluster, and writes them to `cluster.env` in your
   folder. It may ask you one question: which allocation to use, if you have several.
2. **Smoke job.** It shows you the tiny job it is about to submit and its cost (a fraction of a CPU-hour), sends
   it to the debug queue, waits a minute or two, pulls the result back, and shows you the file. You will see
   the compute node's name, `x86_64`, the CPUs that were yours, and "No devices found" for the GPU, which is
   expected (the smoke asks for none).
3. It tells you what it needs from you for a real job: your script, its inputs, the packages it uses, and how
   long one run takes on your laptop.

Before anything real is submitted, the agent shows you the job file, the estimated cost and the share of your
remaining budget, and waits for your yes. That is written into the skill as a rule, not a suggestion.

## 4. After the first job

- **CPU work in Python** (pandas, scikit-learn, data processing): the agent builds an offline package bundle
  on your laptop, installs it once on the cluster, and runs your script as an array of tasks.
- **GPU work** (training, fine-tuning, large inference): the agent builds a container image on your laptop
  (or any Linux machine), copies it to the cluster with a checksum, proves it on one GPU in seconds, then
  runs the real job.
- Everything the agent does and why is in `skills/mn5-first-job/SKILL.md`, which you can read too; the
  references behind it explain the machine, the budget rules and what to do when something fails.

## 5. If something goes wrong

Tell the agent the exact message. The skill has a symptom → cause → fix table
(`references/troubleshooting.md`) covering 45 failures that have actually happened, and a rule to read the
job's error log before changing anything. Two things only you can do: upload a key in the BSC portal, and
write to BSC support (for example to raise a tiny projects quota); the agent will draft the message.

## Layout

```
skills/mn5-first-job/
  SKILL.md        the procedure and the guardrails (the agent reads this first)
  scripts/        preflight, smoke loop, push/pull, submit, status, cost, image build, wheel bundle + venv install
  templates/      job files (smoke, image smoke, single GPU, multi-GPU, CPU array), container.def + Dockerfile
  references/     lessons.md, bsc-marenostrum5.md, software-three-doors.md, troubleshooting.md, budget-and-queues.md
  TESTING.md      what has been run on which machine, with the job ids
```

## Status

`skills/mn5-first-job/TESTING.md` is the only place that states what has been verified. As of 27 October 2026
every row has been run on MareNostrum 5: from macOS, Linux and Windows (WSL2), from a machine with nothing
preinstalled, and by an agent given nothing but this skill.

## Scope

MareNostrum 5 at BSC. Site specifics live in one file (`references/bsc-marenostrum5.md`) so another EuroHPC
site can be added without touching the procedure.

## Credits and licence

Built by Pack2Earth from its allocations on MareNostrum 5 through the BSC AI Factory accelerator pilot and
EuroHPC AI Factories Playground Access, and offered to the next cohorts. Apache-2.0: fork it, fix it, ship it.
