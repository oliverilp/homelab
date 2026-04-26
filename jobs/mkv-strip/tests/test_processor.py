from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import support  # noqa: F401
from mkv_strip.models import Config
from mkv_strip.processor import cleanup_leftovers, should_remove


class StreamRemovalTests(unittest.TestCase):
    def test_removes_configured_audio_language(self) -> None:
        stream = {"codec_type": "audio", "tags": {"language": "rus"}}

        self.assertTrue(should_remove(stream, Config(directories=[Path("/media")])))

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


if __name__ == "__main__":
    unittest.main()
