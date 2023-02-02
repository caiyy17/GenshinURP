//这边先定义一些大气参数，主要都是C#那边传进来的
//我为了方便在这边用宏都替换成UE给的代码中的变量名
//注意UE中Z轴向上，那么我们这个shader中也统一Z轴向上
//所有坐标从unity那边传过来都从xyz变成zxy
//太阳角度这边都是相对相机（也就是说在这个shader中，认为相机在(0,0,r+h)

// float4 _ScreenParams;
// float4 _ProjectionParams;
// float4 _ZBufferParams;

float4x4 custom_MatrixInvVP;
float4x4 custom_MatrixVP;
#define gSkyInvViewProjMat custom_MatrixInvVP
#define gSkyViewProjMat custom_MatrixVP
#define SHADOWMAP_ENABLED 1

//UE标定，z轴向上，视线朝向x轴正方向，左手系
//unity标定，y轴向上，实现朝向z轴正方向，左手系
float3 UnityToUE(inout float3 unityPos)
{
    return unityPos.zxy;
}
float3 UEToUnity(float3 UEPos)
{
    return UEPos.yzx;
}

float3 Spherical2Cartesian(float phi, float theta)
{
    return normalize(float3(
        cos(phi) * cos(theta),
        - sin(phi) * cos(theta),
        sin(theta)
    ));
}

//这边是一些lut的分辨率设置
#define TRANSMITTANCE_TEXTURE_WIDTH _LutInfo.x
#define TRANSMITTANCE_TEXTURE_HEIGHT _LutInfo.y
#define SKYVIEW_TEXTURE_WIDTH _LutInfo.z
#define SKYVIEW_TEXTURE_HEIGHT _LutInfo.w
#define CameraVolumeRes _VolumeInfo.x
#define MultiScatteringLUTRes _VolumeInfo.y
#define MultipleScatteringFactor _VolumeInfo.z

//在unity中我们以m为单位，而大气中我们是用km作为单位的
//所有涉及到相机坐标输入的都需要scale一下
//因为想做太空效果，所以远地面部分做了非线性的映射
//近地面以m为单位，远地面部分由于地面物体看不到了，就逐渐转到km为单位
float GetDistanceScale(float height)
{
    if (height < 4000)
    {
        //对应1-4km
        //scale = 0.001
        return 0.001;
    }
    else if (height < 5000)
    {
        //对应4-100km
        //scale = 0.001 -- 100/5000
        return 0.001 + (height - 4000) / 1000 * (100 - 5) / 5000;
    }
    else if (height < 6000)
    {
        //对应100-6000km
        //scale = 0.2 -- 1
        return 0.02 + (height - 5000) / 1000 * 0.98;
    }
    else
    {
        return 1.0;
    }
}
#define DistanceScale GetDistanceScale(_WorldSpaceCameraPos.y)
//#define DistanceScale 1.0f
#define RAYDPOS 0.001f
#define MAXHEIGHT 20000.0f
#define RayMarchMinMaxSPP float2(1, 30)

#define top_radius _AtmosphereInfo[0].x
#define bottom_radius _AtmosphereInfo[0].y
#define gSunIlluminance _AtmosphereInfo[0].z
#define rayleigh_scale_height _AtmosphereInfo[1].w
#define mie_scale_height _AtmosphereInfo[2].w
#define mie_phase_function_g _AtmosphereInfo[3].w
#define ozone_width _AtmosphereInfo[4].w
#define ozone_info _AtmosphereInfo[5]
//散射量的设置，单位是 1/km
#define rayleigh_scattering _AtmosphereInfo[1].xyz
#define mie_scattering _AtmosphereInfo[2].xyz
#define mie_absorption _AtmosphereInfo[3].xyz
#define absorption_extinction _AtmosphereInfo[4].xyz
#define ground_albedo _AtmosphereInfo[6].xyz

float3 GetCamera()
{
    float3 Position = UnityToUE(_WorldSpaceCameraPos.xyz);
    Position = float3(Position.x * DistanceScale, Position.y * DistanceScale, \
        min(MAXHEIGHT, max(RAYDPOS, Position.z * DistanceScale)));
    return Position;
}
#define camera GetCamera()
//这里标定了相机在地球坐标系下的经纬坐标，(0,0)指向x轴正方向
#define camera_position_on_earth Spherical2Cartesian(_AtmosphereInfo[7].x, _AtmosphereInfo[7].y)
//这边的matrix定义了从局部坐标系到地球坐标系的转换
//局部坐标系采用UE标定，z轴向上（指向地心反方向），x轴面向地球正北方
//地球坐标系经纬度(0,0)指向x轴正方向，z轴指向北极
float3x3 GetCameraMatrix()
{
    //经度
    float cosPhi = cos(_AtmosphereInfo[7].x);
    float sinPhi = sin(_AtmosphereInfo[7].x);
    //纬度
    float cosTheta = cos(_AtmosphereInfo[7].y);
    float sinTheta = sin(_AtmosphereInfo[7].y);
    return float3x3(
        float3(-sinTheta * cosPhi, -sinPhi, cosTheta * cosPhi),
        float3(sinTheta * sinPhi, -cosPhi, -cosTheta * sinPhi),
        float3(cosTheta, 0, sinTheta)
    );
}
#define camera_to_world_matrix GetCameraMatrix()

////////////////////////////////////////////////////////////
// Date
////////////////////////////////////////////////////////////

#define JDC _JdInfo[0]
#define LMST _JdInfo[1]
#define epsilon _JdInfo[2]
#define JDC_STAR _JdInfo[3]

////////////////////////////////////////////////////////////
// Transform
////////////////////////////////////////////////////////////

