from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from . import runtime
from .constants import STRIPPED_SUFFIX
from .models import Config, FileResult, Outcome


class ShutdownRequested(Exception):
    """Raised when Kubernetes or a user asks the process to stop."""


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
    runtime.ACTIVE_PROCESS = subprocess.Popen(cmd)
    try:
        while True:
            return_code = runtime.ACTIVE_PROCESS.poll()
            if return_code is not None:
                return return_code

            if runtime.SHUTDOWN_REQUESTED:
                runtime.ACTIVE_PROCESS.terminate()
                try:
                    runtime.ACTIVE_PROCESS.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    runtime.LOGGER.warning("ffmpeg did not exit after SIGTERM; killing it")
                    runtime.ACTIVE_PROCESS.kill()
                    runtime.ACTIVE_PROCESS.wait(timeout=10)
                cleanup(output_path)
                raise ShutdownRequested()

            time.sleep(1)
    finally:
        runtime.ACTIVE_PROCESS = None


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
        runtime.LOGGER.error("ffprobe launch failed path=%s error=%s", path, error)
        return None

    if result.returncode != 0:
        runtime.LOGGER.error(
            "ffprobe failed path=%s returncode=%s stderr=%s",
            path,
            result.returncode,
            result.stderr.strip(),
        )
        return None

    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        runtime.LOGGER.error("ffprobe returned invalid json path=%s error=%s", path, error)
        return None

    streams = data.get("streams")
    if not isinstance(streams, list):
        runtime.LOGGER.error("ffprobe output had no streams list path=%s", path)
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
            runtime.LOGGER.info("removed incomplete output path=%s", path)
    except OSError as error:
        runtime.LOGGER.warning("could not remove incomplete output path=%s error=%s", path, error)


def stripped_output_path(path: Path) -> Path:
    return path.with_name(f"{path.stem}{STRIPPED_SUFFIX}{path.suffix}")


