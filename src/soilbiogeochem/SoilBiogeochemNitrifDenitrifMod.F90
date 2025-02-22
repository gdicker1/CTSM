module SoilBiogeochemNitrifDenitrifMod

  !-----------------------------------------------------------------------
  ! !DESCRIPTION:
  ! Calculate nitrification and denitrification rates
  !
  !
  ! !USES:
  use shr_kind_mod                    , only : r8 => shr_kind_r8
  use shr_const_mod                   , only : SHR_CONST_TKFRZ
  use shr_log_mod                     , only : errMsg => shr_log_errMsg
  use clm_varpar                      , only : nlevdecomp
  use clm_varcon                      , only : rpi, grav
  use clm_varcon                      , only : d_con_g, d_con_w, secspday
  use clm_varctl                      , only : use_lch4
  use abortutils                      , only : endrun
  use decompMod                       , only : bounds_type
  use SoilStatetype                   , only : soilstate_type
  use WaterStateBulkType                  , only : waterstatebulk_type
  use TemperatureType                 , only : temperature_type
  use SoilBiogeochemCarbonFluxType    , only : soilbiogeochem_carbonflux_type
  use SoilBiogeochemNitrogenStateType , only : soilbiogeochem_nitrogenstate_type
  use SoilBiogeochemNitrogenFluxType  , only : soilbiogeochem_nitrogenflux_type
  use ch4Mod                          , only : ch4_type
  use ColumnType                      , only : col                
  !
  implicit none
  private
  !
  public :: readParams                      ! Read in parameters from params file
  public :: SoilBiogeochemNitrifDenitrif    ! Calculate nitrification and 
  !
  type, private :: params_type
     real(r8) :: k_nitr_max_perday     ! maximum nitrification rate constant (1/day)
     real(r8) :: surface_tension_water ! surface tension of water(J/m^2), Arah an and Vinten 1995
     real(r8) :: rij_kro_a             ! Arah and Vinten 1995)
     real(r8) :: rij_kro_alpha         ! parameter to calculate anoxic fraction of soil  (Arah and Vinten 1995)
     real(r8) :: rij_kro_beta          ! (Arah and Vinten 1995)
     real(r8) :: rij_kro_gamma         ! (Arah and Vinten 1995)
     real(r8) :: rij_kro_delta         ! (Arah and Vinten 1995)
     real(r8) :: denitrif_respiration_coefficient ! Multiplier for heterotrophic respiration for max denitrif rates
     real(r8) :: denitrif_respiration_exponent    ! Exponents for heterotrophic respiration for max denitrif rates
     real(r8) :: denitrif_nitrateconc_coefficient ! Multiplier for nitrate concentration for max denitrif rates
     real(r8) :: denitrif_nitrateconc_exponent    ! Exponent for nitrate concentration for max denitrif rates
     real(r8) :: om_frac_sf            ! Scale factor for organic matter fraction (unitless)
  end type params_type

  type(params_type), private :: params_inst

  logical, public :: no_frozen_nitrif_denitrif = .false.  ! stop nitrification and denitrification in frozen soils

  character(len=*), parameter, private :: sourcefile = &
       __FILE__

  !-----------------------------------------------------------------------