float3 Rx(float3 input, float rad)
{
    float cosRad = cos(rad);
    float sinRad = sin(rad);
    float3x3 rotate = float3x3(
        float3(1, 0, 0),
        float3(0, cosRad, sinRad),
        float3(0, -sinRad, cosRad)
    );
    return mul(rotate, input);
}
float3 Ry(float3 input, float rad)
{
    float cosRad = cos(rad);
    float sinRad = sin(rad);
    float3x3 rotate = float3x3(
        float3(cosRad, 0, sinRad),
        float3(0, 1, 0),
        float3(-sinRad, 0, cosRad)
    );
    return mul(rotate, input);
}
float3 Rz(float3 input, float rad)
{
    float cosRad = cos(rad);
    float sinRad = sin(rad);
    float3x3 rotate = float3x3(
        float3(cosRad, sinRad, 0),
        float3(-sinRad, cosRad, 0),
        float3(0, 0, 1)
    );
    return mul(rotate, input);
}

float3 TransformLocalToEarth(float3 input)
{
    return mul(camera_to_world_matrix, input);
}
float3 TransformEarthToLocal(float3 input)
{
    return mul(input, camera_to_world_matrix);
}

float3 TransformICRSToEarth(float3 input)
{
    float3 output = input;
    float jdc = JDC;
    //Precession
    output = Rz(output, 0.01118 * jdc);
    output = Ry(output, -0.00972 * jdc);
    output = Rz(output, 0.01118 * jdc);

    output = Rz(output, -LMST);
    return output;
}
float3 TransformEarthToICRS(float3 input)
{
    float3 output = input;
    float jdc = JDC;
    output = Rz(output, LMST);
    //Precession
    output = Rz(output, -0.01118 * jdc);
    output = Ry(output, 0.00972 * jdc);
    output = Rz(output, -0.01118 * jdc);

    return output;
}

float3 TransformEclipticToICRS(float3 input)
{
    float3 output = input;
    output = Rx(output, epsilon);
    return output;
}
float3 TransformICRSToEcliptic(float3 input)
{
    float3 output = input;
    output = Rx(output, -epsilon);
    return output;
}

//(1,0,0)对应在uv的(0.5,0.5)
//西经90线u为0，东经90线u为1
//北极点v为1，南极点v为0
void SphericalToUv(in float3 Spherical, out float2 uv)
{
    float Theta = asin(clamp(Spherical.z, -1, 1));
    float2 tempView = normalize(Spherical.xy + RAYDPOS);
    float Phi = acos(clamp((tempView.x), -1, 1));
    if (tempView.y > 0)
    {
        Phi = -Phi;
    }
    uv = saturate(float2((Phi + PI) / (2 * PI), (Theta + PI / 2) / PI));
}

////////////////////////////////////////////////////////////
// Solar System
////////////////////////////////////////////////////////////

#define sun_direction _SolarInfo[0].xyz
#define moon_direction _SolarInfo[1].xyz
#define r_sun _SolarInfo[2].x
#define pi_moon _SolarInfo[2].z
#define sun_illuminance _SolarInfo[2].y
#define moon_illuminance _SolarInfo[2].w
#define sun_angle _SolarInfo[3].z
#define moon_angle _SolarInfo[3].w
#define ll_moon _SolarInfo[3].x
#define f_moon _SolarInfo[3].y
#define shadow_color _SolarInfo[4].xyz
#define far_color _SolarInfo[5].xyz
#define earth_map_illuminance _SolarInfo[6].x
#define earth_night_map_illuminance _SolarInfo[6].y
#define earth_cloud_map_illuminance _SolarInfo[6].z

float3 TransformEclipticToMoon(float3 input)
{
    float3 output = input;
    output = Rz(output, -f_moon - PI);
    output = Rx(output, 0.026920);
    output = Rz(output, -ll_moon + f_moon);
    return output;
}

////////////////////////////////////////////////////////////
// Star
////////////////////////////////////////////////////////////

#define star_size _StarInfo[0]
#define star_illuminance _StarInfo[1]
#define constellation_illuminance _StarInfo[2]
#define far_map_illuminance _StarInfo[3]

float3 BVToRGB(float bv)
{
    if (bv < - 0.40)
    {
        bv = -0.40;
    }
    if (bv > 2.00)
    {
        bv = 2.00;
    }

    float r = 0.0;
    float g = 0.0;
    float b = 0.0;
    float t;

    if (bv < 0.00)
    {
        t = (bv + 0.40) / (0.00 + 0.40);
        r = 0.61 + (0.11 * t) + (0.1 * t * t);
    }
    else if (bv < 0.40)
    {
        t = (bv - 0.00) / (0.40 - 0.00);
        r = 0.83 + (0.17 * t);
    }
    else if (bv <= 2.10)
    {
        t = (bv - 0.40) / (2.10 - 0.40);
        r = 1.00;
    }

    if (bv < 0.00)
    {
        t = (bv + 0.40) / (0.00 + 0.40);
        g = 0.70 + (0.07 * t) + (0.1 * t * t);
    }
    else if (bv < 0.40)
    {
        t = (bv - 0.00) / (0.40 - 0.00);
        g = 0.87 + (0.11 * t);
    }
    else if (bv < 1.60)
    {
        t = (bv - 0.40) / (1.60 - 0.40);
        g = 0.98 - (0.16 * t);
    }
    else if (bv <= 2.00)
    {
        t = (bv - 1.60) / (2.00 - 1.60);
        g = 0.82 - (0.5 * t * t);
    }
    
    if (bv < 0.40)
    {
        t = (bv + 0.40) / (0.40 + 0.40);
        b = 1.00;
    }
    else if (bv < 1.50)
    {
        t = (bv - 0.40) / (1.50 - 0.40);
        b = 1.00 - (0.47 * t) + (0.1 * t * t);
    }
    else if (bv <= 1.94)
    {
        t = (bv - 1.50) / (1.94 - 1.50);
        b = 0.63 - (0.6 * t * t);
    }

    return float3(r, g, b);
}

