#!/bin/bash

# Set compilers
FC=$(MPIFC)
F77=$(FC)

# Linking flags
LINKFLAGS= -L/usr/local/lib
ARFLAGS=

# Compilation flags
# NB for gcc10 you need to add -fallow-argument-mismatch
COMPFLAGS= -O3 $(XC_COMPFLAGS)
COMPFLAGS_F77= $(COMPFLAGS)

# Set BLAS and LAPACK libraries
# MacOS X
# BLAS= -lvecLibFort
# Intel MKL use the Intel tool
# Generic
# BLAS= -llapack -lblas

# Full library call; remove scalapack if using dummy diag module
LIBS= -qmkl=sequential -lmkl_scalapack_lp64 -lmkl_blacs_$(WHICHMPI)_lp64 $(XC_LIB)
# LIBS= $(FFT_LIB) $(XC_LIB) -lscalapack $(BLAS)

# LibXC compatibility (LibXC below) or Conquest XC library

# Conquest XC library
#XC_LIBRARY = CQ
#XC_LIB =
#XC_COMPFLAGS =

# LibXC compatibility
# Choose LibXC version: v4 (deprecated) or v5/6 (v5 and v6 have the same interface)
# XC_LIBRARY = LibXC_v4
XC_DIR = /jet/home/scherbar/aps/libxc-6.2.2-$(MPI)
XC_LIBRARY = LibXC_v5
XC_LIB = -L$(XC_DIR)/lib -lxcf90 -lxc
XC_COMPFLAGS = -I$(XC_DIR)/include

# Set FFT library
FFT_LIB=-lfftw3
FFT_OBJ=fft_fftw3.o

# Matrix multiplication kernel type
MULT_KERN = ompGemm
# Use dummy DiagModule or not
DIAG_DUMMY =