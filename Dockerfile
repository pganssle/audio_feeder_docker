# audio-feeder runs on the free-threaded build of CPython (3.14t), with the GIL
# disabled. There are no official python images for the free-threaded build,
# so this installs a uv-managed one (from python-build-standalone) on Debian.
ARG DEBIAN_VERSION=trixie
ARG UV_VERSION=0.13.1

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM debian:${DEBIAN_VERSION}-slim AS builder

# The version of Python, which must be a free-threaded ("t") build.
ARG PYTHON_VERSION=3.14t

# The requirement used to install audio-feeder. To install a version that
# hasn't been released yet, use e.g.:
#   --build-arg AUDIO_FEEDER_SPEC="audio-feeder @ git+https://github.com/pganssle/audio-feeder@main"
# If there's a clone of audio-feeder in ./audio_feeder or ./audio-feeder, it's
# installed instead.
ARG AUDIO_FEEDER_SPEC="audio_feeder>=0.7.0"
ARG GUNICORN_SPEC="gunicorn>=23.0"
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv

ENV UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_COMPILE_BYTECODE=1 \
    UV_NO_CACHE=1

RUN uv python install "${PYTHON_VERSION}" \
    && uv venv --python "${PYTHON_VERSION}" /opt/venv

# .dockerignore limits the context to gunicorn.conf.py and a local clone of
# audio-feeder, if there is one.
COPY . /context
RUN set -eu; \
    for d in /context/audio_feeder /context/audio-feeder; do \
        if [ -d "$d" ]; then local_clone="$d"; fi; \
    done; \
    if [ -n "${local_clone:-}" ]; then \
        echo "Installing audio-feeder from ${local_clone}"; \
        spec="${local_clone}"; \
    else \
        echo "Installing ${AUDIO_FEEDER_SPEC}"; \
        spec="${AUDIO_FEEDER_SPEC}"; \
    fi; \
    uv pip install --python /opt/venv/bin/python "${spec}" "${GUNICORN_SPEC}"

FROM debian:${DEBIAN_VERSION}-slim

ARG DEBIAN_FRONTEND=noninteractive

# ffmpeg (with the aac encoder, which Debian's build has) is needed to read the
# audio files' metadata and to generate the rendered feeds.
RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# The virtual environment's python is a symlink into /opt/python, so they have
# to be at the same paths as in the builder.
COPY --from=builder /opt/python /opt/python
COPY --from=builder /opt/venv /opt/venv
COPY gunicorn.conf.py /opt/audio_feeder/gunicorn.conf.py

# PYTHON_GIL=0 keeps the GIL disabled even if an extension module hasn't
# declared that it supports free-threading; gunicorn.conf.py checks at startup
# that none of them would have enabled it.
ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHON_GIL=0 \
    PYTHONUNBUFFERED=1 \
    AF_CONFIG_DIR=/etc/audio_feeder \
    GUNICORN_THREADS=12

WORKDIR /etc/audio_feeder
EXPOSE 9090

CMD ["gunicorn", "--config", "/opt/audio_feeder/gunicorn.conf.py"]