struct starData
{
    float index;
    float HIP;
    float Vmag;
    float RAdeg;
    float DEdeg;
    float pmRA;
    float pmDE;
    float BV;
};

struct starResult
{
    float3 color;
    float4 positionCS;
};

starResult ProcessStarData(starData data)
{
    starResult result = (starResult)0;
    float RAdeg = data.RAdeg + JDC_STAR * data.pmRA / 36000;
    float DEdeg = data.DEdeg + JDC_STAR * data.pmDE / 36000;
    float3 viewDir = Spherical2Cartesian(DegToRad(RAdeg), DegToRad(DEdeg));
    //这边Spherical2Cartesian指向x轴
    //然后转到地球的坐标系
    viewDir = TransformICRSToEarth(viewDir);
    viewDir = TransformEarthToLocal(viewDir);
    
    viewDir = UEToUnity(viewDir);
    float3 positionWS = viewDir * 1000;
    float4 positionCS = mul(gSkyViewProjMat, float4(positionWS, 1));
    result.positionCS = positionCS;

    float3 color = exp(-data.Vmag) * BVToRGB(data.BV);
    result.color = color;

    return result;
}

////////////////////////////////////////////////////////////
// Atmospheres
////////////////////////////////////////////////////////////

//这边导入大气参数
struct AtmosphereParameters
{
    // Radius of the planet (center to ground)
    float BottomRadius;
    // Maximum considered atmosphere height (center to atmosphere top)
    float TopRadius;

    // Rayleigh scattering exponential distribution scale in the atmosphere
    float RayleighDensityExpScale;
    // Rayleigh scattering coefficients
    float3 RayleighScattering;

    // Mie scattering exponential distribution scale in the atmosphere
    float MieDensityExpScale;
    // Mie scattering coefficients
    float3 MieScattering;
    // Mie extinction coefficients
    float3 MieExtinction;
    // Mie absorption coefficients
    float3 MieAbsorption;
    // Mie phase function excentricity
    float MiePhaseG;

    // Another medium type in the atmosphere
    float AbsorptionDensity0LayerWidth;
    float AbsorptionDensity0ConstantTerm;
    float AbsorptionDensity0LinearTerm;
    float AbsorptionDensity1ConstantTerm;
    float AbsorptionDensity1LinearTerm;
    // This other medium only absorb light, e.g. useful to represent ozone in the earth atmosphere
    float3 AbsorptionExtinction;

    // The albedo of the ground.
    float3 GroundAlbedo;
};

AtmosphereParameters GetAtmosphereParameters()
{
    AtmosphereParameters Parameters;
    Parameters.AbsorptionExtinction = absorption_extinction;

    // Traslation from Bruneton2017 parameterisation.
    Parameters.RayleighDensityExpScale = -1 / rayleigh_scale_height;
    Parameters.MieDensityExpScale = -1 / mie_scale_height;
    Parameters.AbsorptionDensity0LayerWidth = ozone_width;
    Parameters.AbsorptionDensity0ConstantTerm = ozone_info.x;
    Parameters.AbsorptionDensity0LinearTerm = ozone_info.y;
    Parameters.AbsorptionDensity1ConstantTerm = ozone_info.z;
    Parameters.AbsorptionDensity1LinearTerm = ozone_info.w;

    Parameters.MiePhaseG = mie_phase_function_g;
    Parameters.RayleighScattering = rayleigh_scattering;
    Parameters.MieScattering = mie_scattering;
    Parameters.MieAbsorption = mie_absorption;
    Parameters.MieExtinction = mie_scattering + mie_absorption;
    Parameters.GroundAlbedo = ground_albedo;
    Parameters.BottomRadius = bottom_radius;
    Parameters.TopRadius = top_radius;
    return Parameters;
}

// - r0: ray origin
// - rd: normalized ray direction
// - s0: sphere center
// - sR: sphere radius
// - Returns distance from r0 to first intersecion with sphere,
//   or -1.0 if no intersection.
float raySphereIntersectNearest(float3 r0, float3 rd, float3 s0, float sR)
{
    float a = dot(rd, rd);
    float3 s0_r0 = r0 - s0;
    float b = 2.0 * dot(rd, s0_r0);
    float c = dot(s0_r0, s0_r0) - (sR * sR);
    float delta = b * b - 4.0 * a * c;
    if (delta < 0.0 || a == 0.0)
    {
        return -1.0;
    }
    float sol0 = (-b - sqrt(delta)) / (2.0 * a);
    float sol1 = (-b + sqrt(delta)) / (2.0 * a);
    if (sol0 < RAYDPOS && sol1 < 0.0)
    {
        return -1.0;
    }
    if (sol0 < 0.0)
    {
        return max(0.0, sol1);
    }
    else if (sol1 < 0.0)
    {
        return max(0.0, sol0);
    }
    return max(0.0, min(sol0, sol1));
}

// Texture2D<float4>  TransmittanceLutTexture				: register(t2);
// Texture2D<float4>  SkyViewLutTexture					: register(t3);

// Texture2D<float4>  ViewDepthTexture						: register(t4);
// Texture2D<float4>  ShadowmapTexture						: register(t5);

