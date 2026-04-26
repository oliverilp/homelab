from __future__ import annotations

import logging
import signal
import subprocess
import sys
from pathlib import Path

from .constants import LOGGER_NAME


LOGGER = logging.getLogger(LOGGER_NAME)
ACTIVE_PROCESS: subprocess.Popen[bytes] | None = None
CURRENT_OUTPUT: Path | None = None
SHUTDOWN_REQUESTED = False


def setup_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z",
        handlers=[logging.StreamHandler(sys.stdout)],
    )


def request_shutdown(signum: int, _frame: object) -> None:
    global SHUTDOWN_REQUESTED

    SHUTDOWN_REQUESTED = True
    LOGGER.warning("received signal=%s; stopping after current cleanup", signum)

    if ACTIVE_PROCESS is not None and ACTIVE_PROCESS.poll() is None:
        LOGGER.warning("terminating active ffmpeg process")
        ACTIVE_PROCESS.terminate()


def install_signal_handlers() -> None:
    signal.signal(signal.SIGINT, request_shutdown)
    signal.signal(signal.SIGTERM, request_shutdown)

