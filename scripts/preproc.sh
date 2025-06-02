#!/usr/bin/env bash
###############################################################################
# Diffusion and anatomical MRI minimal preprocessing (CNN-ready, no reverse-PE)
# Requires: MRtrix3, FSL (eddy), ANTs
###############################################################################
set -euo pipefail


device="cuda"


# ─── 1. CLI ARGUMENTS ─────────────────────────────────────────────────────────

base_dir=$1            # e.g. ~/dwi-preprocessing/data
sub_id=$2              # e.g. sub-OAS30001
ses_id=$3              # e.g. ses-d0757
run_id=$4              # e.g. run-01


# cd dwi-preprocessing/scripts
# ./preproc_dwi_t1.sh ~/dwi-preprocessing/data sub-OAS30001 ses-d0757
# ./preproc_dwi_t1.sh "$base_dir" "$sub_id" "$ses_id" "$run_id" "$selected_t1"

# ─── 2. PATHS ────────────────────────────────────────────────────────────────

dwi_dir="${base_dir}/oasis-data/${sub_id}/${ses_id}/dwi"
anat_dir="${base_dir}/oasis-data/${sub_id}/${ses_id}/anat"
wrk_dir="${base_dir}/work/${sub_id}/${ses_id}"
out_dir="${base_dir}/preproc/${sub_id}/${ses_id}"
bet_in="${wrk_dir}/bet_in_${run_id}"
bet_out="${wrk_dir}/bet_out_${run_id}"
split_dir="${wrk_dir}/split_vols"

fp="${sub_id}_${ses_id}_${run_id}_"
fp_nr="${sub_id}_${ses_id}_"    # use for anat because we always take the first T1w image in the anat folder and we need to be able to reuse this if dwi has multiple runs

if [[ "$run_id" == "norun" ]]; then 
    fp="${fp_nr}"   # Use for dwi
else
    fp="${sub_id}_${ses_id}_${run_id}_"
fi

#rm -rf "${wrk_dir}" "${out_dir}"
mkdir -p "${wrk_dir}" "${out_dir}" "${bet_in}" "${bet_out}" "${split_dir}"

# ─── 3. INPUT FILES ──────────────────────────────────────────────────────────

# dwi
dwi_nii="${dwi_dir}/${fp}dwi.nii.gz"
bvec="${dwi_dir}/${fp}dwi.bvec"
bval="${dwi_dir}/${fp}dwi.bval"

# anat
t1_nii="${anat_dir}/$5"

# template
template_nii="$FSLDIR/data/standard/MNI152_T1_2mm_brain.nii.gz"

# ─── 4. INTERMEDIATE NAMES ──────────────────────────────────────────────────

# 4.1: DWI

# convert
dwi_mif="${wrk_dir}/${fp}dwi_ras.mif"
ras_bvec="${wrk_dir}/${fp}dwi_ras.bvec"
ras_bval="${wrk_dir}/${fp}dwi_ras.bval"

# denoise
dwi_den_mif="${wrk_dir}/${fp}dwi_den.mif"  
dwi_noise_mif="${wrk_dir}/${fp}dwi_noise.mif"
dwi_degibbs_mif="${wrk_dir}/${fp}dwi_degibbs.mif"

# bias-mask helper files (for dwibiascorrect)
b0_bias_nii="${wrk_dir}/${fp}b0_for_bias.nii.gz"
mask_bias_nii="${wrk_dir}/${fp}mask_for_bias.nii.gz"
mask_bias_dil_nii="${wrk_dir}/${fp}mask_for_bias_dil.nii.gz"

# bias corr
dwi_bias_mif="${wrk_dir}/${fp}dwi_biascorr.mif"
dwi_biasfield_mif="${wrk_dir}/${fp}dwi_biasfield.mif"
dwi_bias_nii="${wrk_dir}/${fp}dwi_biascorr.nii.gz"

# eddy + motion corr
dwi_emc_nii="${wrk_dir}/${fp}dwi_emc.nii.gz"
dwi_emc_tfs="${wrk_dir}/${fp}dwi_emc.ecclog"
emc_bvec="${wrk_dir}/${fp}dwi_emc.bvec"
dwi_emc_mif="${wrk_dir}/${fp}dwi_emc.mif"

# B0
mean_b0_mif="${wrk_dir}/${fp}mean_b0.mif"
mean_b0_nii="${wrk_dir}/${fp}mean_b0.nii.gz"

# 4.2 T1w

