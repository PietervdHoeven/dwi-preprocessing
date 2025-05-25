#!/usr/bin/env python3
"""
Rotate diffusion gradient vectors by the ANTs affine (LPS → RAS) for an entire DWI series.

Usage:
    syn_rot_bvec.py <affine.mat> <in.bvec> <out.bvec>

Inputs:
  affine.mat   : path to ITK .mat file from antsRegistration (0GenericAffine.mat)
  in.bvec      : path to input FSL-style .bvec file (3xN)
  in.bval
  out.bvec     : path where rotated .bvec will be written

This script:
  1. Loads the 3x3 linear block from the ITK .mat (supports float or double precision)
  2. Converts it from LPS (ITK) → RAS (FSL/MRtrix) via D·R·D, D=diag(-1,-1,1)
  3. Loads bvals/bvecs, builds a gradient_table
  4. Applies the same 3x3 rotation to each b-vector using DIPY's reorient_bvecs
  5. Writes out a new FSL-style .bvec (3 rows x N columns)
"""
import sys
import numpy as np
from scipy.io import loadmat
from dipy.io import read_bvals_bvecs
from dipy.core.gradients import reorient_bvecs, gradient_table

def main():
    aff_mat_path = sys.argv[1]
    bvec_in_path = sys.argv[2]
    bval_in_path = sys.argv[3]
    bvec_out_path = sys.argv[4]

    # 1) load the ITK .mat (could be double or float key)
    mat_dict = loadmat(aff_mat_path)
    # find the key containing AffineTransform_*_3_3
    aff_key = next((k for k in mat_dict if 'AffineTransform' in k and mat_dict[k].size >= 9), None)
    if aff_key is None:
        raise KeyError(f'No AffineTransform_double_3_3 or similar found in {aff_mat_path}')
    arr = np.array(mat_dict[aff_key]).flatten()
    R_lps = arr[:9].reshape((3,3))

    # 2) convert from LPS → RAS via D·R·D where D = diag(-1,-1,1)
    D = np.diag([-1, -1, 1])
    R_ras = D @ R_lps @ D

    # 3) load bvals/bvecs
    bvals, bvecs = read_bvals_bvecs(bval_in_path, bvec_in_path)
    gtab = gradient_table(bvals, bvecs, b0_threshold=1)
    non_b0_indices = np.where(~gtab.b0s_mask)[0]
    num_non_b0 = non_b0_indices.shape[0]

    # 4) build an array of identical affines for each volume
    affines = np.repeat(R_ras[np.newaxis, :, :], num_non_b0, axis=0)

    # apply rotation to all b-vectors
    gtab_new = reorient_bvecs(gtab, affines)
    print(gtab_new)

    # 5) save rotated b-vectors in FSL format (3 rows x N columns)
    np.savetxt(bvec_out_path, gtab_new.bvecs.T, fmt='%.8f')
    print(f"Rotated b-vectors written to {bvec_out_path}")

if __name__ == '__main__':
    main()