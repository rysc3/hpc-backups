#!/bin/bash
module load gcc
spack load netcdf-cxx4@4.3.1
spack load cdo@2.2.2

# Choose 1 for gpu implementation
# module load gcc/.12.3.0-gcc-11.2.0-nvptx
# module load gcc/.13.2.0-gcc-11.2.0-nvptx
module load nvhpc/22.5-gcc-11.2.0