def process_file(path: Path, config: Config) -> FileResult:
    if path.stem.endswith(STRIPPED_SUFFIX):
        runtime.LOGGER.info("skip stripped-output path=%s", path)
        return FileResult(path=path, outcome=Outcome.SKIPPED)

    runtime.LOGGER.info("processing path=%s", path)

    streams = probe(path)
    if streams is None:
        return FileResult(path=path, outcome=Outcome.FAILED)
    if not streams:
        runtime.LOGGER.warning("skip no-streams path=%s", path)
        return FileResult(path=path, outcome=Outcome.FAILED)

    keep: list[dict[str, Any]] = []
    remove: list[dict[str, Any]] = []

    for stream in streams:
        if should_remove(stream, config):
            runtime.LOGGER.info("remove path=%s stream=%s", path, format_stream(stream))
            remove.append(stream)
        else:
            runtime.LOGGER.info("keep path=%s stream=%s", path, format_stream(stream))
            keep.append(stream)

    if not remove:
        runtime.LOGGER.info("skip no-matching-tracks path=%s", path)
        return FileResult(path=path, outcome=Outcome.SKIPPED)

    kept_audio = [stream for stream in keep if stream.get("codec_type") == "audio"]
    if not kept_audio:
        runtime.LOGGER.warning("skip would-remove-all-audio path=%s", path)
        return FileResult(path=path, outcome=Outcome.SKIPPED)

    kept_video = [
        stream
        for stream in keep
        if stream.get("codec_type") == "video"
        and not (stream.get("disposition") or {}).get("attached_pic", 0)
    ]
    if not kept_video:
        runtime.LOGGER.warning("skip would-remove-all-video path=%s", path)
        return FileResult(path=path, outcome=Outcome.SKIPPED)

    removed_types = ",".join(sorted({str(stream.get("codec_type")) for stream in remove}))
    runtime.LOGGER.info(
        "planned-removal path=%s track_count=%s track_types=%s",
        path,
        len(remove),
        removed_types,
    )

    if config.dry_run:
        return FileResult(path=path, outcome=Outcome.MODIFIED)

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
    runtime.CURRENT_OUTPUT = output_path

    if output_path.exists():
        runtime.LOGGER.info("removing leftover output path=%s", output_path)
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

    runtime.LOGGER.info("running ffmpeg path=%s output=%s", path, output_path)

    try:
        return_code = run_ffmpeg(cmd, output_path)
    except OSError as error:
        runtime.LOGGER.error("ffmpeg launch failed path=%s error=%s", path, error)
        cleanup(output_path)
        return FileResult(path=path, outcome=Outcome.FAILED)
    finally:
        runtime.CURRENT_OUTPUT = None

    if return_code != 0:
        runtime.LOGGER.error("ffmpeg failed path=%s returncode=%s", path, return_code)
        cleanup(output_path)
        return FileResult(path=path, outcome=Outcome.FAILED)

    if not output_path.exists():
        runtime.LOGGER.error("ffmpeg succeeded but output missing path=%s output=%s", path, output_path)
        return FileResult(path=path, outcome=Outcome.FAILED)

    original_size = path.stat().st_size
    new_size = output_path.stat().st_size

    if new_size == 0:
        runtime.LOGGER.error("output is empty path=%s output=%s", path, output_path)
        cleanup(output_path)
        return FileResult(path=path, outcome=Outcome.FAILED)

    if new_size < original_size * config.min_output_size_ratio:
        runtime.LOGGER.error(
            "output suspiciously small path=%s original_bytes=%s new_bytes=%s",
            path,
            original_size,
            new_size,
        )
        cleanup(output_path)
        return FileResult(path=path, outcome=Outcome.FAILED)

    saved_mb = (original_size - new_size) / 1_048_576
    runtime.LOGGER.info(
        "remux-success path=%s original_mb=%s new_mb=%s saved_mb=%.1f",
        path,
        original_size // 1_048_576,
        new_size // 1_048_576,
        saved_mb,
    )

    if not config.in_place:
        runtime.LOGGER.info("kept output path=%s", output_path)
        return FileResult(
            path=path,
            outcome=Outcome.MODIFIED,
            original_bytes=original_size,
            new_bytes=new_size,
        )

    try:
        output_path.replace(path)
    except OSError as error:
        runtime.LOGGER.error("replace failed path=%s output=%s error=%s", path, output_path, error)
        return FileResult(path=path, outcome=Outcome.FAILED)

    runtime.LOGGER.info("replaced original path=%s", path)
    return FileResult(
        path=path,
        outcome=Outcome.MODIFIED,
        original_bytes=original_size,
        new_bytes=new_size,
    )


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


def is_stripped_leftover(path: Path) -> bool:
    return path.is_file() and path.suffix.lower() == ".mkv" and path.stem.endswith(STRIPPED_SUFFIX)


def iter_stripped_leftovers(input_path: Path, recursive: bool) -> list[Path]:
    if input_path.is_file():
        return [input_path] if is_stripped_leftover(input_path) else []

    if not input_path.is_dir():
        raise FileNotFoundError(f"configured path is not a file or directory: {input_path}")

    candidates = input_path.rglob("*") if recursive else input_path.glob("*")
    return sorted(path for path in candidates if is_stripped_leftover(path))


def cleanup_leftovers(config: Config) -> list[Path]:
    if not config.cleanup_leftovers:
        return []
    if config.dry_run or not config.in_place:
        runtime.LOGGER.info("skip startup cleanup dry_run=%s in_place=%s", config.dry_run, config.in_place)
        return []

    cleaned: list[Path] = []
    seen: set[Path] = set()

    for directory in config.directories:
        for path in iter_stripped_leftovers(directory, config.recursive):
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            try:
                path.unlink()
                cleaned.append(path)
                runtime.LOGGER.info("removed leftover stripped output path=%s", path)
            except OSError as error:
                runtime.LOGGER.warning(
                    "could not remove leftover stripped output path=%s error=%s",
                    path,
                    error,
                )

    if cleaned:
        runtime.LOGGER.info("startup cleanup removed leftover_count=%s", len(cleaned))
    else:
        runtime.LOGGER.info("startup cleanup found no leftover stripped outputs")

    return cleaned


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
