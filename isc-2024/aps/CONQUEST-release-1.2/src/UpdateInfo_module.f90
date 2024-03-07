!!****h* Conquest/UpdateInfo
!!  NAME
!!   UpdateInfo
!!  PURPOSE
!!   Reads files, performs communication and reconstructs matrices.
!!   The following subroutines are applicable not only to L-matrix
!!   but also to any sort of matrices.
!!  AUTHOR
!!   Michiaki Arita
!!  CREATION DATE
!!   2013/08/22
!!  MODIFICATION HISTORY
!!   2018/Sep/08 tsuyoshi
!!    Added the check for the consistency of the orbitals between the present matrix 
!!    and the one read from the file.
!!    Also added the subroutine ReportMatrixUpdate to check the missing pairs.
!!   2018/10/03 17:10 dave
!!    Changing MPI tags to conform to standard
!!   2019/09/02 tsuyoshi
!!    added nspin in the member of Lmatrix_comm_send and Lmatrix_comm_recv,
!!    and removed n_matrix
!!   2019/11/27 08:11 dave
!!    Tidying source
!!  SOURCE
!!  
module UpdateInfo

  use datatypes
  use global_module, ONLY: flag_MDdebug,iprint_MDdebug, iprint_MD

  implicit none

  type Lmatrix_comm_send
     integer :: nspin
     integer :: natom_remote
     integer :: nrecv_node
     ! Size : 
     integer, pointer :: list_recv_node(:)
     integer, pointer :: natom_recv_node(:)
     ! Size :
     integer, pointer :: atom_ifile(:)
     integer, pointer :: atom_ia_file(:)
  end type Lmatrix_comm_send

  type Lmatrix_comm_recv
     integer :: nspin
     integer :: natom_remote
     integer :: nsend_node
     ! Size : nsend_node
     integer, pointer :: list_send_node(:)
     integer, pointer :: natom_send_node(:)
     integer, pointer :: ibeg_send_node(:)
     ! Size : natom_remote
     integer, pointer :: id_prim_recv(:)
     integer, pointer :: nalpha_prim_recv(:)
     integer, pointer :: nj_prim_recv(:)
     integer, pointer :: njbeta_prim_recv(:)
     integer, pointer :: ibeg1_recv_array(:)
     integer, pointer :: ibeg2_recv_array(:)
  end type Lmatrix_comm_recv

  ! For the report of constructing M_{ia,jb}
  !    2018/Aug/16   Tsuyoshi Miyazaki
  private :: ifile_local, iatom_local, ij_local, ij_success_local, ij_fail_local, &
       min_Rij_fail_local, max_Rij_fail_local, ave_Rij_fail_local, matrix_name
  character(4) :: matrix_name = 'Kmat'
  integer :: ifile_local       ! # of files 
  integer :: iatom_local       ! # of iatom 
  integer :: ij_local          ! # of (ij) pair
  integer :: ij_success_local  ! # of (ij) pair, whose elements are found
  integer :: ij_fail_local     ! # of (ij) pair, whose elements are not found
  real(double) :: min_Rij_fail_local, max_Rij_fail_local, ave_Rij_fail_local, sum_Rij_fail

  integer :: ifile_remote       ! # of files 
  integer :: iatom_remote       ! # of iatom 
  integer :: ij_remote          ! # of (ij) pair
  integer :: ij_success_remote  ! # of (ij) pair, whose elements are found
  integer :: ij_fail_remote     ! # of (ij) pair, whose elements are not found
  real(double) :: min_Rij_fail_remote, max_Rij_fail_remote, ave_Rij_fail_remote  

