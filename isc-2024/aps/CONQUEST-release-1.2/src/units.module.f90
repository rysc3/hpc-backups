! -*- mode: F90; mode: font-lock -*-
! ------------------------------------------------------------------------------
! $Id$
! ------------------------------------------------------------------------------
! Module 
! ------------------------------------------------------------------------------
! Code area 8: General
! ------------------------------------------------------------------------------

!!****h* Conquest/units
!!  NAME
!!   units
!!  PURPOSE
!!   Holds units for converting energy, force etc
!!  AUTHOR
!!   D. R. Bowler
!!  CREATION DATE
!!   2006/11/03
!!  MODIFICATION HISTORY
!!   2018/03/07 10:29 dave
!!    Adding further useful constants and updating values to CODATA
!!   2022/06/09 15:35 dave
!!    Added Avogadro's constant (for unit conversion in DFT-D2)
!!  SOURCE
!!
module units

  use datatypes
  use numbers

  implicit none
  save

  ! Energy
  real(double), parameter :: HaToRy = two
  real(double), parameter :: HaToeV = 27.21138602_double      ! 2014 CODATA value
  real(double), parameter :: RyToeV = half*HaToeV
  real(double), parameter :: eVToJ  = 1.602176634e-19_double  ! Exact following 2018-2019 SI Redefinitions
  
  ! Distance
  real(double), parameter :: BohrToAng = 0.52917721067_double ! 2014 CODATA value
  real(double), parameter :: AngToBohr = one/BohrToAng

  ! Time
  real(double), parameter :: fac_fs2atu = 41.3413745758

  ! Number
  real(double), parameter :: AvogadroC = 6.02214076e23_double
  ! Pressure
  real(double), parameter :: HaBohr3ToGPa = &
    (HaToeV*eVToJ*1e21_double)/(BohrToAng**3)

  ! Memory (?!)
  real(double), parameter :: kB = 0.0009765625_double
  real(double), parameter :: MB = 9.5367431640625e-07_double
  real(double), parameter :: GB = 9.3132257461547852e-10_double
  

  integer, parameter :: har = 1
  integer, parameter :: ryd = 2
  integer, parameter :: ev = 3
  integer, parameter :: bohr = 1
  integer, parameter :: ang = 2
  integer, parameter :: kbytes = 1
  integer, parameter :: mbytes = 2
  integer, parameter :: gbytes = 3

  character(len=2), dimension(3) :: en_units = (/"Ha","Ry","eV"/)
  character(len=2), dimension(2) :: d_units = (/"a0","A "/)
  character(len=2), dimension(3) :: mem_units = (/"kB","MB","GB"/)

  integer :: dist_units, energy_units, m_units
  real(double) :: for_conv, en_conv, dist_conv, mem_conv

end module units
!!***
