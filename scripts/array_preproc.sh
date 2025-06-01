#!/bin/bash
#SBATCH --job-name=preproc_dwi
#SBATCH --partition=gpu_a100
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=18
#SBATCH --mem=120G
#SBATCH --time=05:00:00
#SBATCH --output=logs/slurm_%A_%a.out
#SBATCH --error=logs/slurm_%A_%a.err

# set -euo pipefail

# 1) YOUR HOST PATHS
echo "Initialising path variables"
BASE_DIR=${HOME}/dwi-preprocessing/data
SCRIPTS_DIR=${HOME}/dwi-preprocessing/scripts
ORIG_CONTAINER=${HOME}/dwi-preprocessing/containers/neurotools.img
SES_LIST=${BASE_DIR}/sessions_a.txt

# 2) FIGURE OUT WHICH SESSION TO RUN
echo "parsing participant and session id"
LINE=$( sed -n "${SLURM_ARRAY_TASK_ID}p" "$SES_LIST" )
echo "$LINE"
P_ID=${LINE%%/*}
S_ID=${LINE##*/}
# sub-OAS30008/ses-d3363
# P_ID="sub-OAS30001"
# S_ID="ses-d2430"

echo "Patient id: $P_ID"
echo "Session id: $S_ID"

# 3) STAGE INTO LOCAL SCRATCH
echo "Setting up scratch dir"
mkdir -p "${TMPDIR}/oasis-data/${P_ID}/${S_ID}"
mkdir -p "${TMPDIR}/container"

# copy only that subject/session data
echo "Copying MRI data from ${BASE_DIR}/oasis-data/${P_ID}/${S_ID} to scratch ${TMPDIR}/oasis-data/${P_ID}/${S_ID}"
cp -r "${BASE_DIR}/oasis-data/${P_ID}/${S_ID}/." \
      "${TMPDIR}/oasis-data/${P_ID}/${S_ID}/"

# copy container image into scratch for faster startup
echo "Copying container from ${ORIG_CONTAINER}" to "${TMPDIR}/container/neurotools.img"
cp "${ORIG_CONTAINER}" "${TMPDIR}/container/neurotools.img"
LOCAL_CONTAINER="${TMPDIR}/container/neurotools.img"

# 4) RUN THE PIPELINE INSIDE THE Apptainer
echo "Starting preprocessing pipeline in container $LOCAL_CONTAINER "
apptainer exec --nv --cleanenv \
  -B "${TMPDIR}:/data" \
  -B "${SCRIPTS_DIR}:/scripts" \
  "${LOCAL_CONTAINER}" \
  bash -lc "/scripts/run_preproc.sh /data ${P_ID} ${S_ID}"

# 5) COPY BACK THE RESULTS
echo "Copying preprocessed dMRI from ${TMPDIR}/preproc/${P_ID}/${S_ID} to ${BASE_DIR}/preproc/${P_ID}/${S_ID} "
mkdir -p "${BASE_DIR}/preproc/${P_ID}/${S_ID}"
cp -r "${TMPDIR}/preproc/${P_ID}/${S_ID}/." \
      "${BASE_DIR}/preproc/${P_ID}/${S_ID}"

echo "COMPLETED CLEANING FOR $P_ID $S_ID"

# 6) CLEAN UP (optional)
rm -rf "${TMPDIR}/preproc/${P_ID}/${S_ID}/"
rm -rf "${TMPDIR}/work/${P_ID}/${S_ID}/"
rm -rf "${TMPDIR}/oasis-data/${P_ID}/${S_ID}/"
