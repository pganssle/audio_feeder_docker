"""gunicorn configuration for audio-feeder.

audio-feeder is meant to run on a free-threaded build of Python with the GIL
disabled, so this runs a single worker process with many threads (the
``gthread`` worker), rather than many processes. Any of these settings can be
overridden on the command line or with ``GUNICORN_CMD_ARGS``.

Environment variables:

``GUNICORN_THREADS``
    The number of threads handling requests (default: 12).

``GUNICORN_TIMEOUT``
    Seconds of silence from the worker's main loop before it's killed and
    restarted (default: 60). With the ``gthread`` worker, this doesn't limit
    how long an individual request can take.

``GUNICORN_ACCESS_LOG``, ``GUNICORN_ERROR_LOG``
    Where to write the logs; ``-`` means stdout / stderr.

``AF_REQUIRE_FREE_THREADING``
    If ``1`` (the default), refuse to start if the GIL would be enabled. If
    ``0``, only log a warning.
"""

import os
import subprocess
import sys

from gunicorn import arbiter
from gunicorn.workers import base

wsgi_app = "audio_feeder.app:create_app()"
bind = "0.0.0.0:9090"

workers = 1
worker_class = "gthread"
threads = int(os.environ.get("GUNICORN_THREADS", "12"))
timeout = int(os.environ.get("GUNICORN_TIMEOUT", "60"))
graceful_timeout = 30
keepalive = 5

accesslog = os.environ.get(
    "GUNICORN_ACCESS_LOG", "/etc/audio_feeder/logs/audio_feeder.access.log"
)
errorlog = os.environ.get(
    "GUNICORN_ERROR_LOG", "/etc/audio_feeder/logs/audio_feeder.error.log"
)

# This is run in a fresh interpreter with PYTHON_GIL unset, i.e. in the
# interpreter's default mode, where importing an extension module that hasn't
# declared that it supports free-threading re-enables the GIL (with a
# RuntimeWarning naming the module). With PYTHON_GIL=0, which the image sets,
# the GIL stays disabled anyway, so this is the only way to find out whether
# that's safe.
_GIL_CHECK = """
import importlib, pkgutil, sys
import audio_feeder, audio_feeder.app, gunicorn.workers.gthread
for module in pkgutil.walk_packages(audio_feeder.__path__, "audio_feeder."):
    importlib.import_module(module.name)
sys.exit(3 if sys._is_gil_enabled() else 0)
"""


def _gil_problems() -> str | None:
    """Return a description of why the GIL would be enabled, if it would be."""
    is_gil_enabled = getattr(sys, "_is_gil_enabled", None)
    if is_gil_enabled is None or is_gil_enabled():
        return f"this is not a free-threaded build of Python ({sys.version})"

    env = {k: v for k, v in os.environ.items() if k != "PYTHON_GIL"}
    result = subprocess.run(
        (sys.executable, "-c", _GIL_CHECK),
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 3:
        return (
            "an extension module imported by audio-feeder doesn't support "
            "free-threading, so it would enable the GIL:\n" + result.stderr.strip()
        )
    if result.returncode != 0:
        return (
            f"the free-threading check failed (exit code {result.returncode}):\n"
            + result.stderr.strip()
        )

    return None


def on_starting(server: arbiter.Arbiter) -> None:
    if (problem := _gil_problems()) is None:
        server.log.info("Free-threading check passed: the GIL is disabled")
        return

    if os.environ.get("AF_REQUIRE_FREE_THREADING", "1") == "0":
        server.log.warning("Free-threading check failed, starting anyway: %s", problem)
        return

    server.log.error(
        "Refusing to start: %s\nSet AF_REQUIRE_FREE_THREADING=0 to start anyway.",
        problem,
    )
    raise SystemExit(1)


def post_worker_init(worker: base.Worker) -> None:
    worker.log.info(
        "Worker started with %d threads; GIL enabled: %s",
        threads,
        sys._is_gil_enabled(),
    )
