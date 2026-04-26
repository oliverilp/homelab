from __future__ import annotations

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


def display_path(path: Path, config: Config) -> str:
    for directory in config.directories:
        try:
            return str(path.relative_to(directory))
        except ValueError:
            continue
    return str(path)


def print_summary(
    *,
    config: Config,
    cleaned_files: list[Path],
    changed_files: list[FileResult],
    modified: int,
    skipped: int,
    failed: int,
    total: int,
) -> None:
    total_saved = sum(result.saved_bytes for result in changed_files)
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
            print(f"    original: {format_size(original)} | saved: {format_size(result.saved_bytes)}")
    else:
        print("Changed files: none")

    print("---------------------------------------")
    print(f"Startup cleanup deleted: {len(cleaned_files)}")
    print(f"Total files scanned: {total}")
    print(f"Modified: {modified}")
    print(f"Ignored/skipped: {skipped}")
    print(f"Failed: {failed}")
    print(f"Total saved: {format_size(total_saved)}")
    print("=======================================", flush=True)
