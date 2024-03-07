! -*- mode: F90; mode: font-lock -*-
! ------------------------------------------------------------------------------
! $Id$
! ------------------------------------------------------------------------------
! Module pao_minimisation
! ------------------------------------------------------------------------------
! Code area 6: energy minimisation
! ------------------------------------------------------------------------------

!!****h* Conquest/pao_minimisation *
!!  NAME
!!   pao_minimisation
!!  PURPOSE
!!   Hold the different routines associated with pao minimisation
!!  AUTHOR
!!   D.R.Bowler
!!  CREATION DATE
!!   09:17, 2003/03/24 dave
!!  MODIFICATION HISTORY
!!   2005/07/11 10:22 dave
!!    Changed build_PAO_coeff_grad so that nsf and npao are passed in with 
!!    sensible names and tidied module use
!!   10:09, 13/02/2006 drb 
!!    Removed all explicit references to data_ variables and rewrote
!!    in terms of new matrix routines
!!   2008/02/06 08:31 dave
!!    Changed for output to file not stdout
!!   2008/05/25 ast
!!    Added timers
!!   2014/09/15 18:30 lat
!!    fixed call start/stop_timer to timer_module (not timer_stdlocks_module !)
!!   2021/08/02 14:41 dave
!!    Added dE_PAO to allow comparison with dE from structural optimisation
!!  SOURCE
!!
module pao_minimisation

  use datatypes
  use global_module,          only: io_lun
  use timer_module,           only: start_timer, stop_timer
  use timer_stdclocks_module, only: tmr_std_allocation, tmr_std_matrices

  implicit none

  integer, parameter :: mx_pulay = 5
  integer, parameter :: GdS = 1
  integer, parameter :: KdH = 2
  integer, parameter :: full = 3
  real(double), save :: InitStep_paomin = 5.0_double
  real(double), save :: dE_PAO

!!***

