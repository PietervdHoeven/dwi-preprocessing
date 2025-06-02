#!/usr/bin/env python3
"""
Check required OASIS-3 files for each subject/session.

Usage:
    ./check_oasis_integrity.py list.txt /data/oasis3_root
"""

import argparse
from pathlib import Path
import sys

REQUIRED_SUFFIXES = [
    "_dwi_allruns.bval",
    "_dwi_allruns.bvec",
    "_dwi_allruns.nii.gz",
    "_T1w_preproc.nii.gz",
]


def files_missing(sub: str, ses: str, base: Path) -> list[str]:
    """Return a list of missing files for a single subject/session."""
    folder = base / sub / ses
    prefix = f"{sub}_{ses}"
    missing = [
        suf
        for suf in REQUIRED_SUFFIXES
        if not (folder / f"{prefix}{suf}").is_file()
    ]
    return missing


def main():
    parser = argparse.ArgumentParser(
        description="Verify presence of required OASIS-3 derivative files."
    )
    parser.add_argument("list_file", help="TXT file with sub-XXX/ses-XXX rows")
    parser.add_argument("root_dir", help="Directory containing all subject folders")
    args = parser.parse_args()

    root_dir = Path(args.root_dir).resolve()
    if not root_dir.is_dir():
        sys.exit(f"Root directory not found: {root_dir}")

    incomplete = {}
    with open(args.list_file) as f:
        for line in f:
            entry = line.strip()
            if not entry or entry.startswith("#"):
                continue
            try:
                sub, ses = entry.split("/", 1)
            except ValueError:
                print(f"Skipping malformed line: {entry}", file=sys.stderr)
                continue

            missing = files_missing(sub, ses, root_dir)
            if missing:
                incomplete[entry] = missing

    if not incomplete:
        print("All entries complete.")
        return

    print("Incomplete entries:")
    for entry, miss in sorted(incomplete.items()):
        joined = ", ".join(miss)
        print(f"  {entry}: missing {joined}")


if __name__ == "__main__":
    main()