contains

  !-----------------------------------------------------------------------  
  subroutine readParams ( ncid )
    !
    use ncdio_pio, only: file_desc_t,ncd_io
    !
    ! !ARGUMENTS:
    type(file_desc_t),intent(inout) :: ncid   ! pio netCDF file id
    !
    ! !LOCAL VARIABLES:
    character(len=32)  :: subname = 'CNNitrifDenitrifParamsType'
    character(len=100) :: errCode = '-Error reading in parameters file:'
    logical            :: readv ! has variable been read in or not
    real(r8)           :: tempr ! temporary to read in constant
    character(len=100) :: tString ! temp. var for reading
    !-----------------------------------------------------------------------
    !
    ! read in constants
    !

    tString='surface_tension_water'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%surface_tension_water=tempr

    tString='rij_kro_a'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%rij_kro_a=tempr

    tString='rij_kro_alpha'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%rij_kro_alpha=tempr

    tString='rij_kro_beta'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%rij_kro_beta=tempr

    tString='rij_kro_gamma'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%rij_kro_gamma=tempr

    tString='rij_kro_delta'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%rij_kro_delta=tempr

    tString='k_nitr_max_perday'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%k_nitr_max_perday=tempr

    tString='denitrif_nitrateconc_coefficient'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%denitrif_nitrateconc_coefficient=tempr

    tString='denitrif_nitrateconc_exponent'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%denitrif_nitrateconc_exponent=tempr

    tString='denitrif_respiration_coefficient'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%denitrif_respiration_coefficient=tempr

    tString='denitrif_respiration_exponent'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%denitrif_respiration_exponent=tempr

    tString='om_frac_sf'
    call ncd_io(trim(tString),tempr, 'read', ncid, readvar=readv)
    if ( .not. readv ) call endrun(msg=trim(errCode)//trim(tString)//errMsg(sourcefile, __LINE__))
    params_inst%om_frac_sf=tempr

  end subroutine readParams

  !-----------------------------------------------------------------------
  subroutine SoilBiogeochemNitrifDenitrif(bounds, num_bgc_soilc, filter_bgc_soilc, &
       soilstate_inst, waterstatebulk_inst, temperature_inst, ch4_inst, &
       soilbiogeochem_carbonflux_inst, soilbiogeochem_nitrogenstate_inst, soilbiogeochem_nitrogenflux_inst)
    !
    ! !DESCRIPTION:
    !  calculate nitrification and denitrification rates
    !
    ! !USES:
    use clm_time_manager  , only : get_curr_date
    use CNSharedParamsMod , only : CNParamsShareInst
    !
    ! !ARGUMENTS:
    type(bounds_type)                       , intent(in)    :: bounds  
    integer                                 , intent(in)    :: num_bgc_soilc         ! number of soil columns in filter
    integer                                 , intent(in)    :: filter_bgc_soilc(:)   ! filter for soil columns
    type(soilstate_type)                    , intent(in)    :: soilstate_inst
    type(waterstatebulk_type)                   , intent(in)    :: waterstatebulk_inst
    type(temperature_type)                  , intent(in)    :: temperature_inst
    type(ch4_type)                          , intent(in)    :: ch4_inst
    type(soilbiogeochem_carbonflux_type)    , intent(in)    :: soilbiogeochem_carbonflux_inst
    type(soilbiogeochem_nitrogenstate_type) , intent(in)    :: soilbiogeochem_nitrogenstate_inst
    type(soilbiogeochem_nitrogenflux_type)  , intent(inout) :: soilbiogeochem_nitrogenflux_inst
    !
    ! !LOCAL VARIABLES:
    integer  :: c, fc, reflev, j
    real(r8) :: soil_hr_vr(bounds%begc:bounds%endc,1:nlevdecomp) ! total soil respiration rate (g C / m3 / s)
    real(r8) :: g_per_m3__to__ug_per_gsoil
    real(r8) :: g_per_m3_sec__to__ug_per_gsoil_day
    real(r8) :: mu, sigma
    real(r8) :: t
    real(r8) :: pH(bounds%begc:bounds%endc)
    !debug-- put these type structure for outing to hist files
    real(r8) :: co2diff_con(2)                      ! diffusion constants for CO2
    real(r8) :: eps
    real(r8) :: f_a
    real(r8) :: surface_tension_water ! (J/m^2), Arah and Vinten 1995
    real(r8) :: rij_kro_a             !  Arah and Vinten 1995
    real(r8) :: rij_kro_alpha         !  Arah and Vinten 1995
    real(r8) :: rij_kro_beta          !  Arah and Vinten 1995
    real(r8) :: rij_kro_gamma         !  Arah and Vinten 1995
    real(r8) :: rij_kro_delta         !  Arah and Vinten 1995
    real(r8) :: rho_w  = 1.e3_r8                   ! (kg/m3)
    real(r8) :: r_max
    real(r8) :: r_min(bounds%begc:bounds%endc,1:nlevdecomp)
    real(r8) :: ratio_diffusivity_water_gas(bounds%begc:bounds%endc,1:nlevdecomp)
    real(r8) :: om_frac
    real(r8) :: anaerobic_frac_sat, r_psi_sat, r_min_sat ! scalar values in sat portion for averaging
    real(r8) :: organic_max              ! organic matter content (kg/m3) where
                                         ! soil is assumed to act like peat
    character(len=32) :: subname='nitrif_denitrif' ! subroutine name
    !-----------------------------------------------------------------------

    associate(                                                                                                    & 
         watsat                        =>    soilstate_inst%watsat_col                                          , & ! Input:  [real(r8) (:,:)  ]  volumetric soil water at saturation (porosity) (nlevgrnd)
         watfc                         =>    soilstate_inst%watfc_col                                           , & ! Input:  [real(r8) (:,:)  ]  volumetric soil water at field capacity (nlevsoi)
         bd                            =>    soilstate_inst%bd_col                                              , & ! Input:  [real(r8) (:,:)  ]  bulk density of dry soil material [kg/m3]       
         bsw                           =>    soilstate_inst%bsw_col                                             , & ! Input:  [real(r8) (:,:)  ]  Clapp and Hornberger "b" (nlevgrnd)             
         cellorg                       =>    soilstate_inst%cellorg_col                                         , & ! Input:  [real(r8) (:,:)  ]  column 3D org (kg/m3 organic matter) (nlevgrnd) 
         sucsat                        =>    soilstate_inst%sucsat_col                                          , & ! Input:  [real(r8) (:,:)  ]  minimum soil suction (mm)                       
         soilpsi                       =>    soilstate_inst%soilpsi_col                                         , & ! Input:  [real(r8) (:,:)  ]  soil water potential in each soil layer (MPa)   
         
         h2osoi_vol                    =>    waterstatebulk_inst%h2osoi_vol_col                                     , & ! Input:  [real(r8) (:,:)  ]  volumetric soil water (0<=h2osoi_vol<=watsat) [m3/m3]  (nlevgrnd)
         h2osoi_liq                    =>    waterstatebulk_inst%h2osoi_liq_col                                     , & ! Input:  [real(r8) (:,:)  ]  liquid water (kg/m2) (new) (-nlevsno+1:nlevgrnd)
         
         t_soisno                      =>    temperature_inst%t_soisno_col                                      , & ! Input:  [real(r8) (:,:)  ]  soil temperature (Kelvin)  (-nlevsno+1:nlevgrnd)
         
         o2_decomp_depth_unsat         =>    ch4_inst%o2_decomp_depth_unsat_col                                 , & ! Input:  [real(r8) (:,:)  ]  O2 consumption during decomposition in each soil layer (nlevsoi) (mol/m3/s)
         conc_o2_unsat                 =>    ch4_inst%conc_o2_unsat_col                                         , & ! Input:  [real(r8) (:,:)  ]  O2 conc in each soil layer (mol/m3) (nlevsoi)   
         o2_decomp_depth_sat           =>    ch4_inst%o2_decomp_depth_sat_col                                   , & ! Input:  [real(r8) (:,:)  ]  O2 consumption during decomposition in each soil layer (nlevsoi) (mol/m3/s)
         conc_o2_sat                   =>    ch4_inst%conc_o2_sat_col                                           , & ! Input:  [real(r8) (:,:)  ]  O2 conc in each soil layer (mol/m3) (nlevsoi)   
         finundated                    =>    ch4_inst%finundated_col                                            , & ! Input:  [real(r8) (:)    ]  fractional inundated area in soil column (excluding dedicated wetland columns)

         smin_nh4_vr                   =>    soilbiogeochem_nitrogenstate_inst%smin_nh4_vr_col                  , & ! Input:  [real(r8) (:,:)  ]  (gN/m3) soil mineral NH4 pool                   
         smin_no3_vr                   =>    soilbiogeochem_nitrogenstate_inst%smin_no3_vr_col                  , & ! Input:  [real(r8) (:,:)  ]  (gN/m3) soil mineral NO3 pool                   

         phr_vr                        =>    soilbiogeochem_carbonflux_inst%phr_vr_col                          , & ! Input:  [real(r8) (:,:)  ]  potential hr (not N-limited)                    
         w_scalar                      =>    soilbiogeochem_carbonflux_inst%w_scalar_col                        , & ! Input:  [real(r8) (:,:)  ]  soil water scalar for decomp                    
         t_scalar                      =>    soilbiogeochem_carbonflux_inst%t_scalar_col                        , & ! Input:  [real(r8) (:,:)  ]  temperature scalar for decomp                   
         denit_resp_coef               =>    params_inst%denitrif_respiration_coefficient                       , & ! Input:  [real(r8)        ]  coefficient for max denitrification rate based on respiration
         denit_resp_exp                =>    params_inst%denitrif_respiration_exponent                          , & ! Input:  [real(r8)        ] exponent for max denitrification rate based on respiration
         denit_nitrate_coef            =>    params_inst%denitrif_nitrateconc_coefficient                       , & ! Input:  [real(r8)        ] coefficient for max denitrification rate based on nitrate concentration
         denit_nitrate_exp             =>    params_inst%denitrif_nitrateconc_exponent                          , & ! Input:  [real(r8)        ] exponent for max denitrification rate based on nitrate concentration
         k_nitr_max_perday             =>    params_inst%k_nitr_max_perday                                      , & ! Input:  [real(r8)        ] maximum nitrification rate constant (1/day)
         r_psi                         =>    soilbiogeochem_nitrogenflux_inst%r_psi_col                         , & ! Output:  [real(r8) (:,:)  ]                                                  
         anaerobic_frac                =>    soilbiogeochem_nitrogenflux_inst%anaerobic_frac_col                , & ! Output:  [real(r8) (:,:)  ]                                                  
         ! ! subsets of the n flux calcs (for diagnostic/debugging purposes)
         smin_no3_massdens_vr          =>    soilbiogeochem_nitrogenflux_inst%smin_no3_massdens_vr_col          , & ! Output:  [real(r8) (:,:) ]  (ugN / g soil) soil nitrate concentration       
         k_nitr_t_vr                   =>    soilbiogeochem_nitrogenflux_inst%k_nitr_t_vr_col                   , & ! Output:  [real(r8) (:,:) ]                                                  
         k_nitr_ph_vr                  =>    soilbiogeochem_nitrogenflux_inst%k_nitr_ph_vr_col                  , & ! Output:  [real(r8) (:,:) ]                                                  
         k_nitr_h2o_vr                 =>    soilbiogeochem_nitrogenflux_inst%k_nitr_h2o_vr_col                 , & ! Output:  [real(r8) (:,:) ]                                                  
         k_nitr_vr                     =>    soilbiogeochem_nitrogenflux_inst%k_nitr_vr_col                     , & ! Output:  [real(r8) (:,:) ]                                                  
         wfps_vr                       =>    soilbiogeochem_nitrogenflux_inst%wfps_vr_col                       , & ! Output:  [real(r8) (:,:) ]                                                  
         fmax_denit_carbonsubstrate_vr =>    soilbiogeochem_nitrogenflux_inst%fmax_denit_carbonsubstrate_vr_col , & ! Output:  [real(r8) (:,:) ]                                                  
         fmax_denit_nitrate_vr         =>    soilbiogeochem_nitrogenflux_inst%fmax_denit_nitrate_vr_col         , & ! Output:  [real(r8) (:,:) ]                                                  
         f_denit_base_vr               =>    soilbiogeochem_nitrogenflux_inst%f_denit_base_vr_col               , & ! Output:  [real(r8) (:,:) ]                                                  
         diffus                        =>    soilbiogeochem_nitrogenflux_inst%diffus_col                        , & ! Output:  [real(r8) (:,:) ] diffusivity (unitless fraction of total diffusivity)
         ratio_k1                      =>    soilbiogeochem_nitrogenflux_inst%ratio_k1_col                      , & ! Output:  [real(r8) (:,:) ]                                                  
         ratio_no3_co2                 =>    soilbiogeochem_nitrogenflux_inst%ratio_no3_co2_col                 , & ! Output:  [real(r8) (:,:) ]                                                  
         soil_co2_prod                 =>    soilbiogeochem_nitrogenflux_inst%soil_co2_prod_col                 , & ! Output:  [real(r8) (:,:) ]  (ug C / g soil / day)                           
         fr_WFPS                       =>    soilbiogeochem_nitrogenflux_inst%fr_WFPS_col                       , & ! Output:  [real(r8) (:,:) ]                                                  
         soil_bulkdensity              =>    soilbiogeochem_nitrogenflux_inst%soil_bulkdensity_col              , & ! Output:  [real(r8) (:,:) ]  (kg soil / m3) bulk density of soil (including water)
         pot_f_nit_vr                  =>    soilbiogeochem_nitrogenflux_inst%pot_f_nit_vr_col                  , & ! Output:  [real(r8) (:,:) ]  (gN/m3/s) potential soil nitrification flux     

         pot_f_denit_vr                =>    soilbiogeochem_nitrogenflux_inst%pot_f_denit_vr_col                , & ! Output:  [real(r8) (:,:) ]  (gN/m3/s) potential soil denitrification flux   
         n2_n2o_ratio_denit_vr         =>    soilbiogeochem_nitrogenflux_inst%n2_n2o_ratio_denit_vr_col           & ! Output:  [real(r8) (:,:) ]  ratio of N2 to N2O production by denitrification [gN/gN]
         )

      surface_tension_water = params_inst%surface_tension_water

      ! Set parameters from simple-structure model to calculate anoxic fratction (Arah and Vinten 1995)
      rij_kro_a     = params_inst%rij_kro_a
      rij_kro_alpha = params_inst%rij_kro_alpha
      rij_kro_beta  = params_inst%rij_kro_beta
      rij_kro_gamma = params_inst%rij_kro_gamma
      rij_kro_delta = params_inst%rij_kro_delta

      organic_max = CNParamsShareInst%organic_max

      pH(bounds%begc:bounds%endc) = 6.5_r8  !!! set all soils with the same pH as placeholder here
      co2diff_con(1) =   0.1325_r8
      co2diff_con(2) =   0.0009_r8

      do j = 1, nlevdecomp
         do fc = 1,num_bgc_soilc
            c = filter_bgc_soilc(fc)

            !---------------- calculate soil anoxia state
            ! calculate gas diffusivity of soil at field capacity here
            ! use expression from methane code, but neglect OM for now
            f_a = 1._r8 - watfc(c,j) / watsat(c,j)
            eps =  watsat(c,j)-watfc(c,j) ! Air-filled fraction of total soil volume

            ! use diffusivity calculation including peat
            if (use_lch4) then

               if (organic_max > 0._r8) then
                  om_frac = min(params_inst%om_frac_sf*cellorg(c,j)/organic_max, 1._r8)
                  ! Use first power, not square as in iniTimeConst
               else
                  om_frac = 1._r8
               end if
               diffus (c,j) = (d_con_g(2,1) + d_con_g(2,2)*t_soisno(c,j)) * 1.e-4_r8 * &
                    (om_frac * f_a**(10._r8/3._r8) / watsat(c,j)**2 + &
                    (1._r8-om_frac) * eps**2 * f_a**(3._r8 / bsw(c,j)) ) 

               ! calculate anoxic fraction of soils
               ! use rijtema and kroess model after Riley et al., 2000
               ! caclulated r_psi as a function of psi
               r_min(c,j) = 2 * surface_tension_water / (rho_w * grav * abs(soilpsi(c,j)))
               r_max = 2 * surface_tension_water / (rho_w * grav * 0.1_r8)
               r_psi(c,j) = sqrt(r_min(c,j) * r_max)
               ratio_diffusivity_water_gas(c,j) = (d_con_g(2,1) + d_con_g(2,2)*t_soisno(c,j) ) * 1.e-4_r8 / &
                    ((d_con_w(2,1) + d_con_w(2,2)*t_soisno(c,j) + d_con_w(2,3)*t_soisno(c,j)**2) * 1.e-9_r8)

               if (o2_decomp_depth_unsat(c,j) > 0._r8) then
                  anaerobic_frac(c,j) = exp(-rij_kro_a * r_psi(c,j)**(-rij_kro_alpha) * &
                       o2_decomp_depth_unsat(c,j)**(-rij_kro_beta) * &
                       conc_o2_unsat(c,j)**rij_kro_gamma * (h2osoi_vol(c,j) + ratio_diffusivity_water_gas(c,j) * &
                       watsat(c,j))**rij_kro_delta)
               else
                  anaerobic_frac(c,j) = 0._r8
               endif

            else
               ! NITRIF_DENITRIF requires Methane model to be active, 
               ! otherwise diffusivity will be zeroed out here. EBK CDK 10/18/2011
               anaerobic_frac(c,j) = 0._r8
               diffus (c,j) = 0._r8
               !call endrun(msg=' ERROR: NITRIF_DENITRIF requires Methane model to be active'//errMsg(sourcefile, __LINE__) )
            end if


            !---------------- nitrification
            ! follows CENTURY nitrification scheme (Parton et al., (2001, 1996))

            ! assume nitrification temp function equal to the HR scalar
            k_nitr_t_vr(c,j) = min(t_scalar(c,j), 1._r8)

            ! ph function from Parton et al., (2001, 1996)
            k_nitr_ph_vr(c,j) = 0.56_r8 + atan(rpi * 0.45_r8 * (-5._r8+ pH(c)))/rpi

            ! moisture function-- assume the same moisture function as limits heterotrophic respiration
            ! Parton et al. base their nitrification- soil moisture rate constants based on heterotrophic rates-- can we do the same?
            k_nitr_h2o_vr(c,j) = w_scalar(c,j)

            ! nitrification constant is a set scalar * temp, moisture, and ph scalars
            ! note that k_nitr_max_perday is converted from 1/day to 1/s
            k_nitr_vr(c,j) = k_nitr_max_perday/secspday * k_nitr_t_vr(c,j) * k_nitr_h2o_vr(c,j) * k_nitr_ph_vr(c,j)

            ! first-order decay of ammonium pool with scalar defined above
            pot_f_nit_vr(c,j) = max(smin_nh4_vr(c,j) * k_nitr_vr(c,j), 0._r8)

            ! limit to oxic fraction of soils
            pot_f_nit_vr(c,j)  = pot_f_nit_vr(c,j) * (1._r8 - anaerobic_frac(c,j))

            ! limit to non-frozen soil layers
            if ( t_soisno(c,j) <= SHR_CONST_TKFRZ .and. no_frozen_nitrif_denitrif) then
               pot_f_nit_vr(c,j) = 0._r8
            endif


            !---------------- denitrification
            ! first some input variables an unit conversions
            soil_hr_vr(c,j) = phr_vr(c,j)

            ! CENTURY papers give denitrification in units of per gram soil; need to convert from volumetric to mass-based units here
            soil_bulkdensity(c,j) = bd(c,j) + h2osoi_liq(c,j)/col%dz(c,j)         

            g_per_m3__to__ug_per_gsoil = 1.e3_r8 / soil_bulkdensity(c,j)

            g_per_m3_sec__to__ug_per_gsoil_day = g_per_m3__to__ug_per_gsoil * secspday

            smin_no3_massdens_vr(c,j) = max(smin_no3_vr(c,j), 0._r8) * g_per_m3__to__ug_per_gsoil

            soil_co2_prod(c,j) = (soil_hr_vr(c,j) * (g_per_m3_sec__to__ug_per_gsoil_day))

            !! maximum potential denitrification rates based on heterotrophic respiration rates or nitrate concentrations, 
            !! from (del Grosso et al., 2000)
            fmax_denit_carbonsubstrate_vr(c,j) = (denit_resp_coef * (soil_co2_prod(c,j)**denit_resp_exp)) &
                 / g_per_m3_sec__to__ug_per_gsoil_day
            !  
            fmax_denit_nitrate_vr(c,j) = (denit_nitrate_coef * smin_no3_massdens_vr(c,j)**denit_nitrate_exp)  &
                 / g_per_m3_sec__to__ug_per_gsoil_day

            ! find limiting denitrification rate
            f_denit_base_vr(c,j) = max(min(fmax_denit_carbonsubstrate_vr(c,j), fmax_denit_nitrate_vr(c,j)),0._r8) 

            ! limit to non-frozen soil layers
            if ( t_soisno(c,j) <= SHR_CONST_TKFRZ .and. no_frozen_nitrif_denitrif ) then
               f_denit_base_vr(c,j) = 0._r8
            endif

            ! limit to anoxic fraction of soils
            pot_f_denit_vr(c,j) = f_denit_base_vr(c,j) * anaerobic_frac(c,j)

            ! now calculate the ratio of N2O to N2 from denitrifictaion, following Del Grosso et al., 2000
            ! diffusivity constant (figure 6b)
            ratio_k1(c,j) = max(1.7_r8, 38.4_r8 - 350._r8 * diffus(c,j))

            ! ratio function (figure 7c)
            if ( soil_co2_prod(c,j) > 1.0e-9_r8 ) then
               ratio_no3_co2(c,j) = smin_no3_massdens_vr(c,j) / soil_co2_prod(c,j)
            else
               ! fucntion saturates at large no3/co2 ratios, so set as some nominally large number
               ratio_no3_co2(c,j) = 100._r8
            endif

            ! total water limitation function (Del Grosso et al., 2000, figure 7a)
            wfps_vr(c,j) = max(min(h2osoi_vol(c,j)/watsat(c, j), 1._r8), 0._r8) * 100._r8
            fr_WFPS(c,j) = max(0.1_r8, 0.015_r8 * wfps_vr(c,j) - 0.32_r8)

            ! final ratio expression 
            n2_n2o_ratio_denit_vr(c,j) = max(0.16_r8*ratio_k1(c,j), ratio_k1(c,j)*exp(-0.8_r8 * ratio_no3_co2(c,j))) * fr_WFPS(c,j)

         end do

      end do

    end associate

  end subroutine SoilBiogeochemNitrifDenitrif

end module SoilBiogeochemNitrifDenitrifMod
