from __future__ import annotations

import io
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path

import support  # noqa: F401
from mkv_strip.models import Config, FileResult, Outcome
from mkv_strip.summary import format_duration, format_reduction_percent, print_summary


class SummaryFormattingTests(unittest.TestCase):
    def test_formats_duration(self) -> None:
        self.assertEqual(format_duration(0), "0s")
        self.assertEqual(format_duration(35), "35s")
        self.assertEqual(format_duration(95), "1m 35s")
        self.assertEqual(format_duration(3662), "1h 01m 02s")

    def test_formats_reduction_percent(self) -> None:
        self.assertEqual(format_reduction_percent(1000, 291), "29.1%")
        self.assertEqual(format_reduction_percent(0, 10), "0.0%")

    def test_print_summary_includes_times_and_saved_percentages(self) -> None:
        tz = timezone(timedelta(hours=3))
        output = io.StringIO()

        with redirect_stdout(output):
            print_summary(
                config=Config(directories=[Path("/media")]),
                start_time=datetime(2026, 4, 26, 19, 32, 33, tzinfo=tz),
                end_time=datetime(2026, 4, 26, 20, 33, 35, tzinfo=tz),
                duration_seconds=3662,
                cleaned_files=[Path("/media/movie.stripped.mkv")],
                changed_files=[
                    FileResult(
                        path=Path("/media/movie.mkv"),
                        outcome=Outcome.MODIFIED,
                        original_bytes=1000,
                        new_bytes=709,
                    ),
                ],
                modified=1,
                skipped=496,
                failed=0,
                total=497,
            )

        summary = output.getvalue()

        self.assertIn("Deleted leftover files: 1", summary)
        self.assertIn("movie.stripped.mkv", summary)
        self.assertIn("original: 1000 B | saved: 291 B (29.1%)", summary)
        self.assertIn("Started: 2026-04-26 19:32:33 +0300", summary)
        self.assertIn("Finished: 2026-04-26 20:33:35 +0300", summary)
        self.assertIn("Duration: 1h 01m 02s", summary)
        self.assertIn("Total saved: 291 B (29.1%)", summary)


if __name__ == "__main__":
    unittest.main()