# convert
t1_mif="${wrk_dir}/${fp_nr}T1w.mif"
t1_ras_nii="${wrk_dir}/${fp_nr}T1w_ras.nii.gz"

# denoise
t1_den_nii="${wrk_dir}/${fp_nr}T1w_den.nii.gz"

# bias corr
t1_bias_nii="${wrk_dir}/${fp_nr}T1w_biascorr.nii.gz"

# 4.3 Registration

# vox_size = 2.0
t1_iso_nii="${wrk_dir}/${fp_nr}T1w_2mm.nii.gz"
b0_iso_nii="${wrk_dir}/${fp}b0_2mm.nii.gz"

# BET
b0_brain_nii="${bet_out}/${fp}b0_brain.nii.gz"
b0_mask_nii="${bet_out}/${fp}b0_mask.nii.gz"
t1_brain_nii="${bet_out}/${fp_nr}T1w_brain.nii.gz"
t1_mask_nii="${bet_out}/${fp_nr}T1w_mask.nii.gz"

# Convert
template_mif="${wrk_dir}/${fp_nr}MNI152_T1_2mm_brain_ras.mif"
template_ras_nii="${wrk_dir}/${fp_nr}MNI152_T1_2mm_brain_ras.nii.gz"

# Registration (T1w -> template)
rig_warp_prefix="${wrk_dir}/${fp_nr}T1w_to_template_"
rig_aff="${rig_warp_prefix}0GenericAffine.mat"
t1_clean_nii="${rig_warp_prefix}warped.nii.gz"


# Registration (b0 -> T1w)
syn_warp_prefix="${wrk_dir}/${fp}b0_to_T1w_"
syn_aff="${syn_warp_prefix}0GenericAffine.mat"
syn_warp="${syn_warp_prefix}1Warp.nii.gz"

# 4.4 Applying warp + affine

# dwi mask
b0_sdc_nii="${split_dir}/${fp}dwi_sdc_0.nii.gz"
b0_sdc_brain_nii="${bet_out}/${fp}b0_sdc_brain.nii.gz"
dwi_mask_nii="${bet_out}/${fp}b0_sdc_brain_bet.nii.gz"

# rotate bvecs
ras_syn_aff="${syn_warp_prefix}0GenericAffine_ras.mat"

# final
dwi_preproc_nii="${wrk_dir}/${fp}dwi_preproc.nii.gz"
t1_preproc_nii="${wrk_dir}/${fp_nr}T1w_preproc.nii.gz"
preproc_bvec="${wrk_dir}/${fp}dwi_preproc.bvec"
preproc_bval="${wrk_dir}/${fp}dwi_preproc.bval"

# ─── 5. DWI Pipeline ──────────────────────────────────────────────────────

# 5.1  Convert DWI to .mif (RAS+ orientation & gradients)
[[ -f "$dwi_mif" ]] || mrconvert "$dwi_nii" \
    -fslgrad "$bvec" "$bval" \
    -strides 1,2,3 "$dwi_mif" 

# 5.2 Orient bvecs from LAS+ to RAS+ (we assume all dwi data is in LAS+)
awk 'NR==1 { for(i=1;i<=NF;i++) $i = -$i } 1' \
    "$bvec" > "${ras_bvec}.tmp" \
&& mv "${ras_bvec}.tmp" "$ras_bvec"

# 5.2  Denoise & de‐Gibbs
[[ -f "$dwi_den_mif" ]]     || dwidenoise "$dwi_mif"     "$dwi_den_mif"   -noise "$dwi_noise_mif"
[[ -f "$dwi_degibbs_mif" ]] || mrdegibbs  "$dwi_den_mif" "$dwi_degibbs_mif"

# 5.3a  create a single-b0 image for masking
[[ -f "$b0_bias_nii" ]] || dwiextract "$dwi_degibbs_mif" - -bzero | mrconvert - "$b0_bias_nii"

# 5.3b  run HD-BET on that b0 to obtain a brain mask
[[ -f "$mask_bias_nii" ]] || hd-bet -i "$b0_bias_nii" -o "$mask_bias_nii" --save_bet_mask --no_bet_image -device $device

# 5.3c  dilate the mask by one voxel for safety
mask_bias_nii="${wrk_dir}/${fp}mask_for_bias_bet.nii.gz"
[[ -f "$mask_bias_dil_nii" ]] || maskfilter "$mask_bias_nii" dilate -npass 1 "$mask_bias_dil_nii"

