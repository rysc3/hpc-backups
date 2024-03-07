! $Id$
! -----------------------------------------------------------
! Module group_module
! -----------------------------------------------------------
! Code area 8: indexing
! -----------------------------------------------------------

!!****h* Conquest/group_module
!!  NAME
!!   group_module
!!  PURPOSE
!!   This deals with, and contains variables concerning, the groups 
!!   in the unit cell (i.e. partitions and blocks of integration 
!!   grid points)
!!  AUTHOR
!!   D.R.Bowler
!!  CREATION DATE
!!   20/04/00
!!  MODIFICATION HISTORY
!!   30/05/2001 dave
!!    Added ROBODoc headers
!!   20/06/2001 dave
!!    Added RCS Id and Log tags and used cq_abort throughout
!!   2008/05/16 ast
!!    Added timers
!!   2014/09/15 18:30 lat
!!    fixed call start/stop_timer to timer_module (not timer_stdlocks_module !)
!!  SOURCE
!!
module group_module

  ! Module usage
  use datatypes
  use basic_types
  use timer_module,           only: start_timer,    stop_timer,   cq_timer
  use timer_module,           only: start_backtrace,stop_backtrace
  use timer_stdclocks_module, only: tmr_std_indexing,tmr_std_allocation

  implicit none
  save

  type(group_set) :: parts  ! Partitions of atoms
  type(group_set) :: blocks ! Blocks of integration grid points

  integer :: part_method
  integer, parameter :: HILBERT = 1
  integer, parameter :: PYTHON  = 2
!!***

contains

!!****f* group_module/make_cc2 *
!!
!!  NAME 
!!   make_cc2
!!  USAGE
!! 
!!  PURPOSE
!!   This subroutine constructs arrays which convert from absolute number
!!   of a group to it's "sequence" number on it's node (and tells you 
!!   which node is responsible for it)
!!  INPUTS
!! 
!! 
!!  USES
!! 
!!  AUTHOR
!!   D.R.Bowler
!!  CREATION DATE
!!   20/04/00
!!  MODIFICATION HISTORY
!!   30/05/2001 dave
!!    Added ROBODoc header
!!   2008/05/16 ast
!!    - Added timer
!!   2015/06/08 lat
!!    - Added experimental backtrace
!!  SOURCE
!!
  subroutine make_cc2(groups,numprocs)

    ! Module usage
    use datatypes
    use basic_types

    implicit none

    ! Passed variables
    type(group_set) :: groups
    integer         :: numprocs

    ! Local variables
    type(cq_timer)  :: backtrace_timer
    integer         :: nnd,np,ind_group

!****lat<$
    call start_backtrace(t=backtrace_timer,who='make_cc2',where=8,level=3)
!****lat>$

    call start_timer(tmr_std_indexing)

    do nnd=1,numprocs  ! Loop over processors
      if(groups%ng_on_node(nnd).gt.0) then  
        do np=1,groups%ng_on_node(nnd)  ! Loop over groups on the node
          ind_group=groups%ngnode(groups%inode_beg(nnd)+np-1)  
          groups%i_cc2node(ind_group)=nnd
          groups%i_cc2seq(ind_group)=np
        enddo
      endif
    enddo   

    call stop_timer(tmr_std_indexing)

!****lat<$
    call stop_backtrace(t=backtrace_timer,who='make_cc2')
!****lat>$

    return
  end subroutine make_cc2
!!***

!!****f* group_module/allocate_group_set *
!!
!!  NAME 
!!   allocate_group_set
!!  USAGE
!! 
!!  PURPOSE
!!   Allocates memory and assigns maxima to the group_set type
!!  INPUTS
!! 
!! 
!!  USES
!!   datatypes, basic_types
!!  AUTHOR
!!   D.R.Bowler
!!  CREATION DATE
!!   20/04/00
!!  MODIFICATION HISTORY
!!   30/05/2001 dave
!!    - Added ROBODoc header
!!   2008/05/16 ast
!!    - Added timer
!!   2009/11/03 16:43 dave
!!    - Added memory registration
!!   2015/06/08 lat
!!    - Added experimental backtrace
!!   2018/07/11 12:04 dave
!!    Initialise group members to zero
!!  SOURCE
!!
  subroutine allocate_group_set(groups,mx_node)

    ! Module usage
    use datatypes
    use basic_types
    use GenComms,      only: cq_abort
    use memory_module, only: reg_alloc_mem, type_int
    use global_module, only: area_index

    implicit none

    ! Passed variables
    type(group_set) :: groups
    integer         :: mx_node

    ! Local variables
    type(cq_timer)  :: backtrace_timer
    integer         :: stat