contains

  !!****f* pao_minimisation/vary_pao *
  !!
  !!  NAME 
  !!   vary_support
  !!  USAGE
  !! 
  !!  PURPOSE
  !!   Performs the minimisation with respect to the 
  !!    support functions. The method used is CG. This
  !!    subroutine follows closely the strategy of the
  !!    original konquest program. (Wow)
  !!  INPUTS
  !! 
  !! 
  !!  USES
  !!   pao, common, datatypes, DiagModule, GenBlas, GenComms, logicals, 
  !!   matrix_data, maxima_module, mult_module, numbers, PosTan
  !!  AUTHOR
  !!   D.R.Bowler/E.H.Hernandez
  !!  CREATION DATE
  !!   03/04/95
  !!  MODIFICATION HISTORY
  !!   updated to make use of pao functions.
  !!   updated to include electron gradient
  !!   25/1/96 CMG/EHE line minimisation moved out
  !!   19/5/97 DRB added HeadGordon
  !!   23/05/2001 dave
  !!    Shortened calls to get_pao_gradient and get_electron_gradient
  !!    and added ROBODoc header
  !!   23/05/2001 dave
  !!    Shortened call to line_minimise_support
  !!   08/06/2001 dave
  !!    Added RCS Id and Log tags and changed to use GenComms
  !!   17/06/2002 dave
  !!    Tidied headers, added check for solution method
  !!   09:18, 2003/03/24 dave
  !!    Included in pao_minimisation
  !!   08:29, 2003/04/03 dave
  !!    Changed to use pao_gradient for get_pao_gradient and
  !!    get_electron_gradient
  !!   2007/04/26 12:08 dave
  !!    Changed TestPAOGrads to TestBasisGrads (to allow both blip and
  !!    PAO testing with same flag)
  !!   2008/05/25 ast
  !!    Added timers
  !!   2011/12/06 L.Tong
  !!    - Added spin polarisation
  !!    - Changed local variable sum to summ, to avoid a potential
  !!      confusion with the intrinsic function of the same name.
  !!    - Added registration for memory usage
  !!    - Removed redundant parameter number_of_bands
  !!   2012/03/24 L.Tong
  !!   - Changed spin implementation
  !!   - Removed redundant input parameter real(double) mu
  !!   2016/12/28 18:30 nakata
  !!    matdSFcoeff and matdSFcoeff_e are used instead of
  !!    grad_coeff_array and elec_grad_coeff_array.
  !!    dump_matrix is used instead of writeout_support_functions.
  !!    Removed blips_on_atom, nsf_species, npao_species,
  !!    which are no longer used here.
  !!   2017/02/23 dave
  !!    - Changing location of diagon flag from DiagModule to global and name to flag_diagonalisation
  !!   2019/10/24 11:52 dave
  !!    Changed function calls to FindMinDM
  !!   2019/12/02 nakata
  !!    Removed dump_matrix(SFcoeff), which will be changed to dump_pos_and_matrices in near future
  !!   2019/12/30 tsuyoshi
  !!    introduced dump_pos_and_matrices (every n_dumpSFcoeff iterations)
  !!   2021/07/28 10:39 dave
  !     Tidied up to remove unnecessary calls to get_S, get_H, FindMinDM and get_energy (all done
  !!    in line_minimise_pao)
  !!  SOURCE
  !!
  subroutine vary_pao(n_support_iterations, fixed_potential, vary_mu, &
                      n_cg_L_iterations, L_tolerance, sc_tolerance,   &
                      energy_tolerance, total_energy_last,            &
                      expected_reduction)

    use datatypes
    use logicals
    use numbers
    use GenBlas
    use PosTan,                    only: PulayC, PulayBeta, SCC,       &
                                         SCBeta
    use GenComms,                  only: my_barrier, gsum, inode,      &
                                         ionode, cq_abort, cq_warn
    !use DiagModule,                only: diagon
    use primary_module,            only: bundle
    use cover_module,              only: BCS_parts
    use global_module,             only: flag_vary_basis, iprint_minE, &
                                         ni_in_cell,                   &
                                         flag_self_consistent,         &
                                         id_glob, numprocs, area_minE, &
                                         nspin, spin_factor, nspin_SF, &
                                         flag_diagonalisation, min_layer
    use group_module,              only: parts
    use H_matrix_module,           only: get_H_matrix
    use S_matrix_module,           only: get_S_matrix
    use store_matrix,              only: dump_pos_and_matrices, unit_MSSF_save
    use io_module,                 only: return_prefix
    use support_spec_format,       only: TestBasisGrads, TestTot,      &
                                         TestBoth, TestS, TestH
    use DMMin,                     only: FindMinDM
    use energy,                    only: get_energy, band_energy
    use density_module,            only: density
    use matrix_data,               only: mat, halo, SFcoeff_range
    use maxima_module,             only: maxngrid
    use memory_module,             only: reg_alloc_mem, type_dbl,      &
                                         reg_dealloc_mem
    use mult_module,               only: mat_p, matrix_pos,            &
                                         matSFcoeff, matSFcoeff_tran,  &
                                         matdSFcoeff, matdSFcoeff_e,   &
                                         matrix_scale, matrix_transpose
    use multisiteSF_module,        only: normalise_SFcoeff, n_dumpSFcoeff, flag_mix_LFD_SCF
    use units,                     only: en_conv, en_units, energy_units
    use SelfCon,           only: new_SC_potl
    
    implicit none

    ! Shared variables
    logical      :: vary_mu, fixed_potential, convergence_flag
    integer      :: n_cg_L_iterations
    integer      :: n_support_iterations
    real(double) :: expected_reduction
    real(double) :: total_energy_last, energy_tolerance, L_tolerance, &
                    sc_tolerance

    ! Local variables
    real(double) :: tolerance, con_tolerance
    integer      :: i, part, nsf1, npao2, neigh, proc, ind_part, atom, local_atom, &
                    nsf_local, n_nab_local, npao_local, gcspart, ist, wheremat
    integer      :: length, n_iterations, spin_SF, stat
    logical      :: orig_SC, reset_L, my_atom, orig_LFD_SCF
    real(double) :: diff, total_energy_0, total_energy_test, last_step, &
                    dN_dot_de, dN_dot_dN, summ, E2, E1, g1, g2, &
                    tmp0, val0, val1
    real(double), dimension(nspin_SF) :: dgg, gamma, gg, sum_0, tmp
    real(double), dimension(nspin) :: electrons
    real(double), dimension(:,:), allocatable :: search_direction, &
                                                 last_sd, Psd 
    real(double), dimension(:), allocatable :: grad_copy,        &
                                               grad_copy_dH,     &
                                               grad_copy_dS
    character(len=10) :: subname = "vary_pao: "
    character(len=120) :: prefix

    prefix = return_prefix(subname, min_layer)
    if(inode==ionode .and. iprint_minE + min_layer >= 0) &
         write(io_lun,fmt='(/4x,a)') trim(prefix)//" Starting PAO optimisation"
    reset_L = .true.

    length = mat_p(matSFcoeff(1))%length

    call start_timer (tmr_std_allocation)
    if (TestBasisGrads) then
       allocate(grad_copy(length),    &
                grad_copy_dH(length), &
                grad_copy_dS(length), STAT=stat)
       if (stat /= 0) &
            call cq_abort("vary_pao: failed to allocate tmp2 matrices: ", &
                          length, stat)
       call reg_alloc_mem(area_minE, 3 * length, type_dbl)
    end if
    call stop_timer (tmr_std_allocation)

    ! Set tolerances for self-consistency and L minimisation
    con_tolerance = zero ! SCC*expected_reduction**SCBeta
    tolerance = zero     ! PulayC*(0.1_double*expected_reduction)**PulayBeta
    if (con_tolerance < sc_tolerance) &
         con_tolerance = sc_tolerance
    if (con_tolerance < ten * tolerance) &
         tolerance = 0.1_double * con_tolerance
    con_tolerance = sc_tolerance
    tolerance = L_tolerance
    
    if (inode == ionode .and. iprint_minE + min_layer >= 2) &
         write (io_lun, fmt='(4x,a,2e12.5)') trim(prefix)//' Tolerances: ', &
         con_tolerance, tolerance

    allocate(search_direction(length,nspin_SF), &
             last_sd(length,nspin_SF), Psd(length,nspin_SF), STAT=stat)
    if (stat /= 0) call cq_abort("vary_pao: Error alloc mem: ", length)
    call reg_alloc_mem(area_minE, 3*length*nspin_SF, type_dbl)

    search_direction(:,:) = zero
    Psd(:,:) = zero
    last_sd(:,:) = zero ! TO

    total_energy_0 = total_energy_last
    if (total_energy_last == zero) &
         total_energy_0 = expected_reduction
    total_energy_last = total_energy_0

    ! We need to assemble the gradient
    do spin_SF = 1, nspin_SF
       call matrix_scale(zero, matdSFcoeff(spin_SF))
       call matrix_scale(zero, matdSFcoeff_e(spin_SF))
    enddo
    ! call get_H_matrix before calling build_PAO_coeff ! TM
    !call get_H_matrix(.true., fixed_potential, electrons, density, &
    !                  maxngrid)
    min_layer = min_layer - 1
    call new_SC_potl(.false., con_tolerance, reset_L,             &
         fixed_potential, vary_mu, n_cg_L_iterations, &
         tolerance, total_energy_last)
    total_energy_0 = total_energy_last
    ! Set LFD_SCF to false to avoid undoing PAO optimisation
    orig_LFD_SCF = flag_mix_LFD_SCF ! Use to restore original setting
    flag_mix_LFD_SCF = .false.
    call build_PAO_coeff_grad(full)
    min_layer = min_layer + 1

    if (TestBasisGrads) then
       do spin_SF = 1, nspin_SF
          grad_copy = mat_p(matdSFcoeff(spin_SF))%matrix
          !call dump_matrix("dSFcoeff1",matdSFcoeff(1), inode)
          ! Test PAO gradients
          ! Preserve unperturbed energy and gradient
          E1 = band_energy
          call matrix_scale(zero, matdSFcoeff(spin_SF))
          call matrix_scale(zero, matdSFcoeff_e(spin_SF))
          call build_PAO_coeff_grad(GdS)
          !call dump_matrix("dSFcoeff2",matdSFcoeff(1), inode)
          grad_copy_dS = mat_p(matdSFcoeff(spin_SF))%matrix
          call matrix_scale(zero, matdSFcoeff(spin_SF))
          call matrix_scale(zero, matdSFcoeff_e(spin_SF))
          call build_PAO_coeff_grad(KdH)
          !call dump_matrix("dSFcoeff3",matdSFcoeff(1), inode)
          ! LT 2011/12/06: Note that grad_copy_dH stores the value as the
          ! sum of contribution from both spin components if not flag_SpinDependentSF
          grad_copy_dH = mat_p(matdSFcoeff(spin_SF))%matrix
          ! LT 2011/12/06: end
          do proc = 1, numprocs
             local_atom = 0
             if (inode == proc) then
                my_atom = .true.
             else
                my_atom = .false.
             end if
             do part = 1, parts%ng_on_node(proc)
                ind_part = parts%ngnode(parts%inode_beg(proc) + part - 1)
                do atom = 1, parts%nm_group(ind_part)
                   local_atom = local_atom + 1 ! Is this really primary atom ?
                   nsf_local = 0
                   n_nab_local = 0
                   npao_local = 0
                   if (my_atom) then
                      write (io_lun,fmt='(8x,a,2i6)') 'primary, prim(glob) ', &
                                       local_atom, bundle%ig_prim(local_atom)
                      nsf_local   = mat(part,SFcoeff_range)%ndimi(atom)
                      n_nab_local = mat(part,SFcoeff_range)%n_nab(atom)
                   endif
                   call my_barrier
                   call gsum(nsf_local)
                   call gsum(n_nab_local)
                   ! which coefficient to be shifted
                   do neigh = 1, n_nab_local
                      if (my_atom) then
                         ist = mat(part,SFcoeff_range)%i_acc(atom) + neigh - 1
                         gcspart = BCS_parts%icover_ibeg(mat(part,SFcoeff_range)%i_part(ist)) + &
                                   mat(part,SFcoeff_range)%i_seq(ist) - 1
                         npao_local = mat(part,SFcoeff_range)%ndimj(ist)
                      endif
                      call my_barrier
                      call gsum(npao_local)
                      do nsf1 = 1, nsf_local
                         do npao2 = 1, npao_local
                            if (my_atom) then
                               wheremat = matrix_pos(matSFcoeff(spin_SF), local_atom, &
                                                     halo(SFcoeff_range)%i_halo(gcspart), nsf1, npao2)
                               val0 = mat_p(matSFcoeff(spin_SF))%matrix(wheremat)
                               tmp0 = val0*0.0001_double
                               val1 = val0 + tmp0
                            endif
                            if (TestTot) then
                               ! Shift coefficient a little
                               if (my_atom) then
                                  mat_p(matSFcoeff(spin_SF))%matrix(wheremat) = val1
                                  call matrix_scale(zero,matSFcoeff_tran(spin_SF))
                                  call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
                               endif
                               call my_barrier()
                               ! Recalculate energy and gradient
                               call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
                               call get_H_matrix(.false., fixed_potential, &
                                                 electrons, density, maxngrid)
                               call FindMinDM(n_cg_L_iterations, vary_mu, &
                                              L_tolerance, &
                                              .false., .false.)
                               call get_energy(E2)
                               E2 = band_energy
                               call matrix_scale(zero, matdSFcoeff(spin_SF))
                               call matrix_scale(zero, matdSFcoeff_e(spin_SF))
                               call build_PAO_coeff_grad(full)
                               if (my_atom) then
                                  g1 = mat_p(matdSFcoeff(spin_SF))%matrix(wheremat)
                                  mat_p(matdSFcoeff(spin_SF))%matrix = grad_copy
                                  g2 = mat_p(matdSFcoeff(spin_SF))%matrix(wheremat)
                                  write (io_lun, fmt='(8x,a,2f16.6)') 'Tot: Numerical, analytic grad: ', &
                                                    (E2 - E1) / tmp0, - half * (g1 + g2)
                                  write (io_lun, fmt='(8x,a,5f16.6)') 'Tot:Components: ', &
                                                    tmp0, E1, E2, g1, g2
                               end if
                               ! Shift coefficient back
                               if (my_atom) then
                                  mat_p(matSFcoeff(spin_SF))%matrix(wheremat) = val0
                                  call matrix_scale(zero,matSFcoeff_tran(spin_SF))
                                  call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
                               endif
                               call my_barrier()
                               call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
                               call get_H_matrix(.false., fixed_potential, &
                                                 electrons, density, maxngrid)
                               call my_barrier()
                            end if ! (TestTot)
                            if (TestS .or. TestBoth) then
                               ! Shift coefficient a little
                               ! tmp0 = 0.0001_double * val0
                               if (my_atom) then
                                  mat_p(matSFcoeff(spin_SF))%matrix(wheremat) = val1
                                  call matrix_scale(zero,matSFcoeff_tran(spin_SF))
                                  call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
                               endif
                               call my_barrier()
                               ! Recalculate energy and gradient
                               call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
                               call FindMinDM(n_cg_L_iterations, vary_mu, &
                                              L_tolerance, &
                                              .false., .false.)
                               call get_energy(E2)
                               E2 = band_energy
                               call matrix_scale(zero, matdSFcoeff(spin_SF))
                               call matrix_scale(zero, matdSFcoeff_e(spin_SF))
                               call build_PAO_coeff_grad(GdS)
                               if (my_atom) then
                                  g1 = mat_p(matdSFcoeff(spin_SF))%matrix(wheremat)
                                  mat_p(matdSFcoeff(spin_SF))%matrix = grad_copy_dS
                                  g2 = mat_p(matdSFcoeff(spin_SF))%matrix(wheremat)
                                  write (io_lun,fmt='(8x,a,2f16.6)') 'GdS: Numerical, analytic grad: ',&
                                                   (E2 - E1) / tmp0, - half * (g1 + g2)
                                  write (io_lun,fmt='(8x,a,5f16.6)') 'GdS:Components: ', &
                                                   tmp0, E1, E2, g1, g2
                               end if
                               ! Shift coefficient back
                               if (my_atom) then
                                  mat_p(matSFcoeff(spin_SF))%matrix(wheremat) = val0
                                  call matrix_scale(zero,matSFcoeff_tran(spin_SF))
                                  call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
                               endif
                               call my_barrier()
                               call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
                               call my_barrier()
                            end if ! TestS .or. TestBoth
                            ! ** Test H ** !
                            if (TestH .or. TestBoth) then
                               ! Shift coefficient a little
                               ! tmp0 = 0.0001_double * val0
                               if (my_atom) then
                                  mat_p(matSFcoeff(spin_SF))%matrix(wheremat) = val1
                                  call matrix_scale(zero,matSFcoeff_tran(spin_SF))
                                  call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
                               endif
                               call my_barrier()
                               ! Recalculate energy and gradient
                               call get_H_matrix(.false., fixed_potential, &
                                                 electrons, density, maxngrid)
                               call FindMinDM(n_cg_L_iterations, vary_mu, &
                                              L_tolerance, &
                                              .false., .false.)
                               call get_energy(E2)
                               E2 = band_energy
                               call matrix_scale(zero, matdSFcoeff(spin_SF))
                               call matrix_scale(zero, matdSFcoeff_e(spin_SF))
                               call build_PAO_coeff_grad(KdH)
                               if(my_atom) then
                                  g1 = mat_p(matdSFcoeff(spin_SF))%matrix(wheremat)
                                  mat_p(matdSFcoeff(spin_SF))%matrix = grad_copy_dH
                                  g2 = mat_p(matdSFcoeff(spin_SF))%matrix(wheremat)
                                  write (io_lun, fmt='(8x,a,2f16.6)') 'KdH: Numerical, analytic grad: ',&
                                                    (E2 - E1) / tmp0, - half * (g1 + g2)
                                  write (io_lun, fmt='(8x,a,5f16.6)') 'KdH:Components: ', &
                                                    tmp0, E1, E2, g1, g2
                               end if
                               ! Shift coefficient back
                               if (my_atom) then
                                  mat_p(matSFcoeff(spin_SF))%matrix(wheremat) = val0
                                  call matrix_scale(zero,matSFcoeff_tran(spin_SF))
                                  call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
                               endif
                               call my_barrier()
                               call get_H_matrix(.false., fixed_potential, &
                                                 electrons, density, maxngrid)
