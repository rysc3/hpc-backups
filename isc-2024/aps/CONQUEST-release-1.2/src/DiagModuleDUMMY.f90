!-*- mode: F90; mode: font-lock -*-
! -----------------------------------------------------------------------------
! $Id: DiagModule.dummy.f90,v 1.1 2002/06/25 10:52:10 drb Exp $
! -----------------------------------------------------------------------------
! DiagModule
! -----------------------------------------------------------------------------
! $Log: DiagModule.dummy.f90,v $
! Revision 1.1  2002/06/25 10:52:10  drb
! Added dummy DiagModule which contains necessary variables to compile Conquest
! without needing to link to Scalapack and BLACS
!
! 25/06/2002 drb
!
! Revision 1.1  2002/05/31 13:53:00  drb
! Added DiagModule to Conquest source tree
! 31/05/2002 dave
!
! -----------------------------------------------------------------------------

!******************************************************************************
!
! This is a DUMMY module designed to allow those without BLACS and SCALAPACK to
! compile and run Conquest for order N only
!
!******************************************************************************

!!****h* Conquest/DiagModule *
!!NAME
!! DiagModule - DUMMY module
!!PURPOSE
!! Allows people to run Conquest O(N) only without Scalapack or BLACS
!!USES
!! datatypes, GenComms
!!AUTHOR
!! D.R.Bowler
!!CREATION DATE
!! 24/06/2002 
!!MODIFICATION HISTORY
!!
!!***
module DiagModule

  use datatypes

  implicit none

  save 

  integer :: nkp
  real(double), allocatable, dimension(:)   :: wtk
  real(double), allocatable, dimension(:,:) :: kk
  ! 2007/08/13 dave changed this to be set by user
  real(double) :: kT
  ! Max number of iterations when searching for E_Fermi
  integer :: maxefermi

  ! Flags controlling Methfessel-Paxton approximation to step-function
  integer :: flag_smear_type, iMethfessel_Paxton

  ! Flags controlling the algorithms for finding Fermi Energy when using Methfessel-Paxton smearing
  real(double) :: gaussian_height, finess, NElec_less

  ! Maximum number of steps in the bracking search allowed before halfing incEf 
  ! (introduced guarantee success in the very rare case that Methfessel-Paxton 
  ! approximation may casue the bracket search algorithm to fail.)
  integer :: max_brkt_iterations

  logical :: diagon ! Do we diagonalise or use O(N) ?

contains

  ! -----------------------------------------------------------------------------
  ! Subroutine FindEvals **DUMMY**
  ! -----------------------------------------------------------------------------
  
  !!****f* DiagModule/FindEvals *
  !!
  !!NAME 
  !! FindEvals - returns an error and stops
  !!USAGE
  !! 
  !!PURPOSE
  !! Stop a user without SCALAPACK and BLACS trying to diagonalise
  !!INPUTS
  !! 
  !!USES
  !! datatypes
  !!AUTHOR
  !! D.R.Bowler
  !!CREATION DATE
  !! 24/06/2002
  !!MODIFICATION HISTORY
  !! 2012/08/29 L.Tong
  !! - updated the definition of electrons
  !!SOURCE
  !!
  subroutine FindEvals(electrons)

    use datatypes
    use GenComms, only: cq_abort

    implicit none

    ! Passed variables
    real(double), dimension(:) :: electrons

    write (*, *) 'ERROR: You are using the DUMMY diagonalisation module !'
    write (*, *) 'If you want to diagonalise, use the REAL DiagModule !'
    call cq_abort('FindEvals: No Scalapack or BLACS')

    return

  end subroutine FindEvals
  !!***

end module DiagModule
