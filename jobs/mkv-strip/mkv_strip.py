#!/usr/bin/env python3
"""Remove unwanted language tracks from MKV files by remuxing with ffmpeg."""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import signal
import subprocess
import sys
import time
import traceback
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any


DEFAULT_CONFIG_PATH = Path(os.environ.get("MKV_STRIP_CONFIG", "/etc/mkv-strip/config.json"))
DEFAULT_REMOVE_LANGUAGES = {"rus", "ukr"}
DEFAULT_TITLE_KEYWORDS = {
    "russian",
    "ukrainian",
    "\u0443\u043a\u0440\u0430\u0438\u043d",
    "\u0440\u0443\u0441\u0441\u043a",
    "\u0440\u043e\u0441",
}
MIN_OUTPUT_SIZE_RATIO = 0.05
STRIPPED_SUFFIX = ".stripped"

LOGGER = logging.getLogger("mkv-strip")
ACTIVE_PROCESS: subprocess.Popen[bytes] | None = None
CURRENT_OUTPUT: Path | None = None
SHUTDOWN_REQUESTED = False


class Outcome(Enum):
    MODIFIED = "modified"
    SKIPPED = "skipped"
    FAILED = "failed"


class ShutdownRequested(Exception):
    """Raised when Kubernetes or a user asks the process to stop."""


@dataclass(frozen=True)
class Config:
    directories: list[Path]
    remove_languages: set[str] = field(default_factory=lambda: set(DEFAULT_REMOVE_LANGUAGES))
    title_keywords: set[str] = field(default_factory=lambda: set(DEFAULT_TITLE_KEYWORDS))
    recursive: bool = True
    in_place: bool = True
    keep_going: bool = True
    dry_run: bool = False
    min_output_size_ratio: float = MIN_OUTPUT_SIZE_RATIO
    fail_on_file_errors: bool = True


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
    )


def check_tools() -> None:
    missing = [tool for tool in ("ffmpeg", "ffprobe") if shutil.which(tool) is None]
    if missing:
        raise RuntimeError(f"missing required tools: {', '.join(missing)}")


def run_capture(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )


def run_ffmpeg(cmd: list[str], output_path: Path) -> int:
    global ACTIVE_PROCESS

    ACTIVE_PROCESS = subprocess.Popen(cmd)
    try:
        while True:
            return_code = ACTIVE_PROCESS.poll()
            if return_code is not None:
                return return_code

            if SHUTDOWN_REQUESTED:
                ACTIVE_PROCESS.terminate()
                try:
                    ACTIVE_PROCESS.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    LOGGER.warning("ffmpeg did not exit after SIGTERM; killing it")
                    ACTIVE_PROCESS.kill()
                    ACTIVE_PROCESS.wait(timeout=10)
                cleanup(output_path)
                raise ShutdownRequested()

            time.sleep(1)
    finally:
        ACTIVE_PROCESS = None


def probe(path: Path) -> list[dict[str, Any]] | None:
    try:
        result = run_capture(
            [
                "ffprobe",
                "-v",
                "quiet",
                "-print_format",
                "json",
                "-show_streams",
                str(path),
            ],
        )
    except OSError as error:
        LOGGER.error("ffprobe launch failed path=%s error=%s", path, error)
        return None

    if result.returncode != 0:
        LOGGER.error(
            "ffprobe failed path=%s returncode=%s stderr=%s",
            path,
            result.returncode,
            result.stderr.strip(),
        )
        return None

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        LOGGER.error("ffprobe returned invalid json path=%s error=%s", path, error)
        return None

    streams = data.get("streams")
    if not isinstance(streams, list):
        LOGGER.error("ffprobe output had no streams list path=%s", path)
        return None

    return streams


def should_remove(stream: dict[str, Any], config: Config) -> bool:
    codec_type = stream.get("codec_type", "")
    if codec_type not in ("audio", "subtitle"):
        return False

    tags = stream.get("tags") or {}
    language = str(tags.get("language", "")).lower().strip()
    title = str(tags.get("title", "")).lower().strip()

    return language in config.remove_languages or any(
        keyword in title for keyword in config.title_keywords
    )


