from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from .constants import DEFAULT_REMOVE_LANGUAGES, DEFAULT_TITLE_KEYWORDS, MIN_OUTPUT_SIZE_RATIO


class Outcome(Enum):
    MODIFIED = "modified"
    SKIPPED = "skipped"
    FAILED = "failed"


@dataclass(frozen=True)
class FileResult:
    path: Path
    outcome: Outcome
    original_bytes: int | None = None
    new_bytes: int | None = None

    @property
    def saved_bytes(self) -> int:
        if self.original_bytes is None or self.new_bytes is None:
            return 0
        return max(self.original_bytes - self.new_bytes, 0)


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
    cleanup_leftovers: bool = True