# 5.3d  run N4 bias-field correction with the dilated mask
echo "starting bias correct"
[[ -f "$dwi_bias_mif" ]] || dwibiascorrect ants \
        "$dwi_degibbs_mif" "$dwi_bias_mif" \
        -mask "$mask_bias_dil_nii" \
        -scratch "${wrk_dir}/"
echo "passed bias correct"


# # 5.3  Bias‐field correction (N4 via ANTs)
# echo "starting bias correct"
# [[ -f "$dwi_bias_mif" ]] || dwibiascorrect ants "$dwi_degibbs_mif" "$dwi_bias_mif" -scratch "${wrk_dir}/"
# echo "passed bias correct"

# 5.4  Motion & eddy (legacy eddy_correct)
[[ -f "$dwi_bias_nii" ]]     || mrconvert     "$dwi_bias_mif" "$dwi_bias_nii"
[[ -f "$dwi_emc_nii" ]]      || eddy_correct  "$dwi_bias_nii" "$dwi_emc_nii"  0 trilinear
[[ -f "$emc_bvec" ]]         || bash "$FSLDIR/bin/fdt_rotate_bvecs" "$ras_bvec" "$emc_bvec" "$dwi_emc_tfs"
[[ -f "$dwi_emc_mif" ]]      || mrconvert     "$dwi_emc_nii" "$dwi_emc_mif" -fslgrad "$emc_bvec" "$bval"

# 5.5  Mean b0
[[ -f "$mean_b0_mif" ]] || dwiextract "$dwi_emc_mif" - -bzero | mrmath - mean "$mean_b0_mif" -axis 3
[[ -f "$mean_b0_nii" ]] || mrconvert "$mean_b0_mif" "$mean_b0_nii"

# ─── 6. T1w Pipeline ──────────────────────────────────────────────────────

# 6.1 Convert T1w to .mif (enforce RAS+ orientation)
[[ -f "$t1_mif" ]]      || mrconvert "$t1_nii" -strides 1,2,3 "$t1_mif"
[[ -f "$t1_ras_nii" ]]  || mrconvert "$t1_mif" -strides 1,2,3 "$t1_ras_nii"

# 6.2 Denoise (ANTs non-local means)
[[ -f "$t1_den_nii" ]] || DenoiseImage -d 3 -i "$t1_ras_nii" -o "$t1_den_nii"

# 6.3  Bias-field correction (N4)
[[ -f "$t1_bias_nii" ]] || N4BiasFieldCorrection -d 3 -i "$t1_den_nii" -o "$t1_bias_nii"

# ─── 7. HD-BET + Registration ──────────────────────────────────────────────────────

# 7.1 Resample b0 and T1w to 2.0 iso voxel size
[[ -f "$b0_iso_nii" ]] || mrgrid "$mean_b0_nii" regrid -voxel 2.0 "$b0_iso_nii"
[[ -f "$t1_iso_nii" ]] || mrgrid "$t1_bias_nii" regrid -voxel 2.0 "$t1_iso_nii"

# 7.2 Move denoised and bias-corrected T1w images into bet_in directory
[[ -f "${bet_in}/${fp}b0_brain.nii.gz" ]] || cp "$b0_iso_nii" "${bet_in}/${fp}b0_brain.nii.gz"
[[ -f "${bet_in}/${fp_nr}T1w_brain.nii.gz" ]] || cp "$t1_iso_nii" "${bet_in}/${fp_nr}T1w_brain.nii.gz"

# 7.4 run HD-BET on both DWI and T1w
[[ -f "$b0_brain_nii" ]] || hd-bet -i "$bet_in" -o "$bet_out" --save_bet_mask -device $device

# 7.3 Convert T1w template to .mif and back (enforece RAS+ orientation)
[[ -f "$template_mif" ]]      || mrconvert "$template_nii" -strides 1,2,3 "$template_mif"
[[ -f "$template_ras_nii" ]]  || mrconvert "$template_mif" -strides 1,2,3 "$template_ras_nii"

# 7.5 Registration T1w -> standard template (Rigid)
[[ -f "${rig_warp_prefix}warped.nii.gz" ]] || antsRegistration \
    --dimensionality 3 --float 0 \
    --output [${rig_warp_prefix},${rig_warp_prefix}warped.nii.gz] \
    --interpolation BSpline \
    --winsorize-image-intensities [0.001,0.99] \
    --transform Rigid[0.15] \
    --metric MI[${template_ras_nii},${t1_brain_nii},1,32,Regular,1] \
    --convergence [500x250x100,1e-6,10] \
    --shrink-factors 8x4x2 \
    --smoothing-sigmas 2x1x0vox \

