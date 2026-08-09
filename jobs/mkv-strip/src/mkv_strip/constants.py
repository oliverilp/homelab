from __future__ import annotations

import os
from pathlib import Path


DEFAULT_CONFIG_PATH = Path(os.environ.get("MKV_STRIP_CONFIG", "/etc/mkv-strip/config.json"))
DEFAULT_REMOVE_LANGUAGES = {"rus", "ukr", "bel"}
DEFAULT_TITLE_KEYWORDS = {
    "russian",
    "ukrainian",
    "belarusian",
    "belorussian",
    "byelorussian",
    "\u0443\u043a\u0440\u0430\u0438\u043d",
    "\u0440\u0443\u0441\u0441\u043a",
    "\u0440\u043e\u0441",
    "\u0431\u0435\u043b\u0430\u0440\u0443\u0441",
    "\u0431\u0435\u043b\u043e\u0440\u0443\u0441",
}
LOGGER_NAME = "mkv-strip"
MIN_OUTPUT_SIZE_RATIO = 0.05
STRIPPED_SUFFIX = ".stripped"