contains

  ! ------------------------------------------------------------
  ! Subroutine Matrix_CommRebuild
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/Matrix_CommRebuild *
  !!
  !!  NAME
  !!   Matrix_CommRebuild
  !!  USAGE
  !!   call Matrix_CommRebuild(InfoGlob,InfoMat,range,trans,matA,nfile,symm,n_matrix=**)
  !!  PURPOSE
  !!   Manages communication and reordering of matrix elements
  !! (CAUTION) symm can be used only for the matrices having (trans).
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2013/08/23 michi
  !!   - Replaced call for symmetrise_L with symmetrise_matA, 
  !!     and added trans and symm in dummy arguments
  !!   2014/02/03 michi
  !!   - Bug fix for serial simulations
  !!   - Bug fix for changing the number of processors at the 
  !!     sequential job
  !!   2016/04/06 dave
  !!    Changed Info to pointer from allocatable (gcc 4.4.7 issue)
  !!   2019/11/13 tsuyoshi
  !!    Spin polarized case is introduced
  !!  SOURCE
  !!
  subroutine Matrix_CommRebuild(InfoGlob,InfoMat,range,trans,matA,nfile,symm,n_matrix)

    ! Module usage
    use mpi
    use datatypes
    use numbers,       ONLY: zero
    use global_module, ONLY: io_lun,ni_in_cell,numprocs,glob2node, iprint_MD
    use GenComms,      ONLY: cq_abort,inode,ionode,gcopy,my_barrier
    use mult_module,   ONLY: symmetrise_mat
    use store_matrix,  ONLY: InfoMatrixFile, deallocate_InfoMatrixFile
    use primary_module, ONLY: bundle
    ! db
    use input_module, ONLY: io_assign,io_close
    use io_module, ONLY: get_file_name
    use group_module, ONLY: parts
    use mult_module, ONLY: mat_p
    !2019/Nov/13
    use store_matrix, ONLY: matrix_store_global

    implicit none

    ! passed variables
    type(matrix_store_global),intent(in) :: InfoGlob
    integer :: range,trans
    integer :: matA(:)    ! changed from integer to integer array
    integer,optional :: symm
    integer,optional :: n_matrix
    type(InfoMatrixFile), pointer :: InfoMat(:)

    ! local variables
    integer :: nfile,isize1,isize2
    integer :: nnd,ierr2,ierr3,stat_alloc
    integer :: nstat2(MPI_STATUS_SIZE),nstat3(MPI_STATUS_SIZE)
    integer, allocatable :: isend_array(:),isend2_array(:),irecv_array(:),irecv2_array(:)
    integer, allocatable :: nreq2(:),nreq3(:)
    real(double), allocatable :: send_array(:),recv_array(:)
    logical, allocatable :: flag_remote_iprim(:)

    type(Lmatrix_comm_send) :: LmatrixSend
    type(Lmatrix_comm_recv) :: LmatrixRecv
    ! db
    character(20) :: file_name
    character(20) :: file_name2,file_name3,file_name4, &
         file_name5,file_name6
    integer :: lun_db,lun_db2,lun_db3,lun_db4,lun_db5,lun_db6
    logical :: flag_tmp = .false.
    integer :: nspin_local

    !For Report_UpdateMatrix_Local&Remote
    iatom_local=0; ij_local=0; ij_success_local=0; ij_fail_local=0
    min_Rij_fail_local=zero; max_Rij_fail_local=zero; sum_Rij_fail=zero
    iatom_remote=0; ij_remote=0; ij_success_remote=0; ij_fail_remote=0
    min_Rij_fail_remote=zero; max_Rij_fail_remote=zero
    !For Report_UpdateMatrix_Local&Remote

    nspin_local = 1; if(present(n_matrix)) nspin_local=n_matrix
    !! --------------- DEBUG --------------- !!
    if (flag_MDdebug) then
       call get_file_name('members',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name)
       write (lun_db,*) "=== parts: ==="
       write (lun_db,*) "mx_mem_grp:", parts%mx_mem_grp
       write (lun_db,*) "nm_group:"
       write (lun_db,*) parts%nm_group(1:)
       write (lun_db,*) "icell_beg:"
       write (lun_db,*) parts%icell_beg(1:)
       write (lun_db,*) ""
       write (lun_db,*) "=== bundle: ==="
       write (lun_db,*) "mx_iprim et n_prim:"
       write (lun_db,*) bundle%mx_iprim,bundle%n_prim
       write (lun_db,*) "iprim_seq:"
       write (lun_db,*) bundle%iprim_seq(1:)
       write (lun_db,*) "ig_prim:"
       write (lun_db,*) bundle%ig_prim(1:)
       write (lun_db,*) "bundle%xprim:"
       write (lun_db,*) bundle%xprim(1:)
       write (lun_db,*) "bundle%yprim:"
       write (lun_db,*) bundle%yprim(1:)
       write (lun_db,*) "bundle%zprim:"
       write (lun_db,*) bundle%zprim(1:)
       write (lun_db,*) "bundle%species:"
       write (lun_db,*) bundle%species(:)
    endif
    !! /-------------- DEBUG --------------- !!

    ! The 1st Comunication starts.
    if (numprocs.NE.1) then ! No need for communication when using a single core.
       ! Organise local and remote atoms / Send the size info to remote nodes.
       call alloc_send_array(nfile,LmatrixSend,isend_array,isend2_array,send_array,InfoMat)
       !setting nspin
       LmatrixSend%nspin=nspin_local
       LmatrixRecv%nspin=nspin_local
       call CommMat_send_size(LmatrixSend,isend_array)
       ! Receive the size info and allocate arrays.
       call alloc_recv_array(InfoGlob, irecv_array,irecv2_array, &
            recv_array,LmatrixRecv,isize1,isize2,flag_remote_iprim)
       if (LmatrixRecv%nsend_node.GE.1) then
          allocate (nreq2(LmatrixRecv%nsend_node),nreq3(LmatrixRecv%nsend_node), STAT=stat_alloc)
          if (stat_alloc.NE.0) call cq_abort('Error allocating nreq2 and/or nreq3:', LmatrixRecv%nsend_node)
       endif
    else ! If using only one core.
       allocate (flag_remote_iprim(bundle%n_prim), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating flag_remote_iprim:', bundle%n_prim)
       flag_remote_iprim = .false.
    endif
    call my_barrier()
    if (iprint_MD > 4 .and. inode.EQ.ionode) write (io_lun,*) "Got through the 1st MPI communication !" !db

    ! Get ready for the 2nd & 3rd communication.
    if (LmatrixRecv%nsend_node.GT.0 .AND. numprocs.NE.1) then
       call CommMat_irecv_data(LmatrixRecv,irecv2_array,recv_array,nreq2,nreq3)
    endif
    !! ------------------------------ NOTE: ------------------------------- !! 
    !! If it takes a bunch of time in communication, try with the following !!
    !! statements active. The overlap of communication and calculation can  !!
    !! be expected.							    !!
    !! ------------------------------ NOTE: ------------------------------- !! 
    !! call UpdateMatrix_local(InfoMat,range,matA,flag_remote_iprim,nfile)
    if (LmatrixSend%nrecv_node.GT.0 .AND. numprocs.NE.1) then
       call CommMat_send_neigh(LmatrixSend,isend2_array,InfoMat)
       call CommMat_send_data(LmatrixSend,send_array,InfoMat)
       if (inode==ionode .and. flag_MDdebug .and. iprint_MDdebug > 3) &
            write (io_lun,*) "Finished sending neighbour & L-matrix data", inode !db
    endif
    if (LmatrixRecv%nsend_node.GT.0 .AND. numprocs.NE.1) then
       do nnd = 1, LmatrixRecv%nsend_node
          call MPI_Wait(nreq2(nnd),nstat2,ierr2)
          if (ierr2.NE.MPI_SUCCESS) call cq_abort('Error in MPI_Wait, nreq2.')
          call MPI_Wait(nreq3(nnd),nstat3,ierr3)
          if (ierr3.NE.MPI_SUCCESS) call cq_abort('Error in MPI_Wait, nreq3.')
       enddo
    endif
    if (iprint_MD > 4 .and. inode.EQ.ionode) &
         write (io_lun,*) "Got through communication! Matrix reconstruction follows next."

    !! ----- DEBUG: 12/NOV/2012 ----- !!
    if (flag_MDdebug) then 
       call io_close(lun_db)
       if (iprint_MDdebug.GT.3) then
          call get_file_name('irecv',numprocs,inode,file_name2)
          call get_file_name('irecv2',numprocs,inode,file_name3)
          call get_file_name('recv',numprocs,inode,file_name4)
          call get_file_name('B.symmetriseL',numprocs,inode,file_name5)
          call get_file_name('A.symmetriseL',numprocs,inode,file_name6)
          call io_assign(lun_db2)
          call io_assign(lun_db3)
          call io_assign(lun_db4)
          call io_assign(lun_db5)
          call io_assign(lun_db6)
          open (lun_db2,file=file_name2)
          open (lun_db3,file=file_name3)
          open (lun_db4,file=file_name4)
          open (lun_db5,file=file_name5)
          open (lun_db6,file=file_name6)
          if (allocated(irecv_array) ) write (lun_db2,*) irecv_array(1:)
          if (allocated(irecv2_array)) write (lun_db3,*) irecv2_array(1:)
          if (allocated(recv_array)  ) write (lun_db4,*) recv_array(1:)
          call io_close(lun_db2)
          call io_close(lun_db3)
          call io_close(lun_db4)
       endif
    endif
    !! /---- DEBUG: 12/NOV/2012 ----- !!

    ! Organise and reconstruct Lmatrix data only when communication occurs.
    !! ------------------------------ NOTE: ------------------------------- !! 
    !!  If UpdateMatrix_local is called above, comment out the following   !!
    !!  call statement instead.                                             !!
    !! ------------------------------ NOTE: ------------------------------- !! 
    call UpdateMatrix_local(InfoMat,range,nspin_local,matA,flag_remote_iprim,nfile)
    if (numprocs.NE.1) then
       if (LmatrixSend%nrecv_node.GT.0 .OR. LmatrixRecv%nsend_node.GT.0) then
          if (iprint_MD > 4 .and. inode.EQ.ionode) write (io_lun,*) "Reorganise remote matrix data"
          call UpdateMatrix_remote(range,nspin_local,matA,LmatrixRecv,flag_remote_iprim,irecv2_array,recv_array)
       endif
    endif
    if (flag_MDdebug .AND. iprint_MDdebug.GT.3) write (lun_db5,*) mat_p(matA(1))%matrix(1:)
    if (present(symm)) then
       if (inode.EQ.ionode.AND.iprint_MD>4) write (io_lun,*) "Symmetrisation !"
       call symmetrise_mat(range,nspin_local,trans,matA)
    endif
    call my_barrier()
    if (flag_MDdebug .AND. iprint_MDdebug.GT.3) write (lun_db6,*) mat_p(matA(1))%matrix(1:)
    if (iprint_MD > 4 .and. inode.EQ.ionode) write (io_lun,*) &
         "Got through 2nd & 3rd MPIs and symmetrising matrix !" !db

    ! Deallocation.
    if (numprocs.NE.1) then
       call deallocate_CommMatArrays(isend_array,isend2_array,send_array, &
            irecv_array,irecv2_array,recv_array, &
            LmatrixSend,LmatrixRecv)
       if (iprint_MD > 4 .and. inode.EQ.ionode) write (io_lun,*) "Deallocate CommMatArrays" !db
    else
       deallocate (flag_remote_iprim, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating flag_remote_iprim:', bundle%n_prim)
       if (iprint_MD > 4 .and. inode.EQ.ionode) write (io_lun,*) "Deallocate flag_remote_iprim" !db
    endif

    if (nfile.GT.0) then
       call deallocate_InfoMatrixFile(nfile,InfoMat)
       if (iprint_MD > 4 .and. inode.EQ.ionode) write (io_lun,*) "Deallocate arrays related to InfoMat" !db
    endif

    if (LmatrixRecv%nsend_node.GE.1 .AND. numprocs.NE.1) then
       deallocate (nreq2,nreq3, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating nreq2 and/or nreq3:', &
            LmatrixRecv%nsend_node)
    endif

    if (iprint_MD > 4 .and. inode.EQ.ionode) &
         write (io_lun,*) "Finished communication and matrix reconstruction" !db

    !! --- DEBUG: --- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.3) then
       call io_close(lun_db5)
       call io_close(lun_db6)
    endif
    !! /-- DEBUG: --- !!

    return
  end subroutine Matrix_CommRebuild
  !!***

  ! ------------------------------------------------------------
  ! Subroutine make_glob2node
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/make_glob2node *
  !!
  !!  NAME
  !!   make_glob2node
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Makes the table showing which processors atoms belong to.
  !!   Atoms are represented by global labels.
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!
  !!  SOURCE
  !!
  subroutine make_glob2node

    ! Module usage
    use global_module, ONLY: glob2node,ni_in_cell,id_glob
    use GenComms, ONLY: inode,ionode,cq_abort,gcopy
    use group_module, ONLY: parts

    implicit none

    ! local variables
    integer :: stat_alloc
    integer :: ind_part,id_node,ni,id_global
    ! db
    integer :: lun
    character(13) :: file_name = 'glob2node.dat'
    character(20) :: name

    glob2node = 0
    do ind_part = 1, parts%mx_gcell    
       id_node = parts%i_cc2node(ind_part) ! CC labeling
       if (parts%nm_group(ind_part).NE.0) then
          do ni = 1, parts%nm_group(ind_part)
             id_global = id_glob(parts%icell_beg(ind_part)+ni-1)
             glob2node(id_global) = id_node
             if (glob2node(id_global).EQ.0) &
                  call cq_abort('Error in glob2node.')
          enddo
       endif
    enddo

    return
  end subroutine make_glob2node
  !!***

  ! ------------------------------------------------------------
  ! Subroutine sort_recv_node
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/sort_recv_node *
  !!
  !!  NAME
  !!   sort_recv_node
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Performs heap-sort to decide the node order for MPI communication 
  !!   to send/receive data.
  !!   Be careful! isort_node is the ORDER of receiving nodes, NOT the node ID
  !!   itself!
  !!  INPUTS
  !!   x -> list_node_tmp:
  !!   n -> nrecv_node: no. of nodes for sending or receiving
  !!   x_order -> isort_node: order of nodes for sending or receiving
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2019/11/13 08:14 dave
  !!    Uses heapsort from functions now
  !!  SOURCE
  !!
  ! ------------------------------------------------------------
  ! Subroutine sort_recv_node
  ! ------------------------------------------------------------
  subroutine sort_recv_node(x,n,x_order,comm)

    ! Module usage
    use GenComms, ONLY: cq_abort,inode
    ! DB
    use global_module, ONLY: numprocs
    use io_module, ONLY: get_file_name
    use input_module, ONLY: io_assign,io_close
    use functions, ONLY: heapsort_integer_index

    implicit none

    ! passed variables
    integer, intent(in)  :: n
    integer, intent(in)  :: x(n) ! list_node_tmp MUST NOT be updated
    integer, intent(out) :: x_order(n)
    character(4) :: comm

    ! local variables
    integer :: i,ii,k,stat_alloc
    integer :: tmp,tmp2,min,pos,min_add
    integer, allocatable :: x_dummy(:),x_tmp(:),x_order_tmp(:)
    integer :: lun_db
    character(20) :: file_name


    ! Allocation
    allocate (x_dummy(n),x_tmp(n),x_order_tmp(n), STAT=stat_alloc)
    if (stat_alloc.NE.0) call cq_abort('Error allocating arrays in sort_recv_node:', n)

    x_dummy = x
    do i = 1, n
       x_order(i) = i
    enddo

    !! --- DEBUG: --- !!
    if (flag_MDdebug) then
       call get_file_name('sort_recv_node',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db, file=file_name, position='append')
       write (lun_db,*) "-- Called at ", comm
       write (lun_db,*) "No. of send/recv nodes  :", n
       write (lun_db,*) "init. list_node_tmp(1:n):", x(1:n)
       write (lun_db,*) "init. isort_node(1:n)   :", x_order(1:n)
    endif
    !! /-- DEBUG: --- !!

    ! KERNEL
    if (n.GT.1) then

       call heapsort_integer_index(n,x_dummy,x_order)

       ! Resort: 1. get to know the first node to be sent/received
       !         2. reorder
       min = 1000000
       pos = 0
       min_add = 0
       ! process.1
       do i = 1, n
          tmp = x_dummy(i) - inode
          if (tmp.GT.0) then
             pos = pos + 1
             if (tmp.LT.min) then
                min = tmp
                min_add = i
             endif
          endif
       enddo
       ii = 1
       if (flag_MDdebug) write (lun_db,*) "pos,min,min_add:", pos,min,min_add
       x_tmp = x_dummy
       x_order_tmp = x_order
       ! process.2
       if (min_add.NE.0) then !if there's at least one processor whose ID is larger than 'inode'
          do i = min_add, n
             x_dummy(ii) = x_tmp(i)
             x_order(ii) = x_order_tmp(i)
             ii = ii + 1
          enddo
          do i = 1, min_add-1
             x_dummy(ii)       = x_tmp(i)
             x_order(ii) = x_order_tmp(i)
             ii = ii + 1
          enddo
       endif !(min_add.NE.0)
    endif !(n.GT.1)

    !! --- DEBUG: --- !!
    if (flag_MDdebug) then
       write (lun_db,*) "list_node_tmp:", x(1:n)
       write (lun_db,*) "FINAL. list_node_tmp(dummy):", x_dummy(1:n)
       write (lun_db,*) "FINAL. isort_node          :", x_order(1:n)
       write (lun_db, *) ""
       call io_close(lun_db)
    endif
    !! /-- DEBUG: --- !!

    deallocate (x_tmp,x_order_tmp,x_dummy, STAT=stat_alloc)
    if (stat_alloc.NE.0) call cq_abort('Error deallocating arrays in sort_recv_node:', n)

    return
  end subroutine sort_recv_node
  !!***

  ! ------------------------------------------------------------
  ! Subroutine alloc_send_array
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/alloc_send_array *
  !!
  !!  NAME
  !!   alloc_send_array
  !!  USAGE
  !!
  !!  PURPOSE
  !!   This subroutine can be subdivided into five processes;
  !! 
  !!     1. Check which atom is not my primary atoms and
  !!        make a list of nodes that possess these remote atoms.
  !!     2. Prepare temporary arrays (lists) for receiving nodes.
  !!     3. Sort receiving nodes to prevent a traffic jam in communication.
  !!        To this end, receiving nodes are sorted with an ascending order 
  !!        beginning from (inode+1).
  !!     4. Group and reorder the atoms depending on the node they belong to.
  !!     5. Make three arrays sent to remote nodes.
  !!
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2014/02/03 michi
  !!   - Bug fix for changing the number of processors at the sequential job
  !!   2016/04/06 dave
  !!    Changed Info to pointer from allocatable (gcc 4.4.7 issue)
  !!  SOURCE
  !!
  subroutine alloc_send_array(nfile,LmatrixSend,isend_array,isend2_array,send_array,InfoMat)

    ! Module usage
    use numbers
    use global_module, ONLY: glob2node,numprocs
    use GenComms, ONLY: inode,cq_abort
    use store_matrix, ONLY: InfoMatrixFile, deallocate_InfoMatrixFile
    ! db
    use input_module, ONLY: io_assign,io_close
    use io_module, ONLY: get_file_name
    use global_module, ONLY: io_lun

    implicit none

    ! passed variables
    integer :: nfile
    integer, allocatable :: isend_array(:),isend2_array(:)
    real(double), allocatable :: send_array(:)

    type(Lmatrix_comm_send) :: LmatrixSend
    type(InfoMatrixFile), pointer :: InfoMat(:)

    ! local variables
    ! -- process 1. -- !
    integer :: ifile,iatom,stat_alloc
    integer :: mx_natom_total,idglob_iatom,ind_node
    integer, allocatable :: natomr_to_ifile(:),natomr_to_ia_file(:), &
         natomr_to_inode(:)
    ! -- process 2. -- !
    integer :: iatom2,nnd
    integer, allocatable :: list_node_tmp(:), natom_node_tmp(:), &
         natomr_to_nnd(:), natomr_to_iaINnode(:)
    logical :: flag_find_old
    ! -- process 3. -- !
    integer :: ind_nnd
    integer, allocatable :: ibeg_recv_node(:),isort_node(:),isort_node_inv(:)
    ! -- process 4. -- !
    integer :: iatom_send,ia,iatom_send_max
    integer, allocatable :: iatom_sort(:)
    ! -- process 5. -- !
    integer :: ibeg,ibeg2,ibeg3,ibeg4,nsize_jj,nsize_Lmatrix_remote,jj
    ! db
    integer :: lun_db,lun_db5
    character(20) :: file_name,file_name5


    !! ================================ !!
    !!            PROCESS 1.            !!
    !! ================================ !!

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       call get_file_name('process1',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name,position='append')
    endif
    !! /--------- DEBUG ---------- !!

    mx_natom_total = 0
    if (nfile.GT.0) then
       do ifile = 1, nfile
          mx_natom_total = mx_natom_total + InfoMat(ifile)%natom_i
       enddo
       if (mx_natom_total.GT.0) then
          allocate (natomr_to_ifile(mx_natom_total),natomr_to_ia_file(mx_natom_total), &
               natomr_to_inode(mx_natom_total), STAT=stat_alloc)
          if (stat_alloc.NE.0) call cq_abort('Error allocating natomr_to_ifile, &
               &natomr_to_ia_file and/or natomr_to_inode: ', &
               mx_natom_total)
          natomr_to_ifile=0 ; natomr_to_ia_file=0 ; natomr_to_inode=0
       endif

       LmatrixSend%natom_remote = 0
       do ifile = 1, nfile
          ! Loop over the whole atoms in my Lmatrix files
          do iatom = 1, InfoMat(ifile)%natom_i
             idglob_iatom = InfoMat(ifile)%idglob_i(iatom)
             ind_node = glob2node(idglob_iatom)
             if (inode.NE.ind_node) then ! If iatom is no longer my primary atom
                LmatrixSend%natom_remote = LmatrixSend%natom_remote + 1
                natomr_to_ifile(LmatrixSend%natom_remote) = ifile
                natomr_to_ia_file(LmatrixSend%natom_remote) = iatom
                natomr_to_inode(LmatrixSend%natom_remote) = ind_node    ! receiving node ID
                if (flag_MDdebug .AND. iprint_MDdebug.GT.2) &
                     write (lun_db,*) "iatom,idglob et ind_node:", iatom,idglob_iatom,ind_node   !! DB !!
             endif
          enddo
       enddo
    endif !(nfile.GT.0)

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       write (lun_db,'(a,1x,i5)') "No. of Lmat file I have (nfile):", nfile
       write (lun_db,'(a,1x,i5)') "No. of my primary atoms in Lmat files (mx_natom_total):", &
            mx_natom_total
       write (lun_db,'(a,1x,i5)') "No. of atoms which are no longer my primary atoms (natom_remote):", &
            LmatrixSend%natom_remote
       if (allocated(natomr_to_ifile))   &
            write (lun_db,*) "natomr2ifile   :", natomr_to_ifile(1:LmatrixSend%natom_remote)
       if (allocated(natomr_to_ia_file)) &
            write (lun_db,*) "natomr2ia_ifile:", natomr_to_ia_file(1:LmatrixSend%natom_remote)
       if (allocated(natomr_to_inode))   &
            write (lun_db,*) "natomr2inode   :", natomr_to_inode(1:LmatrixSend%natom_remote)
       write (lun_db,*) ""
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    !! ================================ !!
    !!            PROCESS 2.            !!
    !! ================================ !!

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       call get_file_name('process2',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name)
    endif
    !! /--------- DEBUG ---------- !!

    LmatrixSend%nrecv_node = 0
    if (LmatrixSend%natom_remote.GT.0 .AND. nfile.GT.0) then
       allocate (list_node_tmp(LmatrixSend%natom_remote) , &
            natom_node_tmp(LmatrixSend%natom_remote), &
            natomr_to_nnd(LmatrixSend%natom_remote) , & 
            natomr_to_iaINnode(LmatrixSend%natom_remote), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating arrays in process 2: ', &
            LmatrixSend%natom_remote)
       list_node_tmp=0 ; natom_node_tmp=0 ; natomr_to_nnd=0 ; natomr_to_iaINnode=0
       do iatom2 = 1, LmatrixSend%natom_remote
          ind_node = natomr_to_inode(iatom2)
          flag_find_old = .false.
          if (LmatrixSend%nrecv_node.GT.0) then
             do nnd = 1, LmatrixSend%nrecv_node
                if (ind_node.EQ.list_node_tmp(nnd)) then
                   flag_find_old = .true.
                   natom_node_tmp(nnd) = natom_node_tmp(nnd) + 1    ! # of atoms sent to 'nnd'-th node.
                   natomr_to_nnd(iatom2) = nnd                      ! node (NOT global ID) where iatom2 belongs.
                   natomr_to_iaINnode(iatom2) = natom_node_tmp(nnd) ! atom (NOT global ID) sent to 'nnd'-th N.
                endif
                if (flag_find_old) exit
             enddo
          endif !(nrecv_node.GT.0)

          if (.NOT. flag_find_old) then
             LmatrixSend%nrecv_node = LmatrixSend%nrecv_node + 1 ! No. of receiving nodes.
             list_node_tmp(LmatrixSend%nrecv_node)  = ind_node   ! list of receiving nodes.
             natom_node_tmp(LmatrixSend%nrecv_node) = 1          ! No. of atoms in list_node_tmp(:).
             natomr_to_iaINnode(iatom2) = 1
             natomr_to_nnd(iatom2)      = LmatrixSend%nrecv_node
          endif
       enddo !(iatom2, natom_remote)
    endif !(natom_remote.GT.0)

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       write (lun_db,*) "inode:", inode
       write (lun_db,*) "No. of receiving nodes(nrecv_node):", LmatrixSend%nrecv_node
       write (lun_db,*) "list_node_tmp:", list_node_tmp(1:)
       write (lun_db,*) "natom_node_tmp:", natom_node_tmp(1:)
       write (lun_db,*) "natomr_to_iaINnode:", natomr_to_iaINnode(1:)
       write (lun_db,*) "natomr_to_nnd:", natomr_to_nnd(1:)
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    !! ================================ !!
    !!            PROCESS 3.            !!
    !! ================================ !!

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       call get_file_name('process3',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name)
    endif
    !! /--------- DEBUG ---------- !!

    if (LmatrixSend%nrecv_node.GT.0) then
       allocate (ibeg_recv_node(LmatrixSend%nrecv_node),LmatrixSend%list_recv_node(LmatrixSend%nrecv_node), &
            LmatrixSend%natom_recv_node(LmatrixSend%nrecv_node),isort_node(LmatrixSend%nrecv_node), &
            isort_node_inv(LmatrixSend%nrecv_node), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating arrays in process 3: ', &
            LmatrixSend%nrecv_node)
       isort_node = 0 ; isort_node_inv = 0
       call sort_recv_node(list_node_tmp,LmatrixSend%nrecv_node,isort_node,'send')
       ibeg_recv_node(1) = 1
       do nnd = 1, LmatrixSend%nrecv_node
          ind_nnd = isort_node(nnd)       ! node ORDER (Lmatrix.XXX).
          isort_node_inv(ind_nnd) = nnd   ! node ORDER (asecending order).
          LmatrixSend%list_recv_node(nnd)  = list_node_tmp(ind_nnd)
          LmatrixSend%natom_recv_node(nnd) = natom_node_tmp(ind_nnd)
          if (nnd.GT.1) ibeg_recv_node(nnd) = ibeg_recv_node(nnd-1) + &
               LmatrixSend%natom_recv_node(nnd-1)
       enddo
    endif

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       write (lun_db,*) "inode:", inode
       write (lun_db,*) "isort_node: ", isort_node(1:LmatrixSend%nrecv_node)
       write (lun_db,*) "isort_node_inv: ", isort_node_inv(1:LmatrixSend%nrecv_node)
       write (lun_db,*) "list_recv_node: ", LmatrixSend%list_recv_node(1:LmatrixSend%nrecv_node)
       write (lun_db,*) "natom_recv_node: ", LmatrixSend%natom_recv_node(1:LmatrixSend%nrecv_node)
       write (lun_db,*) "ibeg_recv_node:", ibeg_recv_node(1:LmatrixSend%nrecv_node)
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    !! ==================================== !!
    !!            PROCESS 4 & 5.            !!
    !! ==================================== !!

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       call get_file_name('process4',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name)
    endif
    !! /--------- DEBUG ---------- !!

    if (LmatrixSend%natom_remote.GT.0 .AND. nfile.GT.0) then
       if (flag_MDdebug .AND. iprint_MDdebug.GT.2) &
            write (lun_db,*) "No. of atoms sent to other nodes:", LmatrixSend%natom_remote
       !! =============================== !!
       !!           PROCESS 4.		 !!
       !! =============================== !!
       allocate (iatom_sort(LmatrixSend%natom_remote), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating iatom_sort: ', &
            LmatrixSend%natom_remote)
       iatom_sort = 0
       allocate (LmatrixSend%atom_ifile(LmatrixSend%natom_remote), &
            LmatrixSend%atom_ia_file(LmatrixSend%natom_remote), &
            STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating atom_ifile and/or atom_ia_file: ', &
            LmatrixSend%natom_remote)
       allocate (isend_array(4*LmatrixSend%natom_remote), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating isend_array: ', 4*LmatrixSend%natom_remote)
       do iatom2 = 1, LmatrixSend%natom_remote
          ind_nnd = natomr_to_nnd(iatom2)         ! node ORDER (Lmatrix.XXX).
          nnd = isort_node_inv(ind_nnd)           ! node ORDER (ascending order).
          iatom_send = ibeg_recv_node(nnd)+natomr_to_iaINnode(iatom2)-1

          !! ---------- DEBUG ---------- !!
          if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
             write (lun_db,*) ""
             write (lun_db,*) "ind_nnd et nnd:", ind_nnd,nnd
             write (lun_db,*) "ibeg_recv_node(nnd):", ibeg_recv_node(nnd)
             write (lun_db,*) "natomr_to_iaINnode(iatom2):",natomr_to_iaINnode(iatom2)
             write (lun_db,*) "ind_nnd,nnd, iatom_send:", ind_nnd,nnd,iatom_send
          endif
          !! /--------- DEBUG ---------- !!

          iatom_sort(iatom_send) = iatom2         ! remote atoms in asecnding order.
       enddo
       if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
          write (lun_db,*) ""
          write (lun_db,*) "iatom_sort(1:natom_remote):", iatom_sort(1:)
       endif
       !! =============================== !!
       !!           PROCESS 5.	         !!
       !! =============================== !!
       nsize_jj = 0 ; nsize_Lmatrix_remote = 0
       do iatom_send = 1, LmatrixSend%natom_remote
          iatom2 = iatom_sort(iatom_send)
          ifile  = natomr_to_ifile(iatom2)
          ia     = natomr_to_ia_file(iatom2)
          nsize_jj = nsize_jj + InfoMat(ifile)%jmax_i(ia)
          nsize_Lmatrix_remote = nsize_Lmatrix_remote + 3 * InfoMat(ifile)%jmax_i(ia) &
               + InfoMat(ifile)%jbeta_max_i(ia) * InfoMat(ifile)%alpha_i(ia) * InfoMat(ifile)%nspin
       enddo
       allocate (isend2_array(2*nsize_jj), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating isend2_array: ', 2*nsize_jj)
       allocate (send_array(nsize_Lmatrix_remote), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating send_array: ', nsize_Lmatrix_remote)

       !! --- DEBUG: 07/02/2013 --- !!
       if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
          call get_file_name('process5',numprocs,inode,file_name5)
          call io_assign(lun_db5)
          open (lun_db5, file=file_name5)
          write (lun_db5,'(a,i7/)') "No. of atoms to be sent:", LmatrixSend%natom_remote
          write (lun_db5,'(a)') "Array sizes for isend2_array & send_array !"
          write (lun_db5,'(a,5x,a,i7)') "Size of isend2_array:", "2 x ", nsize_jj
          write (lun_db5,*) "Size of send_array  :", nsize_Lmatrix_remote
          call io_close(lun_db5)
       endif
       !! /-- DEBUG: 07/02/2013 --- !!

       ibeg2=1 ; ibeg3=1 ; ibeg4 = 1
       isend_array=0 ; isend2_array=0 ; send_array = 0.0_double
       do iatom_send = 1, LmatrixSend%natom_remote
          iatom2 = iatom_sort(iatom_send)
          ifile  = natomr_to_ifile(iatom2)
          ia     = natomr_to_ia_file(iatom2)
          LmatrixSend%atom_ifile(iatom_send) = ifile
          LmatrixSend%atom_ia_file(iatom_send) = ia
          if (flag_MDdebug .AND. iprint_MDdebug.GT.2) write (lun_db,*) "iatom2,ifile,ia:", iatom2,ifile,ia
          ! 5-1. Store data in isend_array.
          ibeg=(iatom_send-1)*4+1
          isend_array(ibeg)   = InfoMat(ifile)%idglob_i(ia)
          isend_array(ibeg+1) = InfoMat(ifile)%alpha_i(ia)
          isend_array(ibeg+2) = InfoMat(ifile)%jmax_i(ia)
          isend_array(ibeg+3) = InfoMat(ifile)%jbeta_max_i(ia)

          !! ------------ DEBUG: ------------ !!
          if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
             write (lun_db,*) "glob,alpha,jmax,jbeta(ia):", &
                  InfoMat(ifile)%idglob_i(ia),InfoMat(ifile)%alpha_i(ia),InfoMat(ifile)%jmax_i(ia), &
                  InfoMat(ifile)%jbeta_max_i(ia)
             write (lun_db,*) "rvec_Pij:", InfoMat(ifile)%rvec_Pij(1:3,:)
          endif
          !! /----------- DEBUG: ------------ !!

          ! 5-2. Store data in isend2_array.
          nsize_jj = InfoMat(ifile)%jmax_i(ia)
          if (nsize_jj.EQ.0) call cq_abort('Error in nsize_jj: ', nsize_jj)
          isend2_array(ibeg2:ibeg2+nsize_jj-1) = InfoMat(ifile)%beta_j_i(InfoMat(ifile)%ibeg_Pij(ia) : &
               InfoMat(ifile)%ibeg_Pij(ia)+nsize_jj-1)
          ibeg2 = ibeg2 + nsize_jj
          isend2_array(ibeg2:ibeg2+nsize_jj-1) = InfoMat(ifile)%idglob_j(InfoMat(ifile)%ibeg_Pij(ia) : &
               InfoMat(ifile)%ibeg_Pij(ia)+nsize_jj-1)
          ibeg2 = ibeg2 + nsize_jj
          ! 5-3. Store data in send_array.
          do jj = 1, nsize_jj
             send_array(ibeg3:ibeg3+2) = InfoMat(ifile)%rvec_Pij(1:3,InfoMat(ifile)%ibeg_Pij(ia)+jj-1)
             ibeg3 = ibeg3 + 3
          enddo

          ! spin dependent
          nsize_Lmatrix_remote = InfoMat(ifile)%alpha_i(ia)*InfoMat(ifile)%jbeta_max_i(ia)
          do jj = 1, InfoMat(ifile)%nspin
             send_array(ibeg3:ibeg3+nsize_Lmatrix_remote-1) = &
                  InfoMat(ifile)%data_Lold(InfoMat(ifile)%ibeg_dataL(ia) : &
                  InfoMat(ifile)%ibeg_dataL(ia)+nsize_Lmatrix_remote-1, jj)
             ibeg3 = ibeg3 + nsize_Lmatrix_remote
          enddo

       enddo !(iatom_send, natom_remote)
    endif !(natom_remote.GT.0)

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2 .AND. nfile.GT.0) then
       write (lun_db,*) "---- Process 4. ----"
       !write (lun_db,*) "iatom_send: ", iatom_send
       write (lun_db,*) "iatom_sort(iatom_send): ", iatom_sort(1:LmatrixSend%natom_remote)
       write (lun_db,*) "atom_ifile: ", LmatrixSend%atom_ifile(1:LmatrixSend%natom_remote)
       write (lun_db,*) "atom_ia_file: ", LmatrixSend%atom_ia_file(1:LmatrixSend%natom_remote)
       write (lun_db,*) "---- Process 5. ----"
       write (lun_db,*) "Size of isend_array (4*natom_remote): ", 4*LmatrixSend%natom_remote
       if (allocated(isend_array) ) write (lun_db,*) "isend_array: ", isend_array(1:)
       write (lun_db,*) "Size of isend2_array (nsize_jj*2): ", nsize_jj, "x 2"
       if (allocated(isend2_array)) write (lun_db,*) "isend2_array: ", isend2_array(1:)
       write (lun_db,*) "Size of send_array (nsize_Lmatrix_remote): ", nsize_Lmatrix_remote
       if (allocated(send_array)  ) write (lun_db,*) "send_array: ", send_array(1:)
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    ! Deallocation.
    if (mx_natom_total.GT.0) then
       deallocate (natomr_to_ifile,natomr_to_ia_file,natomr_to_inode, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating arrays used in process 1: ')
    endif
    if (LmatrixSend%natom_remote.GT.0 .AND. nfile.GT.0) then
       deallocate (list_node_tmp,natom_node_tmp,natomr_to_nnd,natomr_to_iaINnode, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating arrays used in process 2: ')
       deallocate (iatom_sort, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating arrays used in process 4: ')
    endif
    if (LmatrixSend%nrecv_node.GT.0) then
       deallocate (ibeg_recv_node,isort_node,isort_node_inv, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating arrays used in process 3: ')
    endif

    return
  end subroutine alloc_send_array
  !!***

  ! ------------------------------------------------------------
  ! Subroutine CommMat_send_size
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/CommMat_send_size *
  !!
  !!  NAME
  !!   CommMat_send_size
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Sends the array size for communication
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2018/10/03 17:10 dave
  !!    Changing MPI tag to conform to standard
  !!  SOURCE
  !!
  subroutine CommMat_send_size(LmatrixSend,isend_array)

    ! Module usage
    use GenComms, ONLY: cq_abort
    use mpi
    use global_module, ONLY: numprocs
    use io_module, ONLY: get_file_name
    use GenComms, ONLY: inode
    use input_module, ONLY: io_assign,io_close
    use global_module, ONLY: io_lun

    implicit none

    ! passed variables
    integer, allocatable, intent(in) :: isend_array(:)
    type(Lmatrix_comm_send) :: LmatrixSend

    ! local variables
    integer :: ibeg,nnd,inode_recv,natom_send,isize
    integer :: tag,ierr
    integer :: nsend_req(LmatrixSend%nrecv_node)
    ! db
    integer :: lun
    character(20) :: file_name

    if (LmatrixSend%nrecv_node.LT.1) return

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       call get_file_name('mpi_send_size',numprocs,inode,file_name)
       call io_assign(lun)
       open (lun,file=file_name,position='append')
       write (lun,*) ""
       write (lun,*) "natom_remote:", LmatrixSend%natom_remote
    endif
    !! /--------- DEBUG ---------- !!

    ibeg = 1
    do nnd = 1, LmatrixSend%nrecv_node                 ! node ORDER (ascending order)e
       inode_recv = LmatrixSend%list_recv_node(nnd)
       natom_send = LmatrixSend%natom_recv_node(nnd)
       if (natom_send.LT.1) call cq_abort('Error: natom_send should take at least 1.')
       tag = 1 
       isize = 4 * natom_send

       !! ------ DEBUG ------ !!
       if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
          write (lun,*) "nnd:", nnd
          write (lun,*) "inode_recv (ID) :", inode_recv
          write (lun,*) "natom_send:", natom_send
          write (lun,*) "Size of isend_array (isize):", isize
          write (lun,*) "ibeg:", ibeg
          write (lun,*) "tag:", tag
          write (lun,*) ""
       endif
       !! /----- DEBUG ------ !!

       call MPI_send(isend_array(ibeg),isize,MPI_INTEGER,inode_recv-1,tag, &
            MPI_COMM_WORLD,ierr)
       if (ierr.NE.MPI_SUCCESS) call cq_abort('Error sending isend_array: ', nnd, ierr)
       ibeg = ibeg + isize
    enddo

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       write (lun,*) "isend_array:"
       write (lun,*) isend_array(1:)
       write (lun,*) ""
       call io_close(lun)
    endif
    !! /--------- DEBUG ---------- !!

    return
  end subroutine CommMat_send_size
  !!***

  ! ------------------------------------------------------------
  ! Subroutine CommMat_send_neigh
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/CommMat_send_neigh *
  !!
  !!  NAME
  !!   CommMat_send_neigh
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Sends the data on neighbours
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2016/04/06 dave
  !!    Changed Info to pointer from allocatable (gcc 4.4.7 issue)
  !!   2018/10/03 17:10 dave
  !!    Changing MPI tag to conform to standard
  !!
  !!  SOURCE
  !!
  subroutine CommMat_send_neigh(LmatrixSend,isend2_array,InfoMat)

    ! Module usage
    use GenComms, ONLY: cq_abort,myid
    use mpi
    !use io_module2, ONLY: InfoL
    use store_matrix, ONLY: InfoMatrixFile
    ! db
    use global_module, ONLY: numprocs,io_lun
    use io_module, ONLY: get_file_name
    use GenComms, ONLY: inode
    use input_module, ONLY: io_assign,io_close

    implicit none

    ! passed variables
    integer, allocatable, intent(in) :: isend2_array(:)
    type(Lmatrix_comm_send) :: LmatrixSend
    type(InfoMatrixFile), pointer :: InfoMat(:)

    ! local variables
    integer :: i,iatom2,nnd,inode_recv,natom_send,isize,ia,ifile,ibeg
    integer :: tag2,ierr,nstat(MPI_STATUS_SIZE)
    integer :: lun_db
    character(20) :: file_name

    if (LmatrixSend%nrecv_node.LT.1) return

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       call get_file_name('mpi_send_neigh',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name,position='append')
    endif
    !! /--------- DEBUG ---------- !!

    ibeg = 1
    iatom2 = 0
    do nnd = 1, LmatrixSend%nrecv_node
       inode_recv = LmatrixSend%list_recv_node(nnd)
       natom_send = LmatrixSend%natom_recv_node(nnd)
       tag2 = 2
       if (natom_send.LT.1) call cq_abort('Error: natom_send should take at least 1.')
       if (inode_recv.EQ.inode) call cq_abort('Error: Receiving nodes must differ from inode!')
       isize = 0
       do i = 1, natom_send
          iatom2 = iatom2 + 1
          ifile  = LmatrixSend%atom_ifile(iatom2)
          ia     = LmatrixSend%atom_ia_file(iatom2)
          isize  = isize + InfoMat(ifile)%jmax_i(ia) * 2
       enddo !(i, natom_send)

       !! ---------- DEBUG ---------- !!
       if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
          write (lun_db,*) "nnd:", nnd
          write (lun_db,*) "inode_recv & natom_send:", inode_recv,natom_send
          write (lun_db,*) "Size of isend2_array (isize):", isize
          write (lun_db,*) "tag2:", tag2
       endif
       !! /--------- DEBUG ---------- !!

       call MPI_send(isend2_array(ibeg),isize,MPI_INTEGER,inode_recv-1,tag2, &
            MPI_COMM_WORLD,ierr)
       if (ierr.NE.MPI_SUCCESS) call cq_abort('Error sending isend2_array: ', nnd, ierr)
       ibeg = ibeg + isize
    enddo !(nnd, nrecv_node)

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       write (lun_db,*) "isend2_array:"
       write (lun_db,*) isend2_array(1:)
       write (lun_db,*) ""
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    return
  end subroutine CommMat_send_neigh
  !!***

  !!****f* UpdateInfo/CommMat_send_data *
  !!
  !!  NAME
  !!   CommMat_send_data
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Sends interatomic distances (r_{iold, jold}) and matrix elements
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2016/04/06 dave
  !!    Changed Info to pointer from allocatable (gcc 4.4.7 issue)
  !!   2018/10/03 17:10 dave
  !!    Changing MPI tag to conform to standard
  !!
  !!  SOURCE
  !!
  subroutine CommMat_send_data(LmatrixSend,send_array,InfoMat)

    ! Module usage
    use numbers
    use GenComms, ONLY: cq_abort
    use mpi
    use store_matrix, ONLY: InfoMatrixFile
    ! db
    use global_module, ONLY: numprocs,io_lun
    use io_module, ONLY: get_file_name
    use GenComms, ONLY: inode
    use input_module, ONLY: io_assign,io_close

    implicit none

    ! passed variables
    real(double), allocatable, intent(in) :: send_array(:)
    type(Lmatrix_comm_send) :: LmatrixSend
    type(InfoMatrixFile), pointer :: InfoMat(:)

    ! local variables
    integer :: i,iatom2,nnd,inode_recv,natom_send,isize,ia,ifile,ibeg
    integer :: tag3,ierr,nstat(MPI_STATUS_SIZE)
    integer :: lun_db
    character(20) :: file_name

    if (LmatrixSend%nrecv_node.LT.1) return

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       call get_file_name('mpi_send_dataL',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name,position='append')
       write (lun_db,*) "n_matrix:", InfoMat%nspin
    endif
    !! /--------- DEBUG ---------- !!

    ibeg = 1
    iatom2 = 0
    do nnd = 1, LmatrixSend%nrecv_node
       inode_recv = LmatrixSend%list_recv_node(nnd)
       natom_send = LmatrixSend%natom_recv_node(nnd)
       tag3 = 3
       if (natom_send.LT.1) call cq_abort('Error: natom_send should take at least 1.')
       if (inode_recv.EQ.inode) call cq_abort('Error: Receiving node must differ from inode!')
       isize = 0
       do i = 1, natom_send
          iatom2 = iatom2 + 1
          ifile  = LmatrixSend%atom_ifile(iatom2)
          ia     = LmatrixSend%atom_ia_file(iatom2)
          isize  = isize + InfoMat(ifile)%jmax_i(ia)*3 &
               + InfoMat(ifile)%alpha_i(ia)*InfoMat(ifile)%jbeta_max_i(ia)*InfoMat(ifile)%nspin
       enddo !(i, natom_send)

       !! ---------- DEBUG ---------- !!
       if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
          write (lun_db,*) "nnd:", nnd
          write (lun_db,*) "inode_recv & natom_send:", inode_recv,natom_send
          write (lun_db,*) "Size of send_array (isize):", isize
          write (lun_db,*) "tag3:", tag3
       endif
       !! /--------- DEBUG ---------- !!

       call MPI_send(send_array(ibeg),isize,MPI_DOUBLE_PRECISION,inode_recv-1,tag3, &
            MPI_COMM_WORLD,ierr)
       if (ierr.NE.MPI_SUCCESS) call cq_abort('Error sending send_array: ', nnd, ierr)
       ibeg = ibeg + isize
    enddo !(nnd, nrecv_node)

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       write (lun_db,*) "send_array:"
       write (lun_db,*) send_array(1:)
       write (lun_db,*) ""
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    return
  end subroutine CommMat_send_data
  !!***

  ! ------------------------------------------------------------
  ! Subroutine alloc_recv_array
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/alloc_recv_array *
  !!
  !!  NAME
  !!   alloc_recv_array
  !!  USAGE
  !!
  !!  PURPOSE
  !!   This subroutine can be divided to four processes;
  !!
  !!     1. Check if my primary set of atoms are in my node.
  !!     2. Sort sending nodes in an acesneding order.
  !!     3. Sort and reorder atoms consistent to the above procedure
  !!        and determine teh size of arrays used for receving info.
  !!     4. Allocating arrays for receiving data.
  !!
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2014/02/03 michi
  !!   - Bug fix for changing the number of processors at the sequential job
  !!   2018/10/03 17:10 dave
  !!    Changing MPI tag to conform to standard
  !!   2019/11/14 tsuyoshi
  !!    Added InfoGlob in dummy arguments, and removed glob2node_old
  !!  SOURCE
  !!
  subroutine alloc_recv_array(InfoGlob,irecv_array,irecv2_array,recv_array, &
       LmatrixRecv,isize1,isize2,flag_remote_iprim)

    ! Module usage
    use numbers
    use GenComms, ONLY: inode,cq_abort
    use primary_module, ONLY: bundle
    use mpi
    ! db
    use input_module, ONLY: io_assign, io_close
    use io_module, ONLY: get_file_name
    use global_module, ONLY: numprocs,io_lun
    use store_matrix, ONLY: matrix_store_global

    implicit none

    ! passed variables
    type(matrix_store_global),intent(in) :: InfoGlob
    integer, allocatable :: irecv2_array(:)
    real(double), allocatable :: recv_array(:)
    logical, allocatable :: flag_remote_iprim(:)

    type(Lmatrix_comm_recv) :: LmatrixRecv

    ! local variables
    ! -- process 1. -- !
    integer :: iprim,nnd,stat_alloc
    integer :: iglob,inode_old,inode_file
    integer, allocatable :: list_node_tmp(:),natom_node_tmp(:)
    logical :: flag_find_old
    ! -- process 2. -- !
    integer :: ind_nnd,ibeg,isize,inode_send
    integer :: tag,ierr,nreq(MPI_STATUS_SIZE)
    integer, allocatable :: isort_node(:),irecv_array(:)
    ! -- process 3. -- !
    integer :: iprim_remote,isize1,isize2,ia,nalpha,nj,njbeta,iglob_local
    logical :: flag_find_iprim
    ! db
    integer :: lun_db
    character(20) :: file_db

    !! ================================ !!
    !!            PROCESS 1.            !!
    !! ================================ !!

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       call get_file_name('recv_proc1',numprocs,inode,file_db)
       call io_assign(lun_db)
       open (lun_db,file=file_db)
    endif
    !! /--------- DEBUG ---------- !!

    allocate (list_node_tmp(bundle%n_prim),natom_node_tmp(bundle%n_prim), &
         STAT=stat_alloc)
    if (stat_alloc.NE.0) call cq_abort('Error allocating arrays used in process 1 (RECV): ', &
         bundle%n_prim)
    allocate (flag_remote_iprim(bundle%n_prim), STAT=stat_alloc)
    if (stat_alloc.NE.0) call cq_abort('Error allocating flag_remote_iprim: ', bundle%n_prim)
    flag_remote_iprim = .false.
    list_node_tmp=0 ; natom_node_tmp=0
    LmatrixRecv%natom_remote = 0 ; LmatrixRecv%nsend_node=0
    do iprim = 1, bundle%n_prim
       flag_find_old = .false.
       iglob = bundle%ig_prim(iprim)
       inode_old  = InfoGlob%glob_to_node(iglob)
       inode_file = WhichNode(inode_old)

       !! -------- DEBUG -------- !!
       if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
          write (lun_db,*) "Check which atom is remote"
          write (lun_db,*) "iprim                             :", iprim
          write (lun_db,*) "glob. label of iprim              :", iglob
          write (lun_db,*) "The above atom used to be in procs.", inode_old
          write (lun_db,*) "inode_file & inode                :", inode_file, inode
          write (lun_db,*) ""
       endif
       !! /------- DEBUG -------- !!

       if (inode_file.NE.inode) then
          flag_remote_iprim(iprim) = .true.
          LmatrixRecv%natom_remote = LmatrixRecv%natom_remote + 1 ! No. of atoms sent to inode.

          !! --- DEBUG: --- !!
          if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
             write (lun_db,*) "Now in if (inode_file.NE.inode) !"
             write (lun_db,*) "remote atoms in iprim & glob          :", iprim, iglob
             write (lun_db,*) "Node IDs to fetch remote primary atoms:", inode_file
          endif
          !! /-- DEBUG: --- !!

          if (LmatrixRecv%nsend_node.LT.1) then
             LmatrixRecv%nsend_node = 1
             list_node_tmp(LmatrixRecv%nsend_node)  = inode_file
             natom_node_tmp(LmatrixRecv%nsend_node) = 1
          else
             do nnd = 1, LmatrixRecv%nsend_node
                if (inode_file.EQ.list_node_tmp(nnd)) then
                   flag_find_old = .true.
                   natom_node_tmp(nnd) = natom_node_tmp(nnd) + 1
                endif
                if (flag_find_old) exit
             enddo !(nnd, nsend_node)
             if (.NOT.flag_find_old) then
                LmatrixRecv%nsend_node = LmatrixRecv%nsend_node + 1
                list_node_tmp(LmatrixRecv%nsend_node)  = inode_file
                natom_node_tmp(LmatrixRecv%nsend_node) = 1
             endif
          endif
       endif !(inode.NE.inode_old)
    enddo !(iprim, n_prim)

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       write (lun_db,*) "flag_remote_iprim:", flag_remote_iprim(1:)
       write (lun_db,*) "No. of primary atoms (natom_remote)                  :", LmatrixRecv%natom_remote
       write (lun_db,*) "No. of procs. sending atoms to this node (nsend_node):", LmatrixRecv%nsend_node
       write (lun_db,*) "list_node_tmp   :"
       write (lun_db,*) list_node_tmp(1:)
       write (lun_db,*) "natom_node_tmp  :"
       write (lun_db,*) natom_node_tmp(1:)
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    !! ================================ !!
    !!            PROCESS 2.            !!
    !! ================================ !!

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       call get_file_name('recv_proc2',numprocs,inode,file_db)
       call io_assign(lun_db)
       open (lun_db,file=file_db)
    endif
    !! /--------- DEBUG ---------- !!

    if (LmatrixRecv%nsend_node.GT.0) then
       allocate (isort_node(LmatrixRecv%nsend_node), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating isort_node: ', &
            LmatrixRecv%nsend_node)
       call sort_recv_node(list_node_tmp,LmatrixRecv%nsend_node,isort_node,'recv')
       allocate (LmatrixRecv%list_send_node(LmatrixRecv%nsend_node) , &
            LmatrixRecv%natom_send_node(LmatrixRecv%nsend_node), &
            LmatrixRecv%ibeg_send_node(LmatrixRecv%nsend_node) , &
            STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating arrays used in process 2 (RECV):', &
            LmatrixRecv%nsend_node)
       allocate (irecv_array(LmatrixRecv%natom_remote*4), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating irecv_array: ', &
            LmatrixRecv%natom_remote*4) 
       irecv_array = 0
       LmatrixRecv%ibeg_send_node(1) = 1
       do nnd = 1, LmatrixRecv%nsend_node
          ind_nnd = isort_node(nnd) ! node ORDER (Lmatrix.XXX).
          LmatrixRecv%list_send_node(nnd)  = list_node_tmp(ind_nnd)
          LmatrixRecv%natom_send_node(nnd) = natom_node_tmp(ind_nnd)
          if (nnd.LT.LmatrixRecv%nsend_node) &
               LmatrixRecv%ibeg_send_node(nnd+1) = LmatrixRecv%ibeg_send_node(nnd) &
               + LmatrixRecv%natom_send_node(nnd)
          ibeg = (LmatrixRecv%ibeg_send_node(nnd)-1) * 4 + 1
          isize = LmatrixRecv%natom_send_node(nnd) * 4
          inode_send = LmatrixRecv%list_send_node(nnd)
          tag = 1

          !! ------ DEBUG ------ !!
          if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
             write (lun_db,*) "nnd,ind_nnd          :", nnd, ind_nnd
             write (lun_db,*) "ibeg,isize,inode_send:", ibeg, isize, inode_send
             write (lun_db,*) "MPI_STATUS_SIZE      :", MPI_STATUS_SIZE
             write (lun_db,*) "tag                  :", tag
          endif
          !! /----- DEBUG ------ !!

          call MPI_recv(irecv_array(ibeg),isize,MPI_INTEGER,inode_send-1,tag, &
               MPI_COMM_WORLD,nreq(nnd),ierr)
          if (ierr.NE.MPI_SUCCESS) call cq_abort('Error receiving irecv_array: ', nnd, ierr)
       enddo
    endif
    deallocate (list_node_tmp,natom_node_tmp, STAT=stat_alloc)
    if (stat_alloc.NE.0) call cq_abort('Error deallocating arrays used in process 1 (RECV):', &
         bundle%n_prim)

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       write (lun_db,*) "nspin"
       write (lun_db,*) "nsend_node:", LmatrixRecv%nsend_node
       write (lun_db,*) "isort_node(nnd):", isort_node(1:)
       if (LmatrixRecv%natom_remote.GT.0) then
          if (associated(LmatrixRecv%list_send_node)) &
               write (lun_db,*) "list_send_node(nnd):", LmatrixRecv%list_send_node(1:)
          if (associated(LmatrixRecv%natom_send_node)) &
               write (lun_db,*) "natom_send_node(nnd):", LmatrixRecv%natom_send_node(1:)
          if (associated(LmatrixRecv%ibeg_send_node)) &
               write (lun_db,*) "ibeg_send_node(nnd):", LmatrixRecv%ibeg_send_node(1:)
          write (lun_db,*) "Size of irecv_array:", LmatrixRecv%natom_remote, "x 4"
          if (allocated(irecv_array)) &
               write (lun_db,*) "irecv_array: ", irecv_array(1:)
       endif
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    ! Should be incorporated in the loop above but, separate it for now.  [24/SEP/2012]
    if (LmatrixRecv%nsend_node.GT.0) then
       deallocate (isort_node, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating isort_node: ', &
            LmatrixRecv%nsend_node)
    endif

    !! ================================ !!
    !!            PROCESS 3.            !!
    !! ================================ !!

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       call get_file_name('recv_proc3',numprocs,inode,file_db)
       call io_assign(lun_db)
       open (lun_db,file=file_db)
       write (lun_db, '(a)') "Primary atoms in this node: (glob. labelling)"
       write (lun_db,*) bundle%ig_prim(1:)
       write (lun_db,*) ""
    endif
    !! /--------- DEBUG ---------- !!

    if (LmatrixRecv%nsend_node.GT.0) then
       allocate (LmatrixRecv%nj_prim_recv(LmatrixRecv%natom_remote), &
            LmatrixRecv%nalpha_prim_recv(LmatrixRecv%natom_remote), &
            LmatrixRecv%njbeta_prim_recv(LmatrixRecv%natom_remote), &
            LmatrixRecv%id_prim_recv(LmatrixRecv%natom_remote), &
            LmatrixRecv%ibeg1_recv_array(LmatrixRecv%natom_remote), &
            LmatrixRecv%ibeg2_recv_array(LmatrixRecv%natom_remote), &
            STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating arrays used in process 3 (RECV): ', &
            LmatrixRecv%natom_remote)
       iprim_remote=0
       LmatrixRecv%id_prim_recv=0 ; LmatrixRecv%nj_prim_recv=0 ; LmatrixRecv%njbeta_prim_recv=0
       isize1=0 ; isize2=0
       LmatrixRecv%ibeg1_recv_array(1)=1 ; LmatrixRecv%ibeg2_recv_array(1)=1
       ibeg = 1
       do nnd = 1, LmatrixRecv%nsend_node 
          do ia = 1, LmatrixRecv%natom_send_node(nnd)
             iprim_remote = iprim_remote + 1
             if (iprim_remote.GT.LmatrixRecv%natom_remote) &
                  call cq_abort('Error iprim_remote should be less than natom_remote:')
             iglob  = irecv_array(ibeg)
             nalpha = irecv_array(ibeg+1)
             nj     = irecv_array(ibeg+2)
             njbeta = irecv_array(ibeg+3)

             !! ----- DEBUG: 07/02/2013 ----- !!
             if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
                write (lun_db,*) "nnd:", nnd
                write (lun_db,*) "iglob, nalpha, nj & njbeta"
                write (lun_db,*) iglob,nalpha,nj,njbeta
             endif
             !! /---- DEBUG: 07/02/2013 ----- !!

             ibeg = ibeg + 4
             LmatrixRecv%nj_prim_recv(iprim_remote) = nj
             LmatrixRecv%nalpha_prim_recv(iprim_remote) = nalpha
             LmatrixRecv%njbeta_prim_recv(iprim_remote) = njbeta
             flag_find_iprim = .false.
             do iprim = 1, bundle%n_prim
                iglob_local = bundle%ig_prim(iprim)
                if (iglob.EQ.iglob_local) then
                   LmatrixRecv%id_prim_recv(iprim_remote) = iprim
                   flag_find_iprim = .true.

                   !! --- DEBUG : --- !!
                   if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
                      write (lun_db,*) "glob ID of remote primary atom:", iglob_local
                      write (lun_db,*) "iprim_remote & id_prim_recv:",  &
                           iprim_remote, LmatrixRecv%id_prim_recv(iprim_remote)
                   endif
                   !! /-- DEBUG : --- !!

                   exit
                endif
             enddo
             if (.NOT.flag_find_iprim) call cq_abort('Error: flag_find_iprim should be T:')
             isize1 = isize1 + nj
             isize2 = isize2 + njbeta * nalpha
             if (iprim_remote.LT.LmatrixRecv%natom_remote) then
                LmatrixRecv%ibeg1_recv_array(iprim_remote+1) &
                     = LmatrixRecv%ibeg1_recv_array(iprim_remote) + nj
                LmatrixRecv%ibeg2_recv_array(iprim_remote+1) &
                     = LmatrixRecv%ibeg2_recv_array(iprim_remote) + njbeta * nalpha * LmatrixRecv%nspin
             endif
          enddo !(ia, natom_send_node)
       enddo !(nnd, nsend_node)
    endif

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.2) then
       if (LmatrixRecv%nsend_node.GT.0) then
          write (lun_db,*) ""
          write (lun_db,*) "nspin  :"
          write (lun_db,*) "nsend_node:", LmatrixRecv%nsend_node
          write (lun_db,*) "natom_send_node:", LmatrixRecv%natom_send_node
          write (lun_db,*) "id_prim_recv(iprim)     :", LmatrixRecv%id_prim_recv(1:)
          write (lun_db,*) "nj_prim_recv(nj)        :", LmatrixRecv%nj_prim_recv(1:)
          write (lun_db,*) "nalpha_prim_recv(nalpha):", LmatrixRecv%nalpha_prim_recv(1:)
          write (lun_db,*) "njbeta_prim_recv(njbeta):", LmatrixRecv%njbeta_prim_recv(1:)
          write (lun_db,*) "njbeta_prim_recv:", LmatrixRecv%njbeta_prim_recv(1:)
          write (lun_db,*) "ibeg1_recv_array:", LmatrixRecv%ibeg1_recv_array(1:)
          write (lun_db,*) "ibeg2_recv_array:", LmatrixRecv%ibeg2_recv_array(1:)
          write (lun_db,'(a)') "< ---------- Sizes for arrays ---------- >"
          write (lun_db,*) "isize1: # of j for all remote primary atoms"
          write (lun_db,*) "isize2: # of Lialpha,jbeta"
          write (lun_db,*) "isize1, isize2:", isize1, isize2
          write (lun_db,*) "For allocations,"
          write (lun_db,*) "irecv2_array(isize1*2) & recv_array(3*isize1+isize2*nspin)"
          write (lun_db,*) "Size for allocations:", isize1,'x',2, isize1*3+isize2*LmatrixRecv%nspin
       endif
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    !! ================================ !!
    !!            PROCESS 4.            !!
    !! ================================ !!
    if (LmatrixRecv%nsend_node.GT.0) then
       ! Allocation to store beta_j and idglob_j.
       allocate (irecv2_array(isize1*2), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating irecv2_array: ', isize1*2)
       ! Allocation to store rvec_Pij and data_Lold.
       allocate (recv_array(3*isize1+isize2*LmatrixRecv%nspin), STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error allocating recv_array: ', isize1*3+isize2*LmatrixRecv%nspin)
       irecv2_array = 1000 ; recv_array=1000.0_double
    endif

    return
  end subroutine alloc_recv_array
  !!***

  !!****f* UpdateInfo/CommMat_irecv_data *
  !!
  !!  NAME
  !!   CommMat_irecv_data
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Receives neighbour data, interatomic distances and matrix elements
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2018/10/03 17:10 dave
  !!    Changing MPI tags to conform to standard
  !!
  !!  SOURCE
  !!
  subroutine CommMat_irecv_data(LmatrixRecv,irecv2_array,recv_array,nreq2,nreq3)

    ! Module usage
    use numbers
    use GenComms, ONLY: cq_abort,myid
    use mpi
    ! db
    use global_module, ONLY: numprocs,io_lun
    use io_module, ONLY: get_file_name
    use GenComms, ONLY: inode
    use input_module, ONLY: io_assign,io_close

    implicit none

    ! passed variables
    integer, allocatable, intent(in) :: irecv2_array(:)
    real(double), allocatable, intent(in) :: recv_array(:)
    type(Lmatrix_comm_recv) :: LmatrixRecv
    integer :: nreq2(LmatrixRecv%nsend_node),nreq3(LmatrixRecv%nsend_node)

    ! local variables
    integer :: iprim_remote,ibeg1,ibeg2,nnd,inode_send,natom_send,ia,isize1,isize2
    integer :: tag2,tag3,ierr
    integer :: ibeg1_tmp,ibeg2_tmp
    integer :: lun_db
    character(25) :: file_name

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       call get_file_name('mpi_irecv_dataL',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name,position='append')
    endif
    !! /--------- DEBUG ---------- !!

    iprim_remote = 0
    ibeg1 = 1 ; ibeg2 = 1
    do nnd = 1, LmatrixRecv%nsend_node
       inode_send = LmatrixRecv%list_send_node(nnd)
       natom_send = LmatrixRecv%natom_send_node(nnd)
       if (inode_send.EQ.inode) call cq_abort('Error: Sending nodes must differ from inode!')
       tag2 = 2
       tag3 = 3
       if (natom_send.LT.1) call cq_abort('Error: natom_send should take at least 1.')
       isize1 = 0 ; isize2 = 0
       do ia = 1, natom_send
          iprim_remote = iprim_remote + 1
          isize1 = isize1 + LmatrixRecv%nj_prim_recv(iprim_remote) * 2
          isize2 = isize2 + LmatrixRecv%nj_prim_recv(iprim_remote)*3 +   &
               LmatrixRecv%njbeta_prim_recv(iprim_remote) * &
               LmatrixRecv%nalpha_prim_recv(iprim_remote) * LmatrixRecv%nspin
       enddo !(ia, natom_send)

       !! ---------- DEBUG ---------- !!
       if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
          write (lun_db,*) "nnd:", nnd
          write (lun_db,*) "inode_send & natom_send:", inode_send,natom_send
          write (lun_db,*) "Size of irecv2_array (isize1):", isize1
          write (lun_db,*) "Size of recv_array (isize2):", isize2
          write (lun_db,*) "tag2 and tag3:", tag2, tag3
       endif
       !! /--------- DEBUG ---------- !!

       call MPI_irecv(irecv2_array(ibeg1),isize1,MPI_INTEGER,inode_send-1,tag2, &
            MPI_COMM_WORLD,nreq2(nnd),ierr)
       if (ierr.NE.0) call cq_abort('Error receiving irecv2_array: ', nnd, ierr)
       call MPI_irecv(recv_array(ibeg2),isize2,MPI_DOUBLE_PRECISION,inode_send-1,tag3, &
            MPI_COMM_WORLD,nreq3(nnd),ierr)
       if (ierr.NE.0) call cq_abort('Error receiving recv_array: ', nnd, ierr)
       ibeg1 = ibeg1 + isize1
       ibeg2 = ibeg2 + isize2
       if (iprim_remote.LT.LmatrixRecv%natom_remote) then
          ibeg1_tmp = (LmatrixRecv%ibeg1_recv_array(iprim_remote+1)-1) * 2 + 1
          ibeg2_tmp = (LmatrixRecv%ibeg1_recv_array(iprim_remote+1)-1) * 3 &
               +LmatrixRecv%ibeg2_recv_array(iprim_remote+1)
          if (ibeg1.NE.ibeg1_tmp) call cq_abort('Error in ibeg1:')
          if (ibeg2.NE.ibeg2_tmp) call cq_abort('Error in ibeg2:')
       endif
    enddo !(nnd, nsend_node)

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       write (lun_db,*) "nreq2(1:nsend_node):", nreq2(1:)
       write (lun_db,*) "nreq3(1:nsend_node):", nreq3(1:)
       write (lun_db,*) "No. of nodes to be sent (nsend_node):", LmatrixRecv%nsend_node
       write (lun_db,*) "list_send_node(1:nsend_node):", LmatrixRecv%list_send_node(1:)
       write (lun_db,*) "No. of atoms to be sent (natom_send):", LmatrixRecv%natom_send_node(1:)
       write (lun_db,'(/a)') "<---------- fetched data ---------->"
       write (lun_db,*) "irecv2_array:", irecv2_array(1:)
       write (lun_db,*) "recv_array:", recv_array(1:)
       write (lun_db,*) ""
       call io_close(lun_db)
    endif
    !! /--------- DEBUG ---------- !!

    return
  end subroutine CommMat_irecv_data
  !!***

  !!****f* UpdateInfo/WhichNode *
  !!
  !!  NAME
  !!   WhichNode
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Get who the sender is by his node ID
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!
  !!  SOURCE
  !!
  function WhichNode(inode_old)

    ! Module usage
    use global_module, ONLY: numprocs
    use GenComms, ONLY: inode

    implicit none

    ! results
    integer :: WhichNode

    ! passed variables
    integer,intent(in) :: inode_old

    ! local variables
    integer :: ifile
    integer :: tmp,nfile,nrest_file,index_old

    if (inode_old.LE.numprocs) then
       WhichNode = inode_old
    elseif (inode_old.GT.numprocs) then
       do
          tmp = inode_old - numprocs
          if (tmp.LE.numprocs) then
             WhichNode = tmp
             exit
          endif
       enddo
    endif

  end function WhichNode
  !!***

  ! ------------------------------------------------------------
  ! Subroutine UpdateMatrix_local
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/UpdateMatrix_local *
  !!
  !!  NAME
  !!   UpdateMatrix_local
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Gets and constructs matrix with i_new and j_new.
  !!   Only deal with neighbours in MY processor.
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2016/04/06 dave
  !!    Changed Info to pointer from allocatable (gcc 4.4.7 issue)
  !!   2017/05/09 dave
  !!    Removed restriction spin and on L-matrix update
  !!   2018/02/12 dave
  !!    Removed delta_ix/y/z=zero condition when flag_move_atom is false
  !!   2018/Sep/07 tsuyoshi
  !!    Added the check of the inconsistency for the number of orbitals (sf1)
  !!    between the present matrix and the one read from the file. 
  !!    Also added the part collecting the information of missing pairs
  !!   2019/Nov/13 tsuyoshi
  !!    spin-dependent version
  !!  SOURCE
  !!
  subroutine UpdateMatrix_local(InfoMat,range,n_matrix,matA,flag_remote_iprim,nfile)

    ! Module usage
    use numbers
    use global_module, ONLY: glob2node,id_glob,atom_coord_diff, &
         runtype, rcellx, rcelly, rcellz, sf, nlpf, atomf
    use species_module, ONLY: nsf_species, natomf_species, nlpf_species
    use Gencomms, ONLY: inode,cq_abort
    use primary_module, ONLY: bundle
    use cover_module, ONLY: BCS_parts
    use store_matrix, ONLY: InfoMatrixFile
    use input_module, ONLY: leqi
    use atom_dispenser, ONLY: atom2part
    use matrix_module, ONLY: matrix_halo
    use matrix_data, ONLY: halo
    use mult_module, ONLY: mat_p
    use global_module, ONLY: numprocs,io_lun
    use io_module, ONLY: get_file_name
    use input_module, ONLY: io_assign,io_close
    use group_module, ONLY: parts
    use matrix_data, ONLY: max_range
    use atom_dispenser, ONLY: allatom2part
    use GenComms, ONLY: ionode
    use global_module, ONLY:  ni_in_cell, atom_coord, shift_in_bohr

    use dimens,        only: r_super_x, r_super_y, r_super_z


    implicit none

    ! passed variables
    integer :: nfile,range,n_matrix
    integer :: matA(n_matrix) ! usually n_matrix = nspin
    logical, allocatable :: flag_remote_iprim(:)
    type(InfoMatrixFile), pointer :: InfoMat(:)

    ! local variables
    integer :: ifile,ibeg1,ibeg2,ibeg_Lij,n1,n2,nLaddr,nLaddr_old, sf1, nprim
    ! --- Finding i --- !
    integer :: ia,idglob_ii,ind_node,n_alpha,ng,ni,iprim
    integer :: npart,ipartx,iparty,ipartz
    real(double) :: xprim_i,yprim_i,zprim_i,deltai_x,deltai_y,deltai_z
    logical :: find_iprim
    ! --- Finding j --- !
    integer :: jj,n_beta,idglob_jj,jcoverx,jcovery,jcoverz,jpart,jpart_nopg, &
         jjj,jcover,idglob_jjj,j_in_halo,jseq,ja,nj,idglob_jjjj
    integer :: BCSp_lx,BCSp_ly,BCSp_lz,BCSp_gx,BCSp_gy,BCSp_gz
    real(double) :: deltaj_x,deltaj_y,deltaj_z,xx_j,yy_j,zz_j
    logical :: find_jcover,flag_jseq

    type(matrix_halo), pointer :: matA_halo
    ! db
    integer :: lun_db,lun_db2,lun_db3,stat_alloc
    integer :: ind_part,atom_id,n,jpart_cell,gcspart,k_off,hp,l,nx,ny,nz,npx,npy,npz
    integer :: alpha,beta,jpart_x,jpart_y,jpart_z
    integer, allocatable :: alpha_i2(:)
    real(double) :: Rijx,Rijy,Rijz,Rij
    logical :: find
    character(20) :: file_name,file_name2,file_name3

    real(double) :: eps, xcover, ycover, zcover, rr
    real(double) :: sum_Rij_fail

    integer :: matA_tmp, isize

    !For Report_UpdateMatrix_Local&Remote
    iatom_local=0; ij_local=0; ij_success_local=0; ij_fail_local=0
    min_Rij_fail_local=zero; max_Rij_fail_local=zero; sum_Rij_fail=zero
    !For Report_UpdateMatrix_Local&Remote

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       call get_file_name('UpdateL1',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name)
       call get_file_name('UpdateL2',numprocs,inode,file_name)
       call io_assign(lun_db2)
       open (lun_db2,file=file_name)
    endif
    !! /--------- DEBUG ---------- !!

    matA_halo => halo(range)

    ! In the case of  n_matrix > 1,  information of pairs are same for all mat_p(matA(:))
    matA_tmp = matA(1)
    if(nfile > 0 ) then
       if(n_matrix.ne.InfoMat(1)%nspin) &
            call cq_abort("Error: mismatch between n_matrix and InfoMat%nspin",n_matrix,InfoMat(1)%nspin)
    endif

    !For checking the consistency of nsf1 between read and present matrices
    sf1 = mat_p(matA_tmp)%sf1_type; nprim = bundle%n_prim
    allocate(alpha_i2(1:nprim), STAT = stat_alloc)
    if(stat_alloc .ne. 0) call cq_abort('Error in allocating alpha_i2 in UpdateMatrix_local',nprim)
    if(sf1 == sf) then
       alpha_i2(1:nprim) =nsf_species(bundle%species(1:nprim))
    elseif(sf1 == atomf) then
       alpha_i2(1:nprim) =natomf_species(bundle%species(1:nprim))
    elseif(sf1 == nlpf) then
       alpha_i2(1:nprim) =nlpf_species(bundle%species(1:nprim))
    else
       call cq_abort(" ERROR in UpdateMatrix_local: No sf1_type : ",sf1)
    endif

    ifile_local = nfile
    do ifile = 1, nfile
       ! Check if "ia" is my primary set of atom.
       ! Loop over "i_old".
       do ia = 1, InfoMat(ifile)%natom_i
          idglob_ii = InfoMat(ifile)%idglob_i(ia)
          ind_node  = glob2node(idglob_ii)
          n_alpha   = InfoMat(ifile)%alpha_i(ia)

          if (ind_node.EQ.inode) then
             find_iprim = .false.
             iprim = 0
             do ng = 1, bundle%groups_on_node
                if (bundle%nm_nodgroup(ng).GT.0) then
                   do ni = 1, bundle%nm_nodgroup(ng)
                      iprim = iprim + 1
                      if (bundle%ig_prim(iprim).EQ.idglob_ii) then
                         find_iprim = .true.
                         exit
                      endif
                   enddo !(ni, nm_group)
                endif
                if (find_iprim) then
                   npart = ng
                   exit
                endif
             enddo !(ng, groups_on_node)
             if (.NOT. find_iprim) call cq_abort('Error: find_iprim must be T - local.')
             if (flag_remote_iprim(iprim)) call cq_abort('Error: flag_remote_iprim must be F.', iprim)

             if (n_alpha .ne. alpha_i2(iprim)) call cq_abort('Error: alpha mismach !',n_alpha, alpha_i2(iprim))
             iatom_local = iatom_local+1

             ! Partitions and positions of "i_new".
             ipartx=bundle%idisp_primx(npart) ; xprim_i=bundle%xprim(iprim)
             iparty=bundle%idisp_primy(npart) ; yprim_i=bundle%yprim(iprim)
             ipartz=bundle%idisp_primz(npart) ; zprim_i=bundle%zprim(iprim)

             ! If atoms move, we need to consider the displacements of each atom.
             ! Displacement in x/y/z of PS of atoms 'i'.
             deltai_x=atom_coord_diff(1,idglob_ii)
             deltai_y=atom_coord_diff(2,idglob_ii)
             deltai_z=atom_coord_diff(3,idglob_ii)
             ! Find i_new neighbours, "j_new", by referring to "j_old". Loop over "j_old" to begin with.
             ibeg1 = InfoMat(ifile)%ibeg_Pij(ia)
             ibeg2 = InfoMat(ifile)%ibeg_dataL(ia)

             do jj = 1, InfoMat(ifile)%jmax_i(ia)
                ij_local = ij_local+1
                n_beta = InfoMat(ifile)%beta_j_i(ibeg1+jj-1)
                idglob_jj = InfoMat(ifile)%idglob_j(ibeg1+jj-1)
                ! Displacement in x/y/z of neighbour 'j' of 'i'.
                deltaj_x=atom_coord_diff(1,idglob_jj)
                deltaj_y=atom_coord_diff(2,idglob_jj)
                deltaj_z=atom_coord_diff(3,idglob_jj)
                xx_j=xprim_i-InfoMat(ifile)%rvec_Pij(1,ibeg1+jj-1)*rcellx+deltaj_x-deltai_x
                yy_j=yprim_i-InfoMat(ifile)%rvec_Pij(2,ibeg1+jj-1)*rcelly+deltaj_y-deltai_y
                zz_j=zprim_i-InfoMat(ifile)%rvec_Pij(3,ibeg1+jj-1)*rcellz+deltaj_z-deltai_z

                Rijx=xprim_i-xx_j
                Rijy=yprim_i-yy_j
                Rijz=zprim_i-zz_j
                Rij = Rijx*Rijx + Rijy*Rijy + Rijz*Rijz
                Rij = sqrt(Rij)

                !! -------- DEBUG -------- !!
                if (flag_MDdebug .and. iprint_MDdebug .gt. 1) then
                   write (lun_db,*) "! --- Neighbours: j ---!"
                   write (lun_db,*) "ibeg1+jj-1:", ibeg1+jj-1
                   write (lun_db,*) "idglob_jj and its beta:", idglob_jj, n_beta
                   write (lun_db,*) "vec_Pij:" 
                   write (lun_db,*) InfoMat(ifile)%rvec_Pij(1:3,ibeg1+jj-1)
                   write (lun_db,*) "delta_i or atom_coord_diff(1:3,idglob_ii):", deltai_x,deltai_y,deltai_z
                   write (lun_db,*) "delta_j or atom_coord_diff(1:3,idglob_jj):", deltaj_x,deltaj_y,deltaj_z
                   write (lun_db,*) "pos of jj (x,y,z):"
                   write (lun_db,*) xx_j, yy_j, zz_j
                   write (lun_db,*) ""
                endif
                !! /------- DEBUG -------- !!

                ! Get the partiton to which jj belongs.
                call atom2part(xx_j,yy_j,zz_j,ind_part,jcoverx,jcovery,jcoverz,idglob_jj)
                if (flag_MDdebug .and. iprint_MDdebug .gt. 1) then
                   write (lun_db,*) "atom2part -> jcover:", jcoverx,jcovery,jcoverz !db
                end if
                ! Get the partition indices with (x,y,z) in CS.
                jcoverx = jcoverx - bundle%nx_origin + BCS_parts%nspanlx + 1
                jcovery = jcovery - bundle%ny_origin + BCS_parts%nspanly + 1
                jcoverz = jcoverz - bundle%nz_origin + BCS_parts%nspanlz + 1
                if (inode==ionode .and. flag_MDdebug .and. iprint_MDdebug > 1) &
                     write (lun_db,*) "jcover in CS:", jcoverx,jcovery,jcoverz
                ! The followings are NOT the error check. These are the treatment for the case
                ! where atoms move and get out of CS.
                if ( (jcoverx.GT.BCS_parts%ncoverx .OR. jcoverx.LT.1) .OR.   &
                     (jcovery.GT.BCS_parts%ncovery .OR. jcovery.LT.1) .OR.   &
                     (jcoverz.GT.BCS_parts%ncoverz .OR. jcoverz.LT.1) ) then
                   write (io_lun,*) 'jj is no longer a neighbour! - local', inode
                   ibeg2 = ibeg2 + n_alpha*n_beta
                   cycle

                   ij_fail_local = ij_fail_local+1
                   sum_Rij_fail = sum_Rij_fail + Rij
                   if(Rij < min_Rij_fail_local) min_Rij_fail_local = Rij
                   if(Rij > max_Rij_fail_local) max_Rij_fail_local = Rij

                endif
                ! Get the partition's indices in two manners; NOPG and CC (gcspart) in CS.
                jpart = (jcoverx-1)*BCS_parts%ncovery*BCS_parts%ncoverz + &
                     (jcovery-1)*BCS_parts%ncoverz + jcoverz
                jpart_nopg = BCS_parts%inv_lab_cover(jpart)

                find_jcover = .false.
                ! Find out "j_new". 
                do jjj = 1, BCS_parts%n_ing_cover(jpart_nopg)
                   jcover = BCS_parts%icover_ibeg(jpart_nopg) + jjj - 1      ! ID in CS
                   idglob_jjj = BCS_parts%ig_cover(jcover)                   ! CS --> glob
                   if (idglob_jj.EQ.idglob_jjj) then
                      find_jcover = .true.
                      jseq = jjj
                      if (flag_MDdebug .and. iprint_MDdebug > 1) &
                           write (lun_db,*) "idglob_jjj:", idglob_jjj
                      exit
                   endif
                enddo !(jjj, n_ing_cover)
                if (.NOT. find_jcover) then
                   xx_j=xprim_i-InfoMat(ifile)%rvec_Pij(1,ibeg1+jj-1)*rcellx+deltaj_x-deltai_x
                   yy_j=yprim_i-InfoMat(ifile)%rvec_Pij(2,ibeg1+jj-1)*rcelly+deltaj_y-deltai_y
                   zz_j=zprim_i-InfoMat(ifile)%rvec_Pij(3,ibeg1+jj-1)*rcellz+deltaj_z-deltai_z
                   write(io_lun,*) ' :ERROR: inode = ',inode
                   write(io_lun,*) ' :ERROR: idglob_jj, idglob_jjj, jcover,jpart_nopg,#ofjjj = ', &
                        idglob_jj, idglob_jjj,jcover,jpart_nopg,BCS_parts%n_ing_cover(jpart_nopg)
                   write(io_lun,*) ' :ERROR: jcoverxyz ',jcoverx,jcovery,jcoverz
                   write(io_lun,*) ' :ERROR: vecRij ', &
                        InfoMat(ifile)%rvec_Pij(1,ibeg1+jj-1), InfoMat(ifile)%rvec_Pij(2,ibeg1+jj-1), &
                        InfoMat(ifile)%rvec_Pij(3,ibeg1+jj-1) 
                   write(io_lun,*) ' :ERROR: deltaj_x  ',deltaj_x,deltaj_y,deltaj_z
                   write(io_lun,*) ' :ERROR: deltai_x  ',deltai_x,deltai_y,deltai_z
                   write(io_lun,*) ' :ERROR: vecRi  ',xprim_i, yprim_i, zprim_i
                   write(io_lun,*) ' :ERROR: vecRj  ',xx_j, yy_j, zz_j
                   call cq_abort('Error: find_cover must be T - local.')
                endif
                ! Now that we have known who "j_new" is w/ its global and CS ID and partition in CS, 
                ! we are going to examine its neighbour ID of the primary set of atom "i_new".
                j_in_halo = matA_halo%i_halo(matA_halo%i_hbeg(jpart)+jseq-1)
                if (j_in_halo.GT.matA_halo%ni_in_halo) &
                     call cq_abort('Error in j_in_halo - local: ', j_in_halo)
                ibeg_Lij = 0
                if (j_in_halo.NE.0) &
                     ibeg_Lij = matA_halo%i_h2d((iprim-1)*matA_halo%ni_in_halo+j_in_halo)
                if (flag_MDdebug .and. iprint_MDdebug > 1) then
                   write (lun_db,*) "id_glob(j) et ibeg_Lij:", idglob_jj, ibeg_Lij
                   write (lun_db,*) ""
                endif
                ! Reorder Lmatrix elements.
                if (ibeg_Lij.NE.0) then
                   if (flag_MDdebug .AND. iprint_MDdebug.GT.1) write (lun_db2,*) "jpart(CC) in CS:", jpart
                   jpart_x = 1 + (jpart-1) / (BCS_parts%ncovery*BCS_parts%ncoverz)
                   jpart_y = 1 + (jpart-1-(jpart_x-1)*BCS_parts%ncovery*BCS_parts%ncoverz) / BCS_parts%ncoverz
                   jpart_z = jpart - (jpart_x-1) * BCS_parts%ncovery * BCS_parts%ncoverz - &
                        (jpart_y-1) * BCS_parts%ncoverz

                   do isize = 1, n_matrix
                      do n1 = 1, n_alpha*n_beta
                         mat_p(matA(isize))%matrix(ibeg_Lij+n1-1) = &
                              InfoMat(ifile)%data_Lold(ibeg2+n1-1,isize)

                         !! --------------- DEBUG: --------------- !!
                         if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
                            write (lun_db2,'(2f25.18,f15.5,i10)') mat_p(matA(isize))%matrix(ibeg_Lij+n1-1), &
                                 InfoMat(ifile)%data_Lold(ibeg2+n1-1,isize), Rij, jcover
                         endif
                         !! --------------- DEBUG: --------------- !!

                      enddo
                   enddo ! isize = 1, n_matrix
                   ij_success_local = ij_success_local+1
                else
                   ij_fail_local = ij_fail_local + 1
                   if(ij_fail_local == 1) then
                      min_Rij_fail_local = Rij; max_Rij_fail_local = Rij
                   endif
                   sum_Rij_fail = sum_Rij_fail + Rij
                   if(Rij < min_Rij_fail_local) min_Rij_fail_local = Rij
                   if(Rij > max_Rij_fail_local) max_Rij_fail_local = Rij
                endif
                ibeg2 = ibeg2 + n_alpha*n_beta
             enddo !(jj, jmax_i)
          endif !(ind_node.EQ.inode)
       enddo !(ia, natom_i)
    enddo !(ifile, nfile)

    if(ij_fail_local > 0) then
       ave_Rij_fail_local = sum_Rij_fail/ij_fail_local
    else
       ave_Rij_fail_local = zero
    endif

    deallocate(alpha_i2, STAT = stat_alloc)
    if(stat_alloc .ne. 0) call cq_abort('Error in deallocating alpha_i2 in UpdateMatrix_local')

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
       call io_close(lun_db)
       call io_close(lun_db2)
    endif
    !! /--------- DEBUG ---------- !!
    return
  end subroutine UpdateMatrix_local
  !!***

  ! ------------------------------------------------------------
  ! Subroutine UpdateMatrix_remote
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/UpdateMatrix_remote *
  !!
  !!  NAME
  !!   UpdateMatrix_remote
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Gets and constructs matrix with i_new and j_new.
  !!   Deals with my remote primary atoms.
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!   2017/05/09 dave
  !!    Removed restriction spin and on L-matrix update 
  !!   2018/02/12 dave
  !!    Removed delta_ix/y/z=zero condition when flag_move_atom is false
  !!   2018/Sep/07 tsuyoshi
  !!    Added the check of the inconsistency for the number of orbitals (sf1)
  !!    between the present matrix and the one read from the file. 
  !!   2019/Nov/13 tsuyoshi
  !!    spin dependent version 
  !!  SOURCE
  !!
  subroutine UpdateMatrix_remote(range,n_matrix,matA,LmatrixRecv,flag_remote_iprim,irecv2_array,recv_array)

    ! Module usage
    use numbers
    use global_module, ONLY: nspin,atom_coord_diff,runtype,io_lun, rcellx, rcelly, rcellz
    use GenComms, ONLY: cq_abort
    use primary_module, ONLY: bundle
    use cover_module, ONLY: BCS_parts
    use input_module, ONLY: leqi
    use atom_dispenser, ONLY: atom2part
    use matrix_module, ONLY: matrix_halo
    use matrix_data, ONLY: halo
    use mult_module, ONLY: mat_p
    use global_module, ONLY: sf, nlpf, atomf
    use species_module, ONLY: nsf_species, natomf_species, nlpf_species
    ! db
    use io_module, ONLY: get_file_name
    use global_module, ONLY: numprocs
    use input_module, ONLY: io_assign,io_close
    use GenComms, ONLY: inode, ionode

    implicit none

    ! passed variables
    integer :: range, n_matrix
    integer :: matA(n_matrix)
    integer, allocatable, intent(in) :: irecv2_array(:)
    real(double), allocatable, intent(in) :: recv_array(:)
    logical, allocatable, intent(in) :: flag_remote_iprim(:)
    type(Lmatrix_comm_recv) :: LmatrixRecv

    ! local variables
    integer :: n1,len, nprim, sf1, stat_alloc
    integer, allocatable :: alpha_i2(:)
    integer :: isize, matA_tmp

    ! --- Finding remote i --- !
    integer :: iprim_remote,iprim,idglob_ii,n_alpha
    real(double) :: xprim_i,yprim_i,zprim_i,deltai_x,deltai_y,deltai_z
    ! --- Finding j --- !
    integer :: ibeg1,ibeg2,nsize1,nsize2,jj,n_beta,idglob_jj,ibeg_dataL, &
         jcoverx,jcovery,jcoverz,jpart,jpart_nopg,jjj,idglob_jjj,  &
         jcover,j_in_halo,jbeg,jseq,ibeg_Lij
    real(double) :: xx_j,yy_j,zz_j,deltaj_x,deltaj_y,deltaj_z
    real(double) :: vec_Rij(3)
    logical :: find_jcover
    integer :: ibeg_dataLtmp, iadd_dataL

    type(matrix_halo), pointer :: matA_halo
    ! db
    integer :: lun_db,lun_db2
    integer :: ind_part
    character(20) :: file_name,file_name2
    real(double) :: Rijx,Rijy,Rijz,Rij, sum_Rij_fail

    !For Report_UpdateMatrix_Local&Remote
    iatom_remote=0; ij_remote=0; ij_success_remote=0; ij_fail_remote=0
    min_Rij_fail_remote=zero; max_Rij_fail_remote=zero; sum_Rij_fail=zero
    !For Report_UpdateMatrix_Local&Remote

    if (LmatrixRecv%natom_remote.LT.1) return

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug) then
       call get_file_name('UpdateLremote',numprocs,inode,file_name)
       call io_assign(lun_db)
       open (lun_db,file=file_name)
       write (lun_db,*) irecv2_array(1:)
       write (lun_db,*) "! ---------------------------------------------- !"
       write (lun_db,*) recv_array(1:)
       write (lun_db,*) "! ---------------------------------------------- !"
       write (lun_db,*) ""
       write (lun_db,*) "No. of remote primary atoms:", LmatrixRecv%natom_remote
       write (lun_db,*) "IDs of remote primary atoms in bundle (LmatrixRecv%id_prim_recv):"
       write (lun_db,*) LmatrixRecv%id_prim_recv(1:)
       write (lun_db,*) "flag_remote_iprim:"
       write (lun_db,*) flag_remote_iprim(1:)
       if (iprint_MDdebug.GT.1) then
          call get_file_name('Matrixremote',numprocs,inode,file_name2)
          call io_assign(lun_db2)
          open (lun_db2,file=file_name2)
       endif
    endif
    !! /--------- DEBUG ---------- !!

    matA_halo => halo(range)
    matA_tmp = matA(1)
    if(n_matrix .ne. LmatrixRecv%nspin) &
         call cq_abort("ERROR: mismatch between n_matrix and LmatrixRecv%nspin",n_matrix,LmatrixRecv%nspin)

    !For checking the consistency of nsf1 between read and present matrices
    sf1 = mat_p(matA_tmp)%sf1_type; nprim = bundle%n_prim
    allocate(alpha_i2(1:nprim), STAT = stat_alloc)
    if(stat_alloc .ne. 0) call cq_abort('Error in allocating alpha_i2 in UpdateMatrix_local',nprim)
    if(sf1 == sf) then
       alpha_i2(1:nprim) =nsf_species(bundle%species(1:nprim))
    elseif(sf1 == atomf) then
       alpha_i2(1:nprim) =natomf_species(bundle%species(1:nprim))
    elseif(sf1 == nlpf) then
       alpha_i2(1:nprim) =nlpf_species(bundle%species(1:nprim))
    else
       call cq_abort(" ERROR in UpdateMatrix_local: No sf1_type : ",sf1)
    endif

    do iprim_remote = 1, LmatrixRecv%natom_remote
       ! Find my REMOTE primary atoms.
       iprim = LmatrixRecv%id_prim_recv(iprim_remote)  ! ID in bundle
       if (.NOT. flag_remote_iprim(iprim)) &
            call cq_abort('Error: flag_remote_iprim must be T.', iprim)

       iatom_remote = iatom_remote+1

       idglob_ii = bundle%ig_prim(iprim)
       n_alpha = LmatrixRecv%nalpha_prim_recv(iprim_remote)
       if(n_alpha .ne. alpha_i2(iprim)) &
            call cq_abort('Error in UpdateMatrix_remote: alpha mismatch !',n_alpha, alpha_i2(iprim))
       xprim_i = bundle%xprim(iprim)
       yprim_i = bundle%yprim(iprim)
       zprim_i = bundle%zprim(iprim)
       ! Displacement in x/y/z of PS of atoms 'i'.
       deltai_x=atom_coord_diff(1,idglob_ii)
       deltai_y=atom_coord_diff(2,idglob_ii)
       deltai_z=atom_coord_diff(3,idglob_ii)

       !! ---------- DEBUG ---------- !!
       if (flag_MDdebug) then
          write (lun_db,*) ""
          write (lun_db,*) "iprim et iprim_remote:", iprim, iprim_remote
          write (lun_db,*) "idglob_ii et alpha:", idglob_ii,n_alpha
          write (lun_db,*) "xyz_prim:", xprim_i,yprim_i,zprim_i
          write (lun_db,*) ""
       endif
       !! /--------- DEBUG ---------- !!

       ! Find neighbours of remote primary set of atom i.
       nsize1 = LmatrixRecv%nj_prim_recv(iprim_remote) ! No. of neigh of iprim_remote
       nsize2 = LmatrixRecv%njbeta_prim_recv(iprim_remote)*n_alpha       ! period betwen n_matrix = 1 and 2
       ibeg1  = (LmatrixRecv%ibeg1_recv_array(iprim_remote)-1)*2+1       ! for irecv2_array
       ibeg2  = (LmatrixRecv%ibeg1_recv_array(iprim_remote)-1)*3 + &
            LmatrixRecv%ibeg2_recv_array(iprim_remote)              ! for recv_array
       if (flag_MDdebug) write (lun_db,*) "ibeg1 et ibeg2 (iprim_remote)", ibeg1, ibeg2, iprim_remote
       ibeg_dataL = ibeg2 + nsize1*3
       do jj = 1, nsize1
          ij_remote = ij_remote+1
          n_beta = irecv2_array(ibeg1+jj-1)
          idglob_jj  = irecv2_array(ibeg1+nsize1+jj-1)

          vec_Rij(1) = recv_array(ibeg2)
          vec_Rij(2) = recv_array(ibeg2+1)
          vec_Rij(3) = recv_array(ibeg2+2)
          ibeg2 = ibeg2+3

          ! Displacement in x/y/z of neighbour 'i'.
          deltaj_x=atom_coord_diff(1,idglob_jj)
          deltaj_y=atom_coord_diff(2,idglob_jj)
          deltaj_z=atom_coord_diff(3,idglob_jj)
          xx_j = xprim_i - vec_Rij(1)*rcellx + deltaj_x - deltai_x
          yy_j = yprim_i - vec_Rij(2)*rcelly + deltaj_y - deltai_y
          zz_j = zprim_i - vec_Rij(3)*rcellz + deltaj_z - deltai_z

          Rijx=xprim_i-xx_j
          Rijy=yprim_i-yy_j
          Rijz=zprim_i-zz_j
          Rij = Rijx*Rijx + Rijy*Rijy + Rijz*Rijz
          Rij = sqrt(Rij)

          !! ---------- DEBUG ---------- !!
          if (flag_MDdebug) then
             write (lun_db,*) "jj, idglob_jj et beta:", jj,idglob_jj, n_beta
             write (lun_db,*) "vec_Rij(1:3):", vec_Rij(1:3)
             write (lun_db,*) "coords(j):", xx_j,yy_j,zz_j
             write (lun_db,*) "ibeg1 et ibeg2", ibeg1, ibeg2
             write (lun_db,*) "ibeg_dataL:", ibeg_dataL
          endif
          !! /--------- DEBUG ---------- !!

          ! Get the partition to which jj belongs (sim-cell).
          call atom2part(xx_j,yy_j,zz_j,ind_part,jcoverx,jcovery,jcoverz,idglob_jj)
          if (flag_MDdebug) write (lun_db,*) "jcoverx,y,z (sim-cell):", jcoverx,jcovery,jcoverz
          ! Get the partitions with (x,y,z) in CS.
          jcoverx=jcoverx-bundle%nx_origin+BCS_parts%nspanlx+1
          jcovery=jcovery-bundle%ny_origin+BCS_parts%nspanly+1
          jcoverz=jcoverz-bundle%nz_origin+BCS_parts%nspanlz+1
          if (inode==ionode .and. flag_MDdebug) &
               write (lun_db,*) "jcover in CS:", jcoverx,jcovery,jcoverz
          if ( (jcoverx.GT.BCS_parts%ncoverx .OR. jcoverx.LT.1) .OR. &
               (jcovery.GT.BCS_parts%ncovery .OR. jcovery.LT.1) .OR. &
               (jcoverz.GT.BCS_parts%ncoverz .OR. jcoverz.LT.1) ) then
             ibeg_dataL = ibeg_dataL + n_alpha*n_beta * n_matrix
             ij_fail_remote = ij_fail_remote + 1
             if(ij_fail_remote == 1) then 
                min_Rij_fail_remote = Rij; max_Rij_fail_remote = Rij
             endif
             sum_Rij_fail = sum_Rij_fail + Rij
             if(Rij < min_Rij_fail_remote) min_Rij_fail_remote = Rij
             if(Rij > max_Rij_fail_remote) max_Rij_fail_remote = Rij
             cycle
          endif
          ! Get local labeling of jj in two ways; NOPG and CC.
          jpart=(jcoverx-1)*BCS_parts%ncovery*BCS_parts%ncoverz + &
               (jcovery-1)*BCS_parts%ncoverz+jcoverz
          jpart_nopg=BCS_parts%inv_lab_cover(jpart)
          ! Find out "j_new".
          find_jcover = .false.
          do jjj = 1, BCS_parts%n_ing_cover(jpart_nopg)
             jcover = BCS_parts%icover_ibeg(jpart_nopg) + jjj - 1          ! local label
             idglob_jjj = BCS_parts%ig_cover(jcover)                       ! glob label
             if (flag_MDdebug) write (lun_db,*) "jjj: glob_id et jcover:", idglob_jjj, jcover
             if (idglob_jjj.EQ.idglob_jj) then
                jseq = jjj
                find_jcover = .true.
                exit
             endif
          enddo
          if (.NOT. find_jcover) &
               call cq_abort('Error: find_jcover must be T - remote.')
          ! Now that we have known who "j_new" is, we are ready to get 
          ! jcover -> j_in_halo -> neigh.
          j_in_halo = matA_halo%i_halo(matA_halo%i_hbeg(jpart)+jseq-1)
          if (j_in_halo.GT.matA_halo%ni_in_halo) &
               call cq_abort('Error in j_in_halo - remote: ', j_in_halo)
          ibeg_Lij = 0
          if (j_in_halo.NE.0) &
               ibeg_Lij = matA_halo%i_h2d((iprim-1)*matA_halo%ni_in_halo+j_in_halo)

          !! ---------- DEBUG ---------- !!
          if (flag_MDdebug) then
             write (lun_db,*) "jpart in NOPG et CC:", jpart_nopg, jpart
             write (lun_db,*) "No. of atoms in jpart:", BCS_parts%n_ing_cover(jpart_nopg)
             write (lun_db,*) "j_in_halo; ibeg_Lij et ibeg_dataL:", j_in_halo, ibeg_Lij, ibeg_dataL
             write (lun_db,*) "n_alpha*n_beta:", n_alpha*n_beta
          endif
          !! /--------- DEBUG ---------- !!

          len = n_alpha*n_beta
          if (ibeg_Lij.NE.0) then
             if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
                write (lun_db2,*) "jpart(CC) in CS:", jpart
                write (lun_db2,*) "i_hbeg(jpart), jseq et jj:", &
                     matA_halo%i_hbeg(jpart),jseq,jj
                write (lun_db2,*) "iprim, matA_halo%ni_in_halo et j_in_halo:", &
                     iprim,matA_halo%ni_in_halo,j_in_halo
                write (lun_db2,*) "ibeg_Lij, ibeg_dataL et n_alpha*n_beta:", &
                     ibeg_Lij,ibeg_dataL,len
             endif

             !     recv_array is arranged as recv_array((alpha,beta),j,spin,i_remote)
             !                        (not recv_array((alpha,beta),spin,j,i_remote) )
             do isize = 1, n_matrix
                ibeg_dataLtmp = ibeg_dataL+(isize-1)*nsize2
                do n1 = 1, len
                   mat_p(matA(isize))%matrix(ibeg_Lij+n1-1) = recv_array(ibeg_dataLtmp+n1-1)
                   !! ---------- DEBUG: ---------- !!
                   if (flag_MDdebug) write (lun_db,*) "ibeg_Lij+n1, ibeg_dataL+n1-1:", &
                        ibeg_Lij+n1-1, ibeg_dataL+n1-1
                   if (flag_MDdebug .AND. iprint_MDdebug.GT.1) then
                      write (lun_db2,'(2f25.18)') mat_p(matA(isize))%matrix(ibeg_Lij+n1-1), &
                           recv_array(ibeg_dataL+n1-1)
                   endif
                   !! /--------- DEBUG: ---------- !!
                enddo
             enddo !isize = 1, n_matrix
          else
             ij_fail_remote = ij_fail_remote + 1
             sum_Rij_fail = sum_Rij_fail + Rij
             if(Rij < min_Rij_fail_remote) min_Rij_fail_remote = Rij
             if(Rij > max_Rij_fail_remote) max_Rij_fail_remote = Rij

          endif !(ibeg_Lij.NE.0)
          ibeg_dataL = ibeg_dataL + len 
       enddo !(jj, nzise1)
    enddo !(iprim_remote, natom_remote)

    if(ij_fail_remote > 0) then
       ave_Rij_fail_remote = sum_Rij_fail/ij_fail_remote
    else
       ave_Rij_fail_remote = zero
    endif

    deallocate(alpha_i2, STAT = stat_alloc)
    if(stat_alloc .ne. 0) call cq_abort('Error in deallocating alpha_i2 in UpdateMatrix_local')

    !! ---------- DEBUG ---------- !!
    if (flag_MDdebug) then
       write (lun_db,*) ""
       write (lun_db,*) "matA_halo%ni_in_halo:", matA_halo%ni_in_halo
       write (lun_db,*) "matA_halo%np_in_halo:", matA_halo%np_in_halo
       write (lun_db,*) "matA_halo%i_h2d:", matA_halo%i_h2d(1:)
       write (lun_db,'(/a)') "Got through UpdateMatrix_remote !"
       call io_close(lun_db)
       if (iprint_MDdebug.GT.1) call io_close(lun_db2)
    endif
    !! /--------- DEBUG ---------- !!

    return
  end subroutine UpdateMatrix_remote
  !!***

  ! ------------------------------------------------------------
  ! Subroutine deallocate_CommMatArrays
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/deallocate_CommMatArrays *
  !!
  !!  NAME
  !!   deallocate_CommMatArrays
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Releases memories of the arrays used in communication
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Michiaki Arita
  !!  CREATION DATE
  !!   2013/08/22
  !!  MODIFICATION
  !!
  !!  SOURCE
  !!
  subroutine deallocate_CommMatArrays(sarray1,sarray2,sarray3,rarray1,rarray2,rarray3, &
       LmatrixSend,LmatrixRecv)

    ! Module usage
    use numbers
    use GenComms, ONLY: cq_abort

    implicit none

    ! passed arrays
    integer, allocatable :: sarray1(:),sarray2(:),rarray1(:),rarray2(:)
    real(double), allocatable :: sarray3(:),rarray3(:)
    type(Lmatrix_comm_send) :: LmatrixSend
    type(Lmatrix_comm_recv) :: LmatrixRecv

    ! local variables
    integer :: stat_alloc

    if (LmatrixSend%nrecv_node.GT.0) then
       deallocate (sarray1,sarray2,sarray3, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating sending arrays.')
       deallocate (LmatrixSend%list_recv_node,LmatrixSend%natom_recv_node, &
            LmatrixSend%atom_ifile,LmatrixSend%atom_ia_file, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating arrays in LmatrixSend.')
    elseif (LmatrixRecv%nsend_node.GT.0) then
       deallocate (rarray1,rarray2,rarray3, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating receiving arrays.')
       deallocate (LmatrixRecv%list_send_node,LmatrixRecv%natom_send_node, &
            LmatrixRecv%ibeg_send_node,LmatrixRecv%id_prim_recv, &
            LmatrixRecv%nalpha_prim_recv,LmatrixRecv%nj_prim_recv, &
            LmatrixRecv%njbeta_prim_recv,LmatrixRecv%ibeg1_recv_array, &
            LmatrixRecv%ibeg2_recv_array, STAT=stat_alloc)
       if (stat_alloc.NE.0) call cq_abort('Error deallocating arrays in LmatrixRecv.')
    endif

    return
  end subroutine deallocate_CommMatArrays
  !!***

  ! ------------------------------------------------------------
  ! Subroutine Report_UpdateMatrix
  ! ------------------------------------------------------------

  !!****f* UpdateInfo/Report_UpdateMatrix *
  !!
  !!  NAME
  !!   Report_UpdateMatrix
  !!  USAGE
  !!
  !!  PURPOSE
  !!   Reports the statistics of UpdateMatrix_local and UpdateMatrix_remote
  !!  INPUTS
  !!
  !!  USES
  !!
  !!  AUTHOR
  !!   Tsuyoshi Miyazaki
  !!  CREATION DATE
  !!   2018/08/16
  !!  MODIFICATION
  !!
  !!  SOURCE
  subroutine Report_UpdateMatrix(matname)
    use datatypes
    use global_module,  only: io_lun, numprocs
    use GenComms,       only: inode, ionode, my_barrier

    implicit none
    character(4), optional :: matname
    integer :: ii

    if(present(matname)) matrix_name=matname
    if(inode == ionode) write(io_lun,'(4x," *** REPORT of UpdateMatrix_Local& Remote for matrix ", 4a)')  &
         matrix_name
    do ii = 1, numprocs
       if(ii == inode) then
          write(io_lun,'(6x," inode = ",i8)') ii
          write(io_lun,'(6x," iatom_local, ij_local, success, fail  = ",4i8)') &
               iatom_local, ij_local, ij_success_local, ij_fail_local
          write(io_lun,'(8x," min_Rij, max_Rij, ave_Rij for local  = ",3f15.5)') &
               min_Rij_fail_local, max_Rij_fail_local, ave_Rij_fail_local  
          write(io_lun,'(6x," iatom_remote, ij_remote, success, fail  = ",4i8)') &
               iatom_remote, ij_remote, ij_success_remote, ij_fail_remote
          write(io_lun,'(8x," min_Rij, max_Rij, ave_Rij for remote  = ",3f15.5)') &
               min_Rij_fail_remote, max_Rij_fail_remote, ave_Rij_fail_remote  
       endif
       call my_barrier()
    enddo
    return
  end subroutine Report_UpdateMatrix
  !!***

end module UpdateInfo