def format_stream(stream: dict[str, Any]) -> str:
    index = stream.get("index", "?")
    codec_type = stream.get("codec_type", "?")
    codec = stream.get("codec_name", "?")
    tags = stream.get("tags") or {}
    language = tags.get("language", "und")
    title = tags.get("title", "")
    channels = stream.get("channels", "")
    channel_text = f" {channels}ch" if channels else ""
    title_text = f" title={title!r}" if title else ""
    return f"[{index:>2}] {codec_type:<9} {codec:<10} lang={language:<4}{channel_text}{title_text}"


def cleanup(path: Path) -> None:
    try:
        if path.exists():
            path.unlink()
            LOGGER.info("removed incomplete output path=%s", path)
    except OSError as error:
        LOGGER.warning("could not remove incomplete output path=%s error=%s", path, error)


def stripped_output_path(path: Path) -> Path:
    return path.with_name(f"{path.stem}{STRIPPED_SUFFIX}{path.suffix}")


def process_file(path: Path, config: Config) -> Outcome:
    global CURRENT_OUTPUT

    if path.stem.endswith(STRIPPED_SUFFIX):
        LOGGER.info("skip stripped-output path=%s", path)
        return Outcome.SKIPPED

    LOGGER.info("processing path=%s", path)

    streams = probe(path)
    if streams is None:
        return Outcome.FAILED
    if not streams:
        LOGGER.warning("skip no-streams path=%s", path)
        return Outcome.FAILED

    keep: list[dict[str, Any]] = []
    remove: list[dict[str, Any]] = []

    for stream in streams:
        if should_remove(stream, config):
            LOGGER.info("remove path=%s stream=%s", path, format_stream(stream))
            remove.append(stream)
        else:
            LOGGER.info("keep path=%s stream=%s", path, format_stream(stream))
            keep.append(stream)

    if not remove:
        LOGGER.info("skip no-matching-tracks path=%s", path)
        return Outcome.SKIPPED

    kept_audio = [stream for stream in keep if stream.get("codec_type") == "audio"]
    if not kept_audio:
        LOGGER.warning("skip would-remove-all-audio path=%s", path)
        return Outcome.SKIPPED

    kept_video = [
        stream
        for stream in keep
        if stream.get("codec_type") == "video"
        and not (stream.get("disposition") or {}).get("attached_pic", 0)
    ]
    if not kept_video:
        LOGGER.warning("skip would-remove-all-video path=%s", path)
        return Outcome.SKIPPED

    removed_types = ",".join(sorted({str(stream.get("codec_type")) for stream in remove}))
    LOGGER.info(
        "planned-removal path=%s track_count=%s track_types=%s",
        path,
        len(remove),
        removed_types,
    )

    if config.dry_run:
        return Outcome.MODIFIED

    remove_indices = {int(stream["index"]) for stream in remove}
    map_args = ["-map", "0"]
    for index in sorted(remove_indices):
        map_args.extend(["-map", f"-0:{index}"])

    disposition_args: list[str] = []
    audio_output_index = 0
    for stream in keep:
        if stream.get("codec_type") == "audio":
            flag = "default" if audio_output_index == 0 else "0"
            disposition_args.extend([f"-disposition:a:{audio_output_index}", flag])
            audio_output_index += 1

    output_path = stripped_output_path(path)
    CURRENT_OUTPUT = output_path

    if output_path.exists():
        LOGGER.info("removing leftover output path=%s", output_path)
        output_path.unlink()

    cmd = [
        "ffmpeg",
        "-y",
        "-i",
        str(path),
        *map_args,
        "-c",
        "copy",
        *disposition_args,
        str(output_path),
    ]

    LOGGER.info("running ffmpeg path=%s output=%s", path, output_path)

    try:
        return_code = run_ffmpeg(cmd, output_path)
    except OSError as error:
        LOGGER.error("ffmpeg launch failed path=%s error=%s", path, error)
        cleanup(output_path)
        return Outcome.FAILED
    finally:
        CURRENT_OUTPUT = None

    if return_code != 0:
        LOGGER.error("ffmpeg failed path=%s returncode=%s", path, return_code)
        cleanup(output_path)
        return Outcome.FAILED

    if not output_path.exists():
        LOGGER.error("ffmpeg succeeded but output missing path=%s output=%s", path, output_path)
        return Outcome.FAILED

    original_size = path.stat().st_size
    new_size = output_path.stat().st_size

    if new_size == 0:
        LOGGER.error("output is empty path=%s output=%s", path, output_path)
        cleanup(output_path)
        return Outcome.FAILED

    if new_size < original_size * config.min_output_size_ratio:
        LOGGER.error(
            "output suspiciously small path=%s original_bytes=%s new_bytes=%s",
            path,
            original_size,
            new_size,
        )
        cleanup(output_path)
        return Outcome.FAILED

    saved_mb = (original_size - new_size) / 1_048_576
    LOGGER.info(
        "remux-success path=%s original_mb=%s new_mb=%s saved_mb=%.1f",
        path,
        original_size // 1_048_576,
        new_size // 1_048_576,
        saved_mb,
    )

    if not config.in_place:
        LOGGER.info("kept output path=%s", output_path)
        return Outcome.MODIFIED

    try:
        output_path.replace(path)
    except OSError as error:
        LOGGER.error("replace failed path=%s output=%s error=%s", path, output_path, error)
        return Outcome.FAILED

    LOGGER.info("replaced original path=%s", path)
    return Outcome.MODIFIED


