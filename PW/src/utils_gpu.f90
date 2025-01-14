!
! Copyright (C) 2017 Quantum ESPRESSO Foundation
! Author: Ivan Carnimeo
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
! General-purpose routines for scalar products, printing,
! linear-algebra operators for exact-exchange and localization
!
!----------------------------------------------------------------------
SUBROUTINE matcalc_gpu( label, DoE, PrtMat, ninner, n, m, U, V, mat, ee )
  !------------------------------------------------------------------
  !! Compute the (n,n) matrix representation \(\langle U|V\rangle\)
  !! and its weighted trace (energy) from \(V(m,n)\) and \(U(m,n)\).
  !
  USE kinds,                ONLY : DP
  USE io_global,            ONLY : stdout
  USE wvfct,                ONLY : current_k
  USE wvfct_gpum,           ONLY : using_wg_d,wg_d
  USE becmod_subs_gpum,     ONLY : calbec_gpu
  !
  IMPLICIT NONE
  !
  CHARACTER(len=*), INTENT(IN) :: label
  !! it specifies the meaning of the output
  LOGICAL, INTENT(IN) :: DoE
  !! if TRUE calculate the trace
  INTEGER, INTENT(IN) :: PrtMat
  !! printing index
  INTEGER, INTENT(IN) :: ninner
  !! inner dimension in the matrix product
  INTEGER, INTENT(IN) :: n
  !! second dimension of U
  INTEGER, INTENT(IN) :: m
  !! second dimension of V
  COMPLEX(DP), INTENT(IN) :: U(ninner,n)
  !! input - U matrix
  COMPLEX(DP), INTENT(IN) :: V(ninner,m)
  !! input - V matrix
  REAL(DP), INTENT(OUT) :: mat(n,m)
  !! output matrix \(\langle U|V\rangle\)
  REAL(DP), INTENT(OUT) :: ee
  !! the weighted trace (energy) of the product
#if defined(__CUDA)
  ATTRIBUTES(DEVICE) :: U, V, mat
#endif
  !
  ! ... local variables
  !
  INTEGER :: i
  CHARACTER(len=2) :: string

  CALL start_clock_gpu('matcalc')

  string = 'M-'
  mat = 0.0_dp
  CALL calbec_gpu(ninner, U, V, mat, m)

  IF( PrtMat > 1 ) CALL errore('matcalc_gpu', 'cannot print matrix', 1)

  IF(DoE) THEN
     CALL using_wg_d(0)
     IF(n/=m) CALL errore('matcalc','no trace for rectangular matrix.',1)
     string = 'E-'
     ee = 0.0_dp
     !$cuf kernel do (1)
     DO i = 1,n
        ee = ee + wg_d(i,current_k)*mat(i,i)
     ENDDO
     IF ( PrtMat > 0 ) WRITE(stdout,'(A,f16.8,A)') string//label, ee, ' Ry'
  ENDIF

  CALL stop_clock_gpu('matcalc')

END SUBROUTINE matcalc_gpu
!
!--------------------------------------------------------------------------
SUBROUTINE matcalc_k_gpu (label, DoE, PrtMat, ik, ninner, n, m, U, V, mat, ee)
  !------------------------------------------------------------------
  !
  USE kinds,                ONLY : dp
  USE io_global,ONLY : stdout
  USE wvfct,                ONLY : wg, npwx
  USE wvfct_gpum,           ONLY : using_wg_d,wg_d
  USE becmod_subs_gpum,     ONLY : calbec_gpu
  USE noncollin_module,     ONLY : noncolin, npol
  IMPLICIT NONE
  !
  ! compute the (n,n) matrix representation <U|V>
  ! and energy from V (m,n) and U(m,n)
  !
  LOGICAL, INTENT(IN) :: DoE
  INTEGER, INTENT(IN) :: PrtMat, ik, ninner, n, m
  COMPLEX(dp), INTENT(IN) :: U(ninner,n), V(ninner,m)
  COMPLEX(dp), INTENT(OUT):: mat(n,m)
  REAL(DP), INTENT(OUT) :: ee
  CHARACTER(len=*), INTENT(IN) :: label
#if defined(__CUDA)
  attributes(DEVICE) :: U, V, mat
#endif
  INTEGER :: i
  CHARACTER(len=2) :: string

  CALL start_clock_gpu('matcalc')

  string = 'M-'
  mat = (0.0_dp, 0.0_dp)
  IF(noncolin) THEN
    noncolin = .false.
    CALL calbec_gpu(ninner, U, V, mat, m)
    noncolin = .true.
  ELSE
    CALL calbec_gpu(ninner, U, V, mat, m)
  ENDIF

  IF( PrtMat > 1 ) CALL errore('matcalc_k_gpu', 'cannot print matrix', 1)

  IF(DoE) THEN
    CALL using_wg_d(0)
    IF(n/=m) CALL errore('matcalc','no trace for rectangular matrix.',1)
    string = 'E-'
    ee = 0.0_dp
    !$cuf kernel do (1)
    DO i = 1,n
      ee = ee + wg_d(i,ik)*DBLE(mat(i,i))
    ENDDO
    IF ( PrtMat > 0 ) WRITE(stdout,'(A,f16.8,A)') string//label, ee, ' Ry'
  ENDIF

  CALL stop_clock_gpu('matcalc')

END SUBROUTINE matcalc_k_gpu
