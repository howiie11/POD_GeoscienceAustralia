MODULE m_pd_force


! ----------------------------------------------------------------------
! MODULE: m_pd_force
! ----------------------------------------------------------------------
! Purpose:
!  Module for calling the pd_force subroutine
! ----------------------------------------------------------------------
! Author :	Dr. Thomas Papanikolaou
!			Cooperative Research Centre for Spatial Information, Australia
! Created:	24 September 2018
! ----------------------------------------------------------------------


      IMPLICIT NONE
      !SAVE 			
  
	  
Contains


SUBROUTINE pd_force (mjd, rsat, vsat, Fvec, PDr, PDv, PD_param)


! ----------------------------------------------------------------------
! SUBROUTINE: pd_force.f03
! ----------------------------------------------------------------------
! Purpose:
!  Partial derivatives of the force model effects w.r.t. the satellite state vector and the (force-related) unknown parameters 
! ----------------------------------------------------------------------
! Input arguments:
! - mjd:			Modified Julian Day number (including the fraction of the day) in Terrestrial Time (TT)
! - rsat:			Satellite Position vector (m)   in inertial frame (ICRF)
! - vsat:			Satellite Velocity vector (m/s) in inertial frame (ICRF)
! 
! Output arguments:
! - Fvec:			Acceleration vector cartesian components in inertial frame (ICRF)
! - PDr: 			Partial derivatives matrix of the acceleration w.r.t. the position vector in ICRF
! - PDv: 			Partial derivatives matrix of the acceleration w.r.t. the velocity vector in ICRF
! - PD_param: 		Partial derivatives matrix of the acceleration w.r.t. the (force-related) unknown parameters in ICRF
! ----------------------------------------------------------------------
! Author :	Dr. Thomas Papanikolaou
! 			Cooperative Research Centre for Spatial Information, Australia
! Created:	September 2018
!
! Changes:     02-05-2019 Tzupang Tseng: use the coefficient from the shadow.f90 for scaling the SRP effect
! ----------------------------------------------------------------------


      USE mdl_precision
      USE mdl_num
      USE mdl_param
      USE mdl_eop
      USE mdl_planets
      USE mdl_tides
      USE m_force_gfm
      USE m_force_tides
      USE m_tides_ocean  
      USE m_pd_geopotential
      USE m_matrixRxR
      USE m_pd_empirical
      USE m_pd_ECOM
      USE m_shadow
      IMPLICIT NONE

! ----------------------------------------------------------------------
! Dummy arguments declaration
! ----------------------------------------------------------------------
! IN
      REAL (KIND = prec_d), INTENT(IN) :: mjd
      REAL (KIND = prec_d), INTENT(IN), DIMENSION(3) :: rsat, vsat
! ----------------------------------------------------------------------
! OUT
      REAL (KIND = prec_d), INTENT(OUT) :: Fvec(3)
      REAL (KIND = prec_d), INTENT(OUT) :: PDr(3,3), PDv(3,3)
      REAL (KIND = prec_d), INTENT(OUT), DIMENSION(:,:), ALLOCATABLE :: PD_param
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Local variables declaration
! ----------------------------------------------------------------------
      REAL (KIND = prec_d), DIMENSION(3) :: rsat_icrf, vsat_icrf, rsat_itrf, vsat_itrf, v_TRS_1, v_TRS_2
	  DOUBLE PRECISION EOP_cr(7)
      DOUBLE PRECISION CRS2TRS(3,3), TRS2CRS(3,3), d_CRS2TRS(3,3), d_TRS2CRS(3,3)	  
! ----------------------------------------------------------------------
      REAL (KIND = prec_d), DIMENSION(3) :: SF, SFgrav, SFnongrav, SFemp    
      REAL (KIND = prec_q), DIMENSION(3) :: Fgrav_itrf , Fgrav_icrf, Fplanets_icrf, Ftides_icrf, Frelativity_icrf
      REAL (KIND = prec_d), DIMENSION(3) :: Fsrp_icrf
      REAL (KIND = prec_d) :: fx, fy, fz, mjd_sav