!****lat<$
    call start_backtrace(t=backtrace_timer,who='allocate_group_set',where=1,level=5)
!****lat>$

    call start_timer(tmr_std_allocation)
    allocate(groups%ng_on_node(mx_node),STAT=stat)
    if(stat/=0) then
       call cq_abort('alloc_gp: error allocating memory to ng_on_node !')
    endif
    allocate(groups%inode_beg(mx_node),STAT=stat)
    if(stat/=0) then
       call cq_abort('alloc_gp: error allocating memory to inode_beg !')
    endif
    call reg_alloc_mem(area_index,2*mx_node,type_int)
    allocate(groups%ngnode(groups%mx_gcell),STAT=stat)
    if(stat/=0) then
       call cq_abort('alloc_gp: error allocating memory to ngnode !')
    endif
    allocate(groups%i_cc2node(groups%mx_gcell),STAT=stat)
    if(stat/=0) then
       call cq_abort('alloc_gp: error allocating memory to i_cc2node !')
    endif
    allocate(groups%i_cc2seq(groups%mx_gcell),STAT=stat)
    if(stat/=0) then
       call cq_abort('alloc_gp: error allocating memory to i_cc2seq !')
    endif
    allocate(groups%nm_group(groups%mx_gcell),STAT=stat)
    if(stat/=0) then
       call cq_abort('alloc_gp: error allocating memory to nm_group !')
    endif
    allocate(groups%icell_beg(groups%mx_gcell),STAT=stat)
    if(stat/=0) then
       call cq_abort('alloc_gp: error allocating memory to icell_beg !')
    endif
    allocate(groups%inv_ngnode(groups%mx_gcell),STAT=stat)
    if(stat/=0) then
       call cq_abort('alloc_gp: error allocating memory to inv_ngnode !')
    endif
    call reg_alloc_mem(area_index,6*groups%mx_gcell,type_int)
    call stop_timer(tmr_std_allocation)
    groups%ng_on_node = 0 
    groups%inode_beg  = 0
    groups%ngnode     = 0
    groups%i_cc2node  = 0
    groups%i_cc2seq   = 0
    groups%nm_group   = 0
    groups%icell_beg  = 0
    groups%inv_ngnode = 0

!****lat<$
    call stop_backtrace(t=backtrace_timer,who='allocate_group_set')
!****lat>$

    return
  end subroutine allocate_group_set
!!***

!!****f* group_module/deallocate_group_set *
!!
!!  NAME 
!!   deallocate_group_set
!!  USAGE
!! 
!!  PURPOSE
!!   Deallocates memory associated with the group_set type
!!  INPUTS
!! 
!! 
!!  USES
!!   datatypes, basic_types
!!  AUTHOR
!!   D.R.Bowler
!!  CREATION DATE
!!   20/04/00
!!  MODIFICATION HISTORY
!!   30/05/2001 dave
!!    Added ROBODoc header
!!   2008/05/16 ast
!!    Added timer
!!   2009/11/03 16:43 dave
!!    Added memory registration
!!   2018/07/11 12:04 dave
!!    Deallocate nm_group
!!  SOURCE
!!
  subroutine deallocate_group_set(groups)

    use basic_types
    use GenComms, ONLY: cq_abort
    use memory_module, ONLY: reg_dealloc_mem, type_int
    use global_module, ONLY: area_index

    implicit none

    ! Passed variables
    type(group_set) :: groups

    ! Local variables
    integer :: stat

    call start_timer(tmr_std_allocation)
    deallocate(groups%inv_ngnode,groups%icell_beg,groups%nm_group,groups%i_cc2seq, &
         groups%i_cc2node,groups%ngnode,groups%inode_beg, &
         groups%ng_on_node,STAT=stat)
    if(stat/=0) then
       call cq_abort('dealloc_gp: error deallocating group_set !')
    endif
    call reg_dealloc_mem(area_index,6*groups%mx_gcell,type_int)
    call stop_timer(tmr_std_allocation)

    return
  end subroutine deallocate_group_set
!!***
end module group_module
