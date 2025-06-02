#!/usr/bin/env bash
###############################################################################
# DWI orchestrator: process all DWI runs and concatenate results
# Usage: ./run_preproc_concat.sh <base_dir> <sub_id> <ses_id>
###############################################################################

set -euo pipefail


base_dir=$1
sub_id=$2
ses_id=$3

dwi_dir="${base_dir}/oasis-data/${sub_id}/${ses_id}/dwi"
anat_dir="${base_dir}/oasis-data/${sub_id}/${ses_id}/anat"
wrk_dir="${base_dir}/work/${sub_id}/${ses_id}"
out_dir="${base_dir}/preproc/${sub_id}/${ses_id}"
mkdir -p "$out_dir" "$wrk_dir"

# Select T1w reference
t1w_files=("$anat_dir"/*_T1w.nii.gz)
if [[ ${#t1w_files[@]} -eq 0 ]]; then
    echo "No T1w image found for ${sub_id} ${ses_id}"
    exit 1
fi
selected_t1=$(basename "${t1w_files[0]}")
echo "Using T1w: ${selected_t1}"

# Process all DWI runs
echo "Current dwi dir: $dwi_dir"
mapfile -t dwi_files < <(find "$dwi_dir" -type f -name "*_dwi.nii.gz")
dwi_concat_list=()
bvec_concat=""
bval_concat=""

echo "$dwi_files"
for dwi_file in "${dwi_files[@]}"; do
    base=$(basename "$dwi_file" _dwi.nii.gz)

    # Extract 'run-xx' if present, else default to 'norun'
    if [[ "$base" =~ (_run-[^_]+) ]]; then
        run_id="${BASH_REMATCH[1]#_}"  # Remove leading underscore
    else
        run_id="norun"
    fi
    echo "Processing run: $run_id"

    bash ~/dev/projects/dwi-preprocessing/scripts/preproc.sh "$base_dir" "$sub_id" "$ses_id" "$run_id" "$selected_t1"
    echo "$base_dir" "$sub_id" "$ses_id" "$run_id" "$selected_t1"

    # Store preprocessed output paths
    if [[ "$run_id" == "norun" ]]; then 
        dwi_out="${wrk_dir}/${sub_id}_${ses_id}_dwi_preproc.nii.gz"
        bvec_out="${wrk_dir}/${sub_id}_${ses_id}_dwi_preproc.bvec"
        bval_out="${wrk_dir}/${sub_id}_${ses_id}_dwi_preproc.bval"
    else
        dwi_out="${wrk_dir}/${sub_id}_${ses_id}_${run_id}_dwi_preproc.nii.gz"
        bvec_out="${wrk_dir}/${sub_id}_${ses_id}_${run_id}_dwi_preproc.bvec"
        bval_out="${wrk_dir}/${sub_id}_${ses_id}_${run_id}_dwi_preproc.bval"
    fi


    dwi_concat_list+=("$dwi_out")
    bvec_files+=("$bvec_out")
    bval_files+=("$bval_out")
done

final_dwi="${out_dir}/${sub_id}_${ses_id}_dwi_allruns.nii.gz"
final_bvec="${out_dir}/${sub_id}_${ses_id}_dwi_allruns.bvec"
final_bval="${out_dir}/${sub_id}_${ses_id}_dwi_allruns.bval"

if (( ${#dwi_concat_list[@]} == 1 )); then
    cp "${dwi_concat_list[0]}" "$final_dwi"
    cp "${bvec_files[0]}"      "$final_bvec"
    cp "${bval_files[0]}"      "$final_bval"
else
    mrcat "${dwi_concat_list[@]}" -axis 3 "$final_dwi"
    paste -d' ' "${bvec_files[@]}" > "$final_bvec"
    paste -d' ' "${bval_files[@]}" > "$final_bval"
fi

echo "Done: concatenated DWI written to $final_dwi"

t1_out="${wrk_dir}/${sub_id}_${ses_id}_T1w_preproc.nii.gz"
final_t1="${out_dir}/${sub_id}_${ses_id}_T1w_preproc.nii.gz" 

echo "Copying clean T1w to out dir"
cp $t1_out $final_t1