! ----------------------------------------------------------------------
      REAL (KIND = prec_q) :: GMearth, aEarth
      INTEGER (KIND = prec_int8) :: n_max, m_max
      INTEGER(KIND = 4)          :: satsvn
! ----------------------------------------------------------------------
      REAL (KIND = prec_q), DIMENSION(3) :: aPlanets_icrf, a_perturb, a_iJ2, a_iJ2_icrf
      DOUBLE PRECISION  JD, Zbody(6)
      INTEGER  NTARG, NCTR, NTARG_body
      REAL (KIND = prec_q), DIMENSION(3) :: rbody
      REAL (KIND = prec_q) :: GMbody
      REAL (KIND = prec_q), DIMENSION(3) :: rSun, rMoon, rMoon_ITRS, rSun_ITRS		
      REAL (KIND = prec_q) :: GM_moon, GM_sun
      REAL (KIND = prec_q) :: C20, Re
! ----------------------------------------------------------------------
      REAL (KIND = prec_q) :: ut1_utc
      REAL (KIND = prec_d) :: xp, yp
! ----------------------------------------------------------------------
      REAL (KIND = prec_q), DIMENSION(5,5) :: dCnm_solid1, dSnm_solid1
      REAL (KIND = prec_q), DIMENSION(3,3) :: dCnm_solid2, dSnm_solid2	
      REAL (KIND = prec_q) :: dC20_perm
      REAL (KIND = prec_q) :: dC21_pse, dS21_pse, dC21_poc, dS21_poc
      INTEGER (KIND = prec_int8) :: sz_tides  
      INTEGER (KIND = prec_int8) :: i , j 
      REAL (KIND = prec_q) :: ax, ay, az
      REAL (KIND = prec_q), DIMENSION(3) :: a_tides, a_solidtides, a_ocean 
      REAL (KIND = prec_q), DIMENSION(3) :: a_solid1, a_solid2, a_pse, a_poc
      REAL (KIND = prec_q), DIMENSION(:,:), ALLOCATABLE :: dCnm_tides, dSnm_tides		
      REAL (KIND = prec_q), DIMENSION(:,:), ALLOCATABLE :: dCnm_ocean, dSnm_ocean		
! ----------------------------------------------------------------------
      REAL (KIND = prec_q), DIMENSION(6) :: Zsat_GCRS, Zearth_GCRS
      REAL (KIND = prec_q), DIMENSION(3) :: vSun
      REAL (KIND = prec_q), DIMENSION(3) :: a_Schwarzschild, a_LenseThirring, a_deSitter
! ----------------------------------------------------------------------
      INTEGER (KIND = prec_int2) :: AllocateStatus, DeAllocateStatus
      CHARACTER (LEN=30) :: fmt_line
      INTEGER (KIND = prec_int2) :: ios
      CHARACTER (LEN=1) :: GNSSid
      INTEGER (KIND = prec_int4) :: PRN_no
      INTEGER :: eclpf, srpid
! ----------------------------------------------------------------------
      REAL (KIND = prec_q) :: beta_ppn, gama_ppn
      REAL (KIND = prec_q) :: c_light
! ----------------------------------------------------------------------
     INTEGER (KIND = prec_int8) :: N_param, PD_Param_ID
      REAL (KIND = prec_d), DIMENSION(3,3) :: Ugrav_icrf, Ugrav_itrf, Ugrav
      REAL (KIND = prec_d) :: PD_EMP_r(3,3), PD_EMP_v(3,3)
      REAL (KIND = prec_d), DIMENSION(:,:), ALLOCATABLE :: PD_EMP_param
      REAL (KIND = prec_q), DIMENSION(:,:), ALLOCATABLE :: PD_ECOM_param
! ----------------------------------------------------------------------
      CHARACTER (LEN=3)  :: PRN_GNSS
      INTEGER (KIND = 4) :: satblk
      CHARACTER (LEN=5)  :: BDSorbtype
      INTEGER (KIND = 4) :: eclipsf
      REAL (KIND = prec_d) :: beta, Mangle, Yangle(2)
      REAL (KIND = prec_d) , Dimension(3) :: eBX_nom, eBX_ecl
      INTEGER (KIND = prec_int2) :: Frame_EmpiricalForces
      REAL (KIND = prec_d) :: Yawangle
      REAL (KIND = prec_q) :: lambda
      CHARACTER (KIND = 1) :: ECLTYP

! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Global variables used
! ----------------------------------------------------------------------
! Module mdl_param.f03:

! FMOD_GRAV, FMOD_NONGRAV
! GFM_Cnm, GFM_Snm
! GFM_Nmax, GFM_Mmax
! OCEAN_Nmax, OCEAN_Mmax
GMearth = GFM_GM
aEarth = GFM_ae
! ----------------------------------------------------------------------
! Module mdl_num.f90:

! Relativistic parameters
beta_ppn = ppn_beta
gama_ppn = ppn_gama
c_light = cslight
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Partial derivatives w.r.t. unknown parameters
N_param = NPARAM_glb
If (N_param == 0) Then
N_param = 1
End If
ALLOCATE (PD_param(3,N_param), STAT = AllocateStatus)
PD_Param_ID = 0
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
If (FMOD_GRAVFIELD == 0) THEN

! Module mdl_num
GMearth = GM_global
aEarth = Earth_radius

END IF
! ----------------------------------------------------------------------

! State Vector in ICRF
rsat_icrf = rsat
vsat_icrf = vsat

! ----------------------------------------------------------------------
! EOP data and Tranformation matrices between ITRF and ICRF
! ----------------------------------------------------------------------
If (FMOD_GRAVFIELD > 0 .OR. FMOD_GRAV(2) > 0 .OR. FMOD_GRAV(3) > 0 .OR. FMOD_GRAV(4) > 0 ) Then

CALL EOP (mjd, EOP_cr, CRS2TRS, TRS2CRS, d_CRS2TRS, d_TRS2CRS)	  

! EOP data corrected at computation epoch 
! Polar motion coordinates
xp = EOP_cr(2) 
yp = EOP_cr(3)
! UT1-UTC
ut1_utc = EOP_cr(4) 

! State Vector in ITRF
! r in ITRF
CALL matrix_Rr (CRS2TRS, rsat_icrf , rsat_itrf)
! v in ITRF 
! v_TRS = TRS2CRS * v_CRS + d_CRS2TRS * r_CRS
CALL matrix_Rr (CRS2TRS, vsat_icrf , v_TRS_1)
CALL matrix_Rr (d_CRS2TRS, rsat_icrf , v_TRS_2)
vsat_itrf = v_TRS_1 + v_TRS_2

End IF 
! ----------------------------------------------------------------------


! ----------------------------------------------------------------------
! Gravitational Effects
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Gravity Field
If (FMOD_GRAV(1) == 0) Then

! Setting to Zero
fx = 0.0D0
fy = 0.0D0
fz = 0.0D0	  
Fgrav_icrf = (/ fx, fy, fz /)

Ugrav_icrf(1,:) = (/0.0D0, 0.0D0, 0.0D0 /)
Ugrav_icrf(2,:) = (/0.0D0, 0.0D0, 0.0D0 /)
Ugrav_icrf(3,:) = (/0.0D0, 0.0D0, 0.0D0 /)

Else 	  

If (FMOD_GRAVFIELD == 0) Then

! Central term of the Earth Gravity Field 
Call force_gm (GMearth, rsat_icrf, fx,fy,fz )
Fgrav_icrf = (/ fx, fy, fz /)
! Partial derivatives
Call pd_gm (GMearth, rsat_icrf, Ugrav_icrf)

Else 

! Earth Gravity Field model acceleration components (spherical harmonics expansion) 
n_max = GFM_Nmax
m_max = GFM_Mmax

! Partial derivatives
Call pd_geopotential(GMearth, aEarth, rsat_itrf, n_max, m_max, GFM_Cnm, GFM_Snm, Fgrav_itrf, Ugrav_itrf)

! Acceleration vector transformation from terrestrial to inertial frame
CALL matrix_Rr (TRS2CRS, Fgrav_itrf , Fgrav_icrf)