!                               call get_H_matrix(.true., fixed_potential, &
!                                                 electrons, density, maxngrid)
                            end if ! TestH .or. TestBoth
                         end do ! npao2
                      end do ! nsf1
                   end do ! neigh
                end do ! atom
             end do ! part
          end do ! proc
       end do ! spin_SF
       call start_timer(tmr_std_allocation)
       deallocate(grad_copy, grad_copy_dH, grad_copy_dS, STAT=stat)
       if (stat /= 0) &
            call cq_abort("vary_pao: failed to &
                          &deallocate tmp2 matrices: ", stat)
       call reg_dealloc_mem(area_minE, 3 * length, type_dbl)
       call stop_timer(tmr_std_allocation)
    end if ! TestBasisGrads

    ! What about preconditioning ?
    call my_barrier()
    ! Now we have a basic gradient, so loop
    dgg = zero
    last_step = 1.0D10
    ! now loop over search directions
    do n_iterations = 1, n_support_iterations
       if (inode == ionode .and. iprint_minE + min_layer >= 1) &
            write (io_lun, fmt='(/4x,a,i3)') trim(prefix)//" PAO iteration ", n_iterations
       do spin_SF = 1, nspin_SF
          ! We need the last search direction for CG manipulations
          call copy(length, search_direction(:,spin_SF), 1, last_sd(:,spin_SF), 1)
          ! The basis for searching is gradient
          call copy(length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, search_direction(:,spin_SF), 1)
          ! Now project gradient tangential to the constant Ne hyperplane
          if (.not. flag_diagonalisation) then
             dN_dot_de = dot(length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, &
                                     mat_p(matdSFcoeff_e(spin_SF))%matrix, 1)
             dN_dot_dN = dot(length, mat_p(matdSFcoeff_e(spin_SF))%matrix, 1, &
                                     mat_p(matdSFcoeff_e(spin_SF))%matrix, 1)
             call gsum(dN_dot_de)
             call gsum(dN_dot_dN)
             if (inode == ionode .and. iprint_minE + min_layer >= 3) &
                write (io_lun, fmt='(4x,a,2e12.5)') trim(prefix)//' dN.de, dN.dN ', &
                                   dN_dot_de, dN_dot_dN
             call axpy(length, - (dN_dot_de / dN_dot_dN), &
                       mat_p(matdSFcoeff_e(spin_SF))%matrix, 1, search_direction(:,spin_SF), 1)
          end if
          ! *THINK* Do we need/want to precondition ?
          Psd(:,spin_SF) = search_direction(:,spin_SF)
          ! Now determine conjugate directions
          gg(spin_SF) = dgg(spin_SF)
          dgg(spin_SF) = dot(length, search_direction(:,spin_SF), 1, Psd(:,spin_SF), 1)
          call gsum(dgg(spin_SF))
          if (gg(spin_SF) /= zero) then
             gamma(spin_SF) = dgg(spin_SF) / gg(spin_SF)
          else
             gamma(spin_SF) = zero
          end if
          !gamma = zero
          ! if (mod(n_iterations, 5) == 0) gamma = zero
          if (inode == ionode .and. iprint_minE + min_layer >= 2) &
               write (io_lun, '(4x,A,I2,A,2F10.6)') trim(prefix)//' For spin(',spin_SF, &
               ') dgg and gamma are ', dgg(spin_SF), gamma(spin_SF)

          ! Construct the actual search direction
          call copy(length, Psd(:,spin_SF), 1, search_direction(:,spin_SF), 1)
          call axpy(length, gamma(spin_SF), last_sd(:,spin_SF), 1, search_direction(:,spin_SF), 1)
          ! And project perpendicular to electron gradient
          if (.not. flag_diagonalisation) then
             dN_dot_de = dot(length, search_direction(:,spin_SF), 1, &
                                     mat_p(matdSFcoeff_e(spin_SF))%matrix, 1)
             dN_dot_dN = dot(length, mat_p(matdSFcoeff_e(spin_SF))%matrix, 1, &
                                     mat_p(matdSFcoeff_e(spin_SF))%matrix, 1)
             call gsum(dN_dot_de)
             call gsum(dN_dot_dN)
             if (inode == ionode .and. iprint_minE + min_layer >=3) &
                  write (io_lun, fmt='(4x,a,2e12.5)') trim(prefix)//' dN.de, dN.dN ', &
                                    dN_dot_de, dN_dot_dN
             call axpy(length, - (dN_dot_de / dN_dot_dN), &
                       mat_p(matdSFcoeff_e(spin_SF))%matrix, 1, search_direction(:,spin_SF), 1)
          end if
          ! Check this !
          sum_0(spin_SF) = dot(length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, search_direction(:,spin_SF), 1)
          call gsum(sum_0(spin_SF))
          if (inode == ionode .and. iprint_minE + min_layer >=3) &
               write (io_lun, '(4x,A,I2,A,F15.7)') trim(prefix)//' sum_0(',spin_SF,') is ', &
               sum_0(spin_SF)
          call my_barrier()

          call my_barrier()
          tmp(spin_SF) = dot(length, search_direction(:,spin_SF), 1, mat_p(matdSFcoeff(spin_SF))%matrix, 1)
          call gsum(tmp(spin_SF))
       enddo ! spin_SF

       ! Temporarily turn off basis variation so that we don't do
       ! unnecessary calculations
       flag_vary_basis = .false.
       !orig_SC = flag_self_consistent
       !flag_self_consistent = .false.
       call line_minimise_pao(search_direction, fixed_potential,     &
                              vary_mu, n_cg_L_iterations, tolerance, &
                              con_tolerance, total_energy_0,         &
                              expected_reduction, last_step, tmp)
       flag_vary_basis = .true.

       ! Normalise and writeout
       !call normalise_SFcoeff
       !do spin_SF = 1,nspin_SF
       !   call matrix_scale(zero,matSFcoeff_tran(spin_SF))
       !   call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
       !enddo

       ! Write out current SF coefficients every n_dumpSFcoeff, if n_dumpSFcoeff > 0)
       if (n_dumpSFcoeff > 0) then
          if(mod(n_iterations,n_dumpSFcoeff) == 0) call dump_pos_and_matrices(index = unit_MSSF_save)
       endif

       ! Find change in energy for convergence
       diff = total_energy_last - total_energy_0
       dE_PAO = diff
       if (abs(diff / total_energy_0) <= energy_tolerance) then
          if(inode==ionode .and. iprint_minE + min_layer>0) &
               write(io_lun, fmt='(4x,a,i3,2(a,f15.7,a2))') trim(prefix)//" Iter: ", &
               n_iterations," E: ",total_energy_0*en_conv,en_units(energy_units),&
               " dE: ",diff*en_conv,en_units(energy_units)
          if (inode == ionode) & !  .and. iprint_minE + min_layer >-1) &
               write (io_lun, fmt='(/4x,a,f15.7,a2,a,i3,a)') &
               trim(prefix)//" Minimisation converged to ",total_energy_0*en_conv, &
               en_units(energy_units), " after ",n_iterations," iterations"
          convergence_flag = .true.
          total_energy_last = total_energy_0
          ! Commented out because we don't want to reset to LFD after
          ! a successful PAO optimisation 
          !flag_mix_LFD_SCF = orig_LFD_SCF
          deallocate(search_direction, last_sd, Psd, STAT=stat)
          if (stat /= 0) call cq_abort("vary_pao: Error dealloc mem")
          call reg_dealloc_mem(area_minE, 3*length*nspin_SF, type_dbl)
          return
       else
          if(inode==ionode .and. iprint_minE + min_layer>=0) &
               write(io_lun, fmt='(4x,a,i3,2(a,f15.7,a2))') trim(prefix)//" Iter: ", &
               n_iterations," E: ",total_energy_0*en_conv,en_units(energy_units),&
               " dE: ",diff*en_conv,en_units(energy_units)
       end if

       ! prepare for next iteration
       ! Find new self-consistent energy 
       !call new_SC_potl(.false., sc_tolerance, reset_L,             &
       !     fixed_potential, vary_mu, n_L_iterations, &
       !     L_tolerance, total_energy_0)
       ! We need to assemble the gradient
       do spin_SF = 1, nspin_SF
          call matrix_scale(zero, matdSFcoeff(spin_SF))
          call matrix_scale(zero, matdSFcoeff_e(spin_SF))
       enddo
       ! Generate dS and dH
       call build_PAO_coeff_grad(full)
       do spin_SF = 1, nspin_SF
          summ = dot(length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, mat_p(matdSFcoeff(spin_SF))%matrix, 1)
          call gsum(summ)
          if (inode == ionode .and. iprint_minE + min_layer >= 3) &
               write (io_lun, fmt='(4x,a,i1,a,e12.5)') trim(prefix)//' Dot prod of gradient (',&
               spin_SF,'): ', summ
       enddo
       total_energy_last = total_energy_0
    end do ! n_iterations
    if(inode==ionode) &
         write(io_lun,fmt='(/4x,a,i4,a,f15.7,x,a2)') &
         trim(prefix)//" Ending unconverged after ",n_support_iterations," iterations with dE ", &
         en_conv*diff,en_units(energy_units)
    call cq_warn(subname,"PAO optimisation finished after maximum iterations: ",n_support_iterations)
    flag_mix_LFD_SCF = orig_LFD_SCF
    deallocate(search_direction, last_sd, Psd, STAT=stat)
    if (stat /= 0) call cq_abort("vary_pao: Error dealloc mem")
    call reg_dealloc_mem(area_minE, 3*length*nspin_SF, type_dbl)

    return
    
  end subroutine vary_pao
  !!***

  !!****f* pao_minimisation/pulay_min_pao *
  !! PURPOSE
  !! INPUTS
  !! OUTPUT
  !! RETURN VALUE
  !! AUTHOR
  !!   David Bowler
  !! CREATION DATE 
  !!
  !! MODIFICATION HISTORY
  !!   2011/12/05 L.Tong
  !!   - Added RoboDoc header for adding modification history
  !!   - Added spin polarisation
  !!   - changed sum to summ to avoid potential confusion with
  !!     intrinsic function of the same name
  !!   - removed local variable energy_in, this appears to be only
  !!     used as a dump for energy calculated from LNV_matrix_multiply
  !!     subroutine, and its value is not used anywhere in the
  !!     subroutine, this is the same function as tmp, so just use tmp
  !!     for this purpose.
  !!   - removed redundant parameter number_of_bands
  !!   - the temp arrays are not deallocated, fixed this potential
  !!     memory leak
  !!   - added register for memory usage
  !!   2012/03/24 L.Tong
  !!   - Changed spin implementation
  !!   - made temporary arrays automatic
  !!   - removed redundant input parameter real(double) mu
  !!   2016/12/26 18:30 nakata
  !!    Removed unused search_direction, Psd, last_sd, FindMinDM
  !!   2016/12/28 18:30 nakata
  !!    Removed support_spec_format(blips_on_atom), which is no longer used here.
  !!    matdSFcoeff and matdSFcoeff_e are used instead of
  !!    grad_coeff_array and elec_grad_coeff_array.
  !!    dump_matrix is used instead of writeout_support_functions.
  !!   2017/02/23 dave
  !!    - Changing location of diagon flag from DiagModule to global and name to flag_diagonalisation
  !!   2019/12/02 nakata
  !!    Removed dump_matrix(SFcoeff), which will be changed to dump_pos_and_matrices in near future
  !! SOURCE
  !!
  subroutine pulay_min_pao(n_support_iterations, fixed_potential,   &
                           vary_mu, n_cg_L_iterations, L_tolerance, &
                           sc_tolerance, energy_tolerance,          &
                           total_energy_last, expected_reduction)

    use datatypes
    use logicals
    use numbers
    use Pulay,               only: DoPulay
    use mult_module,         only: LNV_matrix_multiply, matM12, matM4, &
                                   mat_p, matSFcoeff, matSFcoeff_tran, &
                                   matdSFcoeff, matdSFcoeff_e,         &
                                   matrix_scale, matrix_transpose
    use GenBlas,             only: dot, copy
    use PosTan,              only: PulayC, PulayBeta, SCC, SCBeta
    use GenComms,            only: my_barrier, gsum, inode, ionode,    &
                                   cq_abort
    !use DiagModule,          only: diagon
    use primary_module,      only: bundle
    use global_module,       only: flag_vary_basis, iprint_minE,       &
                                   ni_in_cell, nspin, spin_factor,     &
                                   area_minE, nspin_SF, flag_diagonalisation
    use SelfCon,             only: new_SC_potl
    use S_matrix_module,     only: get_S_matrix
    use energy,              only: get_energy, kinetic_energy, nl_energy
    use memory_module,       only: reg_alloc_mem, type_dbl,            &
                                   reg_dealloc_mem
    use multisiteSF_module,  only: normalise_SFcoeff
    use store_matrix,        only: dump_pos_and_matrices
