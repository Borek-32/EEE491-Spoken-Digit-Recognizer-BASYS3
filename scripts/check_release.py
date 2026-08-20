#!/usr/bin/env python3
"""Fail-closed public-release, privacy and checksum gate."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "SHA256SUMS"

REQUIRED_FILES = {
    ".gitattributes",
    ".gitignore",
    "CITATION.cff",
    "LICENSE",
    "NOTICE.md",
    "README.md",
    "REPRODUCIBILITY.md",
    "constraints/jc_homefab.xdc",
    "docs/report/EEE491_MFCC_Final_Report_2026-08-20.pdf",
    "hardware/homefab_mic_adc_pcb/kicad/evidence/bundle_validation.json",
    "scripts/build_jc_homefab.tcl",
    "scripts/expected_pinmap.tcl",
    "scripts/recreate_project.tcl",
    "scripts/run_release_checks.sh",
    "verification/matlab/run_safe_module_verifiers.m",
    "verification/run_testbenches.tcl",
}

FORBIDDEN_SUFFIXES = {
    ".backup",
    ".bit",
    ".dcp",
    ".docx",
    ".jou",
    ".log",
    ".pb",
    ".pid",
    ".rpx",
    ".str",
    ".wdb",
    ".xpr",
}

FORBIDDEN_DIRECTORY_PATTERNS = (
    re.compile(r"^\.Xil$", re.IGNORECASE),
    re.compile(r".*\.(?:cache|gen|hw|runs|sim)$", re.IGNORECASE),
    re.compile(r"^(?:__pycache__|accuracy_sessions|build_results)$", re.IGNORECASE),
)

PRIVATE_TEXT_PATTERNS = {
    "Linux home path": re.compile(r"/home/[^\s<]+"),
    "macOS user path": re.compile(r"/Users/[^\s<]+"),
    "Windows user path": re.compile(r"[A-Za-z]:\\\\Users\\\\", re.IGNORECASE),
    "temporary build path": re.compile(r"/tmp/[^\s<]+"),
    "Digilent USB by-id": re.compile(r"usb-Digilent", re.IGNORECASE),
    "Digilent target serial": re.compile(r"\b2101[0-9A-F]{8,}\b", re.IGNORECASE),
    "personal email": re.compile(
        r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE
    ),
    "fixed Vivado install path": re.compile(
        r"/(?:opt|tools)/[^\s]*/Vivado/bin|/AMD/[0-9.]+/Vivado/bin",
        re.IGNORECASE,
    ),
}


def repository_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if relative.parts and relative.parts[0] == ".git":
            continue
        if path.is_symlink():
            raise ValueError(f"symlink is not permitted: {relative.as_posix()}")
        if path.is_file() and path != MANIFEST:
            files.append(path)
    return sorted(files, key=lambda item: item.relative_to(ROOT).as_posix())


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def expected_manifest(files: list[Path]) -> str:
    return "".join(
        f"{sha256(path)}  ./{path.relative_to(ROOT).as_posix()}\n" for path in files
    )


def inspect_text(path: Path) -> list[str]:
    raw = path.read_bytes()
    if b"\x00" in raw[:8192]:
        return []
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return []
    findings = []
    for label, pattern in PRIVATE_TEXT_PATTERNS.items():
        match = pattern.search(text)
        if match:
            line = text.count("\n", 0, match.start()) + 1
            findings.append(f"{path.relative_to(ROOT).as_posix()}:{line}: {label}")
    return findings


def validate_git_clean_filters(files: list[Path]) -> list[str]:
    relative_paths = [path.relative_to(ROOT).as_posix() for path in files]
    stdin_paths = "".join(f"{path}\n" for path in relative_paths)

    def hash_objects(*extra_args: str) -> list[str]:
        try:
            result = subprocess.run(
                ["git", "hash-object", *extra_args, "--stdin-paths"],
                cwd=ROOT,
                input=stdin_paths,
                text=True,
                capture_output=True,
                check=False,
            )
        except OSError as exc:
            raise RuntimeError(f"cannot execute Git clean-filter check: {exc}") from exc
        if result.returncode != 0:
            detail = result.stderr.strip() or f"exit status {result.returncode}"
            raise RuntimeError(f"Git clean-filter check failed: {detail}")
        hashes = result.stdout.splitlines()
        if len(hashes) != len(relative_paths):
            raise RuntimeError(
                "Git clean-filter check returned "
                f"{len(hashes)} hashes for {len(relative_paths)} files"
            )
        return hashes

    try:
        raw_hashes = hash_objects("--no-filters")
        filtered_hashes = hash_objects()
    except RuntimeError as exc:
        return [str(exc)]

    return [
        f"Git clean filter would alter manifest candidate: {relative_paths[index]}"
        for index, (raw_hash, filtered_hash) in enumerate(
            zip(raw_hashes, filtered_hashes, strict=True)
        )
        if raw_hash != filtered_hash
    ]


def validate_content(files: list[Path]) -> list[str]:
    failures: list[str] = []
    relative_files = {path.relative_to(ROOT).as_posix() for path in files}
    missing = sorted(REQUIRED_FILES - relative_files)
    failures.extend(f"missing required file: {path}" for path in missing)

    for directory in sorted(
        (path for path in ROOT.rglob("*") if path.is_dir()),
        key=lambda item: item.relative_to(ROOT).as_posix(),
    ):
        relative = directory.relative_to(ROOT)
        if relative.parts and relative.parts[0] == ".git":
            continue
        if any(
            pattern.fullmatch(directory.name)
            for pattern in FORBIDDEN_DIRECTORY_PATTERNS
        ):
            failures.append(f"forbidden generated directory: {relative.as_posix()}/")

    for path in files:
        relative = path.relative_to(ROOT)
        if path.suffix.lower() in FORBIDDEN_SUFFIXES:
            failures.append(f"forbidden generated/private suffix: {relative.as_posix()}")
        # The gate necessarily contains the forbidden-pattern literals. Skip
        # only its own source while continuing to scan every other text file.
        if path.resolve() != Path(__file__).resolve():
            failures.extend(inspect_text(path))

    failures.extend(validate_git_clean_filters(files))

    counts = {
        "rtl": len(list((ROOT / "rtl").glob("*.vhd"))),
        "testbench": len(list((ROOT / "testbench").glob("*.vhd"))),
        "xci": len(list((ROOT / "ip").glob("*/*.xci"))),
        "coe": len(list((ROOT / "data").glob("*.coe"))),
    }
    expected_counts = {"rtl": 11, "testbench": 11, "xci": 20, "coe": 5}
    for label, expected in expected_counts.items():
        if counts[label] != expected:
            failures.append(f"{label} count is {counts[label]}, expected {expected}")

    xdc_files = sorted(
        path.relative_to(ROOT).as_posix() for path in (ROOT / "constraints").glob("*.xdc")
    )
    if xdc_files != ["constraints/jc_homefab.xdc"]:
        failures.append(f"canonical top-level XDC set is ambiguous: {xdc_files}")

    if (ROOT / "hardware/homefab_mic_adc_pcb/REPORT_ADDITION_QUEUE.md").exists():
        failures.append("internal report drafting queue is present")

    evidence_path = (
        ROOT
        / "hardware/homefab_mic_adc_pcb/kicad/evidence/bundle_validation.json"
    )
    if evidence_path.exists():
        try:
            evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
            if evidence.get("status") != "PASS_NET_ASSIGNMENT":
                failures.append("KiCad evidence does not retain PASS_NET_ASSIGNMENT")
            if evidence.get("pcb_drc", {}).get("violations") != 126:
                failures.append("KiCad DRC boundary is not the retained 126 findings")
            if evidence.get("schematic_erc", {}).get("violations") != 28:
                failures.append("KiCad ERC boundary is not the retained 28 findings")
        except (OSError, json.JSONDecodeError) as exc:
            failures.append(f"cannot parse KiCad bundle evidence: {exc}")

    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write-checksums",
        action="store_true",
        help="replace SHA256SUMS with the current sorted release manifest",
    )
    args = parser.parse_args()

    try:
        files = repository_files()
    except ValueError as exc:
        print(f"RELEASE_CHECK_FAIL: {exc}", file=sys.stderr)
        return 1

    failures = validate_content(files)
    manifest_text = expected_manifest(files)

    if args.write_checksums:
        if failures:
            for failure in failures:
                print(f"RELEASE_CHECK_FAIL: {failure}", file=sys.stderr)
            print("Refusing to write checksums until content checks pass.", file=sys.stderr)
            return 1
        MANIFEST.write_text(manifest_text, encoding="utf-8", newline="\n")
        print(f"CHECKSUMS_WRITTEN={len(files)}")
        return 0

    if not MANIFEST.exists():
        failures.append("SHA256SUMS is missing")
    elif MANIFEST.read_text(encoding="utf-8") != manifest_text:
        failures.append("SHA256SUMS is stale or does not exactly match release contents")

    if failures:
        for failure in failures:
            print(f"RELEASE_CHECK_FAIL: {failure}", file=sys.stderr)
        return 1

    total_bytes = sum(path.stat().st_size for path in files)
    largest = max(files, key=lambda path: path.stat().st_size)
    print("RELEASE_CHECK=PASS")
    print(f"FILE_COUNT={len(files)}")
    print(f"TOTAL_BYTES={total_bytes}")
    print(f"LARGEST_FILE={largest.relative_to(ROOT).as_posix()}")
    print(f"LARGEST_FILE_BYTES={largest.stat().st_size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
