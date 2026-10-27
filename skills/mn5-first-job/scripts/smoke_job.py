#!/usr/bin/env python3
"""smoke_job.py: the first job. Standard library only, so it runs on a node with no
internet and no packages installed. It proves the loop (transfer, submit, run,
retrieve) and records what the compute node looks like.

Writes smoke_result.json into the current directory (the job's run dir)."""
import json, os, platform, socket, subprocess, sys, time


def probe(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30).stdout.strip()[:2000]
    except Exception as exc:  # the probe is informational, never fatal
        return f"unavailable: {exc}"


def importable(name):
    try:
        mod = __import__(name)
        return getattr(mod, "__version__", "present")
    except Exception as exc:
        return f"no ({type(exc).__name__})"


def probe_cuda():
    try:
        import torch  # noqa
        return torch.cuda.is_available()
    except Exception:
        return "no torch"


t0 = time.time()
total = sum(i * i for i in range(2_000_000))  # a few seconds of real CPU work
result = {
    "hostname": socket.gethostname(),
    "python": sys.version.split()[0],
    "python_executable": sys.executable,
    "machine": platform.machine(),
    "cpu_count_visible": os.cpu_count(),
    "cwd": os.getcwd(),
    "slurm": {k: v for k, v in os.environ.items() if k.startswith("SLURM_")},
    "cuda_visible_devices": os.environ.get("CUDA_VISIBLE_DEVICES"),
    "nvidia_smi": probe(["nvidia-smi", "-L"]),
    "imports": {n: importable(n) for n in ("numpy", "pandas", "sklearn", "torch")},
    "torch_cuda_available": probe_cuda(),
    "work_seconds": round(time.time() - t0, 2),
    "checksum": total % 1_000_003,
}
with open("smoke_result.json", "w") as fh:
    json.dump(result, fh, indent=2)
print(json.dumps(result, indent=2))
print("SMOKE_OK")