! PD matrix transformation ITRF to ICRF
! (df/dr)_Inertial = EOP(t) * (df/dr)_Terrestrial * inv( EOP(t) )
Ugrav = MATMUL(TRS2CRS, Ugrav_itrf) 		
Ugrav_icrf = MATMUL(Ugrav, TRANSPOSE(TRS2CRS)) 		

End IF

End If
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Planetary/Lunar orbital perturbations
! ----------------------------------------------------------------------
If (FMOD_GRAV(2) > 0) Then

! Julian Day Number of the input epoch
JD = mjd + 2400000.5D0

! Center celestial body: Earth
NCTR = 3 

! Planets perturbation loop
aPlanets_icrf = (/ 0.D0, 0.0D0, 0.0D0 /)
DO NTARG_body = 1 , 11
   IF (NTARG_body /= 3) THEN 
		
! Celestial body's (NTARG) Cartesian coordinates w.r.t. Center body (NCTR)
      NTARG = NTARG_body
      CALL  PLEPH ( JD, NTARG, NCTR, Zbody )
	  
! Cartesian coordinates of the celestial body in meters: KM to M
	  rbody(1) = Zbody(1) * 1000.D0
	  rbody(2) = Zbody(2) * 1000.D0
	  rbody(3) = Zbody(3) * 1000.D0

! GM gravity constants of the solar system bodies
      GMbody = GMconst(NTARG)
  
! ----------------------------------------------------------------------
! Point-mass perturbations vector due to the selected celestial body
      CALL force_gm3rd (rbody, rsat_icrf, GMbody , a_perturb)
! Overall (sum) planetary pertrubation acceleration vector
	  aPlanets_icrf = aPlanets_icrf + a_perturb
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Sun
      if (NTARG == 11) then
	  rSun = rbody
	  vSun = (/ Zbody(4), Zbody(5), Zbody(6) /) * 1000.D0 ! KM/sec to m/sec	  
      GM_sun = GMbody     
! ----------------------------------------------------------------------
! Moon
      else if (NTARG == 10) then
	  rMoon = rbody
      GM_moon = GMbody
      end if
! ----------------------------------------------------------------------  
   END IF
END DO  
	  
! ----------------------------------------------------------------------
! Indirect J2 effect
! ----------------------------------------------------------------------
! Sun and Moon position vectors in terrestrial reference frame 
! Transformation GCRS to ITRS 
CALL matrix_Rr (CRS2TRS,rMoon , rMoon_ITRS)
CALL matrix_Rr (CRS2TRS,rSun  , rSun_ITRS)

If (FMOD_GRAVFIELD > 0) Then
! C20 spherical harmonic coefficient of geopotential 
C20 = GFM_Cnm(2+1,0+1)
!Re = GFM_ae
Else If (FMOD_GRAVFIELD == 0) then
C20 = -4.841694552725D-04
!Re = Earth_radius
End IF

! Earth Radius
Re = aEarth
  
! Indirect J2 effect of Sun and Moon
CALL indirectJ2(C20,Re,GM_moon,rMoon_ITRS,GM_sun,rSun_ITRS , a_iJ2)

! Acceleration vector transformation from terrestrial to inertial frame
CALL matrix_Rr (TRS2CRS, a_iJ2 , a_iJ2_icrf)
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Planetary/Lunar perturbation accleration
Fplanets_icrf = aPlanets_icrf + a_iJ2_icrf
! ----------------------------------------------------------------------

ELSE If (FMOD_GRAV(2) == 0) Then
Fplanets_icrf = (/ 0.D0, 0.0D0, 0.0D0 /)
End IF	  
! ----------------------------------------------------------------------


! ----------------------------------------------------------------------
! Tidal effects
! ----------------------------------------------------------------------
If (FMOD_GRAV(3) > 0) Then

! ----------------------------------------------------------------------
! Solid Earth Tides
! ----------------------------------------------------------------------
! Frequency-independent : Step 1 (IERS Conventions 2010)
If (FMOD_TIDES(1) > 0) Then 
      CALL tides_solid1(rMoon_ITRS, rSun_ITRS, GMearth, aEarth, GM_moon, GM_sun, dCnm_solid1, dSnm_solid1)  
