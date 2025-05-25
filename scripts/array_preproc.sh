#!/bin/bash
#SBATCH --job-name=preproc_dwi
#SBATCH --partition=gpu_a100
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=18
#SBATCH --mem=120G
#SBATCH --time=00:02:30
#SBATCH --output=logs/slurm_%A_%a.out
#SBATCH --error=logs/slurm_%A_%a.err

set -euo pipefail

# 1) YOUR HOST PATHS
BASE_DIR=${HOME}/dwi-preprocessing/data
SCRIPTS_DIR=${HOME}/dwi-preprocessing/scripts
ORIG_CONTAINER=${HOME}/dwi-preprocessing/containers/neurotools.img
SES_LIST=${BASE_DIR}/ses_list.txt

# 2) FIGURE OUT WHICH SESSION TO RUN
LINE=$( sed -n "${SLURM_ARRAY_TASK_ID}q;d" "$SES_LIST" )
P_ID=${LINE%%/*}
S_ID=${LINE##*/}

# 3) STAGE INTO LOCAL SCRATCH
# Use SLURM tmpdir if available, otherwise node-local scratch
mkdir -p "${TMPDIR}/oasis-data/${P_ID}/${S_ID}"

# copy only that subject/session data
cp -r "${BASE_DIR}/oasis-data/${P_ID}/${S_ID}" \
      "${TMPDIR}/oasis-data/${P_ID}/${S_ID}"

# copy container image into scratch for faster startup
mkdir -p "${TMPDIR}/container"
cp "${ORIG_CONTAINER}" "${TMPDIR}/container/neurotools.img"
LOCAL_CONTAINER="${TMPDIR}/container/neurotools.img"

# 4) RUN THE PIPELINE INSIDE THE Apptainer
apptainer exec --nv --cleanenv \
  -B "${TMPDIR}:/data" \
  -B "${SCRIPTS_DIR}:/scripts" \
  "${LOCAL_CONTAINER}" \
  bash -lc "/scripts/run_preproc.sh /data ${P_ID} ${S_ID}"

# 5) COPY BACK THE RESULTS
mkdir -p "${BASE_DIR}/preproc/${P_ID}/${S_ID}"
cp -r "${TMPDIR}/preproc/${P_ID}/${S_ID}" \
      "${BASE_DIR}/preproc/${P_ID}/${S_ID}"

# 6) CLEAN UP (optional)
rm -rf "${TMPDIR}"
