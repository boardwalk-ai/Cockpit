"""Tests for the sample study-materials generator (offline, no API)."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

from scripts.generate_sample_materials import (
    SUPPORTED_SIZES,
    build_document,
    generate_files,
    parse_args,
    word_count,
)
from scripts.sample_materials_catalog import SUPPORTED_SUBJECTS

BACKEND_ROOT = Path(__file__).resolve().parents[1]
CLI = [sys.executable, "-m", "scripts.generate_sample_materials"]


def test_count_writes_exact_number_of_files(tmp_path: Path):
    paths = generate_files(5, "biology", "short", tmp_path)
    assert len(paths) == 5
    assert len(list(tmp_path.iterdir())) == 5
    assert all(p.is_file() for p in paths)


@pytest.mark.parametrize("subject", SUPPORTED_SUBJECTS)
def test_supported_subject_generation(subject: str, tmp_path: Path):
    paths = generate_files(2, subject, "short", tmp_path)
    assert len(paths) == 2
    for path in paths:
        text = path.read_text(encoding="utf-8")
        assert text.strip()
        assert subject in path.name
        assert subject.title() in text or subject in text.lower()


def test_short_medium_long_size_differences():
    short = build_document("history", "short", 0)[3]
    medium = build_document("history", "medium", 0)[3]
    long = build_document("history", "long", 0)[3]
    short_n, medium_n, long_n = word_count(short), word_count(medium), word_count(long)
    assert short_n < medium_n < long_n
    assert short_n >= 220
    assert medium_n >= 650
    assert long_n >= 1400


def test_generated_content_is_non_empty(tmp_path: Path):
    for path in generate_files(3, "economics", "medium", tmp_path):
        text = path.read_text(encoding="utf-8")
        assert text.strip()
        assert word_count(text) > 50
        assert "Key Terms" in text or "KEY TERMS" in text


def test_filenames_are_unique_and_readable(tmp_path: Path):
    paths = generate_files(8, "networking", "short", tmp_path)
    names = [p.name for p in paths]
    assert len(names) == len(set(names))
    for name in names:
        assert name.startswith("networking-")
        assert "-short-" in name
        stem = Path(name).stem
        assert stem.replace("-", "").replace("_", "").isalnum()
        assert " " not in name


def test_txt_and_md_generation(tmp_path: Path):
    paths = generate_files(4, "biology", "short", tmp_path)
    suffixes = {p.suffix for p in paths}
    assert ".md" in suffixes
    assert ".txt" in suffixes
    for path in paths:
        assert path.suffix in {".md", ".txt"}
        assert path.read_text(encoding="utf-8").strip()


def test_files_differ_meaningfully(tmp_path: Path):
    paths = generate_files(4, "biology", "medium", tmp_path)
    bodies = [p.read_text(encoding="utf-8") for p in paths]
    titles = [body.splitlines()[0] for body in bodies]
    assert len(set(titles)) == len(titles)
    assert len(set(bodies)) == len(bodies)
    # Pairwise overlap should stay well below identical-boilerplate levels.
    for i, left in enumerate(bodies):
        for right in bodies[i + 1 :]:
            left_words = set(left.lower().split())
            right_words = set(right.lower().split())
            overlap = len(left_words & right_words) / len(left_words | right_words)
            assert overlap < 0.85


def test_invalid_subject_and_count(tmp_path: Path):
    with pytest.raises(SystemExit):
        parse_args(
            ["--count", "1", "--subject", "chemistry", "--size", "short", "--out", str(tmp_path)]
        )
    with pytest.raises(SystemExit):
        parse_args(
            ["--count", "0", "--subject", "biology", "--size", "short", "--out", str(tmp_path)]
        )
    with pytest.raises(SystemExit):
        parse_args(
            ["--count", "2", "--subject", "biology", "--size", "huge", "--out", str(tmp_path)]
        )


def test_cli_creates_output_folder(tmp_path: Path):
    dest = tmp_path / "nested" / "out"
    result = subprocess.run(
        CLI + ["--count", "2", "--subject", "history", "--size", "short", "--out", str(dest)],
        cwd=BACKEND_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    files = list(dest.iterdir())
    assert len(files) == 2
    assert "Wrote 2" in result.stdout


def test_supported_sizes_constant():
    assert SUPPORTED_SIZES == ("short", "medium", "long")