!    use io_module,           only: dump_matrix

    implicit none

    ! Shared variables
    logical :: vary_mu, fixed_potential, convergence_flag
    integer :: n_cg_L_iterations, n_support_iterations
    real(double) :: expected_reduction, total_energy_last, &
                    energy_tolerance, L_tolerance, sc_tolerance

    ! Local variables
    logical      :: reset_L
    integer      :: j, ii, spin_SF
    integer      :: length, n_iterations, npmod, pul_mx, stat
    real(double) :: gg, step, diff, total_energy_0, total_energy_test, &
                    g0, summ, tolerance, con_tolerance
    real(double), dimension(nspin)             :: electrons, energy_tmp
    real(double), dimension(mx_pulay,mx_pulay) :: Aij 
    real(double), dimension(mx_pulay)          :: alph
    ! real(double), dimension(mx_pulay*mx_pulay) :: Aij1
    real(double), dimension(:,:,:), allocatable :: data_gradstore, &
                                                   data_paostore


    length = mat_p(matSFcoeff(1))%length

    allocate(data_gradstore(length,mx_pulay,nspin_SF), &
             data_paostore(length,mx_pulay,nspin_SF), STAT=stat)
    if (stat /= 0) &
         call cq_abort("pulay_min_pao: Error alloc mem: ", &
                       length, mx_pulay)
    call reg_alloc_mem(area_minE, 2*mx_pulay*length*nspin_SF, type_dbl)

    ! Set tolerances for self-consistency and L minimisation
    con_tolerance = SCC * expected_reduction**SCBeta
    tolerance = PulayC * (0.1_double * expected_reduction)**PulayBeta
    if (con_tolerance < sc_tolerance) &
         con_tolerance = sc_tolerance
    if (con_tolerance < ten * tolerance) &
         tolerance = 0.1_double * con_tolerance
    con_tolerance = sc_tolerance

    if (inode == ionode) &
         write(io_lun, *) 'Tolerances: ', &
                          con_tolerance, tolerance, energy_tolerance
    if (inode == ionode) &
         write(io_lun, *) inode, ' entering pulay_min_pao'

    total_energy_0 = total_energy_last
    if (total_energy_last == zero) &
         total_energy_0 = expected_reduction
    total_energy_last = total_energy_0

    ! We need to assemble the gradient
    if (.not. flag_diagonalisation) then
       call LNV_matrix_multiply(electrons, energy_tmp, doK, doM1,   &
                                doM2, dontM3, doM4, dontphi, dontE, &
                                mat_M12=matM12, mat_M4=matM4)
    end if

    ! We should have the elements built by H_matrix_module and
    ! S_matrix_module Now we take the sum over j\beta (nsf2 = \beta;
    ! neigh = j)
    do spin_SF = 1, nspin_SF
       call matrix_scale(zero, matdSFcoeff(spin_SF))
       call matrix_scale(zero, matdSFcoeff_e(spin_SF))
    enddo
    call build_PAO_coeff_grad(full)

    ! What about preconditioning ?       
    call my_barrier()
    ! Now we have a basic gradient, so loop
    g0 = zero
    do spin_SF = 1, nspin_SF
       g0 = g0 + dot(length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, &
                             mat_p(matdSFcoeff(spin_SF))%matrix, 1)
    enddo
    call gsum(g0)
    if (inode == ionode) &
         write (io_lun, *) 'Dot product of initial gradient ', g0
    ! Store gradient
    do spin_SF = 1, nspin_SF
       call copy(length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, data_gradstore(1:,1,spin_SF), 1)
       data_paostore(:,1,spin_SF) = mat_p(matSFcoeff(spin_SF))%matrix
    enddo

    diff = zero
    ! now loop over search directions
    do n_iterations = 1, n_support_iterations
       if (inode == ionode) write (io_lun, 7) n_iterations
       npmod = mod(n_iterations, mx_pulay) + 1
       pul_mx = min(n_iterations + 1, mx_pulay)
       step = diff / g0 ! Base step on present gradient and expected dE
       if (step == zero) step = 0.01_double
       if (inode == ionode) &
            write (io_lun, *) 'npmod, pul_mx and step: ', &
                              npmod, pul_mx, step
       do spin_SF = 1, nspin_SF
          ! Build PAO coefficients
          if (npmod > 1) then
             mat_p(matSFcoeff(spin_SF))%matrix = mat_p(matSFcoeff(spin_SF))%matrix + step * &
                                                 data_gradstore(:,npmod-1,spin_SF)
          else
             mat_p(matSFcoeff(spin_SF))%matrix = mat_p(matSFcoeff(spin_SF))%matrix + step * &
                                                 data_gradstore(:,pul_mx,spin_SF)
          endif
       enddo
       if (inode == ionode) write (io_lun, *) 'Normalising'
       ! Normalise
       call normalise_SFcoeff
       do spin_SF = 1,nspin_SF
          call matrix_scale(zero,matSFcoeff_tran(spin_SF))
          call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
       enddo

       ! Find change in energy for convergence

       ! Get energy and gradient for step
       if (inode == ionode) write (io_lun, *) 'Getting new S, H, E'
       flag_vary_basis = .true.
       ! Find new self-consistent energy 
       ! 1. Generate S
       call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
       ! 2. If we're building K as 3LSL-2LSLSL, we need to make K now
       if (.not. flag_diagonalisation) then
          call LNV_matrix_multiply(electrons, energy_tmp, doK, dontM1,&
                                   dontM2, dontM3, dontM4, dontphi, dontE)
       end if
       reset_L = .true.
       ! 3. Get a new self-consistent potential and Hamiltonian
       ! I've not put a call to get_H_matrix here because it's
       ! currently in new_SC_potl
       call new_SC_potl(.false., con_tolerance, reset_L,             &
                        fixed_potential, vary_mu, n_cg_L_iterations, &
                        tolerance, total_energy_0)
       do spin_SF = 1, nspin_SF
          call matrix_scale(zero, matdSFcoeff(spin_SF))
          call matrix_scale(zero, matdSFcoeff_e(spin_SF))
       enddo
       call build_PAO_coeff_grad(full)
       do spin_SF = 1, nspin_SF
          summ = dot (length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, mat_p(matdSFcoeff(spin_SF))%matrix, 1)
          call gsum(summ)
          if (inode == ionode) &
               write (io_lun, *) 'Dot prod of gradient(',spin_SF,'): ', summ
          ! Store PAO and gradient at this step
          call copy(length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, data_gradstore(1:,npmod,spin_SF), 1)
          call copy(length, mat_p(matSFcoeff(spin_SF))%matrix, 1, data_paostore(1:,npmod,spin_SF), 1)
       enddo

       ! Now mix pulay
       Aij = zero
       do ii = 1, pul_mx
          do j = 1, pul_mx
             gg = zero
             do spin_SF = 1, nspin_SF
                gg = gg + spin_factor * dot(length, data_gradstore(1:,j,spin_SF), 1, &
                                                    data_gradstore(1:,ii,spin_SF), 1)
             enddo
             call gsum(gg)
             Aij(j,ii) = gg
             ! Aij1(j+(ii-1) * pul_mx) = gg
          end do
       end do
       ! Solve to get alphas
       call DoPulay(npmod, Aij, alph, pul_mx, mx_pulay)
       if (inode == ionode) write (io_lun, *) 'Alph: ', alph

       ! Make new supports
       do spin_SF = 1, nspin_SF
          call matrix_scale(zero,matSFcoeff(spin_SF))
          do ii = 1, pul_mx
             mat_p(matSFcoeff(spin_SF))%matrix = mat_p(matSFcoeff(spin_SF))%matrix &
                                               + alph(ii) * data_paostore(:,ii,spin_SF)
          end do
       enddo
       ! Normalise
       call normalise_SFcoeff
       do spin_SF = 1,nspin_SF
          call matrix_scale(zero,matSFcoeff_tran(spin_SF))
          call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
       enddo

       ! re-evaluate the gradient and energy at new position
       ! Find new self-consistent energy 
       ! 1. Generate S
       call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
       ! 2. If we're building K as 3LSL-2LSLSL, we need to make K now
       if (.not. flag_diagonalisation) then
          call LNV_matrix_multiply(electrons, energy_tmp, doK, dontM1,&
                                   dontM2, dontM3, dontM4, dontphi, dontE)
       end if
       reset_L = .true.
       ! 3. Get a new self-consistent potential and Hamiltonian
       ! I've not put a call to get_H_matrix here because it's
       ! currently in new_SC_potl
       call new_SC_potl(.false., con_tolerance, reset_L,             &
                        fixed_potential, vary_mu, n_cg_L_iterations, &
                        tolerance, total_energy_0)

       do spin_SF = 1, nspin_SF
          call matrix_scale(zero, matdSFcoeff(spin_SF))
          call matrix_scale(zero, matdSFcoeff_e(spin_SF))
       enddo
       call build_PAO_coeff_grad(full)

       do spin_SF = 1, nspin_SF
          summ = dot (length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, mat_p(matdSFcoeff(spin_SF))%matrix, 1)
          call gsum(summ)
          if (inode == ionode) &
               write (io_lun, *) 'Dot prod of gradient(',spin_SF,'): ', summ
          ! Replace step with real L
          call copy(length, mat_p(matdSFcoeff(spin_SF))%matrix, 1, data_gradstore(1:, npmod, spin_SF), 1)
          call copy(length, mat_p(matSFcoeff(spin_SF))%matrix, 1, data_paostore(1:, npmod, spin_SF), 1)
       enddo

    ! Write out current SF coefficients with some iprint (in future)
    ! if (iprint_basis>=3) call dump_pos_and_matrices