// Texture2D<float4>  MultiScatTexture						: register(t6);
// Texture3D<float4>  AtmosphereCameraScatteringVolume		: register(t7);

// RWTexture2D<float4>  OutputTexture						: register(u0);
// RWTexture2D<float4>  OutputTexture1						: register(u1);

#ifndef GROUND_GI_ENABLED
    #define GROUND_GI_ENABLED 0
#endif
#ifndef TRANSMITANCE_METHOD
    #define TRANSMITANCE_METHOD 2
#endif
#ifndef MULTISCATAPPROX_ENABLED
    #define MULTISCATAPPROX_ENABLED 0
#endif
#ifndef SHADOWMAP_ENABLED
    #define SHADOWMAP_ENABLED 0
#endif
#ifndef MEAN_ILLUM_MODE
    #define MEAN_ILLUM_MODE 0
#endif
#ifndef USE_CornetteShanks
    #define USE_CornetteShanks 0
#endif
#ifndef RENDER_SUN_DISK
    #define RENDER_SUN_DISK 0
#endif

#define PLANET_RADIUS_OFFSET 0.01f

struct Ray
{
    float3 o;
    float3 d;
};

Ray createRay(in float3 p, in float3 d)
{
    Ray r;
    r.o = p;
    r.d = d;
    return r;
}

////////////////////////////////////////////////////////////
// LUT functions
////////////////////////////////////////////////////////////

// Transmittance LUT function parameterisation from Bruneton 2017 https://github.com/ebruneton/precomputed_atmospheric_scattering
// uv in [0,1]
// viewZenithCosAngle in [-1,1]
// viewHeight in [bottomRAdius, topRadius]

// We should precompute those terms from resolutions (Or set resolution as #defined constants)
float fromUnitToSubUvs(float u, float resolution)
{
    return(u + 0.5f / resolution) * (resolution / (resolution + 1.0f));
}
float fromSubUvsToUnit(float u, float resolution)
{
    return(u - 0.5f / resolution) * (resolution / (resolution - 1.0f));
}

void UvToLutTransmittanceParams(AtmosphereParameters Atmosphere, out float viewHeight, out float viewZenithCosAngle, in float2 uv)
{
    // uv.y = 1时在天顶
    //uv = float2(fromSubUvsToUnit(uv.x, gResolution.x), fromSubUvsToUnit(uv.y, gResolution.y)); // No real impact so off
    float x_mu = uv.x;
    float x_r = uv.y;

    float H = sqrt(Atmosphere.TopRadius * Atmosphere.TopRadius - Atmosphere.BottomRadius * Atmosphere.BottomRadius);
    float rho = H * x_r;
    viewHeight = sqrt(rho * rho + Atmosphere.BottomRadius * Atmosphere.BottomRadius);

    float d_min = Atmosphere.TopRadius - viewHeight;
    float d_max = rho + H;
    float d = d_min + x_mu * (d_max - d_min);
    viewZenithCosAngle = d == 0.0 ? 1.0f : (H * H - rho * rho - d * d) / (2.0 * viewHeight * d);
    viewZenithCosAngle = clamp(viewZenithCosAngle, -1.0, 1.0);
}

void LutTransmittanceParamsToUv(AtmosphereParameters Atmosphere, in float viewHeight, in float viewZenithCosAngle, out float2 uv)
{
    float H = sqrt(max(0.0f, Atmosphere.TopRadius * Atmosphere.TopRadius - Atmosphere.BottomRadius * Atmosphere.BottomRadius));
    float rho = sqrt(max(0.0f, viewHeight * viewHeight - Atmosphere.BottomRadius * Atmosphere.BottomRadius));

    float discriminant = viewHeight * viewHeight * (viewZenithCosAngle * viewZenithCosAngle - 1.0) + Atmosphere.TopRadius * Atmosphere.TopRadius;
    float d = max(0.0, (-viewHeight * viewZenithCosAngle + sqrt(max(0.0f, discriminant)))); // Distance to atmosphere boundary

    float d_min = Atmosphere.TopRadius - viewHeight;
    float d_max = rho + H;
    float x_mu = (d - d_min) / (d_max - d_min);
    float x_r = rho / H;

    uv = float2(x_mu, x_r);
    //uv = float2(fromUnitToSubUvs(uv.x, TRANSMITTANCE_TEXTURE_WIDTH), fromUnitToSubUvs(uv.y, TRANSMITTANCE_TEXTURE_HEIGHT)); // No real impact so off

}

#define NONLINEARSKYVIEWLUT 1
void UvToSkyViewLutParams(AtmosphereParameters Atmosphere, out float viewZenithCosAngle, out float lightViewCosAngle, out float lightViewSinAngle, in float viewHeight, in float2 uv)
{
    // uv.y = 0时在天顶
    // Constrain uvs to valid sub texel range (avoid zenith derivative issue making LUT usage visible)
    uv = float2(fromSubUvsToUnit(uv.x, gResolution.x), fromSubUvsToUnit(uv.y, gResolution.y));

    float Vhorizon = sqrt(viewHeight * viewHeight - Atmosphere.BottomRadius * Atmosphere.BottomRadius);
    float CosBeta = Vhorizon / viewHeight;				// GroundToHorizonCos
    float Beta = acos(CosBeta);
    float ZenithHorizonAngle = PI - Beta;
    float viewZenithAngle;

    if (uv.y < 0.5f)
    {
        float coord = 2.0 * uv.y;
        coord = 1.0 - coord;
        #if NONLINEARSKYVIEWLUT
            coord *= coord;
        #endif
        coord = 1.0 - coord;
        viewZenithAngle = ZenithHorizonAngle * coord;
    }
    else
    {
        float coord = uv.y * 2.0 - 1.0;
        #if NONLINEARSKYVIEWLUT
            coord *= coord;
        #endif
        viewZenithAngle = ZenithHorizonAngle + Beta * coord;
    }
    viewZenithCosAngle = cos(viewZenithAngle);

    float coord = uv.x;
    float lightViewAngle = 2 * PI * uv.x;
    lightViewCosAngle = cos(lightViewAngle);
    lightViewSinAngle = sin(lightViewAngle);
    viewZenithCosAngle = clamp(viewZenithCosAngle, -1.0, 1.0);
}

