! -*- mode: F90; mode: font-lock -*-
! ------------------------------------------------------------------------------
! $Id$
! ------------------------------------------------------------------------------
! Module atomic_density
! ------------------------------------------------------------------------------
! Code area 5: Self consistency
! ------------------------------------------------------------------------------

!!****h* Conquest/atomic_density *
!!  NAME
!!   atomic_density
!!  PURPOSE
!!   Holds data structures for storing atomic densities and routines for reading 
!!   or building these densities
!!  USES
!!
!!  AUTHOR
!!   D.R.Bowler and M.J.Gillan
!!  CREATION DATE
!!   24/09/2002 
!!  MODIFICATION HISTORY
!!   12:15, 25/09/2002 mjg & drb 
!!    Added rcut_dens - maximum atomic density table cutoff
!!   17:25, 2003/03/18 dave
!!    Added second derivative to radial density type and splining routine
!!   15:32, 08/04/2003 drb 
!!    Added debugging statements
!!   17:28, 2003/06/10 tm
!!    spline problem fixed
!!   2008/02/04 08:21 dave
!!    Changed for output to file not stdout
!!   2008/05/23 ast
!!    Added timers
!!   2014/09/15 18:30 lat
!!    fixed call start/stop_timer to timer_module (not timer_stdlocks_module !)
!!   2015/11/09 08:31 dave with TM and NW from Mizuho
!!    Added new variables to radial_density type for neutral atom potential
!!   2016/01/07 13:41 dave
!!    Added calculation of delta for atomic density (makes more sense here than in make_neutral_atom !)
!!  SOURCE
!!
module atomic_density

  use datatypes
  use global_module,          only: io_lun
  use timer_stdclocks_module, only: tmr_std_allocation, tmr_std_chargescf
  use timer_module,           only: start_timer, stop_timer


  implicit none
  save
  
  type radial_density
     integer :: length
     real(double) :: cutoff
     real(double), pointer, dimension(:) :: table
     real(double), pointer, dimension(:) :: d2_table

     ! for Neutral atom potential
     real(double) :: delta
     integer :: k_length
     real(double) :: k_delta
     real(double), pointer, dimension(:) :: k_table
  end type radial_density

  type(radial_density), allocatable, dimension(:) :: atomic_density_table

  ! Maximum cutoff atomic on charge density tables
  real(double), allocatable, dimension(:) :: rcut_dens

!!***

contains

! -----------------------------------------------------------
! Subroutine make_atomic_density_from_paos
! -----------------------------------------------------------