Else If (FMOD_TIDES(1) == 0) Then  
      dCnm_solid1 = 0.0D0
      dSnm_solid1 = 0.0D0
End if

! Frequency-dependent : Step 2 (IERS Conventions 2010)
If (FMOD_TIDES(2) > 0) Then 
      CALL tides_solid2(mjd, ut1_utc , dCnm_solid2, dSnm_solid2)
Else If (FMOD_TIDES(2) == 0) Then
      dCnm_solid2 = 0.0D0
      dSnm_solid2 = 0.0D0
End if
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Zero Tide term
CALL tide_perm (dC20_perm)
! Tide system of the input gravity field model is set in the GFM_tide global variable in the module mdl_param.f03
if (GFM_tide == 'zero_tide') then
   dCnm_solid1(2+1,0+1) = dCnm_solid1(2+1,0+1) - dC20_perm
   !dCnm_solid2(2+1,0+1) = dCnm_solid2(2+1,0+1) - dC20_perm
end if	  
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Pole Tide
! ----------------------------------------------------------------------
! Solid Earth pole tide
dC21_pse = 0.0D0
dS21_pse = 0.0D0
If (FMOD_TIDES(4) == 1) Then 
      CALL tide_pole_se (mjd,xp,yp , dC21_pse, dS21_pse)  
End if
 
! Ocean pole tide
dC21_poc = 0.0D0
dS21_poc = 0.0D0
If (FMOD_TIDES(5) == 1) Then 
      CALL tide_pole_oc (mjd,xp,yp , dC21_poc, dS21_poc)
end if
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! dCnm, dSnm arrays sum
sz_tides = SIZE (dCnm_solid1,DIM=1)
ALLOCATE (dCnm_tides(sz_tides,sz_tides), STAT = AllocateStatus)
      IF (AllocateStatus /= 0) THEN
         PRINT *, "Error: Not enough memory"
         PRINT *, "Error: SUBROUTINE force_sum.f03"
         PRINT *, "Error: Allocatable Array: dCnm_tides | Nmax:", sz_tides
!         STOP "*** Not enough memory ***"
      END IF  
ALLOCATE (dSnm_tides(sz_tides,sz_tides), STAT = AllocateStatus)
      IF (AllocateStatus /= 0) THEN
         PRINT *, "Error: Not enough memory"
         PRINT *, "Error: SUBROUTINE force_sum.f03"
         PRINT *, "Error: Allocatable Array: dSnm_tides | Nmax:", sz_tides
!         STOP "*** Not enough memory ***"
      END IF  
dCnm_tides = dCnm_solid1
dSnm_tides = dSnm_solid1

Do i = 1 , 3
Do j = 1 , 3
   dCnm_tides(i,j) = dCnm_tides(i,j) + dCnm_solid2(i,j) 
   dSnm_tides(i,j) = dSnm_tides(i,j) + dSnm_solid2(i,j) 
End Do
End Do

dCnm_tides(2+1,1+1) = dCnm_tides(2+1,1+1) + dC21_pse + dC21_poc 
dSnm_tides(2+1,1+1) = dSnm_tides(2+1,1+1) + dS21_pse + dS21_poc

! Acceleration cartesian components
CALL force_tides(rsat_itrf, GMearth, aEarth, sz_tides-1, sz_tides-1, dCnm_tides, dSnm_tides, ax,ay,az)
a_solidtides(1) = ax
a_solidtides(2) = ay
a_solidtides(3) = az
DEALLOCATE (dCnm_tides,   STAT = DeAllocateStatus)
DEALLOCATE (dSnm_tides,   STAT = DeAllocateStatus)
sz_tides = 0
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Ocean Tides
a_ocean = (/ 0.D0, 0.0D0, 0.0D0 /)
If (FMOD_TIDES(3) == 1) Then 
      CALL tides_ocean(OCEAN_Nmax, OCEAN_Mmax, mjd, ut1_utc, dCnm_ocean, dSnm_ocean)
      ! Acceleration cartesian components
	  !CALL force_tides(rsat_itrf, GMearth, aEarth, sz_tides-1, sz_tides-1, dCnm_ocean, dSnm_ocean, ax,ay,az)
	  CALL force_tides(rsat_itrf, GMearth, aEarth, OCEAN_Nmax, OCEAN_Mmax, dCnm_ocean, dSnm_ocean, ax,ay,az)
      a_ocean (1) = ax
      a_ocean (2) = ay
      a_ocean (3) = az  
      DEALLOCATE (dCnm_ocean,   STAT = DeAllocateStatus)
      DEALLOCATE (dSnm_ocean,   STAT = DeAllocateStatus)
      sz_tides = 0
