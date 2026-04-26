from __future__ import annotations

from . import runtime
from .config import load_config, parse_args
from .processor import cleanup
from .runner import run


def main() -> int:
    runtime.setup_logging()
    runtime.install_signal_handlers()

    try:
        config = load_config(parse_args())
        return run(config)
    except Exception as error:
        runtime.LOGGER.error("fatal error=%s", error)
        if runtime.CURRENT_OUTPUT is not None:
            cleanup(runtime.CURRENT_OUTPUT)
        return 1

