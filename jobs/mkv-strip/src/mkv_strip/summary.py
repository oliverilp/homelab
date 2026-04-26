from __future__ import annotations

from datetime import datetime
from pathlib import Path

from .models import Config, FileResult


def format_size(num_bytes: int) -> str:
    units = ("B", "KiB", "MiB", "GiB", "TiB")
    value = float(num_bytes)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            if unit == "B":
                return f"{int(value)} {unit}"
            return f"{value:.1f} {unit}"
        value /= 1024
    return f"{value:.1f} TiB"


def format_reduction_percent(original_bytes: int, saved_bytes: int) -> str:
    if original_bytes <= 0:
        return "0.0%"
    return f"{(saved_bytes / original_bytes) * 100:.1f}%"


def display_path(path: Path, config: Config) -> str:
    for directory in config.directories:
        try:
            return str(path.relative_to(directory))
        except ValueError:
            continue
    return str(path)


def format_datetime(value: datetime) -> str:
    return value.strftime("%Y-%m-%d %H:%M:%S %z")


def format_duration(seconds: float) -> str:
    total_seconds = max(0, int(round(seconds)))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    if hours:
        return f"{hours}h {minutes:02d}m {seconds:02d}s"
    if minutes:
        return f"{minutes}m {seconds:02d}s"
    return f"{seconds}s"


def print_summary(
    *,
    config: Config,
    start_time: datetime,
    end_time: datetime,
    duration_seconds: float,
    cleaned_files: list[Path],
    changed_files: list[FileResult],
    modified: int,
    skipped: int,
    failed: int,
    total: int,
) -> None:
    total_saved = sum(result.saved_bytes for result in changed_files)
    total_original = sum(result.original_bytes or 0 for result in changed_files)
    print()
    print("========== mkv-strip summary ==========")

    if cleaned_files:
        print(f"Deleted leftover files: {len(cleaned_files)}")
        for path in cleaned_files:
            print(f"  {display_path(path, config)}")
    else:
        print("Deleted leftover files: none")

    print()

    if changed_files:
        print("Changed files:")
        for result in changed_files:
            print(f"  {display_path(result.path, config)}")
            original = result.original_bytes or 0
            percent = format_reduction_percent(original, result.saved_bytes)
            print(f"    original: {format_size(original)} | saved: {format_size(result.saved_bytes)} ({percent})")
    else:
        print("Changed files: none")

    print("---------------------------------------")
    print(f"Started: {format_datetime(start_time)}")
    print(f"Finished: {format_datetime(end_time)}")
    print(f"Duration: {format_duration(duration_seconds)}")
    print(f"Startup cleanup deleted: {len(cleaned_files)}")
    print(f"Total files scanned: {total}")
    print(f"Modified: {modified}")
    print(f"Ignored/skipped: {skipped}")
    print(f"Failed: {failed}")
    print(f"Total saved: {format_size(total_saved)} ({format_reduction_percent(total_original, total_saved)})")
    print("=======================================", flush=True)
