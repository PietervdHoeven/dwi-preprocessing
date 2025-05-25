apptainer exec --nv --cleanenv \
  -B ~/dwi-preprocessing/data:/data \
  -B ~/dwi-preprocessing/scripts:/scripts \
  ~/dwi-preprocessing/containers/neurotools.img \
  bash -lc "/scripts/run_preproc.sh /data sub-OAS30001 ses-d0757"
