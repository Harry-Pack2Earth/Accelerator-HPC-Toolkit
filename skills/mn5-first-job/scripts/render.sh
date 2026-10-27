#!/usr/bin/env bash
# render.sh — fill __TOKENS__ in a template from cluster.env plus KEY=VALUE arguments.
# Usage: scripts/render.sh <template> <output> [KEY=VALUE ...]
# Fails if any __TOKEN__ is left unfilled, so a half-rendered sbatch never reaches the cluster.
# Tokens come from cluster.env (PROJECT, QOS_DEBUG, SCRATCH_DIR, RESULTS_DIR, VENV_DIR, CONTAINER_MODULE ...) and from
# KEY=VALUE arguments; the per-template list is in SKILL.md. ENTRYPOINT must be an absolute path: jobs cd into
# their scratch run directory first.
set -euo pipefail
[[ $# -ge 2 ]] || { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
TEMPLATE="$1"; OUT="$2"; shift 2
ENV_FILE="${HPC_ENV:-cluster.env}"
[[ -f "$ENV_FILE" ]] || { echo "missing $ENV_FILE: run scripts/preflight.sh first" >&2; exit 2; }
python3 - "$TEMPLATE" "$OUT" "$ENV_FILE" "$@" <<'PY'
import re, sys
template, out, env_file, *pairs = sys.argv[1:]
values = {}
for line in open(env_file):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1); values[k] = v.strip().strip('"')
for p in pairs:
    k, v = p.split("=", 1); values[k] = v
if "CONTAINER_MODULE" not in values and values.get("CONTAINER_MODULES"):
    # newest version listed (module avail prints 3.11.5 before 4.1.5)
    def vkey(m): return [int(x) if x.isdigit() else x for x in m.split("/")[-1].split(".")]
    values["CONTAINER_MODULE"] = sorted(values["CONTAINER_MODULES"].split(), key=vkey)[-1]
ep = values.get("ENTRYPOINT")
if ep is not None and not ep.startswith("/"):
    sys.exit(f"ENTRYPOINT must be absolute (jobs cd into their run dir first): {ep}")
text = open(template).read()
text = re.sub(r"__([A-Z0-9_]+)__", lambda m: values.get(m.group(1), m.group(0)), text)
left = sorted(set(re.findall(r"__([A-Z0-9_]+)__", text)))
if left:
    sys.exit(f"unfilled tokens in {template}: {', '.join(left)} (pass KEY=VALUE)")
open(out, "w").write(text)
print(f"rendered {out}")
PY
