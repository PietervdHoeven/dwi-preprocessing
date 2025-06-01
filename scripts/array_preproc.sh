#!/bin/bash
#SBATCH --job-name=preproc_dwi
#SBATCH --partition=gpu_a100
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=18
#SBATCH --mem=120G
#SBATCH --time=05:00:00
#SBATCH --output=logs/slurm_%A_%a.out
#SBATCH --error=logs/slurm_%A_%a.err

# --------------- 0) SAFEGUARD SCRATCH CLEANUP ---------------
trap 'echo "[$(date)] Cleaning TMPDIR for $P_ID/$S_ID"
     rm -rf "${TMPDIR}/oasis-data/${P_ID}/${S_ID}"
     rm -rf "${TMPDIR}/preproc/${P_ID}/${S_ID}"
     rm -rf "${TMPDIR}/work/${P_ID}/${S_ID}"
' EXIT

# --------------- 1) HOST PATHS ---------------
echo "[$(date)] Initialising path variables"
BASE_DIR="${HOME}/dwi-preprocessing/data"
SCRIPTS_DIR="${HOME}/dwi-preprocessing/scripts"
CONTAINER="${HOME}/dwi-preprocessing/containers/neurotools.img"
SES_LIST="${BASE_DIR}/sessions_a.txt"

# --------------- 2) WHICH SESSION ---------------
echo "[$(date)] Parsing participant and session ID"
echo "[$(date)] SLURM_ARRAY_TASK_ID: ${SLURM_ARRAY_TASK_ID}"
echo "[$(date)] Session list: ${SES_LIST}"
LINE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SES_LIST}")
echo $"[$(date)] Processing line: $LINE"
P_ID=${LINE%%/*}   # e.g. sub-OAS30008
S_ID=${LINE##*/}   # e.g. ses-d3363

echo "[$(date)] Patient id: $P_ID"
echo "[$(date)] Session id: $S_ID"

# --------------- 3) STAGE DATA INTO SCRATCH ---------------
echo "[$(date)] Setting up scratch dir"
mkdir -p "${TMPDIR}/oasis-data/${P_ID}/${S_ID}"

echo "[$(date)] Copying raw MRI data to scratch"
cp -r "${BASE_DIR}/oasis-data/${P_ID}/${S_ID}/." \
      "${TMPDIR}/oasis-data/${P_ID}/${S_ID}/"

# No need to copy the container; just reference the shared SIF:
LOCAL_CONTAINER="${CONTAINER}"

# --------------- 4) RUN PIPELINE INSIDE Apptainer ---------------
echo "[$(date)] Starting preprocessing pipeline in container $LOCAL_CONTAINER"
apptainer exec --nv --cleanenv \
  -B "${TMPDIR}:/data" \
  -B "${SCRIPTS_DIR}:/scripts" \
  "${LOCAL_CONTAINER}" \
  bash -lc "/scripts/run_preproc.sh /data ${P_ID} ${S_ID}"

# --------------- 5) COPY BACK RESULTS ---------------
echo "[$(date)] Copying results back to home"
mkdir -p "${BASE_DIR}/preproc/${P_ID}/${S_ID}"
cp -r "${TMPDIR}/preproc/${P_ID}/${S_ID}/." \
      "${BASE_DIR}/preproc/${P_ID}/${S_ID}"

echo "[$(date)] COMPLETED CLEANING FOR $P_ID $S_ID"
