from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import support  # noqa: F401
from mkv_strip import processor
from mkv_strip.models import Config, Outcome
from mkv_strip.processor import cleanup_leftovers, process_file, should_remove


class StreamRemovalTests(unittest.TestCase):
    def test_removes_configured_audio_language(self) -> None:
        stream = {"codec_type": "audio", "tags": {"language": "rus"}}

        self.assertTrue(should_remove(stream, Config(directories=[Path("/media")])))

    def test_removes_belarusian_audio_and_subtitles(self) -> None:
        config = Config(directories=[Path("/media")])
        audio = {"codec_type": "audio", "tags": {"language": "bel"}}
        subtitle = {"codec_type": "subtitle", "tags": {"language": "eng", "title": "Belarusian"}}

        self.assertTrue(should_remove(audio, config))
        self.assertTrue(should_remove(subtitle, config))

    def test_removes_matching_title_keyword(self) -> None:
        stream = {"codec_type": "subtitle", "tags": {"language": "eng", "title": "Russian forced"}}

        self.assertTrue(should_remove(stream, Config(directories=[Path("/media")])))

    def test_keeps_unmatched_audio_and_video(self) -> None:
        config = Config(directories=[Path("/media")])
        english_audio = {"codec_type": "audio", "tags": {"language": "eng", "title": "English"}}
        video = {"codec_type": "video", "tags": {"language": "und"}}

        self.assertFalse(should_remove(english_audio, config))
        self.assertFalse(should_remove(video, config))


class StartupCleanupTests(unittest.TestCase):
    def test_deletes_leftover_stripped_mkv_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            nested = root / "season"
            nested.mkdir()
            leftover = root / "movie.stripped.mkv"
            nested_leftover = nested / "episode.stripped.mkv"
            keep_mkv = root / "movie.mkv"
            keep_text = root / "notes.stripped.txt"

            for path in (leftover, nested_leftover, keep_mkv, keep_text):
                path.write_text("placeholder", encoding="utf-8")

            cleaned = cleanup_leftovers(Config(directories=[root], recursive=True))

            self.assertEqual(
                {path.name for path in cleaned},
                {"movie.stripped.mkv", "episode.stripped.mkv"},
            )
            self.assertFalse(leftover.exists())
            self.assertFalse(nested_leftover.exists())
            self.assertTrue(keep_mkv.exists())
            self.assertTrue(keep_text.exists())


STREAMS = [
    {"index": 0, "codec_type": "video", "codec_name": "hevc", "tags": {"language": "und"}},
    {"index": 1, "codec_type": "audio", "codec_name": "eac3", "tags": {"language": "eng"}},
    {"index": 2, "codec_type": "audio", "codec_name": "eac3", "tags": {"language": "rus"}},
]


class GrowingSourceTests(unittest.TestCase):
    """A still-downloading source must never be replaced by a remux of its partial bytes."""

    def test_fails_when_source_grows_during_remux(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "movie.mkv"
            source.write_bytes(b"x" * 1000)

            def fake_ffmpeg(_cmd: list[str], output_path: Path) -> int:
                # ffmpeg reads the partial file while the torrent client keeps appending.
                with source.open("ab") as handle:
                    handle.write(b"x" * 9000)
                output_path.write_bytes(b"y" * 900)
                return 0

            with (
                mock.patch.object(processor, "probe", return_value=(STREAMS, None)),
                mock.patch.object(processor, "run_ffmpeg", side_effect=fake_ffmpeg),
            ):
                result = process_file(source, Config(directories=[Path(temp_dir)]))

            self.assertEqual(result.outcome, Outcome.FAILED)
            self.assertIn("download in progress", result.error or "")
            self.assertEqual(source.read_bytes(), b"x" * 10000)
            self.assertFalse((Path(temp_dir) / "movie.stripped.mkv").exists())

    def test_replaces_original_when_source_is_stable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "movie.mkv"
            source.write_bytes(b"x" * 1000)

            def fake_ffmpeg(_cmd: list[str], output_path: Path) -> int:
                output_path.write_bytes(b"y" * 900)
                return 0

            with (
                mock.patch.object(processor, "probe", return_value=(STREAMS, None)),
                mock.patch.object(processor, "run_ffmpeg", side_effect=fake_ffmpeg),
            ):
                result = process_file(source, Config(directories=[Path(temp_dir)]))

            self.assertEqual(result.outcome, Outcome.MODIFIED)
            self.assertEqual(source.read_bytes(), b"y" * 900)


if __name__ == "__main__":
    unittest.main()