# 7.6 Registration b0 -> T1w (Rigid + Affine + Warp)
[[ -f "${syn_warp_prefix}warped.nii.gz" ]] || antsRegistration \
    --dimensionality 3 --float 0 \
    --output [${syn_warp_prefix},${syn_warp_prefix}warped.nii.gz] \
    --interpolation BSpline \
    --winsorize-image-intensities [0.001,0.99] \
    --transform Rigid[0.15] \
    --metric MI[${t1_clean_nii},${b0_brain_nii},1,32,Regular,1] \
    --convergence [500x250x100,1e-6,10] \
    --shrink-factors 8x4x2 \
    --smoothing-sigmas 2x1x0vox \
    --transform Affine[0.25] \
    --metric MI[${t1_clean_nii},${b0_brain_nii},1,32,Regular,1] \
    --convergence [500x500x250x100,1e-6,10] \
    --shrink-factors 16x8x4x2 \
    --smoothing-sigmas 3x2x1x0vox \
    --transform SyN[0.1,1,0] \
    --metric MI[${t1_clean_nii},${b0_brain_nii},1,64,Regular,1] \
    --convergence [500x500x250x150,1e-6,10] \
    --shrink-factors 18x9x4x2 \
    --smoothing-sigmas 2x2x1x0vox

# ─── 8. Apply warp + affine ──────────────────────────────────────────────────────

# 8.1 split motion corrected dwi
nvol=$(mrinfo "$dwi_emc_nii" -size | awk '{print $4}')
if [[ ! -f "${split_dir}/${fp}dwi_0.nii.gz" ]]; then
    echo "Splitting 4-D DWI into 3-D volumes ..."
    for (( v=0; v<nvol; v++ )); do
        mrconvert "$dwi_emc_nii" "${split_dir}/${fp}dwi_${v}.nii.gz" -coord 3 $v
    done
fi

# 8.2 apply warp + affine to each 3D vol
if [[ ! -f "${split_dir}/${fp}dwi_0_sdc.nii.gz" ]]; then
    echo "Applying affine + warp to each volume ..."
    for (( v=0; v<nvol; v++ )); do
        in_vol="${split_dir}/${fp}dwi_${v}.nii.gz"
        out_vol="${split_dir}/${fp}dwi_sdc_${v}.nii.gz"
        antsApplyTransforms \
            -d 3 \
            -i "$in_vol" \
            -r "$t1_clean_nii" \
            -o "$out_vol" \
            -n Linear \
            -t "$syn_warp" \
            -t "$syn_aff"
    done
fi

# 8.3 hd-bet the b0 (we assume the first vol is always the b0)
[[ -f "$b0_sdc_brain_nii" ]] || hd-bet -i "$b0_sdc_nii" -o "$b0_sdc_brain_nii" --save_bet_mask -device $device

# 8.4 Apply mask to each dwi volume
if [[ ! -f "${split_dir}/${fp}dwi_brain_0.nii.gz" ]]; then
    echo "Applying mask to each corrected vol ..."
    for (( v=0; v<nvol; v++ )); do
        in_vol="${split_dir}/${fp}dwi_sdc_${v}.nii.gz"
        out_vol="${split_dir}/${fp}dwi_brain_${v}.nii.gz"
        mrcalc "$in_vol" "$dwi_mask_nii" -mult "$out_vol"
    done
fi

# 8.4 Combine all dwi vols into one 4D object
if [[ ! -f "$dwi_preproc_nii" ]]; then
    echo "Concatenating $nvol volumes into 4-D DWI ..."
    vol_list=$(printf "${split_dir}/${fp}dwi_brain_%d.nii.gz " $(seq 0 $((nvol-1))))
    mrcat $vol_list -axis 3 "$dwi_preproc_nii"
fi

# 8.5 rotate bvecs with syn registration affine (care! syn_aff is in LPS and bvec in RAS. See python script for logic)
/usr/bin/python scripts/rotate_bvecs.py "${syn_warp_prefix}0GenericAffine.mat" "${emc_bvec}" "${bval}" "${wrk_dir}/${fp}dwi_preproc.bvec"
cp "$bval" "$preproc_bval"

# 8.6 move anat data to out_dir
cp "$t1_clean_nii" "$t1_preproc_nii"

