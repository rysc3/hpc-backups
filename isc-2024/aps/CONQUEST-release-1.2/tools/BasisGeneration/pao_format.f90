! -*- mode: F90; mode: font-lock; column-number-mode: true; vc-back-end: CVS -*-
! ------------------------------------------------------------------------------
! $Id$
! ------------------------------------------------------------------------------
! Module pao_format
! ------------------------------------------------------------------------------
! Code area 11: basis functions
! ------------------------------------------------------------------------------

!!****h* Conquest/pao_format *
!!  NAME
!!   pao_format
!!  PURPOSE
!!   Creates a defined type to hold data for pseudo-atomic orbitals,
!!   and creates an array variable pao to hold this data.
!!     greatest_angmom: the largest angular momentum for which tables
!!       of PAO data are to be read (s = 0, p = 1, etc...).
!!     n_zeta_in_angmom: for angular momentum n_am the number of
!!       zeta values for which PAO data are to be read.
!!     length: number of entries in radial table
!!       of PAO data for ang. mom. n_am and zeta value n_zeta, counting
!!       the entry at the origin. (For example, if length = 11, then
!!       this means that 11 values will be read - one value at the origin
!      and 10 other values.)
!!     cutoff: radial distance of last value in table
!!       for ang. mom. n_am and zeta value n_zeta. (As a cross-check on
!!       your understanding, note that the radial interval between successive
!!       points in the table is thus cutoff/(length - 1).)
!!     table: the values of the PAO orbitals. For s-orbitals,
!!       these give directly the values of the orbitals. For p-orbitals,
!!       you have to multiply by x, y or z, depending on whether you
!!       want the px, py, or pz orbital. For d-orbitals, you multiply
!!       by yz, zx, xy, x^2 - y^2, or 3 z^2 - r^2. In all cases, you
!!       have to put in the appropriate normalisation constant.
!!  USES
!!   common, datatypes
!!  AUTHOR
!!   Mike Gillan
!!  CREATION DATE
!!   22/6/02
!!  MODIFICATION HISTORY
!!   9/8/02 Mike Gillan:
!!    defined type reorganised to allow easier dynamic memory allocation
!!   11:34, 24/09/2002 mjg & drb 
!!    Changed type uni_table to type table_and_occ to store occupation numbers for individual zetas
!!   14:02, 2003/12/19 dave & rc
!!    Moved occupation numbers outside table type
!!  SOURCE
module pao_format

  use datatypes

  implicit none

  save

  ! -------------------------------------------------------
  ! RCS ident string for object file id
  ! -------------------------------------------------------
  character(len=80), private :: RCSid = "$Id$"

  type table
     integer :: length
     real(double) :: cutoff
     real(double), pointer, dimension(:) :: table
     real(double), pointer, dimension(:) :: table2
     !RC real(double) :: occ
  end type table!_and_occ

  type angmom_pao
     integer :: n_zeta_in_angmom
     type(table), pointer, dimension(:) :: zeta
     real(double), pointer, dimension(:) :: occ
  end type angmom_pao

  type species_pao
     integer :: greatest_angmom
     integer :: count
     type(angmom_pao), pointer, dimension(:) :: angmom
  end type species_pao

  type(species_pao), allocatable, dimension(:) :: pao

  real(double) :: kcut, del_k

end module pao_format
!!***
