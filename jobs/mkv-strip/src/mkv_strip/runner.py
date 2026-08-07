from __future__ import annotations

import traceback
from datetime import datetime
from time import monotonic

from . import runtime
from .models import Config, FileResult, Outcome
from .processor import check_tools, cleanup, cleanup_leftovers, collect_files, process_file
from .processor import stripped_output_path, ShutdownRequested
from .summary import print_summary


def run(config: Config) -> int:
    check_tools()
    start_time = datetime.now().astimezone()
    start_monotonic = monotonic()

    runtime.LOGGER.info(
        "starting directories=%s remove_languages=%s recursive=%s in_place=%s keep_going=%s dry_run=%s",
        ",".join(str(path) for path in config.directories),
        ",".join(sorted(config.remove_languages)),
        config.recursive,
        config.in_place,
        config.keep_going,
        config.dry_run,
    )

    cleaned_files = cleanup_leftovers(config)

    files = collect_files(config)
    if not files:
        end_time = datetime.now().astimezone()
        duration_seconds = monotonic() - start_monotonic
        runtime.LOGGER.info(
            "done cleanup_deleted=%s modified=0 skipped=0 failed=0 total=0 duration_seconds=%.0f",
            len(cleaned_files),
            duration_seconds,
        )
        print_summary(
            config=config,
            start_time=start_time,
            end_time=end_time,
            duration_seconds=duration_seconds,
            cleaned_files=cleaned_files,
            changed_files=[],
            failed_files=[],
            modified=0,
            skipped=0,
            failed=0,
            total=0,
        )
        return 0

    modified = 0
    skipped = 0
    failed = 0
    changed_files: list[FileResult] = []
    failed_files: list[FileResult] = []

    runtime.LOGGER.info("found files=%s", len(files))

    for path in files:
        if runtime.SHUTDOWN_REQUESTED:
            failed += 1
            failed_files.append(FileResult(path=path, outcome=Outcome.FAILED, error="shutdown requested"))
            break

        try:
            result = process_file(path, config)
        except ShutdownRequested:
            failed += 1
            failed_files.append(
                FileResult(path=path, outcome=Outcome.FAILED, error="interrupted mid-file by shutdown"),
            )
            break
        except Exception as error:
            failed += 1
            runtime.LOGGER.error("unexpected-error path=%s traceback=%s", path, traceback.format_exc())
            failed_files.append(
                FileResult(
                    path=path,
                    outcome=Outcome.FAILED,
                    error=f"unexpected {type(error).__name__}: {error}",
                ),
            )
            cleanup(stripped_output_path(path))
            if not config.keep_going:
                break
            continue

        if result.outcome == Outcome.MODIFIED:
            modified += 1
            changed_files.append(result)
        elif result.outcome == Outcome.SKIPPED:
            skipped += 1
        else:
            failed += 1
            failed_files.append(result)
            if not config.keep_going:
                break

    end_time = datetime.now().astimezone()
    duration_seconds = monotonic() - start_monotonic
    runtime.LOGGER.info(
        "done cleanup_deleted=%s modified=%s skipped=%s failed=%s total=%s duration_seconds=%.0f",
        len(cleaned_files),
        modified,
        skipped,
        failed,
        len(files),
        duration_seconds,
    )
    print_summary(
        config=config,
        start_time=start_time,
        end_time=end_time,
        duration_seconds=duration_seconds,
        cleaned_files=cleaned_files,
        changed_files=changed_files,
        failed_files=failed_files,
        modified=modified,
        skipped=skipped,
        failed=failed,
        total=len(files),
    )

    if runtime.SHUTDOWN_REQUESTED:
        return 143
    if failed and config.fail_on_file_errors:
        return 1
    return 0