void SkyViewLutParamsToUv(AtmosphereParameters Atmosphere, in bool IntersectGround, in float viewZenithCosAngle, in float lightViewCosAngle, in float lightViewSinAngle, in float viewHeight, out float2 uv)
{
    float Vhorizon = sqrt(viewHeight * viewHeight - Atmosphere.BottomRadius * Atmosphere.BottomRadius);
    float CosBeta = Vhorizon / viewHeight;				// GroundToHorizonCos
    float Beta = acos(CosBeta);
    float ZenithHorizonAngle = PI - Beta;
    float ViewZenithAngle = acos(viewZenithCosAngle);

    //if (!IntersectGround)
    if (viewZenithCosAngle > cos(ZenithHorizonAngle))
    {
        float coord = ViewZenithAngle / ZenithHorizonAngle;
        coord = 1.0 - coord;
        #if NONLINEARSKYVIEWLUT
            coord = sqrt(max(0, coord));
        #endif
        coord = 1.0 - coord;
        uv.y = coord * 0.5f;
    }
    else
    {
        float coord = (ViewZenithAngle - ZenithHorizonAngle) / Beta;
        #if NONLINEARSKYVIEWLUT
            coord = sqrt(max(0, coord));
        #endif
        uv.y = coord * 0.5f + 0.5f;
    }
    {
        float coord = acos(lightViewCosAngle) / 2 / PI;
        if (lightViewSinAngle < 0)
        {
            uv.x = coord;
        }
        else
        {
            uv.x = 1 - coord;
        }
    }
    uv = saturate(uv);
    // Constrain uvs to valid sub texel range (avoid zenith derivative issue making LUT usage visible)
    uv = float2(fromUnitToSubUvs(uv.x, SKYVIEW_TEXTURE_WIDTH), fromUnitToSubUvs(uv.y, SKYVIEW_TEXTURE_HEIGHT));
}

////////////////////////////////////////////////////////////
// Participating media
////////////////////////////////////////////////////////////

float getAlbedo(float scattering, float extinction)
{
    return scattering / max(0.001, extinction);
}
float3 getAlbedo(float3 scattering, float3 extinction)
{
    return scattering / max(0.001, extinction);
}

struct MediumSampleRGB
{
    float3 scattering;
    float3 absorption;
    float3 extinction;

    float3 scatteringMie;
    float3 absorptionMie;
    float3 extinctionMie;

    float3 scatteringRay;
    float3 absorptionRay;
    float3 extinctionRay;

    float3 scatteringOzo;
    float3 absorptionOzo;
    float3 extinctionOzo;

    float3 albedo;
};

MediumSampleRGB sampleMediumRGB(in float3 WorldPos, in AtmosphereParameters Atmosphere)
{
    const float viewHeight = max(0.0, length(WorldPos) - Atmosphere.BottomRadius);

    const float densityMie = exp(Atmosphere.MieDensityExpScale * viewHeight);
    const float densityRay = exp(Atmosphere.RayleighDensityExpScale * viewHeight);
    const float densityOzo = saturate(viewHeight < Atmosphere.AbsorptionDensity0LayerWidth ?
    (Atmosphere.AbsorptionDensity0LinearTerm * viewHeight + Atmosphere.AbsorptionDensity0ConstantTerm) :
    (Atmosphere.AbsorptionDensity1LinearTerm * viewHeight + Atmosphere.AbsorptionDensity1ConstantTerm));

    MediumSampleRGB s;

    s.scatteringMie = densityMie * Atmosphere.MieScattering;
    s.absorptionMie = densityMie * Atmosphere.MieAbsorption;
    s.extinctionMie = densityMie * Atmosphere.MieExtinction;

    s.scatteringRay = densityRay * Atmosphere.RayleighScattering;
    s.absorptionRay = 0.0f;
    s.extinctionRay = s.scatteringRay + s.absorptionRay;

    s.scatteringOzo = 0.0;
    s.absorptionOzo = densityOzo * Atmosphere.AbsorptionExtinction;
    s.extinctionOzo = s.scatteringOzo + s.absorptionOzo;

    s.scattering = s.scatteringMie + s.scatteringRay + s.scatteringOzo;
    s.absorption = s.absorptionMie + s.absorptionRay + s.absorptionOzo;
    s.extinction = s.extinctionMie + s.extinctionRay + s.extinctionOzo;
    s.albedo = getAlbedo(s.scattering, s.extinction);

    return s;
}

////////////////////////////////////////////////////////////
// Sampling functions
////////////////////////////////////////////////////////////

// Generates a uniform distribution of directions over a sphere.
// Random zetaX and zetaY values must be in [0, 1].
// Top and bottom sphere pole (+-zenith) are along the Y axis.
float3 getUniformSphereSample(float zetaX, float zetaY)
{
    float phi = 2.0f * 3.14159f * zetaX;
    float theta = 2.0f * acos(sqrt(1.0f - zetaY));
    float3 dir = float3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi));
    return dir;
}

