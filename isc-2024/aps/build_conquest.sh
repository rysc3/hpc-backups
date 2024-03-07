########### Return Home ###############
cd
cd aps #Route to my test directory



########## Building libxc ##############

# Load intel compilers and mpi modules
# Intel Modules         :  intel/20.4  |  intel/2021.3.0
# Intel_MPI Modules     :  intelmpi/20.4  |  intelmpi/2021.3.0-intel2021.3.0
# OpenMPI Modules       :  openmpi/3.1.6-intel20.4  |  openmpi/4.0.2-intel20.4  |  openmpi/4.0.5-gcc10.2.0  |  openmpi/4.1.1-gcc8.3.1  |  openmpi/4.0.5-nvhpc22.9  | more gcc8,gcc10,clang and nvhpc modules available
# Phdf5 Modules         :  phdf5/1.10.7-openmpi4.0.2-intel20.4  |  phdf5/1.12.1-intelmpi20.4-intel20.4  |  phdf5/1.10.7-openmpi4.0.5-gcc10.2.0  |  phdf5/1.12.1-mvapich2-2.3.5-gcc8.3.1

#Load FFTW, MKL, SCALAPACK, Intel and MPI comilers and modules
module load fftw/3.3.8 mkl/2020.4.304 scalapack/2.1.0 intel/20.4 openmpi/4.0.2-intel20.4

# OLD
#cd libxc-6.2.2
#./configure  CC=mpicc FC=mpif90 --prefix=/jet/home/scherbar/aps/CONQUEST-release-1.2
#make
#make install

# NEW


########### Return Home ############### 
cd
cd aps #Route to my test directory




############# Building CONQUEST  #################
cd CONQUEST
# Load intel compilers and mpi modules
module load fftw/3.3.8 mkl/2020.4.304 scalapack/2.1.0 intel/20.4 openmpi/4.0.2-intel20.4
cd CONQUEST-release/src

## Edit system.make file
    # Edit system.make for XC lib and include paths, and FFT & blas libraries.
        
        # uncomment generic BLAS and add MKL and scalapack libraries
        #BLAS = -L$(MKLROOT)/lib/intel64 -lmkl_intel_lp64 -lmkl_sequential -lmkl_core -lpthread -lm -lscalapack

        # Change LINKFLAGS to lmod library variable
        # LINKFLAGS=$LIBRARY_PATH

        # -- XC_LIBRARY = LibXC_v6-- # v6 doesn't exist within src of CONQUEST
        # XC_LIBRARY = LibXC_v5
        # -- XC_COMPFLAGS= -I/jet/home/scherbar/aps/libxc-6.2.2 -- # cant find thing here
        # XC_COMPFLAGS=$INCLUDE # cant find mpif90
    
    # Add correct flag (-qopenmp for Intel) for OpenMP to compile and link arguements
        #COMPFLAGS= -O3 $(SC_COMPFLAGS) -qopenmp

    # Set MULT_KERN to ompGemm
        # MULT_KERN = ompGemm

make

############# Clean Up CONQUEST ################
module unload fftw/3.3.8 mkl/2020.4.304 scalapack/2.1.0 intel/20.4 openmpi/4.0.2-intel20.4