def iter_mkv_files(input_path: Path, recursive: bool) -> list[Path]:
    if input_path.is_file():
        if input_path.suffix.lower() == ".mkv" and not input_path.stem.endswith(STRIPPED_SUFFIX):
            return [input_path]
        return []

    if not input_path.is_dir():
        raise FileNotFoundError(f"configured path is not a file or directory: {input_path}")

    candidates = input_path.rglob("*") if recursive else input_path.glob("*")
    return sorted(
        path
        for path in candidates
        if path.is_file()
        and path.suffix.lower() == ".mkv"
        and not path.stem.endswith(STRIPPED_SUFFIX)
    )


def collect_files(config: Config) -> list[Path]:
    files: list[Path] = []
    seen: set[Path] = set()

    for directory in config.directories:
        for path in iter_mkv_files(directory, config.recursive):
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            files.append(path)

    return sorted(files)


def run(config: Config) -> int:
    check_tools()

    LOGGER.info(
        "starting directories=%s remove_languages=%s recursive=%s in_place=%s keep_going=%s dry_run=%s",
        ",".join(str(path) for path in config.directories),
        ",".join(sorted(config.remove_languages)),
        config.recursive,
        config.in_place,
        config.keep_going,
        config.dry_run,
    )

    files = collect_files(config)
    if not files:
        LOGGER.info("done modified=0 skipped=0 failed=0 total=0")
        return 0

    modified = 0
    skipped = 0
    failed = 0

    LOGGER.info("found files=%s", len(files))

    for path in files:
        if SHUTDOWN_REQUESTED:
            failed += 1
            break

        try:
            outcome = process_file(path, config)
        except ShutdownRequested:
            failed += 1
            break
        except Exception:
            failed += 1
            LOGGER.error("unexpected-error path=%s traceback=%s", path, traceback.format_exc())
            cleanup(stripped_output_path(path))
            if not config.keep_going:
                break
            continue

        if outcome == Outcome.MODIFIED:
            modified += 1
        elif outcome == Outcome.SKIPPED:
            skipped += 1
        else:
            failed += 1
            if not config.keep_going:
                break

    LOGGER.info(
        "done modified=%s skipped=%s failed=%s total=%s",
        modified,
        skipped,
        failed,
        len(files),
    )

    if SHUTDOWN_REQUESTED:
        return 143
    if failed and config.fail_on_file_errors:
        return 1
    return 0


def main() -> int:
    setup_logging()
    install_signal_handlers()

    try:
        config = load_config(parse_args())
        return run(config)
    except Exception as error:
        LOGGER.error("fatal error=%s", error)
        if CURRENT_OUTPUT is not None:
            cleanup(CURRENT_OUTPUT)
        return 1


if __name__ == "__main__":
    sys.exit(main())

