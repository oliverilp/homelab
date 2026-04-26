from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import support


def run_command(cmd: list[str], *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        env=env,
    )


@unittest.skipIf(
    shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None,
    "ffmpeg and ffprobe are required for the integration test",
)
class FfmpegIntegrationTests(unittest.TestCase):
    def test_strips_generated_russian_audio_track(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            media_dir = Path(temp_dir)
            input_path = media_dir / "sample.mkv"

            create_result = run_command(
                [
                    "ffmpeg",
                    "-y",
                    "-v",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "testsrc=size=64x64:rate=1:duration=2",
                    "-f",
                    "lavfi",
                    "-i",
                    "sine=frequency=440:sample_rate=8000:duration=2",
                    "-f",
                    "lavfi",
                    "-i",
                    "sine=frequency=880:sample_rate=8000:duration=2",
                    "-map",
                    "0:v:0",
                    "-map",
                    "1:a:0",
                    "-map",
                    "2:a:0",
                    "-metadata:s:a:0",
                    "language=eng",
                    "-metadata:s:a:1",
                    "language=rus",
                    "-c:v",
                    "mpeg4",
                    "-q:v",
                    "5",
                    "-c:a",
                    "aac",
                    "-b:a",
                    "32k",
                    "-shortest",
                    str(input_path),
                ],
            )
            self.assertEqual(create_result.returncode, 0, create_result.stderr)

            env = os.environ.copy()
            env["PYTHONPATH"] = str(support.SRC_ROOT)
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            run_result = run_command(
                [
                    sys.executable,
                    "-B",
                    "-m",
                    "mkv_strip",
                    str(media_dir),
                    "--recursive",
                    "--in-place",
                    "--keep-going",
                ],
                env=env,
            )
            self.assertEqual(run_result.returncode, 0, run_result.stderr + run_result.stdout)

            probe_result = run_command(
                [
                    "ffprobe",
                    "-v",
                    "quiet",
                    "-print_format",
                    "json",
                    "-show_streams",
                    str(input_path),
                ],
            )
            self.assertEqual(probe_result.returncode, 0, probe_result.stderr)

            data = json.loads(probe_result.stdout)
            audio_languages = [
                stream.get("tags", {}).get("language")
                for stream in data["streams"]
                if stream.get("codec_type") == "audio"
            ]

            self.assertEqual(audio_languages, ["eng"])
            self.assertFalse((media_dir / "sample.stripped.mkv").exists())
            self.assertIn("Changed files:", run_result.stdout)
            self.assertIn("Modified: 1", run_result.stdout)
            self.assertIn("Failed: 0", run_result.stdout)


if __name__ == "__main__":
    unittest.main()
