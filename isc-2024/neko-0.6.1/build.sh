#!/bin/bash
source /jet/packages/oneapi/v2023.2.0/compiler/2023.2.1/env/vars.sh
source /jet/packages/oneapi/v2023.2.0//mpi/2021.10.0/env/vars.sh

export MPIFC=mpiifort 
export CC=mpiicc
export FC=$MPIFC

./regen.sh 
./configure --prefix=/jet/home/scherbar/neko-0.6.1
make
make install