!!****f* atomic_density/make_atomic_density_from_paos *
!!
!!  NAME 
!!   make_atomic_density_from_paos
!!  USAGE
!! 
!!  PURPOSE
!!   Makes atomic densities from PAOs read in 
!!  INPUTS
!! 
!! 
!!  USES
!!   datatypes, GenComms, global_module, numbers, pao_format
!!  AUTHOR
!!   M.J.Gillan and D.R.Bowler
!!  CREATION DATE
!!   Summer 2002
!!  MODIFICATION HISTORY
!!   11:53, 24/09/2002 mjg & drb 
!!    Incorporated into atomic_density
!!   12:35, 25/09/2002 mjg & drb 
!!    Added rcut_dens to keep track of maximum cutoff on atomic charge density
!!   13:52, 29/07/2003 drb 
!!    Changed iprint level at which 2001 point table printed out...
!!   2007/11/16 10:19 dave
!!    Changed linear interpolation to spline interpolation to fix forces problem
!!   2008/03/03 18:40 dave
!!    Changed float to real()
!!   2008/05/23 ast
!!    Added timers
!!   2017/03/23 drb
!!    Change to use delta from PAO structure, not calculate it
!!   2019/12/24 tsuyoshi
!!    Removed flag_aotmic_density_from_pao
!!    We don't need make_atomic_denisty_from_paos any more.
!!  SOURCE
!!
  subroutine make_atomic_density_from_paos(inode,ionode,n_species)

    use datatypes
    use GenComms, ONLY : cq_abort, gcopy
    use global_module, ONLY : iprint_SC, area_SC
    use numbers, ONLY : zero, one, four, pi, six
    use pao_format
    use memory_module, ONLY: reg_alloc_mem, type_dbl

    implicit none

    real(double), parameter :: one_over_four_pi = one/(four*pi)
    integer, intent(in) :: inode,ionode, n_species
    integer :: alls, i, nt, n_am, n_sp, n_zeta
    integer, parameter :: default_atomic_density_length = 2001
    real(double) :: cutoff, density_deltar, pao_deltar, r, rn_am, val
    real(double) :: a, b, c, d, r1, r2, r3, r4, rr

    call start_timer(tmr_std_chargescf)
    call start_timer(tmr_std_allocation)
    if(allocated(atomic_density_table)) then
       do i=1,size(atomic_density_table)
          deallocate(atomic_density_table(i)%table)
       end do
       deallocate(atomic_density_table)
    end if
    allocate(atomic_density_table(n_species),STAT = alls)
    if(alls /= 0) call cq_abort('make_atomic_density_from_paos: error allocating atomic_density_table ',n_species)

    allocate(rcut_dens(n_species),STAT=alls)
    call reg_alloc_mem(area_SC, n_species, type_dbl)
    if (alls /= 0) call cq_abort('make_atomic_density_from_paos: error allocating rcut_dens ',n_species)
    call stop_timer(tmr_std_allocation)
    rcut_dens = 0.0_double
    do n_sp = 1, n_species
       ! By default, use max PAO cut-off radius as density cut-off
       cutoff = zero
       do n_am = 0, pao(n_sp)%greatest_angmom
          if(pao(n_sp)%angmom(n_am)%n_zeta_in_angmom > 0) then
             do n_zeta = 1, pao(n_sp)%angmom(n_am)%n_zeta_in_angmom
                cutoff = max(cutoff,pao(n_sp)%angmom(n_am)%zeta(n_zeta)%cutoff)
             end do
          end if
       end do
       atomic_density_table(n_sp)%cutoff = cutoff
       rcut_dens(n_sp)=atomic_density_table(n_sp)%cutoff
       !if(atomic_density_table(n_sp)%cutoff>rcut_dens) rcut_dens=atomic_density_table(n_sp)%cutoff
       if((inode == ionode).and.(iprint_SC >= 2)) &
            &write(unit=io_lun,fmt='(/10x," radial cut-off to be used is taken to be max PAO cut-off radius for &
            &this species:",f12.6)') atomic_density_table(n_sp)%cutoff     
       ! By default, use the parameter given above for length
       atomic_density_table(n_sp)%length = default_atomic_density_length
       ! Check for sensible length
       if(atomic_density_table(n_sp)%length < 2) &
            &call cq_abort('make_atomic_density_from_paos: table length must be >= 2',&
            &atomic_density_table(n_sp)%length)
       ! Allocate space for atomic density
       call start_timer(tmr_std_allocation)
       allocate(atomic_density_table(n_sp)%table(atomic_density_table(n_sp)%length),STAT = alls)
       if(alls /= 0) call cq_abort('make_atomic_density_from_paos: &
            &failed to allocate atomic_density_table(n_sp)%table()')
       call reg_alloc_mem(area_SC,atomic_density_table(n_sp)%length, type_dbl)
       call stop_timer(tmr_std_allocation)

       ! initiate to zero table of atomic density for current species and calculate table spacing
       do nt = 1, atomic_density_table(n_sp)%length
          atomic_density_table(n_sp)%table(nt) = zero
       end do
       ! Find spacing of table
       density_deltar = atomic_density_table(n_sp)%cutoff/&
            &real(atomic_density_table(n_sp)%length-1,double)
       atomic_density_table(n_sp)%delta = density_deltar
       ! Write out info and check angular momentum
       if((inode == ionode).and.(iprint_SC >= 2)) &
            write(unit=io_lun,fmt='(/10x," greatest ang. mom. for making density from PAOs:",i3)') &
            &pao(n_sp)%greatest_angmom
       if(pao(n_sp)%greatest_angmom < 0) &
            &call cq_abort('make_atomic_density_from_paos: greatest ang. mom. cannot be negative')
       ! Loop over angular momenta
       do n_am = 0, pao(n_sp)%greatest_angmom
          ! Check for zeta
          if(pao(n_sp)%angmom(n_am)%n_zeta_in_angmom > 0) then
             ! Loop over zetas
             do n_zeta = 1, pao(n_sp)%angmom(n_am)%n_zeta_in_angmom
                if(pao(n_sp)%angmom(n_am)%zeta(n_zeta)%length > 1) then
                   pao_deltar = pao(n_sp)%angmom(n_am)%zeta(n_zeta)%delta
                   do nt = 1, atomic_density_table(n_sp)%length
                      r = real(nt-1,double)*density_deltar
                      i = 1 + floor(r/pao_deltar)
                      if(i+1 <= pao(n_sp)%angmom(n_am)%zeta(n_zeta)%length) then
                         if(n_am /=0) then
                            rn_am = r**n_am
                         else
                            rn_am = one
                         endif
                         rr = real(i,double)*pao_deltar
                         a = (rr - r)/pao_deltar
                         b = one - a
                         c = a * ( a * a - one ) * pao_deltar * pao_deltar / six
                         d = b * ( b * b - one ) * pao_deltar * pao_deltar / six
                         r1 = pao(n_sp)%angmom(n_am)%zeta(n_zeta)%table(i)
                         r2 = pao(n_sp)%angmom(n_am)%zeta(n_zeta)%table(i+1)
                         r3 = pao(n_sp)%angmom(n_am)%zeta(n_zeta)%table2(i)
                         r4 = pao(n_sp)%angmom(n_am)%zeta(n_zeta)%table2(i+1)
                         val = a*r1 + b*r2 + c*r3 + d*r4
                         atomic_density_table(n_sp)%table(nt) = atomic_density_table(n_sp)%table(nt) + &
                              &one_over_four_pi * pao(n_sp)%angmom(n_am)%occ(n_zeta) * &
                              &(rn_am * val )**2
                      end if ! if(i+1<=pao(...)%length
                   end do ! do nt = atomic_density_table()%length
                end if ! if(pao(...)%length > 1
             end do ! do n_zeta = pao(...)%n_zeta_in_angmom
          end if ! pao(...)%n_zeta_in_angmom > 0
       end do ! n_am = pao(...)%greatest_angmom
       do nt = 1, atomic_density_table(n_sp)%length
          r = (nt-1)*density_deltar
          if(inode==ionode.AND.iprint_SC>3) write(io_lun,fmt='(10x,"Radial table: ",i5,2f15.8)') &
               nt,r,atomic_density_table(n_sp)%table(nt)
       end do
    end do ! n_sp = n_species
    do n_sp = 1,n_species
       if(inode == ionode.AND.iprint_SC>2) &
            write(io_lun,fmt='(10x,"Atomic density cutoff for species ",i4," : ",f15.8)') n_sp,rcut_dens(n_sp)
    end do
    call stop_timer(tmr_std_chargescf)
  end subroutine make_atomic_density_from_paos
!!***

! -----------------------------------------------------------
! Subroutine spline_atomic_density
! -----------------------------------------------------------

!!****f* atomic_density/spline_atomic_density *
!!
!!  NAME 
!!   spline_atomic_density
!!  USAGE
!! 
!!  PURPOSE
!!   Build spline tables for the radial tables of atomic densities
!!  INPUTS
!! 
!! 
!!  USES
!! 
!!  AUTHOR
!!   D.R.Bowler
!!  CREATION DATE
!!   17:18, 2003/03/18 dave
!!  MODIFICATION HISTORY
!!   17:27, 2003/06/10 tm
!!    Fixed over-run problem with splining
!!   2008/05/23 ast
!!    Added timers
!!   2019/08/16 14:36 dave
!!    Removed dsplint and output of derivative (unnecessary)
!!  SOURCE
!!
  subroutine spline_atomic_density(n_species)

    use datatypes
    use numbers
    use splines, ONLY: spline
    use GenComms, ONLY: cq_abort, inode, ionode
    use global_module, ONLY: iprint_SC, area_SC
    use memory_module, ONLY: reg_alloc_mem, type_dbl

    implicit none

    ! Passed variables
    integer :: n_species
    ! Local variables

    integer :: i, n, stat

    real(double) :: d_end, d_origin, delta_r, r

    call start_timer(tmr_std_chargescf)
    ! loop over species and do the interpolation
    do n=1, n_species
       call start_timer(tmr_std_allocation)
       allocate(atomic_density_table(n)%d2_table(atomic_density_table(n)%length), STAT=stat)
       if(stat/=0) call cq_abort('spline_atomic_density: error allocating d2_table ! ',stat)
       call reg_alloc_mem(area_SC,atomic_density_table(n)%length, type_dbl)
       call stop_timer(tmr_std_allocation)
       ! do the splining for the table
       delta_r = atomic_density_table(n)%cutoff/real(atomic_density_table(n)%length-1,double)
       d_origin = (atomic_density_table(n)%table(2)- atomic_density_table(n)%table(1))/delta_r
       d_end = (atomic_density_table(n)%table(atomic_density_table(n)%length)- &
            atomic_density_table(n)%table(atomic_density_table(n)%length-1))/delta_r
       !d_origin = 1e30_double
       !d_end = 1e30_double
       call spline( atomic_density_table(n)%length, delta_r, atomic_density_table(n)%table(:),  &
            d_origin, d_end, atomic_density_table(n)%d2_table(:) )
       if(inode==ionode.AND.iprint_SC>3) then
          write(io_lun,fmt='(10x,"Atomic density for species ",i5)') n
          do i=1,atomic_density_table(n)%length
             r = real(i-1,double)*delta_r
             write(io_lun,fmt='(10x,2f20.12)') r,atomic_density_table(n)%table(i)
          end do
       end if
    end do
    call stop_timer(tmr_std_chargescf)
    return
  end subroutine spline_atomic_density
!!***

end module atomic_density