End if
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Tides acceleration cartesian components : Overall effects
! ----------------------------------------------------------------------
!a_tides = a_solid1 + a_solid2 + a_ocean + a_pse + a_poc
a_tides = a_solidtides + a_ocean 
 
! Acceleration vector transformation from terrestrial to inertial frame
CALL matrix_Rr (TRS2CRS, a_tides , Ftides_icrf)
! ----------------------------------------------------------------------
 
Else If (FMOD_GRAV(3) == 0) Then
Ftides_icrf = (/ 0.D0, 0.0D0, 0.0D0 /)
End IF
! End of Tidal effects
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Relativistic effects
! ----------------------------------------------------------------------
If (FMOD_GRAV(4) > 0) Then

! Satellite State Vector in GCRS
Zsat_GCRS = (/rsat_icrf(1), rsat_icrf(2), rsat_icrf(3), vsat_icrf(1), vsat_icrf(2), vsat_icrf(3) /) 

! Earth state vector w.r.t. Sun
Zearth_GCRS = -1.0D0 * (/ rSun(1),rSun(2),rSun(3) , vSun(1),vSun(2),vSun(3) /)
!PRINT *,"Zearth_GCRS",Zearth_GCRS

! Schwarzschild terms
CALL rel_schwarzschild (Zsat_GCRS, Zearth_GCRS, GMearth, beta_ppn, gama_ppn, c_light, a_Schwarzschild)

! Lense-Thirring effects	  
CALL rel_LenseThirring (Zsat_GCRS, Zearth_GCRS,  GMearth, gama_ppn, c_light , a_LenseThirring)
a_LenseThirring = (/ 0.D0, 0.0D0, 0.0D0 /)

! de Sitter effect or geodesic precesssion 
CALL rel_deSitter (Zsat_GCRS, Zearth_GCRS, GMearth, GM_sun, gama_ppn, c_light , a_deSitter)

Frelativity_icrf = a_Schwarzschild + a_LenseThirring + a_deSitter

Else If (FMOD_GRAV(4) == 0) Then

Frelativity_icrf = (/ 0.D0, 0.0D0, 0.0D0 /)

End IF
! ----------------------------------------------------------------------

! Summary of gravitational effects 
SFgrav = Fgrav_icrf + Fplanets_icrf + Ftides_icrf + Frelativity_icrf 
! End of Gravitational Effects
! ----------------------------------------------------------------------


! ----------------------------------------------------------------------
! Attitude model :: GNSS Yaw-attitude models
! ----------------------------------------------------------------------
! Variables "satblk" and "BDSorbtype" are temporary manually configured 
! in the main program file (main_pod.f03) through setting the global variables:  

! GPS case: Satellite Block ID:        1=I, 2=II, 3=IIA, IIR=(4, 5), IIF=6
satblk = SATblock_glb

! Beidou case: 'IGSO', 'MEO'
BDSorbtype = BDSorbtype_glb

fmt_line = '(A1,I2.2)'
READ (PRN, fmt_line , IOSTAT=ios) GNSSid, PRN_no

! Yaw-attitude model
PRN_GNSS = PRN
CALL attitude (mjd, rsat_icrf, vsat_icrf, rSun, PRN_GNSS, satblk, BDSorbtype, &
                     eclipsf, beta, Mangle, Yangle, eBX_nom, eBX_ecl)
! ----------------------------------------------------------------------


! ----------------------------------------------------------------------
! shadow model :: A conical model is applied.
!                 lambda = 1     : In SUN LIGHT AREA
!                        = 0     : In UMBRA AREA (full eclipse)
!                 0 < lambda < 1 : In PENUMBRA AREA
! ----------------------------------------------------------------------
CALL shadow (rsat_icrf, rSun, rMoon, lambda, ECLTYP )
!if ( ECLTYP .ne. ' ') then
!   print*, mjd, lambda, ECLTYP
!endif

