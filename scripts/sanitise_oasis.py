import os
import re
import shutil
import argparse
from pathlib import Path
from datetime import datetime

def get_correct_filename(subj, sess, modality, run=None):
    if run:
        return f"{subj}_{sess}_{run}_{modality}.nii.gz"
    else:
        return f"{subj}_{sess}_{modality}.nii.gz"

def log(message, log_file):
    print(message)
    with open(log_file, 'a') as f:
        f.write(message + '\n')

def rename_and_clean(root_dir, dry_run=False):
    root_path = Path(root_dir)
    log_file = f"cleanup_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"

    nii_files = list(root_path.rglob("*.nii.gz"))
    for file in nii_files:
        fname = file.name

        # Correct common typos before matching
        corrected_fname = fname.replace("sess-", "ses-")

        m = re.match(r"(sub-OAS3\d+)_ses-(d\d+)(?:_(run-\d+))?_(\w+)\.nii\.gz", corrected_fname)
        if not m:
            log(f"[WARN] Skipping unexpected file format: {file}", log_file)
            continue

        subj_id = m.group(1)
        sess_id = f"ses-{m.group(2)}"
        run = m.group(3)
        modality = m.group(4)

        # For DWI, ensure sidecars exist before moving
        if modality == 'dwi':
            base = file.with_name(file.name.replace('.nii.gz', ''))
            bval = file.parent / (base.name + '.bval')
            bvec = file.parent / (base.name + '.bvec')

            if not bval.exists() or not bvec.exists():
                log(f"[WARN] Removing incomplete DWI (missing bval or bvec): {file}", log_file)
                if not dry_run:
                    file.unlink(missing_ok=True)
                    (file.parent / (base.name + '.json')).unlink(missing_ok=True)
                    bval.unlink(missing_ok=True)
                    bvec.unlink(missing_ok=True)
                continue

        # Determine correct directory and filename
        modality_dir = 'anat' if modality == 'T1w' else modality
        correct_dir = root_path / subj_id / sess_id / modality_dir
        correct_dir.mkdir(parents=True, exist_ok=True)
        correct_fname = get_correct_filename(subj_id, sess_id, modality, run)
        correct_path = correct_dir / correct_fname

        # Move the NIfTI
        if file.resolve() != correct_path.resolve():
            log(f"[INFO] Moving {file} -> {correct_path}", log_file)
            if not dry_run:
                shutil.move(str(file), str(correct_path))

            # Prepare sidecar stems without .nii.gz
            old_stem = file.name.replace('.nii.gz', '')
            new_stem = correct_fname.replace('.nii.gz', '')
            extensions = ['.bval', '.bvec', '.json'] if modality == 'dwi' else ['.json']

            # Move sidecar files
            for ext in extensions:
                sidecar = file.parent / f"{old_stem}{ext}"
                new_sidecar = correct_path.parent / f"{new_stem}{ext}"
                if sidecar.exists():
                    log(f"[INFO] Moving sidecar {sidecar} -> {new_sidecar}", log_file)
                    if not dry_run:
                        shutil.move(str(sidecar), str(new_sidecar))

    # Clean up empty directories
    for dir in sorted(root_path.rglob("*"), reverse=True):
        if dir.is_dir() and not any(dir.iterdir()):
            log(f"[INFO] Removing empty directory: {dir}", log_file)
            if not dry_run:
                dir.rmdir()

    # Integrity check for DWI sidecars
    for dwi_file in root_path.rglob("*_dwi.nii.gz"):
        stem = dwi_file.name[:-7]
        parent = dwi_file.parent
        bval = parent / f"{stem}.bval"
        bvec = parent / f"{stem}.bvec"
        json = parent / f"{stem}.json"
        if not bval.exists() or not bvec.exists() or not json.exists():
            log(f"[ERROR] DWI missing sidecars: {dwi_file}", log_file)
            for missing in [bval, bvec, json]:
                if not missing.exists():
                    log(f"Missing: {missing.name}", log_file)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Clean up OASIS-3 dataset structure and filenames.")
    parser.add_argument("--root", type=str, required=True, help="Path to the root of the dataset")
    parser.add_argument("--dry-run", action="store_true", help="Run without making changes")
    args = parser.parse_args()

    rename_and_clean(args.root, dry_run=args.dry_run)