// Generate a sample (using importance sampling) along an infinitely long path with a given constant extinction.
// Zeta is a random number in [0,1]
float infiniteTransmittanceIS(float extinction, float zeta)
{
    return -log(1.0f - zeta) / extinction;
}
// Normalized PDF from a sample on an infinitely long path according to transmittance and extinction.
float infiniteTransmittancePDF(float extinction, float transmittance)
{
    return extinction * transmittance;
}

// Same as above but a sample is generated constrained within a range t,
// where transmittance = exp(-extinction*t) over that range.
float rangedTransmittanceIS(float extinction, float transmittance, float zeta)
{
    return -log(1.0f - zeta * (1.0f - transmittance)) / extinction;
}

float RayleighPhase(float cosTheta)
{
    float factor = 3.0f / (16.0f * PI);
    return factor * (1.0f + cosTheta * cosTheta);
}

float CornetteShanksMiePhaseFunction(float g, float cosTheta)
{
    float k = 3.0 / (8.0 * PI) * (1.0 - g * g) / (2.0 + g * g);
    return k * (1.0 + cosTheta * cosTheta) / pow(abs(1.0 + g * g - 2.0 * g * - cosTheta), 1.5);
}

float hgPhase(float g, float cosTheta)
{
    #ifdef USE_CornetteShanks
        return CornetteShanksMiePhaseFunction(g, cosTheta);
    #else
        // Reference implementation (i.e. not schlick approximation).
        // See http://www.pbr-book.org/3ed-2018/Volume_Scattering/Phase_Functions.html
        float numer = 1.0f - g * g;
        float denom = 1.0f + g * g + 2.0f * g * cosTheta;
        return numer / (4.0f * PI * denom * sqrt(denom));
    #endif
}

float dualLobPhase(float g0, float g1, float w, float cosTheta)
{
    return lerp(hgPhase(g0, cosTheta), hgPhase(g1, cosTheta), w);
}

float uniformPhase()
{
    return 1.0f / (4.0f * PI);
}

////////////////////////////////////////////////////////////
// Misc functions
////////////////////////////////////////////////////////////

// From http://jcgt.org/published/0006/01/01/
void CreateOrthonormalBasis(in float3 n, out float3 b1, out float3 b2)
{
    float sign = n.z >= 0.0f ? 1.0f : - 1.0f; // copysignf(1.0f, n.z);
    const float a = -1.0f / (sign + n.z);
    const float b = n.x * n.y * a;
    b1 = float3(1.0f + sign * n.x * n.x * a, sign * b, -sign * n.x);
    b2 = float3(b, sign + n.y * n.y * a, -n.y);
}

float mean(float3 v)
{
    return dot(v, float3(1.0f / 3.0f, 1.0f / 3.0f, 1.0f / 3.0f));
}

float whangHashNoise(uint u, uint v, uint s)
{
    uint seed = (u * 1664525u + v) + s;
    seed = (seed ^ 61u) ^(seed >> 16u);
    seed *= 9u;
    seed = seed ^(seed >> 4u);
    seed *= uint(0x27d4eb2d);
    seed = seed ^(seed >> 15u);
    float value = float(seed) / (4294967296.0);
    return value;
}

bool MoveToTopAtmosphere(inout float3 WorldPos, in float3 WorldDir, in float AtmosphereTopRadius)
{
    float viewHeight = length(WorldPos);
    if (viewHeight > AtmosphereTopRadius)
    {
        float tTop = raySphereIntersectNearest(WorldPos, WorldDir, float3(0.0f, 0.0f, 0.0f), AtmosphereTopRadius);
        if (tTop >= 0.0f)
        {
            float3 UpVector = WorldPos / viewHeight;
            float3 UpOffset = UpVector * - PLANET_RADIUS_OFFSET;
            WorldPos = WorldPos + WorldDir * tTop + UpOffset;
        }
        else
        {
            // Ray is not intersecting the atmosphere
            return false;
        }
    }
    return true; // ok to start tracing

}

#if MULTISCATAPPROX_ENABLED
    float3 GetMultipleScattering(AtmosphereParameters Atmosphere, float3 scattering, float3 extinction, float3 worlPos, float SunZenithCosAngle)
    {
        float2 uv = saturate(float2(SunZenithCosAngle * 0.5f + 0.5f, (length(worlPos) - Atmosphere.BottomRadius) / (Atmosphere.TopRadius - Atmosphere.BottomRadius)));
        uv = float2(fromUnitToSubUvs(uv.x, MultiScatteringLUTRes), fromUnitToSubUvs(uv.y, MultiScatteringLUTRes));

        float3 multiScatteredLuminance = customSample(_MultiScat, sampler_MultiScat, uv).xyz;
        //multiScatteredLuminance = 0.0f;

        return multiScatteredLuminance;
    }
#endif

