apptainer exec --nv --cleanenv \
  -B /home/spieterman/dev/projects/dwi-preprocessing/data:/data \
  -B /home/spieterman/dev/projects/dwi-preprocessing/scripts:/scripts \
  /home/spieterman/dev/projects/dwi-preprocessing/containers/neurotools.img \
  bash -lc "/scripts/run_preproc.sh /data sub-OAS30001 ses-d4467"