! ----------------------------------------------------------------------
! Non-Gravitational Effects
! ----------------------------------------------------------------------
if (FMOD_NONGRAV(1) > 0 .OR. FMOD_NONGRAV(2) > 0 .or. FMOD_NONGRAV (3) > 0) Then
! PRN: GNSS constellation ID letter + Satellite number
fmt_line = '(A1,I2.2)'
READ (PRN, fmt_line , IOSTAT=ios) GNSSid, PRN_no

CALL prn_shift (GNSSid, PRN_no, PRN_no)
!print*,GNSSid, PRN_no

END IF

! ----------------------------------------------------------------------
! Solar Radiation
! ----------------------------------------------------------------------
if (FMOD_NONGRAV(1) > 0) Then


! SRP model
srpid =  SRP_MOD_glb

CALL force_srp (lambda, eBX_ecl, GMearth, PRN_no, eclipsf, srpid, rsat_icrf, vsat_icrf, rSun, fx, fy, fz )
Fsrp_icrf = (/ fx, fy, fz /)

IF (ECOM_param_glb /= 0) THEN ! Condition added 5/6/2019 in order to avoid program segment fault

CALL pd_ECOM (lambda, eBX_ecl, GMearth, PRN_no, eclipsf, rsat_icrf, vsat_icrf, rSun, PD_ECOM_param )

END IF

Else IF (FMOD_NONGRAV(1) == 0) Then

	Fsrp_icrf = (/ 0.D0, 0.0D0, 0.0D0 /)

End IF
! ----------------------------------------------------------------------

! Summary of non-gravitational effects
SFnongrav = Fsrp_icrf
! End of non-Gravitational Effects
! ----------------------------------------------------------------------


! ----------------------------------------------------------------------
! Empirical forces
! ----------------------------------------------------------------------
IF (EMP_param_glb == 1) Then

!Call pd_empirical (rsat_icrf, vsat_icrf, GMearth, SFemp, PD_EMP_r, PD_EMP_v, PD_EMP_param)	
Frame_EmpiricalForces = Frame_EmpiricalForces_glb	
Yawangle = Yangle(2)
CALL pd_empirical (rsat_icrf, vsat_icrf, GMearth, Yawangle, Frame_EmpiricalForces, & 
                   SFemp, PD_EMP_r, PD_EMP_v, PD_EMP_param)
	
Else IF (EMP_param_glb == 0) Then
	SFemp = (/ 0.0D0, 0.0D0, 0.0D0 /)
	Do i = 1 , 3
		Do j = 1 , 3
			PD_EMP_r(i,j) = 0.0D0
		End Do
	End Do
	!PD_EMP_param = 
End IF
! ----------------------------------------------------------------------


! ----------------------------------------------------------------------
! Acceleration sum of the force model
! ----------------------------------------------------------------------
!SF = Fgrav_icrf + Fplanets_icrf + Ftides_icrf + Frelativity_icrf + Fsrp_icrf
SF = SFgrav + SFnongrav + SFemp 		
Fvec = SF
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Partial derivatives w.r.t state vector - overall matrix
! ----------------------------------------------------------------------
! PD w.r.t position vector
PDr = Ugrav_icrf + PD_EMP_r
! PD  w.r.t velocity vector
!PDv
! ----------------------------------------------------------------------

! ----------------------------------------------------------------------
! Partial derivatives w.r.t unknown parameters to be estimated
! ----------------------------------------------------------------------
IF (EMP_param_glb == 1) Then
PD_param = PD_EMP_param
End IF


IF (ECOM_param_glb == 1 .or.  ECOM_param_glb == 2) Then
PD_param = PD_ECOM_param
END IF
!print*,'ECOM_param_glb=',ECOM_param_glb
!print*,'PD_param=',PD_param
!print*,'NPARAM_glb=',NPARAM_glb
!pause

! ----------------------------------------------------------------------

END SUBROUTINE

END Module
