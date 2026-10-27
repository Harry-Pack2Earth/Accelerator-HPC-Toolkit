# Dockerfile: the same image as container.def, for machines where Docker is the builder (macOS; Docker Desktop on
# Windows). Docker builds it for linux/amd64; scripts/build_sif.sh then converts the result to a .sif straight from
# the Docker daemon, running nothing. Keep this file and container.def in step: same base tag, same requirements,
# same chmod.
FROM nvcr.io/nvidia/pytorch:25.01-py3
# Pin a dated tag. Never :latest. Do NOT list torch in requirements.txt: the NGC image ships one matched to its CUDA.
COPY requirements.txt /opt/app/requirements.txt
COPY src /opt/app/src
RUN set -e; \
    BASE_NUMPY="$(python -m pip show numpy 2>/dev/null | awk '/^Version:/{print $2}')"; \
    if [ -n "$BASE_NUMPY" ]; then echo "numpy==$BASE_NUMPY" > /tmp/constraints.txt; else : > /tmp/constraints.txt; fi; \
    python -m pip install --no-cache-dir -c /tmp/constraints.txt -r /opt/app/requirements.txt; \
    chmod -R a+rX /opt/app
ENV PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONPATH=/opt/app/src
