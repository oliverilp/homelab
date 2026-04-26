from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from .constants import DEFAULT_CONFIG_PATH, DEFAULT_REMOVE_LANGUAGES, DEFAULT_TITLE_KEYWORDS
from .constants import MIN_OUTPUT_SIZE_RATIO
from .models import Config


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Strip configured audio and subtitle tracks from MKV files.",
    )
    parser.add_argument(
        "directories",
        nargs="*",
        help="MKV file or directory paths. Overrides directories from the config file.",
    )
    parser.add_argument(
        "--config",
        default=str(DEFAULT_CONFIG_PATH),
        help=f"JSON config path. Defaults to {DEFAULT_CONFIG_PATH}.",
    )
    parser.add_argument(
        "--remove-langs",
        nargs="+",
        default=None,
        metavar="LANG",
        help="ISO 639-2 language codes to remove. Overrides config remove_languages.",
    )
    parser.add_argument(
        "--recursive",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Recursively crawl directories.",
    )
    parser.add_argument(
        "--in-place",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Replace original files after successful remux.",
    )
    parser.add_argument(
        "--keep-going",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Continue after per-file failures.",
    )
    parser.add_argument(
        "--dry-run",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Preview changes without writing files.",
    )
    return parser.parse_args()


def read_json_config(config_path: Path) -> dict[str, Any]:
    if not config_path.exists():
        if config_path == DEFAULT_CONFIG_PATH:
            return {}
        raise FileNotFoundError(f"config file does not exist: {config_path}")

    with config_path.open("r", encoding="utf-8") as config_file:
        data = json.load(config_file)

    if not isinstance(data, dict):
        raise ValueError("config file must contain a JSON object")

    return data


def as_string_list(raw: Any, key: str) -> list[str]:
    if raw is None:
        return []
    if isinstance(raw, str):
        return [raw]
    if isinstance(raw, list) and all(isinstance(item, str) for item in raw):
        return raw
    raise ValueError(f"config key {key!r} must be a string or list of strings")


def as_bool(raw: Any, key: str, default: bool) -> bool:
    if raw is None:
        return default
    if isinstance(raw, bool):
        return raw
    raise ValueError(f"config key {key!r} must be a boolean")


def as_float(raw: Any, key: str, default: float) -> float:
    if raw is None:
        return default
    if isinstance(raw, int | float):
        return float(raw)
    raise ValueError(f"config key {key!r} must be a number")


def load_config(args: argparse.Namespace) -> Config:
    raw = read_json_config(Path(args.config))
    configured_directories = as_string_list(
        raw.get("directories", raw.get("paths")),
        "directories",
    )
    directories = args.directories or configured_directories

    if not directories:
        raise ValueError("no directories configured; set config directories or pass paths")

    remove_languages = {
        lang.lower().strip()
        for lang in as_string_list(raw.get("remove_languages"), "remove_languages")
    } or set(DEFAULT_REMOVE_LANGUAGES)
    if args.remove_langs is not None:
        remove_languages = {lang.lower().strip() for lang in args.remove_langs}

    title_keywords = {
        keyword.lower().strip()
        for keyword in as_string_list(raw.get("title_keywords"), "title_keywords")
    } or set(DEFAULT_TITLE_KEYWORDS)

    recursive = as_bool(raw.get("recursive"), "recursive", True)
    in_place = as_bool(raw.get("in_place"), "in_place", True)
    keep_going = as_bool(raw.get("keep_going"), "keep_going", True)
    dry_run = as_bool(raw.get("dry_run"), "dry_run", False)

    if args.recursive is not None:
        recursive = args.recursive
    if args.in_place is not None:
        in_place = args.in_place
    if args.keep_going is not None:
        keep_going = args.keep_going
    if args.dry_run is not None:
        dry_run = args.dry_run

    min_ratio = as_float(
        raw.get("min_output_size_ratio"),
        "min_output_size_ratio",
        MIN_OUTPUT_SIZE_RATIO,
    )
    if min_ratio <= 0 or min_ratio >= 1:
        raise ValueError("min_output_size_ratio must be greater than 0 and less than 1")

    return Config(
        directories=[Path(directory) for directory in directories],
        remove_languages=remove_languages,
        title_keywords=title_keywords,
        recursive=recursive,
        in_place=in_place,
        keep_going=keep_going,
        dry_run=dry_run,
        min_output_size_ratio=min_ratio,
        fail_on_file_errors=as_bool(
            raw.get("fail_on_file_errors"),
            "fail_on_file_errors",
            True,
        ),
        cleanup_leftovers=as_bool(
            raw.get("cleanup_leftovers"),
            "cleanup_leftovers",
            True,
        ),
    )

