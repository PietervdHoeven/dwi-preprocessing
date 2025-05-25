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

    bash /scripts/preproc.sh "$base_dir" "$sub_id" "$ses_id" "$run_id" "$selected_t1"
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
    bvec_concat+=$(cat "$bvec_out")$'\n'
    bval_concat+=$(cat "$bval_out")$'\n'
done

# Final concatenation
final_dwi="${out_dir}/${sub_id}_${ses_id}_dwi_allruns.nii.gz"
final_bvec="${out_dir}/${sub_id}_${ses_id}_dwi_allruns.bvec"
final_bval="${out_dir}/${sub_id}_${ses_id}_dwi_allruns.bval"

num_runs=${#dwi_concat_list[@]}

if [[ $num_runs -eq 1 ]]; then
    echo "Only one run -> no concatenation needed."
    cp   "${dwi_concat_list[0]}" "$final_dwi"
    cp   "${bvec_out}"          "$final_bvec"   # variables still in scope
    cp   "${bval_out}"          "$final_bval"
else
    echo "Concatenating $num_runs runs with mrcat ..."
    mrcat "${dwi_concat_list[@]}" -axis 3 "$final_dwi"
    # merge b-vec / b-val rows
    echo "$bvec_concat" | paste -sd' ' - > "$final_bvec"
    echo "$bval_concat" | paste -sd' ' - > "$final_bval"
fi

echo "Done: concatenated DWI written to $final_dwi"

t1_out="${wrk_dir}/${sub_id}_${ses_id}_T1w_preproc.nii.gz"
final_t1="${out_dir}/${sub_id}_${ses_id}_T1w_preproc.nii.gz" 

echo "Copying clean T1w to out dir"
cp $t1_out $final_t1