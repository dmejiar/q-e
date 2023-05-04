!
! Copyright (C) Quantum ESPRESSO group
! Copyright (C) 2022 Advanced Micro Devices, Inc. All Rights Reserved.
!
! This file is distributed under the terms of the
! GNU General Public License. See the file `License'
! in the root directory of the present distribution,
! or http://www.gnu.org/copyleft/gpl.txt .
!
#if defined(__HIP)

MODULE enums
  USE iso_c_binding
  IMPLICIT NONE

  ENUM, BIND(C) 
      ENUMERATOR :: HIP_SUCCESS = 0
  END ENUM

  ENUM, BIND(C) 
      ENUMERATOR :: HIPFFT_SUCCESS = 0
  END ENUM

  ENUM, BIND(C)
    ENUMERATOR :: HIPFFT_R2C = 42
    ENUMERATOR :: HIPFFT_C2R = 44
    ENUMERATOR :: HIPFFT_C2C = 41
    ENUMERATOR :: HIPFFT_D2Z = 106
    ENUMERATOR :: HIPFFT_Z2D = 108
    ENUMERATOR :: HIPFFT_Z2Z = 105
  END ENUM

END MODULE

MODULE hipfft
  USE iso_c_binding
  USE enums
  IMPLICIT NONE

  INTEGER(C_INT), PARAMETER, PUBLIC :: HIPFFT_FORWARD = -1, HIPFFT_BACKWARD = 1

  INTERFACE  
     FUNCTION HipDeviceSynchronize() &
         BIND(C,name="hipDeviceSynchronize")
        use iso_c_binding
        use enums
        implicit none
        integer(kind(HIP_SUCCESS)) :: hipDeviceSynchronize

     END FUNCTION hipDeviceSynchronize

     FUNCTION hipfftPlan1d(plan,nx,myType,batch) BIND(C, name="hipfftPlan1d")
       USE iso_c_binding
       USE enums
       implicit none
       integer(kind(HIPFFT_SUCCESS)) :: hipfftPlan1d
       type(c_ptr) :: plan
       integer(c_int),value :: nx
       integer(kind(HIPFFT_R2C)),value :: myType
       integer(c_int),value :: batch
     END FUNCTION

     FUNCTION hipfftExecZ2Z(plan,idata,odata,direction) BIND(C, name="hipfftExecZ2Z")
       USE iso_c_binding
       USE enums
       IMPLICIT NONE
       INTEGER(kind(HIPFFT_SUCCESS)) :: hipfftExecZ2Z
       TYPE(C_PTR),VALUE :: plan
       TYPE(C_PTR),VALUE :: idata
       TYPE(C_PTR),VALUE :: odata
       INTEGER(C_INT),VALUE :: direction
     END FUNCTION

     FUNCTION hipfftPlanMany(plan,rank,n,inembed,istride,idist,onembed,ostride,odist,myType,batch) &
         bind(c, name="hipfftPlanMany")
       USE iso_c_binding
       USE enums
       IMPLICIT NONE
       INTEGER(KIND(HIPFFT_SUCCESS)) :: hipfftPlanMany
       TYPE(C_PTR) :: plan
       INTEGER(C_INT),VALUE :: rank
       TYPE(C_PTR),VALUE :: n
       TYPE(C_PTR),VALUE :: inembed
       INTEGER(C_INT),VALUE :: istride
       INTEGER(C_INT),VALUE :: idist
       TYPE(C_PTR),VALUE :: onembed
       INTEGER(C_INT),VALUE :: ostride
       INTEGER(C_INT),VALUE :: odist
       INTEGER(KIND(HIPFFT_R2C)),VALUE :: myType
       INTEGER(C_INT),VALUE :: batch
     END FUNCTION

     FUNCTION hipfftDestroy(plan) BIND(C, name="hipfftDestroy")
       USE iso_c_binding
       USE enums
       IMPLICIT NONE
       INTEGER(kind(HIPFFT_SUCCESS)) :: hipfftDestroy
       TYPE(C_PTR),VALUE :: plan

     END FUNCTION

END INTERFACE

CONTAINS

  SUBROUTINE hipcheck(hiperror)
      USE enums
      IMPLICIT NONE

      INTEGER(KIND(HIP_SUCCESS)) :: hiperror

      IF (hiperror /= HIP_SUCCESS) THEN
         WRITE (*, *) "HIP ERROR: ERROR CODE = ", hiperror
         CALL EXIT(hiperror)
      END IF
  END SUBROUTINE hipCheck

  SUBROUTINE hipfftcheck(hiperror)
      USE enums
      IMPLICIT NONE

      INTEGER(KIND(HIPFFT_SUCCESS)) :: hiperror

      IF (hiperror /= HIPFFT_SUCCESS) THEN
         WRITE (*, *) "HIPFFT ERROR: ERROR CODE = ", hiperror
         CALL EXIT(hiperror)
      END IF
  END SUBROUTINE hipfftCheck
  

END MODULE

!=----------------------------------------------------------------------=!
   MODULE fft_scalar_hipfft
!=----------------------------------------------------------------------=!

       USE, intrinsic :: ISO_C_BINDING
       USE hipfft
       USE fft_param

       IMPLICIT NONE
        SAVE

        PRIVATE
        PUBLIC :: cft_1z_omp, cft_2xy_omp, cfft3d_omp, cfft3ds_omp

!=----------------------------------------------------------------------=!
   CONTAINS
!=----------------------------------------------------------------------=!

!
!=----------------------------------------------------------------------=!
!
!
!
!         FFT along "z"
!
!
!
!=----------------------------------------------------------------------=!
!

   SUBROUTINE cft_1z_omp(c, nsl, nz, ldz, isign, cout, in_place)

!     driver routine for nsl 1d complex fft's of length nz
!     ldz >= nz is the distance between sequences to be transformed
!     (ldz>nz is used on some architectures to reduce memory conflicts)
!     input  :  c(ldz*nsl)   (complex)
!     output : cout(ldz*nsl) (complex - NOTA BENE: transform is not in-place!)
!     isign > 0 : backward (f(G)=>f(R)), isign < 0 : forward (f(R) => f(G))
!     Up to "ndims" initializations (for different combinations of input
!     parameters nz, nsl, ldz) are stored and re-used if available

     INTEGER, INTENT(IN)           :: isign
     INTEGER, INTENT(IN)           :: nsl, nz, ldz
     LOGICAL, INTENT(IN), OPTIONAL :: in_place

     COMPLEX (DP) :: c(:), cout(:)

     REAL (DP)  :: tscale
     INTEGER    :: i, err, idir, ip, void
     INTEGER, SAVE :: zdims( 3, ndims ) = -1
     INTEGER, SAVE :: icurrent = 1
     LOGICAL :: found

     LOGICAL, SAVE :: is_inplace

     ! AMD hipFFT library variables

     INTEGER, SAVE :: hipfft_status = 0
     type(c_ptr), SAVE :: hipfft_planz( ndims ) = c_null_ptr

     IF (PRESENT(in_place)) THEN
       is_inplace = in_place
     ELSE
       is_inplace = .false.
     END IF
     !
     ! Check dimensions and corner cases.
     !
     IF ( nsl <= 0 ) THEN
       CALL fftx_error__(" fft_scalar: cft_1z ", " nsl out of range ", nsl)
       RETURN

     END IF
     !
     !   Here initialize table only if necessary
     !
     CALL lookup()

     IF( .NOT. found ) THEN
       !   no table exist for these parameters
       !   initialize a new one
       !
       CALL init_plan()
     END IF

     !
     !   Now perform the FFTs using machine specific drivers
     !

#if defined(__FFT_CLOCKS)
     CALL start_clock( 'cft_1z' )
#endif

     IF (isign < 0) THEN


        IF (is_inplace) THEN
            !$omp target data use_device_ptr(c)
              hipfft_status = hipfftExecZ2Z(hipfft_planz(ip), c_loc(c), c_loc(c), HIPFFT_FORWARD)
            !$omp end target data
        ELSE
            !$omp target data use_device_ptr(c, cout)
              hipfft_status = hipfftExecZ2Z(hipfft_planz(ip), c_loc(c), c_loc(cout), HIPFFT_FORWARD)
            !$omp end target data
        ENDIF
        CALL hipCheck(hipDeviceSynchronize())
        IF(hipfft_status /= 0) CALL fftx_error__(' cft_1z GPU ',' stopped in hipfftExecZ2Z(Forward) ')
            CALL hipfftCheck(hipfft_status)

        tscale = 1.0_DP / nz
        IF (is_inplace) THEN
           !$omp target teams distribute parallel do simd
           DO i=1, ldz * nsl
              c( i ) = c( i ) * tscale
           END DO
        ELSE
           !$omp target teams distribute parallel do simd
           DO i=1, ldz * nsl
              cout( i ) = cout( i ) * tscale
           END DO
        END IF

     ELSE IF (isign > 0) THEN
        IF (is_inplace) THEN
            !$omp target data use_device_ptr(c)
              hipfft_status = hipfftExecZ2Z(hipfft_planz(ip), c_loc(c), c_loc(c), HIPFFT_BACKWARD)
            !$omp end target data
        ELSE
            !$omp target data use_device_ptr(c, cout)
            hipfft_status = hipfftExecZ2Z(hipfft_planz(ip), c_loc(c), c_loc(cout), HIPFFT_BACKWARD)
            !$omp end target data
        ENDIF
        IF(hipfft_status /= 0) CALL fftx_error__(' cft_1z GPU ',' stopped in hipfftExecZ2Z(Backward) ')
            CALL hipfftCheck(hipfft_status)

        CALL hipCheck(hipDeviceSynchronize())

     END IF

#if defined(__FFT_CLOCKS)
     CALL stop_clock( 'cft_1z' )
#endif

     RETURN

   CONTAINS !=------------------------------------------------=!

     SUBROUTINE lookup()

     DO ip = 1, ndims
        !   first check if there is already a table initialized
        !   for this combination of parameters
        !   The initialization in ESSL and FFTW v.3 depends on all three parameters
        found = ( nz == zdims(1,ip) ) .AND. ( nsl == zdims(2,ip) ) .AND. ( ldz == zdims(3,ip) )
        IF (found) EXIT
     END DO
     END SUBROUTINE lookup

     SUBROUTINE init_plan()
       IMPLICIT NONE
       INTEGER, PARAMETER :: RANK=1
       INTEGER :: FFT_DIM(RANK), DATA_DIM(RANK)
       INTEGER :: STRIDE, DIST, BATCH

        FFT_DIM(1) = nz
       DATA_DIM(1) = ldz
            STRIDE = 1
             DIST = ldz
             BATCH = nsl


       IF( hipfft_planz( icurrent) /= c_null_ptr ) THEN
           hipfft_status = hipfftDestroy( hipfft_planz( icurrent) )
           CALL fftx_error__(" fft_scalar_hipFFT: cft_1z_omp ", " hipfftDestroy failed ", hipfft_status)
       ENDIF
       hipfft_status = hipfftPlanMany(hipfft_planz( icurrent), RANK, c_loc(FFT_DIM), &
                              c_loc(DATA_DIM), STRIDE, DIST, &
                              c_loc(DATA_DIM), STRIDE, DIST, &
                              HIPFFT_Z2Z, BATCH )
       CALL fftx_error__(" fft_scalar_hipFFT: cft_1z_omp ", " hipfftPlanMany failed ", hipfft_status)

#ifdef TRACK_FLOPS
       zflops( icurrent ) = 5.0d0 * REAL( nz ) * log( REAL( nz ) )/log( 2.d0 )
#endif

       zdims(1,icurrent) = nz; zdims(2,icurrent) = nsl; zdims(3,icurrent) = ldz;
       ip = icurrent
       icurrent = MOD( icurrent, ndims ) + 1
     END SUBROUTINE init_plan


   END SUBROUTINE cft_1z_omp

   SUBROUTINE cft_2xy_omp(r_d, nzl, nx, ny, ldx, ldy, isign, pl2ix)

!     driver routine for nzl 2d complex fft's of lengths nx and ny
!     input : r_d(ldx*ldy)  complex, transform is in-place
!     ldx >= nx, ldy >= ny are the physical dimensions of the equivalent
!     2d array: r2d(ldx, ldy) (x first dimension, y second dimension)
!     (ldx>nx, ldy>ny used on some architectures to reduce memory conflicts)
!     pl2ix(nx) (optional) is 1 for columns along y to be transformed
!     isign > 0 : backward (f(G)=>f(R)), isign < 0 : forward (f(R) => f(G))
!     Up to "ndims" initializations (for different combinations of input
!     parameters nx,ny,nzl,ldx) are stored and re-used if available
     IMPLICIT NONE

     INTEGER, INTENT(IN) :: isign, ldx, ldy, nx, ny, nzl
     !FIXME: stream support not yet working
     !INTEGER(kind = hip_stream_kind), INTENT(IN) :: stream
     INTEGER, OPTIONAL, INTENT(IN) :: pl2ix(:)
     COMPLEX (DP), TARGET :: r_d(ldx,ldy,nzl)
     INTEGER :: i, k, j, err, idir, ip, kk, void, istat
     REAL(DP) :: tscale
     INTEGER, SAVE :: icurrent = 1
     INTEGER, SAVE :: dims( 6, ndims) = -1
     LOGICAL :: dofft( nfftx ), found
     INTEGER, PARAMETER  :: stdout = 6
#ifdef TRACK_FLOPS
     REAL (DP), SAVE :: xyflops( ndims ) = 0.d0
#endif

     INTEGER, SAVE :: hipfft_status = 0
     type(c_ptr), SAVE :: hipfft_plan_2d( ndims ) = c_null_ptr
     INTEGER :: batch_1, batch_2

     dofft( 1 : nx ) = .TRUE.
     batch_1 = nx
     batch_2 = 0
     IF( PRESENT( pl2ix ) ) THEN
       IF( SIZE( pl2ix ) < nx ) &
         CALL fftx_error__( ' cft_2xy ', ' wrong dimension for arg no. 8 ', 1 )
       DO i = 1, nx
         IF( pl2ix(i) < 1 ) dofft( i ) = .FALSE.
       END DO

       i=1
       do while(pl2ix(i) >= 1 .and. i<=nx); i=i+1; END DO
       batch_1 = i-1
       do while(pl2ix(i) < 1 .and. i<=nx); i=i+1; END DO
       batch_2 = nx-i+1
     END IF

     !
     !   Here initialize table only if necessary
     !

     CALL lookup()

     IF( .NOT. found ) THEN

       !   no table exist for these parameters
       !   initialize a new one
       CALL init_plan()

     END IF

     !istat = hipfftSetStream(hipfft_plan_2d(ip), stream)
     !CALL fftx_error__(" fft_scalar_hipFFT: cft_2xy_omp ", " failed to set stream ", istat)

     !
     !   Now perform the FFTs using machine specific drivers
     !

#if defined(__FFT_CLOCKS)
     CALL start_clock( 'GPU_cft_2xy' )
#endif

     IF( isign < 0 ) THEN
        !
        tscale = 1.0_DP / ( nx * ny )
        !
        !$omp target data use_device_ptr(r_d)
        istat = hipfftExecZ2Z( hipfft_plan_2d(ip), c_loc(r_d), c_loc(r_d), HIPFFT_FORWARD )
        !$omp end target data
        CALL fftx_error__(" fft_scalar_hipFFT: cft_2xy_omp ", " hipfftExecZ2Z failed ", istat)
        CALL hipCheck(hipDeviceSynchronize())

        !!!$omp target teams distribute parallel do simd
        !$omp target teams distribute parallel do collapse(3)
        DO k=1, nzl
           DO j=1, ldy
             DO i=1, ldx
                r_d(i,j,k) = r_d(i,j,k) * tscale
              END DO
           END DO
        END DO

     ELSE IF( isign > 0 ) THEN
        !$omp target data use_device_ptr(r_d)
        istat = hipfftExecZ2Z( hipfft_plan_2d(ip), c_loc(r_d), c_loc(r_d), HIPFFT_BACKWARD )
        !$omp end target data

        CALL fftx_error__(" fft_scalar_hipFFT: cft_2xy_omp ", " hipfftExecZ2Z failed ", istat)
        CALL hipCheck(hipDeviceSynchronize())
     END IF



#if defined(__FFT_CLOCKS)
     CALL stop_clock( 'GPU_cft_2xy' )
#endif

#ifdef TRACK_FLOPS
     fft_ops = fft_ops + xyflops( ip )
#endif

     RETURN

   CONTAINS

     SUBROUTINE lookup()

     DO ip = 1, ndims
       !   first check if there is already a table initialized
       !   for this combination of parameters
       found = ( ny == dims(1,ip) ) .AND. ( nx == dims(3,ip) )
       found = found .AND. ( ldx == dims(2,ip) ) .AND.  ( nzl == dims(4,ip) )
       IF (found) EXIT
     END DO
     END SUBROUTINE lookup

     SUBROUTINE init_plan()
       IMPLICIT NONE
       INTEGER, PARAMETER :: RANK=2
       INTEGER :: FFT_DIM(RANK), DATA_DIM(RANK)
       INTEGER :: STRIDE, DIST, BATCH

        FFT_DIM(1) = ny
        FFT_DIM(2) = nx
       DATA_DIM(1) = ldy
       DATA_DIM(2) = ldx
            STRIDE = 1
              DIST = ldx*ldy
             BATCH = nzl

       IF( hipfft_plan_2d( icurrent) /= c_null_ptr ) THEN
           istat = hipfftDestroy( hipfft_plan_2d(icurrent) )
           CALL fftx_error__(" fft_scalar_hipFFT: cft_2xy_omp ", " hipfftDestroy failed ", istat)
       ENDIF

       istat = hipfftPlanMany( hipfft_plan_2d( icurrent), RANK, c_loc(FFT_DIM), &
                              c_loc(DATA_DIM), STRIDE, DIST, &
                              c_loc(DATA_DIM), STRIDE, DIST, &
                              HIPFFT_Z2Z, BATCH )
       CALL fftx_error__(" fft_scalar_hipFFT: cft_2xy_omp ", " hipfftPlanMany failed ", istat)


#ifdef TRACK_FLOPS
       xyflops( icurrent ) = REAL( ny*nzl )                    * 5.0d0 * REAL( nx ) * log( REAL( nx )  )/log( 2.d0 ) &
                           + REAL( nzl*BATCH_1 + nzl*BATCH_2 ) * 5.0d0 * REAL( ny ) * log( REAL( ny )  )/log( 2.d0 )

#endif
       dims(1,icurrent) = ny; dims(2,icurrent) = ldx;
       dims(3,icurrent) = nx; dims(4,icurrent) = nzl;
       ip = icurrent
       icurrent = MOD( icurrent, ndims ) + 1
     END SUBROUTINE init_plan

   END SUBROUTINE cft_2xy_omp
   
   SUBROUTINE cfft3d_omp( f_d, nx, ny, nz, ldx, ldy, ldz, howmany, isign)

  !     driver routine for 3d complex fft of lengths nx, ny, nz
  !     input  :  f_d(ldx*ldy*ldz)  complex, transform is in-place
  !     ldx >= nx, ldy >= ny, ldz >= nz are the physical dimensions
  !     of the equivalent 3d array: f3d(ldx,ldy,ldz)
  !     (ldx>nx, ldy>ny, ldz>nz may be used on some architectures
  !      to reduce memory conflicts - not implemented for FFTW)
  !     isign > 0 : f(G) => f(R)   ; isign < 0 : f(R) => f(G)
  !
  !     Up to "ndims" initializations (for different combinations of input
  !     parameters nx,ny,nz) are stored and re-used if available

     IMPLICIT NONE

     INTEGER, INTENT(IN) :: nx, ny, nz, ldx, ldy, ldz, howmany, isign
     COMPLEX (DP) :: f_d(:)
     !FIXME: Add stream support
     !INTEGER(kind = cuda_stream_kind) :: stream
     INTEGER :: i, k, j, err, idir, ip, istat
     REAL(DP) :: tscale
     INTEGER, SAVE :: icurrent = 1
     INTEGER, SAVE :: dims(4,ndims) = -1

     type(c_ptr), SAVE :: hipfft_plan_3d( ndims ) = c_null_ptr


     IF ( nx < 1 ) &
         call fftx_error__('cfft3d',' nx is less than 1 ', 1)
     IF ( ny < 1 ) &
         call fftx_error__('cfft3d',' ny is less than 1 ', 1)
     IF ( nz < 1 ) &
         call fftx_error__('cfft3d',' nz is less than 1 ', 1)
     IF ( nx /= ldx .or. ny /= ldy .or. nz /= ldz ) &
         call fftx_error__('cfft3d',' leading dimensions must match data dimension ', 1)
     !
     !   Here initialize table only if necessary
     !
     CALL lookup()

     IF( ip == -1 ) THEN

       !   no table exist for these parameters
       !   initialize a new one

       CALL init_plan()

     END IF

     !
     !   Now perform the 3D FFT using the machine specific driver
     !
     !FIXME: Add stream support
     !istat = cufftSetStream(cufft_plan_3d(ip), stream)
     !call fftx_error__(" fft_scalar_cuFFT: cfft3d_omp ", " failed to set stream ", istat)

     IF( isign < 0 ) THEN

        !$omp target data use_device_ptr(f_d)
        istat = hipfftExecZ2Z( hipfft_plan_3d(ip), c_loc(f_d), c_loc(f_d), HIPFFT_FORWARD )
        !$omp end target data
        call fftx_error__(" fft_scalar_hipFFT: cfft3d_omp ", " hipfftExecZ2Z failed ", istat)
        CALL hipCheck(hipDeviceSynchronize())

       tscale = 1.0_DP / DBLE( nx * ny * nz )
       !$omp target teams distribute parallel do simd
        DO i=1, ldx*ldy*ldz*howmany
           f_d( i ) = f_d( i ) * tscale
        END DO

     ELSE IF( isign > 0 ) THEN

        !$omp target data use_device_ptr(f_d)
        istat = hipfftExecZ2Z( hipfft_plan_3d(ip), c_loc(f_d), c_loc(f_d), HIPFFT_BACKWARD )
        !$omp end target data
        call fftx_error__(" fft_scalar_hipFFT: cfft3d_omp ", " hipfftExecZ2Z failed ", istat)
        CALL hipCheck(hipDeviceSynchronize())

     END IF

     RETURN

   CONTAINS

     SUBROUTINE lookup()
     ip = -1
     DO i = 1, ndims
       !   first check if there is already a table initialized
       !   for this combination of parameters
       IF ( ( nx == dims(1,i) ) .and. &
            ( ny == dims(2,i) ) .and. &
            ( nz == dims(3,i) ) .and. &
            ( howmany == dims(4,i) ) ) THEN
         ip = i
         EXIT
       END IF
     END DO
     END SUBROUTINE lookup

     SUBROUTINE init_plan()
       INTEGER, PARAMETER :: RANK=3
       INTEGER :: FFT_DIM(RANK), DATA_DIM(RANK)
       INTEGER :: STRIDE, DIST, BATCH

        FFT_DIM(1) = nz
        FFT_DIM(2) = ny
        FFT_DIM(3) = nx
       DATA_DIM(1) = ldz
       DATA_DIM(2) = ldy
       DATA_DIM(3) = ldx
            STRIDE = 1
              DIST = ldx*ldy*ldz
             BATCH = howmany

       IF( hipfft_plan_3d( icurrent) /= c_null_ptr ) THEN
           istat = hipfftDestroy( hipfft_plan_3d(icurrent) )
           call fftx_error__(" fft_scalar_hipFFT: cfft3d_omp ", " hipfftDestroy failed ", istat)
       ENDIF

       istat = hipfftPlanMany( hipfft_plan_3d( icurrent), RANK, c_loc(FFT_DIM), &
                              c_loc(DATA_DIM), STRIDE, DIST, &
                              c_loc(DATA_DIM), STRIDE, DIST, &
                              HIPFFT_Z2Z, BATCH )
       call fftx_error__(" fft_scalar_hipFFT: cfft3d_omp ", " hipfftPlanMany failed ", istat)

       dims(1,icurrent) = nx; dims(2,icurrent) = ny; dims(3,icurrent) = nz
       dims(4,icurrent) = howmany
       ip = icurrent
       icurrent = MOD( icurrent, ndims ) + 1
     END SUBROUTINE init_plan

   END SUBROUTINE cfft3d_omp

   SUBROUTINE cfft3ds_omp(f, nx, ny, nz, ldx, ldy, ldz, howmany, isign, do_fft_z, do_fft_y)
     !
     implicit none

     integer :: nx, ny, nz, ldx, ldy, ldz, isign, howmany
     !
     complex(DP) :: f ( ldx * ldy * ldz )
     integer :: do_fft_y(:), do_fft_z(:)
     !
     CALL cfft3d_omp(f, nx, ny, nz, ldx, ldy, ldz, howmany, isign)

   END SUBROUTINE cfft3ds_omp

!=----------------------------------------------------------------------=!
END MODULE fft_scalar_hipfft
!=----------------------------------------------------------------------=!
#endif