!       if (nspin_SF == 1) then
!          call dump_matrix("SFcoeff",    matSFcoeff(1), inode)
!       else
!          call dump_matrix("SFcoeff_up", matSFcoeff(1), inode)
!          call dump_matrix("SFcoeff_dn", matSFcoeff(2), inode)
!       end if

       diff = total_energy_last - total_energy_0
       dE_PAO = diff
       total_energy_last = total_energy_0
       if (abs(diff / total_energy_0) <= energy_tolerance) then
          if (inode == ionode) write (io_lun, 18) total_energy_0
          convergence_flag = .true.
          total_energy_last = total_energy_0
          deallocate(data_gradstore, data_paostore, STAT=stat)
          if (stat /= 0) call cq_abort("pulay_min_pao: Error dealloc mem")
          call reg_dealloc_mem(area_minE, 2*mx_pulay*length*nspin_SF, type_dbl)
          return
       end if
    end do ! n_iterations

    deallocate(data_gradstore, data_paostore, STAT=stat)
    if (stat /= 0) call cq_abort("pulay_min_pao: Error dealloc mem")
    call reg_dealloc_mem(area_minE, 2*mx_pulay*length*nspin_SF, type_dbl)

    return

! 1   format(20x,'mu = ',f10.7,'start energy = ',f15.7)
! 2   format(/20x,'Current Total Energy : ',f15.7,' a.u. ')
! 3   format(20x,'Previous Total Energy: ',f15.7,' a.u. ')
! 4   format(20x,'Difference           : ',f15.7,' a.u. ')
! 5   format(20x,'Required difference  : ',f15.7,' a.u. '/)
7   format(/20x,'------------ PAO Variation #: ',i5,' ------------',/)
18  format(///20x,'The minimisation has converged to a total energy:', &
           //20x,' Total energy = ',f15.7)

  end subroutine pulay_min_pao
  !!***

!!****f* multisiteSF_module/LFD_SCF *
!!
!!  NAME
!!   LFD_SCF
!!
!!  PURPOSE
!!   This subroutine is to update SF coefficients by LFD method using SCF density.
!!
!!   This subroutine is based on sub:line_minimise_pao in pao_minimisation.f90.
!!
!!   This subroutine is called in sub:
!!
!!  AUTHOR
!!   A.Nakata
!!  CREATION DATE
!!   2017/01/17
!!  MODIFICATION DATE
!!   2017/01/31 15:56 dave
!!    Small bug fix: changed dimension of rhototal to maxngrid
!!   2019/10/24 11:52 dave
!!    Changed function calls to FindMinDM
!!   201912/02 nakata
!!    Removed dump_matrix(SFcoeff), which will be changed to dump_pos_and_matrices in near future
!!  SOURCE
!!
  subroutine LFD_SCF(fixed_potential, vary_mu, n_cg_L_iterations, L_tolerance, &
                          sc_tolerance, expected_reduction, total_energy, rho)

    use logicals
    use numbers,            only: BIG, ten, zero
    use global_module,      only: nspin, ni_in_cell, ne_in_cell, spin_factor, nspin_SF, &
                                  area_minE, area_ops, flag_diagonalisation, iprint_basis, min_layer
    use PosTan,             only: PulayC, PulayBeta, SCC, SCBeta
    use GenComms,           only: gsum, inode, ionode, cq_abort, my_barrier
    use dimens,             only: n_my_grid_points, grid_point_volume
    use maxima_module,      only: maxngrid
    use DMMin,              only: FindMinDM
    use SelfCon,            only: new_SC_potl
    use S_matrix_module,    only: get_S_matrix
    use H_matrix_module,    only: get_H_matrix
    use mult_module,        only: LNV_matrix_multiply, mat_p, matSFcoeff, matSFcoeff_tran, &
                                  matrix_scale, matrix_transpose 
    use GenBlas,            only: dot
    use memory_module,      only: reg_alloc_mem, type_dbl, reg_dealloc_mem
    use store_matrix,       only: dump_pos_and_matrices, unit_MSSF_save
    use multisiteSF_module, only: initial_SFcoeff, LFD_max_iteration, LFD_Thresh_EnergyRise, &
                                  LFD_threshD, LFD_threshE, n_dumpSFcoeff
    use units,              only: en_conv, en_units, energy_units
    use io_module,                 only: return_prefix

    implicit none

    ! Passed variables
    logical :: fixed_potential, vary_mu
    integer :: n_cg_L_iterations
    real(double) :: L_tolerance, sc_tolerance, expected_reduction
    real(double) :: total_energy
    real(double), dimension(maxngrid,nspin) :: rho   ! = density

    ! Local variables
    logical :: reset_L, convergence_flag
    real(double), allocatable, dimension(:,:) :: data_PAO0
    real(double), allocatable, dimension(:) :: rho_total
    real(double), dimension(maxngrid,nspin) :: rho_0, resid
    real(double) :: total_energy_last, total_energy_0, diff_E, R0, tolerance, con_tolerance
    real(double), dimension(nspin) :: electrons, energy_tmp
    integer :: spin, spin_SF, iter, length, stat
    character(len=10) :: subname = "LFD_SCF:  "
    character(len=120) :: prefix

    prefix = return_prefix(subname, min_layer)
    if (inode==ionode .and. iprint_basis + min_layer >= 0) &
         write(io_lun,fmt='(/4x,a)') trim(prefix)//" Starting LFD"

    length = mat_p(matSFcoeff(1))%length

    convergence_flag = .false.

    ! Set tolerances for self-consistency and L minimisation
    con_tolerance = SCC * expected_reduction**SCBeta
    tolerance = PulayC * (0.1_double * expected_reduction)**PulayBeta
    if (con_tolerance < sc_tolerance) &
         con_tolerance = sc_tolerance
    if (con_tolerance < ten * tolerance) &
         tolerance = 0.1_double * con_tolerance
    con_tolerance = sc_tolerance

    ! initialise
    rho_0  = zero
    diff_E = BIG
    R0     = zero

    ! First, make a copy of the coefficients FOR THIS PRIMARY SET
    allocate(data_PAO0(length,nspin_SF), STAT=stat)
    if (stat /= 0) &
         call cq_abort("LFD_SCF: Error alloc mem: ", length*nspin_SF)
    call reg_alloc_mem(area_minE, length*nspin_SF, type_dbl)
    data_PAO0 = zero
    do spin_SF = 1, nspin_SF
       data_PAO0(:,spin_SF) = mat_p(matSFcoeff(spin_SF))%matrix
    enddo

    ! Copy present energy and rho
    total_energy_0 = total_energy
    do spin = 1, nspin
       rho_0(1:n_my_grid_points,spin) = rho(1:n_my_grid_points,spin)
    end do

    do iter = 1, LFD_max_iteration
       if (inode == ionode .and. iprint_basis + min_layer>=1) &
            write (io_lun, fmt='(4x,a,i3)') trim(prefix)//" LFD variation ", iter

       ! Make new multisite SF coefficients with updated density
       ! matSpao is not rebuild, matHpao is rebuild 
       call initial_SFcoeff(.false., .true., fixed_potential, .false.)

       call my_barrier

       ! Find new self-consistent energy
       if (inode==ionode .and. iprint_basis + min_layer >= 4) &
            write(io_lun,fmt='(4x,a)') trim(prefix)//' perform SC calculation.'
       ! 1. Get new S_sf matrix 
       call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
       ! 2. If we're building K as 3LSL-2LSLSL, we need to make K now
       if (.not. flag_diagonalisation) then
          call LNV_matrix_multiply(electrons, energy_tmp, doK, dontM1,&
                                   dontM2, dontM3, dontM4, dontphi, dontE)
       end if
       reset_L = .true.
       ! 3. Get a new self-consistent potential and Hamiltonian
       min_layer = min_layer - 2 ! I'm imposing two here temporarily
       ! because otherwise we get too much output from energy
       call new_SC_potl(.false., con_tolerance, reset_L,             &
                        fixed_potential, vary_mu, n_cg_L_iterations, &
                        tolerance, total_energy_last)
       min_layer = min_layer + 2

       ! Check convergency by energy (diff_E) and density (R0)
       ! energy
       dE_PAO = total_energy_last - total_energy_0
       diff_E = (total_energy_last - total_energy_0) / ni_in_cell
       ! density
       resid = zero
       do spin = 1, nspin
          resid(1:n_my_grid_points,spin) = rho(1:n_my_grid_points,spin) &
                                         - rho_0(1:n_my_grid_points,spin)
       end do
       R0 = zero
       do spin = 1, nspin
          R0 = R0 + spin_factor * &
               dot(n_my_grid_points, resid(:,spin), 1, resid(:,spin), 1)
       end do
       ! cross term
       ! R0 = R0 + two * &
       !      dot(n_my_grid_points, resid(:,1), 1, resid(:,nspin), 1)
       call gsum(R0)
       R0 = sqrt(grid_point_volume * R0) / ne_in_cell

       if (diff_E.gt.zero .and. inode==ionode .and. iprint_basis + min_layer>=1) &
            write(io_lun,'(4x,A,f15.7,A,i3)') &
            trim(prefix)//' Energy rose by ', diff_E, ' at iteration # ',iter 
       if (inode == ionode .and. iprint_basis + min_layer>=0) &
            write(io_lun,'(4x,A,I3,2(3X,A,F17.10,1x,A2),(3X,A,F17.10)/)') &
            trim(prefix)//' iter =',iter, &
            'Total energy =',total_energy_last*en_conv,en_units(energy_units), &
            'diff_E=',diff_E*en_conv,en_units(energy_units),'R0 =',R0

       if (ABS(diff_E).le.LFD_threshE) then
          ! Energy converged
          convergence_flag = .true.
          total_energy = total_energy_last
          if (inode==ionode .and. iprint_basis + min_layer >= -1) &
               write(io_lun,fmt='(/4x,a,f15.7,a2,a,i3,a)') &
               trim(prefix)//" LFD converged to ", total_energy*en_conv, &
               en_units(energy_units)," after ",iter," iterations"
       else if (R0.le.LFD_threshD) then
          ! Density converged
          convergence_flag = .true.
          total_energy = total_energy_last
          if (inode==ionode .and. iprint_basis + min_layer >=-1) &
               write(io_lun,fmt='(/4x,a,f15.7,a2,a,i3,a)') &
               trim(prefix)//" LFD converged to ", total_energy*en_conv, &
               en_units(energy_units)," after ",iter," iterations"
       else if (diff_E.gt.zero .and. ABS(diff_E).le.LFD_Thresh_EnergyRise) then
          ! Energy rises so finish iteration with the previous SF coefficients and density
          convergence_flag = .true.
          total_energy = total_energy_0
          do spin_SF = 1, nspin_SF
             mat_p(matSFcoeff(spin_SF))%matrix = data_PAO0(:,spin_SF)
             call matrix_scale(zero,matSFcoeff_tran(spin_SF))
             call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
          enddo
          do spin = 1, nspin
             rho(1:n_my_grid_points,spin) = rho_0(1:n_my_grid_points,spin)
          enddo
          if (inode==ionode .and. iprint_basis + min_layer >=0) then
             write(io_lun,'(4x,A,f15.7,1x,A2,A,i3,a)') &
                  trim(prefix)//' Energy rose by ', diff_E*en_conv,en_units(energy_units), &
                  ' at iteration # ', iter, ' Returning to previous iteration'
             write(io_lun,'(4x,A,i3)') &
                  trim(prefix)//&
                  &' SF coefficients and density are returned to those at previous iteration # ', &
                  iter-1
             write(io_lun,'(4x,A,f15.7,1x,A2)') &
                  trim(prefix)//' Total energy = ',total_energy*en_conv,en_units(energy_units)
          end if
          ! Reconstruct S, H and K with previous density 
          call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
          call get_H_matrix(.false., fixed_potential, electrons, &
                            rho, maxngrid)
          call FindMinDM(n_cg_L_iterations, vary_mu, L_tolerance, &
                         reset_L, .false.)
       else 
          ! Save present energy and density
          total_energy   = total_energy_last
          total_energy_0 = total_energy_last
          do spin = 1, nspin
             rho_0(1:n_my_grid_points,spin) = rho(1:n_my_grid_points,spin)
          end do
          do spin_SF = 1, nspin_SF
             data_PAO0(:,spin_SF) = mat_p(matSFcoeff(spin_SF))%matrix
          end do
          if (inode==ionode .and. iprint_basis + min_layer >2) &
               write(io_lun,'(/4x,A,i5)') &
               trim(prefix)//' Save SF coefficients at iteration # ',iter
       endif

       ! Write out current SF coefficients and density matrices with some iprint (in future)
       if(n_dumpSFcoeff > 0 ) then
          if(mod(iter,n_dumpSFcoeff) ==0) call dump_pos_and_matrices(index=unit_MSSF_save)
       endif
       ! Go out if converged
       if (convergence_flag) then
          deallocate(data_PAO0)
          call reg_dealloc_mem(area_minE, length*nspin_SF, type_dbl)
          return
       endif
    enddo ! iter

    if (inode==ionode) write(io_lun,'(4x,A,I3,A)') &
         trim(prefix)//' Not converged after ',LFD_max_iteration,' iterations.'
    deallocate(data_PAO0)

    call reg_dealloc_mem(area_minE, length*nspin_SF, type_dbl)
    !
    return
    !
  end subroutine LFD_SCF
  !!***

  !!****f* pao_minimisation/line_minimise_pao *
  !!
  !!  NAME 
  !!   line_minimise_pao
  !!  USAGE
  !! 
  !!  PURPOSE
  !!   Performs a line minimisation on the support functions
  !!  INPUTS
  !! 
  !! 
  !!  USES
  !!   atoms, pao_grid_transform_module, pao,
  !!   calc_matrix_elements_module, common, datatypes, DiagModule,
  !!   dimens, GenBlas, GenComms, logicals, matrix_data, maxima_module,
  !!   mult_module, numbers, SelfCon, set_bucket_module, S_matrix_module
  !!  AUTHOR
  !!   D.R.Bowler
  !!  CREATION DATE
  !!   13/01/98
  !!  MODIFICATION HISTORY
  !!   18/05/2001 dave
  !!    ROBODoc header, changed new_SC_potl call
  !!   24/05/2001 dave
  !!    Shortened call to get_pao_gradient
  !!    Shortened subroutine call
  !!   25/05/2001 dave
  !!    Used get_S_matrix from S_matrix_module
  !!   11/06/2001 dave
  !!    Added RCS Id and Log tags and GenComms dependencies
  !!   17/06/2002 dave
  !!    Added flag to only get K if OrderN solution method is used (and
  !!    tweaked headers)
  !!   31/07/2002 dave
  !!    Changed to use data_M12 from matrix_data and not pass to
  !!    subsidiary routines
  !!   13:52, 04/02/2003 drb 
  !!    Further changes related to diagonalisation (where M12 comes from
  !!    etc)
  !!   09:20, 2003/03/24 dave
  !!    Included in pao_minimisation
  !!   08:29, 2003/04/03 dave
  !!    Changed to use pao_gradient for get_pao_gradient and
  !!    get_electron_gradient
  !!   09:14, 2003/04/10 dave
  !!    Completely rewrote in a more transparent way (closely based on
  !!    safemin in move_atoms.module)
  !!   2008/05/25 ast
  !!    Added timers
  !!   2011/12/06 L.Tong
  !!    - Added spin polarisation
  !!    - Added registration for memory usage
  !!    - changed sum to summ to avoid potential confusion with
  !!      intrinsic function of the same name
  !!    - removed redundant parameter number_of_bands
  !!    - removed module global dependence on matM12 and matM4, not used
  !!      in the subroutine
  !!   2012/03/24 L.Tong
  !!   - Changed spin implementation
  !!   - removed redundant input parameter real(double) mu
  !!   2012/06/18 L.Tong
  !!   - removed unused variable k0
  !!   2016/07/29 18:30 nakata
  !!    Renamed supports_on_atom -> blips_on_atom
  !!   2016/12/19 18:15 nakata
  !!    Removed unused flag_vary_basis
  !!   2017/02/23 dave
  !!    - Changing location of diagon flag from DiagModule to global and name to flag_diagonalisation
  !!  SOURCE
  !!
  subroutine line_minimise_pao(search_direction, fixed_potential,     &
                               vary_mu, n_cg_L_iterations, tolerance, &
                               con_tolerance, total_energy_0,         &
                               expected_reduction, last_step,         &
                               g_dot_sd)

    use datatypes
    use numbers
    use logicals
    use mult_module,         only: LNV_matrix_multiply, mat_p,        &
                                   matSFcoeff, matSFcoeff_tran,       &
                                   matrix_scale, matrix_transpose
    use GenBlas,             only: copy, axpy, dot
    use SelfCon,             only: new_SC_potl
    use S_matrix_module,     only: get_S_matrix
    use GenComms,            only: gsum, my_barrier, cq_abort, inode, &
                                   ionode
    use global_module,       only: ni_in_cell,                        &
         area_minE, nspin, nspin_SF, flag_diagonalisation, &
         iprint_minE, min_layer
    use primary_module,      only: bundle
    use memory_module,       only: reg_alloc_mem, reg_dealloc_mem,    &
                                   type_dbl
    use multisiteSF_module,  only: normalise_SFcoeff
    use units,                     only: en_conv, en_units, energy_units
    use io_module,                 only: return_prefix

    implicit none

    ! Passed variables
    logical      :: vary_mu, fixed_potential, reset_L
    integer      :: n_cg_L_iterations
    real(double) :: tolerance, con_tolerance
    real(double) :: total_energy_0
    real(double) :: expected_reduction, last_step
    real(double), dimension(:)   :: g_dot_sd
    real(double), dimension(:,:) :: search_direction

    ! Local variables
    integer      :: length, n_atoms, stat
    integer      :: i, iter, spin_SF
    real(double) :: k1, k2, k3, kmin, lambda
    real(double) :: e0, e1, e2, e3, energy_out
    real(double), dimension(nspin_SF) :: tmp
    real(double), dimension(:,:), allocatable :: data_PAO0
    real(double), dimension(nspin)            :: electrons, energy_tmp
    ! real(double), dimension(:), allocatable :: data_PAO
    ! real(double), dimension(:), allocatable :: data_full
    logical :: done = .false. ! flag of line minimisation
    real(double), save :: kmin_last = zero
    real(double), save :: dE = zero ! Use this to guess initial step ?
    character(len=14) :: subname = "line_min_pao: "
    character(len=120) :: prefix

    !min_layer = min_layer - 1
    prefix = return_prefix(subname, min_layer)
    if (inode == ionode .and. iprint_minE + min_layer >= 1) &
         write (io_lun, fmt='(4x,a,f15.7,a2)') trim(prefix)//' On entry to pao line_min, dE is ', &
                           dE*en_conv, en_units(energy_units)

    n_atoms = bundle%n_prim
    length = mat_p(matSFcoeff(1))%length
    do spin_SF = 1, nspin_SF
       tmp(spin_SF) = dot(length, search_direction(:,spin_SF), 1, search_direction(:,spin_SF), 1)
       call gsum(tmp(spin_SF))
       ! search_direction(:,spin_SF) = search_direction(:,spin_SF) / sqrt(tmp(spin_SF))
       if (inode == ionode .and. iprint_minE + min_layer >= 2) &
            write (io_lun, fmt='(4x,a,f15.7)') trim(prefix)//' Searchdir: ', tmp(spin_SF)
    enddo

    ! if (nspin_SF == 1) then
    !    call dump_matrix("SFcoeff",    matSFcoeff(1), inode)
    ! else
    !    call dump_matrix("SFcoeff_up", matSFcoeff(1), inode)
    !    call dump_matrix("SFcoeff_dn", matSFcoeff(2), inode)
    ! end if

    ! First, make a copy of the coefficients FOR THIS PRIMARY SET
    allocate(data_PAO0(length,nspin_SF), STAT=stat)    
    if (stat /= 0) &
         call cq_abort("line_minimise_pao: Error alloc mem: ", length*nspin_SF)
    call reg_alloc_mem(area_minE, length*nspin_SF, type_dbl)
    do spin_SF = 1, nspin_SF
       data_PAO0(:,spin_SF) = mat_p(matSFcoeff(spin_SF))%matrix
    enddo

    ! We're assuming that we've ALREADY gone to a self-consistent
    ! ground state before arriving here
    iter = 1
    k1 = zero
    e1 = total_energy_0
    k2 = zero
    e2 = total_energy_0
    e3 = e2
    lambda = two

    ! Loop to find a bracketing triplet
    if (dE == zero .or. kmin_last == zero) then
      k3 = InitStep_paomin
    else
      !k3=0.5_double*dE/g_dot_sd
      k3 = kmin_last
    end if

    done = .false.
    do while (.not. done)
       do spin_SF = 1, nspin_SF
          call copy(length, data_PAO0(:,spin_SF), 1, mat_p(matSFcoeff(spin_SF))%matrix, 1)
          call axpy(length, k3, search_direction(:,spin_SF), 1, mat_p(matSFcoeff(spin_SF))%matrix, 1 )
       enddo
       ! Normalise
       call normalise_SFcoeff
       do spin_SF = 1,nspin_SF
          call matrix_scale(zero,matSFcoeff_tran(spin_SF))
          call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
       enddo

       ! Find new self-consistent energy 
       ! 1. Get new S matrix
       call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
       ! 2. If we're building K as 3LSL-2LSLSL, we need to make K now
       if (.not. flag_diagonalisation) then
          call LNV_matrix_multiply(electrons, energy_tmp, doK, dontM1,&
                                   dontM2, dontM3, dontM4, dontphi, dontE)
       end if
       reset_L = .false. !true.
       ! 3. Get a new self-consistent potential and Hamiltonian
       ! I've not put a call to get_H_matrix here because it's
       ! currently in new_SC_potl
       min_layer = min_layer - 1
       call new_SC_potl(.false., con_tolerance, reset_L,             &
                        fixed_potential, vary_mu, n_cg_L_iterations, &
                        tolerance, e3)
       min_layer = min_layer + 1
       if (inode == ionode .and. iprint_minE + min_layer >= 2) &
            write (io_lun, &
                   fmt='(4x,a,i3," &
                        &step and energy are ",f15.10,f25.10)') &
                  trim(prefix)//" In pao_min, iter ",iter, k3, e3
       if (inode == ionode .and. iprint_minE + min_layer >= 2) &
            write (io_lun, &
                   fmt='(4x,a, i3," k1, k2, k3, &
                        &= ", 3f15.8)') &
                        trim(prefix)//" iter=",iter, k1, k2, k3
       if (e3 < e2) then ! We're still going down hill
          k1 = k2
          e1 = e2
          k2 = k3
          e2 = e3
          k3 = k3 * lambda  
          iter = iter + 1
       else if (k2 == zero) then
          k3 = k3 / lambda
       else
          done = .true.
       end if
       if (k3 < very_small) &
            call cq_abort('Step too small: line_minimise_pao failed!')
    end do

    ! Turn  basis variation back on
    ! Interpolate to find minimum.
    kmin = half * (((k1 * k1 - k3 * k3) * (e1 - e2) - &
                    (k1 * k1 - k2 * k2) * (e1 - e3)) / &
                   ((k1 - k3) * (e1 - e2) - (k1 - k2) * (e1 - e3)))
    kmin_last = kmin
    if (inode == ionode .and. iprint_minE + min_layer >= 2) &
         write (io_lun, fmt='(4x,a,4f15.7)') &
         trim(prefix)//' In pao_min, bracketed - min from extrap: ', &
                           k1, k2, k3, kmin
    if (inode == ionode .and. iprint_minE + min_layer >= 2) &
         write (io_lun, fmt='(4x,a,3f15.7)') trim(prefix)//' In pao_min, bracketed - energies: ', &
                           e1, e2, e3

    ! Change blips: start from blip0
    do spin_SF = 1, nspin_SF
       call copy(length, data_PAO0(:,spin_SF), 1, mat_p(matSFcoeff(spin_SF))%matrix, 1)
       call axpy(length, kmin, search_direction(:,spin_SF), 1, mat_p(matSFcoeff(spin_SF))%matrix, 1)
    enddo
    call normalise_SFcoeff
    do spin_SF = 1,nspin_SF
       call matrix_scale(zero,matSFcoeff_tran(spin_SF))
       call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
    enddo
    iter = iter + 1

    ! Find new self-consistent energy 
    ! 1. Get new S matrix
    call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
    ! 2. If we're building K as 3LSL-2LSLSL, we need to make K now
    if (.not. flag_diagonalisation) then
       call LNV_matrix_multiply(electrons, energy_tmp, doK, dontM1, &
                                dontM2, dontM3, dontM4, dontphi, dontE)
    end if
    reset_L = .false. !true.
    ! 3. Get a new self-consistent potential and Hamiltonian
    ! I've not put a call to get_H_matrix here because it's currently
    ! in new_SC_potl
    min_layer = min_layer - 1
    call new_SC_potl(.false., con_tolerance, reset_L, fixed_potential,&
                     vary_mu, n_cg_L_iterations, tolerance, energy_out)
    min_layer = min_layer + 1

    ! If the interpolation failed, go back to the previous "minimum"
    if (energy_out > e2) then 
       kmin = k2
       do spin_SF = 1, nspin_SF
          call copy(length, data_PAO0(:,spin_SF), 1, mat_p(matSFcoeff(spin_SF))%matrix, 1)
          call axpy(length, kmin, search_direction(:,spin_SF), 1, &
                    mat_p(matSFcoeff(spin_SF))%matrix, 1)
       enddo
       call normalise_SFcoeff
       do spin_SF = 1,nspin_SF
          call matrix_scale(zero,matSFcoeff_tran(spin_SF))
          call matrix_transpose(matSFcoeff(spin_SF), matSFcoeff_tran(spin_SF))
       enddo
       iter = iter + 1

       ! Find new self-consistent energy 
       ! 1. Get new S matrix
       call get_S_matrix(inode, ionode, build_AtomF_matrix=.false.)
       ! 2. If we're building K as 3LSL-2LSLSL, we need to make K now
       if (.not. flag_diagonalisation) then
          call LNV_matrix_multiply(electrons, energy_tmp, doK, dontM1,&
                                   dontM2, dontM3, dontM4, dontphi, dontE)
       end if
       reset_L = .false. !true.
       ! 3. Get a new self-consistent potential and Hamiltonian
       min_layer = min_layer - 1
       call new_SC_potl(.false., con_tolerance, reset_L,             &
                        fixed_potential, vary_mu, n_cg_L_iterations, &
                        tolerance, energy_out)
       min_layer = min_layer + 1
    end if
    if (inode == ionode .and. iprint_minE + min_layer >= 0) &
         write(io_lun, fmt='(4x,a,i3,a)') trim(prefix)//" Found minimum after ",iter," iterations"
    if (inode == ionode .and. iprint_minE + min_layer >= 2) &
         write (io_lun, fmt='(4x,a,f25.10,x,a2)') &
         trim(prefix)//" At exit energy is ",energy_out*en_conv,en_units(energy_units)
    dE = total_energy_0 - energy_out
    if (inode == ionode .and. iprint_minE + min_layer >= 2) &
         write (io_lun, fmt='(4x,a,f25.10,2f25.10,x,a2)') &
         trim(prefix)//" On exit, dE is ",dE*en_conv, &
         total_energy_0*en_conv, energy_out*en_conv,en_units(energy_units)
    total_energy_0 = energy_out

    deallocate(data_PAO0, STAT=stat)
    if (stat /= 0) call cq_abort("line_minimise_pao: Error dealloc mem")
    call reg_dealloc_mem(area_minE, length*nspin_SF, type_dbl)
    !min_layer = min_layer + 1

    return
  end subroutine line_minimise_pao
  !!***


  !!****f* pao_minimisation/build_PAO_coeff_grad *
  !!
  !!  NAME 
  !!   build_PAO_coeff_grad
  !!  USAGE
  !! 
  !!  PURPOSE
  !!   Builds the gradient of energy wrt PAO coefficients
  !!  INPUTS
  !!   flag: if 1, do G.dS, if 2 do K.dH, if 3 do both.
  !! 
  !!   The gradient is calculated for atoms in this processor's primary set by matrix multuplications
  !!       dM/dC(sf_i,pao_k) = sum_l,j {A(sf_i,sf_j) * M(pao_k,pao_l) * C(pao_l,sf_j)} * factor
  !!                         = sum_j   {A(sf_i,sf_j) * M(pao_k,sf_j)} * factor
  !!       where i = primary atom
  !!             k = neighbour of atom i in MSrange (so that i and k are not always in the same node)
  !!             A = M12, M4 or K
  !!             M = S       or H
  !!             C = SFcoeff
  !!
  !!  USES
  !! 
  !!  AUTHOR
  !!   D.R.Bowler
  !!  CREATION DATE
  !!   2004 sometime
  !!  MODIFICATION HISTORY
  !!   2006/06/21 08:18 dave
  !!    Changed for variable NSF and new basis storage scheme
  !!   2008/05/25 ast
  !!    Added timers
  !!   2011/12/05 L.Tong
  !!   - Added spin polarisation
  !!   - Changed temporary array sum to summ, to avoid confusion with
  !!      intrinsic function sum
  !!   2012/03/24 L.Tong
  !!   - Changed spin implementation
  !!   - Note that now matM4(1) stores spin up channel only even for
  !!     spin non-polarised caluclations, hence requires a spin_factor
  !!     correction when accumulating its contribution to the
  !!     coefficients
  !!   2016/11/16 nakata
  !!   - Changed how to calculate gradients
  !!   - Done by matrix multiplications as A(sf,sf) * (M(paof,paof) * C(paof,sf))^T
  !!    (This can be done also as C(sf,paof) * A(sf,sf) * M(paof,paof))
  !!    (Previously, since we stored coefficients for ALL atoms locally (shown by the
  !!     flag_paos_atoms_in_cell), we needed to do a gsum at the end (having stored
  !!     the coefficients for each primary atom in the appropriate part of the array)
  !!   2017/02/23 dave
  !!    - Changing location of diagon flag from DiagModule to global and name to flag_diagonalisation
  !!  SOURCE
  !!
  subroutine build_PAO_coeff_grad(flag)

    use datatypes
    use logicals
    use numbers
    use matrix_data,         only: aSs_range, aHs_range
    use mult_module,         only: LNV_matrix_multiply, matM12, matM4, &
                                   matK, matHatomf, matSatomf,         &
                                   matSFcoeff_tran,                    &
                                   matdSFcoeff, matdSFcoeff_e,         &
                                   matrix_scale, matrix_product,       &
                                   matrix_sum,                         &
                                   mult, aSs_trans, aHs_trans,         &
                                   aSa_sCaTr_aSs, sSs_sSa_sCa,         &
                                   aHa_sCaTr_aHs, sHs_sHa_sCa,         &
                                   allocate_temp_matrix, free_temp_matrix
    use global_module,       only: nspin, spin_factor, atomf, sf,      &
                                   flag_SpinDependentSF, flag_diagonalisation

    ! Passed variables
    integer :: flag

    ! Local variables
    integer      :: spin, spin_SF, mat_tmpS, mat_tmpH
    real(double), dimension(nspin) :: e1, e2

    
    if (.not. flag_diagonalisation) then
       ! e1 and e2 are not used, just used for dumping the electron
       ! numbers and energies
       call LNV_matrix_multiply(e1, e2, doK, doM1, doM2, dontM3, doM4,&
                                dontphi, dontE, mat_M12=matM12,       &
                                mat_M4=matM4)
    end if

    ! We should have the elements built by H_matrix_module and
    ! S_matrix_module Now we take the sum over j\beta (nsf2 = \beta;
    ! neigh = j)

    call start_timer(tmr_std_matrices)

    if (flag == KdH .or. flag == full) then
       mat_tmpH     = allocate_temp_matrix(aHs_range,aHs_trans,atomf,sf)
       spin_SF = 1
       do spin = 1, nspin
          if (flag_SpinDependentSF) spin_SF = spin
          ! dH = H(paof,sf)
          call matrix_scale(zero,mat_tmpH)
          call matrix_product(matHatomf(spin), matSFcoeff_tran(spin_SF), mat_tmpH, mult(aHa_sCaTr_aHs))
!         tmpH(paof,sf) will be transposed to (sf,paof) in matrix_product with mult_type=2
!         so we don't have to take transpose here.
          !call matrix_transpose(mat_tmpH,mat_tmpHtran)
          ! First do K.dH
          call matrix_product(matK(spin), mat_tmpH, matdSFcoeff(spin_SF), mult(sHs_sHa_sCa))
       enddo ! spin
       call free_temp_matrix(mat_tmpH)
    endif

    if (flag == GdS .or. flag == full .or. .not.flag_diagonalisation) then
       mat_tmpS     = allocate_temp_matrix(aSs_range,aSs_trans,atomf,sf)
       spin_SF = 1 ! spin of coefficients
       do spin = 1, nspin
          if (flag_SpinDependentSF) spin_SF = spin
          ! dS = S(paof,sf)
          if (spin.eq.spin_SF) then
             call matrix_scale(zero,mat_tmpS)
             call matrix_product(matSatomf, matSFcoeff_tran(spin_SF), mat_tmpS, mult(aSa_sCaTr_aSs))
             !call matrix_transpose(mat_tmpS,mat_tmpStran)
          endif
          ! Now do G.dS
          if (flag == GdS) then
             call matrix_product(matM12(spin), mat_tmpS, matdSFcoeff(spin_SF), mult(sSs_sSa_sCa))
          else if (flag == full) then
             call matrix_product(matM12(spin), mat_tmpS, matdSFcoeff_e(spin_SF), mult(sSs_sSa_sCa)) ! once save in matdSFcoeff_e
             call matrix_sum(one, matdSFcoeff(spin_SF), one, matdSFcoeff_e(spin_SF))                ! sum up with K.dH
          endif
          ! Electron gradient
          if (.not. flag_diagonalisation) then
             ! No problems with electron number when diagonalising
             call matrix_product(matM4(spin), mat_tmpS, matdSFcoeff_e(spin_SF), mult(sSs_sSa_sCa))
          endif
       enddo ! spin
       call free_temp_matrix(mat_tmpS)
    endif

    call matrix_scale(-two*spin_factor, matdSFcoeff(spin_SF)) ! -2*spin_factor
    if (.not. flag_diagonalisation) call matrix_scale(-spin_factor, matdSFcoeff_e(spin_SF)) ! -spin_factor

    call stop_timer(tmr_std_matrices)

    return
  end subroutine build_PAO_coeff_grad
  !*****

                   !*** Test gradients ***!
                   ! Shift coefficient
                   !if(inode==ionode) tmp = 0.001_double*blips_on_atom(bundle%ig_prim(iprim))%supp_func(nsf1)%coefficients(npao1)
                   ! blips_on_atom(bundle%ig_prim(iprim))%supp_func(nsf1)%coefficients(npao1) = &
                   !      blips_on_atom(bundle%ig_prim(iprim))%supp_func(nsf1)%coefficients(npao1) + tmp
                   !write(io_lun,*) 'On this proc, global(iprim) is ',iprim,bundle%ig_prim(iprim)
                   !%%!  tmp = 0.001_double*blips_on_atom(1)%supp_func(nsf1)%coefficients(npao1)
                   !%%!  blips_on_atom(1)%supp_func(nsf1)%coefficients(npao1) = &
                   !%%!       blips_on_atom(1)%supp_func(nsf1)%coefficients(npao1) + tmp
                   !%%!  ! Get gradient
                   !%%!  ! 1. Generate data_dS
                   !%%!  call get_S_matrix(support, inode, ionode, ntwof, SUPPORT_SIZE)
                   !%%!  ! 3. Generate data_dH
                   !%%!  call PAO_to_grid(inode-1,support,ntwof,SUPPORT_SIZE)
                   !%%!  call get_H_matrix( iprint_minE, .true., fixed_potential, &
                   !%%!       total_energy_test, electrons, ewald_energy, core_correction, &
                   !%%!       potential, density, pseudopotential, &
                   !%%!       support, workspace_support, inode, ionode, &
                   !%%!       N_GRID_MAX, ntwof, SUPPORT_SIZE)
                   !%%!  call FindMinDM(n_cg_L_iterations, number_of_bands, vary_mu, &
                   !%%!       L_tolerance, mu, inode, ionode, .false., .false.)
                   !%%!  call get_energy(E2, core_correction, ewald_energy)
                   !%%!  !call new_SC_potl( .false., con_tolerance, &
                   !%%!  !     reset_L, fixed_potential, vary_mu, n_cg_L_iterations, &
                   !%%!  !     number_of_bands, tolerance, mu,&
                   !%%!  !     E2, ewald_energy, core_correction,&
                   !%%!  !     potential, pseudopotential, density,&
                   !%%!  !     support, workspace_support, workspace2_support,&
                   !%%!  !     inode, ionode,&
                   !%%!  !     N_GRID_MAX, ntwof, SUPPORT_SIZE)
                   !%%!  gradient(npao1,nsf1,iprim) = zero
                   !%%!  point = mat(part,Srange)%offset+mat(part,Srange)%i_acc(memb)
                   !%%!  sum = dot(nsf*mat(part,Srange)%n_nab(memb),data_M12(nsf1,1:,point:),1,data_dS(npao1,1:,point:),1)
                   !%%!  gradient(npao1,nsf1,iprim) = gradient(npao1,nsf1,iprim) + four*sum
                   !%%!  !tmpgrad = four*sum
                   !%%!  point = mat(part,Hrange)%offset+mat(part,Hrange)%i_acc(memb)
                   !%%!  sum = dot(nsf*mat(part,Hrange)%n_nab(memb),data_K(nsf1,1:,point:),1,data_dH(npao1,1:,point:),1)
                   !%%!  gradient(npao1,nsf1,iprim) = gradient(npao1,nsf1,iprim) + four*sum
                   !%%!  !H2 = data_H(nsf1,npao,point)
                   !%%!  !H2a = data_H(nsf1,3,point)
                   !%%!  !E2 = nl_energy
                   !%%!  !BE2 = band_energy
                   !%%!  tmpgrad = gradient(npao1,nsf1,iprim)
                   !%%!  ! Shift coefficient
                   !%%!  !blips_on_atom(bundle%ig_prim(iprim))%supp_func(nsf1)%coefficients(npao1) = &
                   !%%!  !     blips_on_atom(bundle%ig_prim(iprim))%supp_func(nsf1)%coefficients(npao1) - tmp
                   !%%!  blips_on_atom(1)%supp_func(nsf1)%coefficients(npao1) = &
                   !%%!       blips_on_atom(1)%supp_func(nsf1)%coefficients(npao1) - tmp
                   !%%!  ! Get gradient
                   !%%!  ! 1. Generate data_dS
                   !%%!  call get_S_matrix(support, inode, ionode, ntwof, SUPPORT_SIZE)
                   !%%!  ! 3. Generate data_dH
                   !%%!  call PAO_to_grid(inode-1,support,ntwof,SUPPORT_SIZE)
                   !%%!  call get_H_matrix( iprint_minE, .true., fixed_potential, &
                   !%%!       total_energy_test, electrons, ewald_energy, core_correction, &
                   !%%!       potential, density, pseudopotential, &
                   !%%!       support, workspace_support, inode, ionode, &
                   !%%!       N_GRID_MAX, ntwof, SUPPORT_SIZE)
                   !%%!  call FindMinDM(n_cg_L_iterations, number_of_bands, vary_mu, &
                   !%%!       L_tolerance, mu, inode, ionode, .false., .false.)
                   !%%!  call get_energy(E1, core_correction, ewald_energy)
                   !%%!  !call new_SC_potl( .false., con_tolerance, &
                   !%%!  !     reset_L, fixed_potential, vary_mu, n_cg_L_iterations, &
                   !%%!  !     number_of_bands, tolerance, mu,&
                   !%%!  !     E1, ewald_energy, core_correction,&
                   !%%!  !     potential, pseudopotential, density,&
                   !%%!  !     support, workspace_support, workspace2_support,&
                   !%%!  !     inode, ionode,&
                   !%%!  !     N_GRID_MAX, ntwof, SUPPORT_SIZE)
                   !write(io_lun,*) 'Numerical, analytic grad: ',(E2-E1)/tmp, 0.5_double*(tmpgrad+gradient(npao1,nsf1,iprim))
                   ! BE1 = band_energy
                   !%%! H1 = data_H(nsf1,1,point)
                   !%%! H1a = data_H(nsf1,3,point)
                   !%%! E1 = nl_energy
                   !write(io_lun,*) 'Numerical, analytic grad: ',(BE2-BE1)/tmp, 0.5_double*(tmpgrad+four*sum)
                   !write(io_lun,*) 'Numerical, analytic grad: ',(E2-E1)/tmp, 0.5_double*(tmpgrad+gradient(npao1,nsf1,iprim))
                   !%%! write(io_lun,*) 'M Numerical, analytic: ',(H2-H1)/tmp,data_dH(npao1,1,point)
                   !%%! write(io_lun\,*) 'M Numerical, analytic: ',(H2a-H1a)/tmp,data_dH(npao1,3,point)
                   !sum = dot(nsf*mat(part,Srange)%n_nab(memb),data_K(nsf1,1:,point:),1,data_dC_NL(npao1,1,point),1)
                   !gradient(npao1,nsf1,iprim) = gradient(npao1,nsf1,iprim) + sum
                   !sum = dot(nsf*mat(part,Srange)%n_nab(memb),data_K(nsf1,1:,point:),1,data_dHloc(npao1,1,point),1)
                   !gradient(npao1,nsf1,iprim) = gradient(npao1,nsf1,iprim) + sum

end module pao_minimisation