float3 getShadow(in AtmosphereParameters Atmosphere, float3 P)
{
    //return 1.0f;
    float radius = Atmosphere.BottomRadius;
    float3 SunDir = sun_direction;
    float3 MoonDir = normalize(moon_direction - P * pi_moon / radius);
    float HalfSunRad = DegToRad(sun_angle / 2);
    float HalfMoonRad = DegToRad(moon_angle / 2);
    float CosHalfApexMax = cos(HalfSunRad + HalfMoonRad);
    float CosHalfApexMin = cos(HalfSunRad - HalfMoonRad);
    float SdotM = dot(SunDir, MoonDir);
    float darkness = 0;
    if (SdotM > CosHalfApexMax)
    {
        float angle = acos(SdotM);
        if (SdotM >= CosHalfApexMin)
        {
            darkness = saturate((moon_angle * moon_angle) / (sun_angle * sun_angle));
        }
        else
        {
            float SMAngle = acos(SdotM);
            float a = HalfSunRad, b = HalfMoonRad, c = SMAngle;
            float p = (a + b + c) / 2;
            float CosA = clamp((b * b + c * c - a * a) / (2 * b * c), -1, 1);
            float CosB = clamp((a * a + c * c - b * b) / (2 * a * c), -1, 1);
            float angleA = acos(CosA);
            float angleB = acos(CosB);
            float areaTriangle = sqrt(max(0, p * (p - a) * (p - b) * (p - c)));
            float areaA = angleA * b * b;
            float areaB = angleB * a * a;
            float areaCross = areaA + areaB - areaTriangle * 2;
            float areaScale = areaCross / (PI * HalfSunRad * HalfSunRad);
            darkness = areaScale;

            //darkness = saturate((SdotM - CosHalfApexMax) / (CosHalfApexMin - CosHalfApexMax));
            //shadow = 1 - saturate(areaIntersect) / sun_angle * sun_angle;

        }
        const float SoftEdge = saturate(2.0f * (SdotM - CosHalfApexMax) / (1.0f - CosHalfApexMax));
        darkness *= SoftEdge;
    }
    float3 shadow = darkness * shadow_color + (1 - darkness);
    return shadow;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

//这边就是采样函数，沿着给定的WorldDir直线，采样一定的样本
//对于每个样本计算太阳的贡献，T(p,v) * Scatter * T(s,p)
//由于我们从大气顶部积分到底部，T(p,v)就不采样Transmittance的RT了，每个样本采样一次RT
//剩下的直接就积分掉了，Transmittance，SingleScatter和MultiScatter系数都是用这个函数
//我这边为了方便，把他们拆开来了
struct SingleScatteringResult
{
    float3 L;						// Scattered light (luminance)
    float3 OpticalDepth;			// Optical depth (1/m)
    float3 Transmittance;			// Transmittance in [0,1] (unitless)
    float3 MultiScatAs1;
};

SingleScatteringResult IntegrateScatteredLuminance(
    in float2 pixPos, in float3 WorldPos, in float3 WorldDir, in float3 SunDir, in AtmosphereParameters Atmosphere,
    in bool ground, in float SampleCountIni, in float DepthBufferValue, in bool VariableSampleCount,
    in bool MieRayPhase, in float tMaxMax = 9000000.0f)
{
    SingleScatteringResult result = (SingleScatteringResult)0;
    result.L = 0;
    result.OpticalDepth = 0;
    result.Transmittance = 1.0f;
    result.MultiScatAs1 = 0;

    if (dot(WorldPos, WorldPos) <= Atmosphere.BottomRadius * Atmosphere.BottomRadius)
    {
        return result;	// Camera is inside the planet ground

    }
    // Compute next intersection with atmosphere or ground
    float3 earthO = float3(0.0f, 0.0f, 0.0f);
    float tBottom = raySphereIntersectNearest(WorldPos, WorldDir, earthO, Atmosphere.BottomRadius);
    float tTop = raySphereIntersectNearest(WorldPos, WorldDir, earthO, Atmosphere.TopRadius);
    float tMax = 0.0f;
    if (tBottom < 0.0f)
    {
        if (tTop < 0.0f)
        {
            tMax = 0.0f; // No intersection with earth nor atmosphere: stop right away
            return result;
        }
        else
        {
            tMax = tTop;
        }
    }
    else
    {
        if (tTop > 0.0f)
        {
            tMax = min(tTop, tBottom);
        }
    }
    // if (DepthBufferValue >= 0.0f)
    // {
    // 		float tDepth = DepthBufferValue / 1000;
    // 		if (tDepth < tMax)
    // 		{
    // 			tMax = tDepth;
    // 		}
    // }
    tMax = min(tMax, tMaxMax);

    // Sample count
    float SampleCount = SampleCountIni;
    float SampleCountFloor = SampleCountIni;
    float tMaxFloor = tMax;
    if (VariableSampleCount)
    {
        SampleCount = min(SampleCountIni, lerp(RayMarchMinMaxSPP.x, RayMarchMinMaxSPP.y, saturate(tMax * 0.01)));
        SampleCountFloor = floor(SampleCount);
        tMaxFloor = tMax * SampleCountFloor / SampleCount;	// rescale tMax to map to the last entire step segment.

    }
    float dt = tMax / SampleCount;

    // Phase functions
    const float uniformPhase = 1.0 / (4.0 * PI);
    const float3 wi = SunDir;
    const float3 wo = WorldDir;
    float cosTheta = dot(wi, wo);
    float MiePhaseValue = hgPhase(Atmosphere.MiePhaseG, -cosTheta);	// mnegate cosTheta because due to WorldDir being a "in" direction.
    float RayleighPhaseValue = RayleighPhase(cosTheta);

    #ifdef ILLUMINANCE_IS_ONE
        // When building the scattering factor, we assume light illuminance is 1 to compute a transfert function relative to identity illuminance of 1.
        // This make the scattering factor independent of the light. It is now only linked to the atmosphere properties.
        float3 globalL = 1.0f;
    #else
        float3 globalL = gSunIlluminance;
    #endif

    // Ray march the atmosphere to integrate optical depth
    float3 L = 0.0f;
    float3 throughput = 1.0;
    float3 OpticalDepth = 0.0;
    float t = 0.0f;
    float tPrev = 0.0;
    const float SampleSegmentT = 0.3f;
    for (float s = 0.0f; s < SampleCount; s += 1.0f)
    {
        if (VariableSampleCount)
        {
            // More expenssive but artefact free
            float t0 = (s) / SampleCountFloor;
            float t1 = (s + 1.0f) / SampleCountFloor;
            // Non linear distribution of sample within the range.
            t0 = t0 * t0;
            t1 = t1 * t1;
            // Make t0 and t1 world space distances.
            t0 = tMaxFloor * t0;
            if (t1 > 1.0)
            {
                t1 = tMax;
                //	t1 = tMaxFloor;	// this reveal depth slices

            }
            else
            {
                t1 = tMaxFloor * t1;
            }
            //t = t0 + (t1 - t0) * (saturate(whangHashNoise(pixPos.x, pixPos.y, _Time.y * 60))); // With dithering required to hide some sampling artefact relying on TAA later? This may even allow volumetric shadow?
            t = t0 + (t1 - t0) * SampleSegmentT;
            dt = t1 - t0;
        }
        else
        {
            //t = tMax * (s + SampleSegmentT) / SampleCount;
            // Exact difference, important for accuracy of multiple scattering
            float NewT = tMax * (s + SampleSegmentT) / SampleCount;
            dt = NewT - t;
            t = NewT;
        }
        float3 P = WorldPos + t * WorldDir;

        //sample the medium
        MediumSampleRGB medium = sampleMediumRGB(P, Atmosphere);
        const float3 SampleOpticalDepth = medium.extinction * dt;
        const float3 SampleTransmittance = exp(-SampleOpticalDepth);
        OpticalDepth += SampleOpticalDepth;

        //phase and transmittance for the sun
        float pHeight = length(P);
        const float3 UpVector = P / pHeight;
        float SunZenithCosAngle = dot(SunDir, UpVector);
        float2 uv;
        LutTransmittanceParamsToUv(Atmosphere, pHeight, SunZenithCosAngle, uv);
        float3 TransmittanceToSun = 0;
        TransmittanceToSun = customSample(_TransmittanceLut, sampler_TransmittanceLut, uv).xyz;

        float3 PhaseTimesScattering;
        if (MieRayPhase)
        {
            PhaseTimesScattering = medium.scatteringMie * MiePhaseValue + medium.scatteringRay * RayleighPhaseValue;
        }
        else
        {
            PhaseTimesScattering = medium.scattering * uniformPhase;
        }

        // Earth shadow
        float tEarth = raySphereIntersectNearest(P, SunDir, earthO + PLANET_RADIUS_OFFSET * UpVector, Atmosphere.BottomRadius);
        float earthShadow = tEarth >= 0.0f ? 0.0f : 1.0f;
        //earthShadow = 1;

        // Dual scattering for multi scattering
        float3 multiScatteredLuminance = 0.0f;
        #if MULTISCATAPPROX_ENABLED
            multiScatteredLuminance = GetMultipleScattering(Atmosphere, medium.scattering, medium.extinction, P, SunZenithCosAngle);
        #endif

        float3 shadow = 1.0f;
        #if SHADOWMAP_ENABLED
            // First evaluate opaque shadow
            shadow = getShadow(Atmosphere, P);
        #endif

        float3 S = globalL * (earthShadow * shadow * TransmittanceToSun * PhaseTimesScattering + multiScatteredLuminance * medium.scattering);

        // When using the power serie to accumulate all sattering order, serie r must be <1 for a serie to converge.
        // Under extreme coefficient, MultiScatAs1 can grow larger and thus result in broken visuals.
        // The way to fix that is to use a proper analytical integration as proposed in slide 28 of http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite/
        // However, it is possible to disable as it can also work using simple power serie sum unroll up to 5th order. The rest of the orders has a really low contribution.
        #define MULTI_SCATTERING_POWER_SERIE 1

        #if MULTI_SCATTERING_POWER_SERIE == 0
            // 1 is the integration of luminance over the 4pi of a sphere, and assuming an isotropic phase function of 1.0/(4*PI)
            result.MultiScatAs1 += throughput * medium.scattering * 1 * dt;
        #else
            float3 MS = medium.scattering * 1;
            float3 MSint = (MS - MS * SampleTransmittance) / medium.extinction;
            result.MultiScatAs1 += throughput * MSint;
        #endif

        #if 0
            L += throughput * S * dt;
            throughput *= SampleTransmittance;
        #else
            // See slide 28 at http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite/
            float3 Sint = (S - S * SampleTransmittance) / medium.extinction;	// integrate along the current step segment
            L += throughput * Sint;														// accumulate and also take into account the transmittance from previous steps
            throughput *= SampleTransmittance;
        #endif

        tPrev = t;
    }

    if (ground && tMax == tBottom && tBottom > 0.0)
    {
        // Account for bounced light off the earth
        float3 P = WorldPos + tBottom * WorldDir;
        float pHeight = length(P);

        const float3 UpVector = P / pHeight;
        float SunZenithCosAngle = dot(SunDir, UpVector);
        float2 uv;
        LutTransmittanceParamsToUv(Atmosphere, pHeight, SunZenithCosAngle, uv);
        float3 TransmittanceToSun = 0;
        TransmittanceToSun = customSample(_TransmittanceLut, sampler_TransmittanceLut, uv).xyz;
        
        float3 shadow = 1.0f;
        #if SHADOWMAP_ENABLED
            // First evaluate opaque shadow
            shadow = getShadow(Atmosphere, P);
        #endif

        const float NdotL = saturate(dot(normalize(UpVector), normalize(SunDir)));
        L += globalL * TransmittanceToSun * throughput * NdotL * Atmosphere.GroundAlbedo / PI * shadow;
    }

    result.L = L;
    result.OpticalDepth = OpticalDepth;
    result.Transmittance = throughput;
    return result;
}