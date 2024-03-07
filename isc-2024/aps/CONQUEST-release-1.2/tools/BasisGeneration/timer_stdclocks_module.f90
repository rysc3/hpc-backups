! -*- mode: F90; mode: font-lock; column-number-mode: true; vc-back-end: CVS -*-
! ------------------------------------------------------------------------------
! $Id:$
! ------------------------------------------------------------------------------
! Module timer_stdclocks_module
! ------------------------------------------------------------------------------
! Code area 9: General
! ------------------------------------------------------------------------------

!!****h* Conquest/timer_stdclocks_module *
!!  NAME
!!    timer_stdclocks_module
!!  USES
!!
!!  PURPOSE
!!    Standard clocks (declarations of timers) for Conquest
!!    These are (should) be used for total timing
!!    Local timers can be declared (timer_module) locally
!!    in any routine
!!  AUTHOR
!!    A.S.Torralba
!!  CREATION DATE
!!    15/05/2008
!!  MODIFICATION HISTORY
!!    2012/09/05 L.Tong
!!    - Added timer for matrix multiplication
!!    2014/09/12 L.Truflandier
!!    - Added timer for area 9 (?) and tmr_std_exx
!!  TODO
!!
!!  SOURCE
!!
module timer_stdclocks_module

  use timer_module

  implicit none

  ! RCS tag for object file identification
  character(len=80), save, private :: RCSid = "$Id:$"

  type(cq_timer),save :: tmr_std_initialisation   ! Code area: 1
  type(cq_timer),save :: tmr_std_matrices         ! Code area: 2
  type(cq_timer),save :: tmr_std_hmatrix          ! Code area: 3
  type(cq_timer),save :: tmr_std_smatrix          ! Code area: 3
  type(cq_timer),save :: tmr_std_densitymat       ! Code area: 4
  type(cq_timer),save :: tmr_std_chargescf        ! Code area: 5
  type(cq_timer),save :: tmr_std_eminimisation    ! Code area: 6
  type(cq_timer),save :: tmr_std_moveatoms        ! Code area: 7
  type(cq_timer),save :: tmr_std_indexing         ! Code area: 8
  type(cq_timer),save :: tmr_std_general          ! Code area: 9
  type(cq_timer),save :: tmr_std_pseudopot        ! Code area: 10
  type(cq_timer),save :: tmr_std_basis            ! Code area: 11
  type(cq_timer),save :: tmr_std_integration      ! Code area: 12
  type(cq_timer),save :: tmr_std_allocation       ! ? **<lat>**
  type(cq_timer),save :: tmr_std_matmult          ! ? **<lat>**
  type(cq_timer),save :: tmr_std_exx              

contains

! ------------------------------------------------------------------------------
! Subroutine print_time_report
! ------------------------------------------------------------------------------

!!****f* H_matrix_module/print_time_report *
!!
!!  NAME
!!   print_time_report
!!  USAGE
!!
!!  PURPOSE
!!   Prints a report on the total times accumulated in the standard timers
!!  INPUTS
!!
!!
!!  USES
!!
!!  AUTHOR
!!   A.S.Torralba
!!  CREATION DATE
!!   15/05/08
!!  MODIFICATION HISTORY
!!   2012/09/05 L.Tong
!!   - Added timer for matrix multiplication
!!   2012/10/03 L.A. Truflandier
!!   - Added printing for general and exx
!!  SOURCE
!!
  subroutine print_time_report(io_lun)

    implicit none

    integer, optional :: io_lun

    call print_timer(tmr_std_initialisation,"area  1 - Initialisation",         io_lun)
    call print_timer(tmr_std_matrices,      "area  2 - Matrices",               io_lun)
    call print_timer(tmr_std_hmatrix,       "area  3 - A - Operators: H Matrix",io_lun)
    call print_timer(tmr_std_smatrix,       "area  3 - B - Operators: S Matrix",io_lun)
    call print_timer(tmr_std_densitymat,    "area  4 - Density matrix",         io_lun)
    call print_timer(tmr_std_chargescf,     "area  5 - Charge density and SCF", io_lun)
    call print_timer(tmr_std_eminimisation, "area  6 - Energy minimisation",    io_lun)
    call print_timer(tmr_std_moveatoms,     "area  7 - Atom movements",         io_lun)
    call print_timer(tmr_std_indexing,      "area  8 - Indexing and grids",     io_lun)
    call print_timer(tmr_std_general,       "area  9 - General",                io_lun)
    call print_timer(tmr_std_pseudopot,     "area 10 - Pseudopotentials",       io_lun)
    call print_timer(tmr_std_basis,         "area 11 - Basis functions and operations",io_lun)
    call print_timer(tmr_std_integration,   "area 12 - Integration",            io_lun)
    call print_timer(tmr_std_exx,           "area 13 - Exact exchange",         io_lun)
    call print_timer(tmr_std_allocation,    "   allocating memory",             io_lun)
    call print_timer(tmr_std_matmult,       "   matrix multiplication",         io_lun)

    return
  end subroutine print_time_report
!!***

end module timer_stdclocks_module


