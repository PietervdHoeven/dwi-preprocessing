bvec_1="/home/spieterman/dev/projects/dwi-preprocessing/data/oasis-data/sub-OAS30001/ses-d4467/dwi/sub-OAS30001_ses-d4467_run-01_dwi.bvec"
bvec_2="/home/spieterman/dev/projects/dwi-preprocessing/data/oasis-data/sub-OAS30001/ses-d4467/dwi/sub-OAS30001_ses-d4467_run-02_dwi.bvec"
bvec_3="/home/spieterman/dev/projects/dwi-preprocessing/data/oasis-data/sub-OAS30001/ses-d4467/dwi/sub-OAS30001_ses-d4467_run-03_dwi.bvec"

bvec_files=("$bvec_1" "$bvec_2" "$bvec_3")

bvec_concat="test.bvec"

paste -d' ' "${bvec_files[@]}" > "$bvec_concat"