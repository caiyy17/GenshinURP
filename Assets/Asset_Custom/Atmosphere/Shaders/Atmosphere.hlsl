#ifndef CUSTOM_ATMOSPHERE_INCLUDED
#define CUSTOM_ATMOSPHERE_INCLUDED

CBUFFER_START(_Atmosphere)
    float4 _LutInfo;
    float4 _VolumeInfo;
    float4 _AtmosphereInfo[9];
    float4 _StarInfo;
    float4 _JdInfo;
    float4 _SolarInfo[20];
CBUFFER_END

//大气散射涉及到4张RT
TEXTURE2D(_TransmittanceLut);
SAMPLER(sampler_TransmittanceLut);
TEXTURE2D(_SkyViewLut);
SAMPLER(sampler_SkyViewLut);
TEXTURE2D(_SkyViewTransLut);
SAMPLER(sampler_SkyViewTransLut);
TEXTURE2D(_CameraVolume);
SAMPLER(sampler_CameraVolume);
TEXTURE2D(_MultiScat);
SAMPLER(sampler_MultiScat);
TEXTURE2D(_SkyMap);
SAMPLER(sampler_SkyMap);

//这是正常渲染的颜色信息和深度信息
// TEXTURE2D(_CameraDepthTexture);
// SAMPLER(sampler_CameraDepthTexture);
// TEXTURE2D(_CameraOpaqueTexture);
// SAMPLER(sampler_CameraOpaqueTexture);
TEXTURE2D(_CustomDepthTexture);
SAMPLER(sampler_CustomDepthTexture);
TEXTURE2D(_CustomColorTexture);
SAMPLER(sampler_CustomColorTexture);

//这边提供地球的texture和银河的texture
TEXTURE2D(_EarthMap);
SAMPLER(sampler_EarthMap);
TEXTURE2D(_EarthCloudMap);
SAMPLER(sampler_EarthCloudMap);
TEXTURE2D(_EarthNightMap);
SAMPLER(sampler_EarthNightMap);
TEXTURE2D(_MoonMap);
SAMPLER(sampler_MoonMap);
TEXTURE2D(_FarMap);
SAMPLER(sampler_FarMap);
TEXTURE2D(_StarMap);
SAMPLER(sampler_StarMap);

//由于computeshader的采样和一般shader有些不通用，这边采样函数在shader内部定义，其他函数都在input内部
#define customSample(tex, sampler, uv) SAMPLE_TEXTURE2D_LOD(tex, sampler, uv, 0)
#include "AtmosphereInput.hlsl"

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 baseUV : VAR_BASE_UV;
    float4 color : TEXCOORD0;
};

//后处理统一的Vertex函数，覆盖全屏
Varyings DefaultPassVertex(uint vertexID : SV_VertexID)
{
    Varyings output = (Varyings)0;
    output.positionCS = float4(
        vertexID <= 1 ? - 1.0 : 3.0,
        vertexID == 1 ? 3.0 : - 1.0,
        0.0, 1.0
    );
    output.baseUV = float2(
        vertexID <= 1 ? 0.0 : 2.0,
        vertexID == 1 ? 2.0 : 0.0
    );
    if (_ProjectionParams.x < 0.0)
    {
        output.baseUV.y = 1 - output.baseUV.y;
    }
    return output;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

//Transmittance记录：对于不同Height的点，不同角度太阳sunZenith，光从大气顶端到这个点的衰减
//所以是关于(H,theta)的函数，采样是地平线附近的样本更加密集
//对于任意两点之间的衰减，将采样LUT的到的值相除即可
float4 TransmittanceLutPS(Varyings Input) : SV_TARGET
{
    float2 pixPos = Input.positionCS.xy;
    AtmosphereParameters Atmosphere = GetAtmosphereParameters();
    // Compute camera position from LUT coords
    // 上方为天顶
    float2 uv = (pixPos) / float2(gResolution);
    float viewHeight;
    float viewZenithCosAngle;
    UvToLutTransmittanceParams(Atmosphere, viewHeight, viewZenithCosAngle, uv);

    //  A few extra needed constants
    float3 WorldPos = float3(0.0f, 0.0f, viewHeight);
    float3 WorldDir = float3(0.0f, sqrt(max(0, 1.0 - viewZenithCosAngle * viewZenithCosAngle)), viewZenithCosAngle);

    const bool ground = false;
    const float SampleCountIni = 40.0f;	// Can go a low as 10 sample but energy lost starts to be visible.
    const float DepthBufferValue = -1.0;
    const bool VariableSampleCount = false;
    const bool MieRayPhase = false;

    SingleScatteringResult ss = IntegrateScatteredLuminance(pixPos, WorldPos, WorldDir, sun_direction, Atmosphere, ground, SampleCountIni, DepthBufferValue, VariableSampleCount, MieRayPhase);
    float3 transmittance = exp(-ss.OpticalDepth);

    return float4(transmittance, 1.0f);
}

//渲染天空盒子，虽然天空整体低频，但是地平线附近变化还是剧烈的，直接用32*3的LUT会不太够
//所以另外渲染一张天空，比那个用高一些的分辨率，同时地平线附近多采样一些
//采样uv由viewZenith和lightView构成，所以对于相机高度和太阳角度都是定死的，换了参数要重新来一遍
//viewZenith就是视线和天顶的夹角，而lightView是两个平面的夹角
//这个夹角是视线天顶平面（两条射线组成一个平面）和太阳天顶平面的夹角，相当于太阳固定的情况下往不同的地方看
//由于后期需要计算阴影，我们把lightView取消了，将基点定为x轴正方向，太阳方向使用真实太阳方向
void SkyViewLutPS(Varyings Input,
    out float4 GT0 : SV_Target0,
    out float4 GT1 : SV_Target1)
{
    float2 pixPos = Input.positionCS.xy;
    AtmosphereParameters Atmosphere = GetAtmosphereParameters();

    float3 WorldDir;
    float3 SunDir;
    //这边也是debug用的，不使用不均匀采样可以看清楚天空的样子
    //float3 ClipSpace = float3((pixPos / float2(gResolution))*float2(2.0, -2.0) - float2(1.0, -1.0), 1.0);
    //WorldDir = float3(
    //     sin(ClipSpace.x * PI) * cos(ClipSpace.y * PI / 2),
    //     cos(ClipSpace.x * PI) * cos(ClipSpace.y * PI / 2),
    //     sin(ClipSpace.y * PI / 2));
    //SunDir = sun_direction;
    
    float3 WorldPos = float3(0, 0, Atmosphere.BottomRadius + camera.z);
    float viewHeight = length(WorldPos);
    //下方为天顶
    float2 uv = pixPos / float2(gResolution);
    float viewZenithCosAngle;
    float lightViewCosAngle;
    float lightViewSinAngle;
    UvToSkyViewLutParams(Atmosphere, viewZenithCosAngle, lightViewCosAngle, lightViewSinAngle, viewHeight, uv);
    float viewZenithSinAngle = sqrt(saturate(1 - viewZenithCosAngle * viewZenithCosAngle));

    SunDir = sun_direction;
    WorldPos = float3(0.0f, 0.0f, viewHeight);
    //我们定义视线中心方向朝向x轴正方向
    WorldDir = float3(
        viewZenithSinAngle * lightViewCosAngle,
        viewZenithSinAngle * lightViewSinAngle,
        viewZenithCosAngle);

    //Move to top atmospehre
    if (!MoveToTopAtmosphere(WorldPos, WorldDir, Atmosphere.TopRadius))
    {
        // Ray is not intersecting the atmosphere
        GT0 = float4(0, 0, 0, 1);
        GT1 = float4(1, 1, 1, 1);
        return;
    }

    const bool ground = false;
    const float SampleCountIni = 30;
    const float DepthBufferValue = -1.0;
    const bool VariableSampleCount = true;
    const bool MieRayPhase = true;

    SingleScatteringResult ss = IntegrateScatteredLuminance(pixPos, WorldPos, WorldDir, SunDir, Atmosphere, ground, SampleCountIni, DepthBufferValue, VariableSampleCount, MieRayPhase);
    const float Transmittance = dot(ss.Transmittance, float3(1.0f / 3.0f, 1.0f / 3.0f, 1.0f / 3.0f));
    GT0 = float4(ss.L, Transmittance);
    GT1 = float4(ss.Transmittance, Transmittance);
    return;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

//caution: hard-coded number
#define AP_SLICE_COUNT CameraVolumeRes
#define AP_KM_PER_SLICE min(max(4.0f, camera.z), 20.0f)

float AerialPerspectiveDepthToSlice(float depth)
{
    return depth * (1.0f / AP_KM_PER_SLICE);
}
float AerialPerspectiveSliceToDepth(float slice)
{
    return slice * AP_KM_PER_SLICE;
}

float4 CameraVolumePS(Varyings Input) : SV_TARGET
{
    //0.5-31.5, 32.5-63.5...
    float2 pixPos = Input.positionCS.xy;
    float sliceId = floor(pixPos.x / gResolution.y);
    //0.5-31.5
    pixPos.x = pixPos.x - sliceId * gResolution.y;
    //0.5/32-31.5/32
    float2 uv = pixPos / gResolution.y;
    //0-1
    uv = saturate(float2(fromSubUvsToUnit(uv.x, gResolution.y), fromSubUvsToUnit(uv.y, gResolution.y)));
    //(-1)-1
    float4 ClipSpace = float4(uv * float2(2.0, 2.0) - float2(1.0, 1.0), 1.0, 1.0);
    if (_ProjectionParams.x < 0.0)
    {
        ClipSpace.y *= -1;
    }
    float4 HPos = mul(gSkyInvViewProjMat, ClipSpace);
    float3 WorldDir = normalize(HPos.xyz / HPos.w);

    WorldDir = UnityToUE(WorldDir);
    AtmosphereParameters Atmosphere = GetAtmosphereParameters();
    float earthR = Atmosphere.BottomRadius;
    float3 earthO = float3(0.0, 0.0, -earthR);
    float3 camPos = float3(0, 0, earthR + camera.z);
    float3 SunDir = sun_direction;
    float3 SunLuminance = 0.0;

    //sliceId(0-31) -> Slice 0.5/32-31.5/32 -> 0.5^2/32 - 31.5^2/32
    float Slice = ((sliceId + 0.5f) / AP_SLICE_COUNT);
    Slice *= Slice;	// squared distribution
    Slice *= AP_SLICE_COUNT;

    float3 WorldPos = camPos;
    float viewHeight;

    // Compute position from froxel information
    float tMax = AerialPerspectiveSliceToDepth(Slice);
    float3 newWorldPos = WorldPos + tMax * WorldDir;

    // If the voxel is under the ground, make sure to offset it out on the ground.
    viewHeight = length(newWorldPos);
    if (viewHeight <= (Atmosphere.BottomRadius + PLANET_RADIUS_OFFSET))
    {
        // return float4(1,1,1,1);
        // Apply a position offset to make sure no artefact are visible close to the earth boundaries for large voxel.
        newWorldPos = normalize(newWorldPos) * (Atmosphere.BottomRadius + PLANET_RADIUS_OFFSET);
        WorldDir = normalize(newWorldPos - camPos);
        tMax = length(newWorldPos - camPos);
    }
    float tMaxMax = tMax;

    // Move ray marching start up to top atmosphere.
    viewHeight = length(WorldPos);
    if (viewHeight >= Atmosphere.TopRadius)
    {
        float3 prevWorlPos = WorldPos;
        if (!MoveToTopAtmosphere(WorldPos, WorldDir, Atmosphere.TopRadius))
        {
            // Ray is not intersecting the atmosphere
            return float4(0.0, 0.0, 0.0, 1.0);
        }
        float LengthToAtmosphere = length(prevWorlPos - WorldPos);
        if (tMaxMax < LengthToAtmosphere)
        {
            // tMaxMax for this voxel is not within earth atmosphere
            return float4(0.0, 0.0, 0.0, 1.0);
        }
        // Now world position has been moved to the atmosphere boundary: we need to reduce tMaxMax accordingly.
        tMaxMax = max(0.0, tMaxMax - LengthToAtmosphere);
    }

    const bool ground = false;
    const float SampleCountIni = 30;
    const float DepthBufferValue = -1.0;
    const bool VariableSampleCount = false;
    const bool MieRayPhase = true;

    SingleScatteringResult ss = IntegrateScatteredLuminance(pixPos, WorldPos, WorldDir, SunDir, Atmosphere, ground, SampleCountIni, DepthBufferValue, VariableSampleCount, MieRayPhase, tMaxMax);
    const float Transmittance = dot(ss.Transmittance, float3(1.0f / 3.0f, 1.0f / 3.0f, 1.0f / 3.0f));
    return float4(ss.L, Transmittance);
}


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

float3 GetFarLuminance(float2 pixPos, float3 WorldDir)
{
    //////////////////////////////////////////////////
    //星空背景颜色
    //////////////////////////////////////////////////
    float3 FarPos = TransformLocalToEarth(WorldDir);
    FarPos = TransformEarthToICRS(FarPos);
    FarPos = Rz(FarPos, PI / 2);
    //重新还原经纬度，可以得到我们正在渲染的点是地球的什么经纬度
    //经纬度坐标中间点是(0,0)，对应坐标方向(1,0,0)，即朝向x轴正方向
    float2 farUV;
    SphericalToUv(FarPos, farUV);
    //farUV = float2(fromUnitToSubUvs(farUV.x, gResolution.x), fromUnitToSubUvs(farUV.y, gResolution.y));
    //由于从天球内部观察天球，外表贴图要做一个u的反转
    farUV.x = 1 - farUV.x;
    //return float3(farUV,0);
    float3 color = SAMPLE_TEXTURE2D_LOD(_FarMap, sampler_FarMap, farUV, 0).xyz * far_map_illuminance + far_color;
    //////////////////////////////////////////////////
    //星空
    //////////////////////////////////////////////////
    float2 starUV = pixPos / gResolution;
    color += SAMPLE_TEXTURE2D_LOD(_StarMap, sampler_StarMap, starUV, 0).xyz;
    return color;
}

float4 GetSunLuminance(float3 WorldPos, float3 WorldDir)
{
    #if RENDER_SUN_DISK
        float CosHalfApex = cos(0.5 * sun_angle * 3.14159 / 180.0);
        float ViewDotLight = dot(WorldDir, sun_direction);
        if (ViewDotLight > CosHalfApex)
        {
            const float3 SunLuminance = sun_illuminance;
            const float SoftEdge = saturate(2.0f * (ViewDotLight - CosHalfApex) / (1.0f - CosHalfApex));
            return float4(SunLuminance * SoftEdge, SoftEdge);
        }
    #endif
    return 0;
}

float4 GetMoonLuminance(float3 WorldPos, float3 WorldDir, float radius)
{
    #if RENDER_MOON_DISK
        float CosHalfApex = cos(0.5 * moon_angle * 3.14159 / 180.0);
        //因为月球距离地球的距离不算特别远，所以需要根据当前高度对月亮角度进行修正
        float3 MoonDir = normalize(moon_direction - pi_moon * WorldPos / radius);
        float ViewDotLight = dot(WorldDir, MoonDir);
        if (ViewDotLight > CosHalfApex)
        {
            float t_moon = raySphereIntersectNearest(float3(0, 0, 0), WorldDir, MoonDir, sin(0.5 * moon_angle * 3.14159 / 180.0));
            if (t_moon > 0)
            {
                float3 MoonPos = normalize(-MoonDir + t_moon * WorldDir);
                float NdotL = dot(MoonPos, sun_direction);
                NdotL = smoothstep(0, 0.5, NdotL);
                MoonPos = TransformLocalToEarth(MoonPos);
                MoonPos = TransformEarthToICRS(MoonPos);
                MoonPos = TransformICRSToEcliptic(MoonPos);
                MoonPos = TransformEclipticToMoon(MoonPos);
                float2 moonUV;
                SphericalToUv(MoonPos, moonUV);
                float3 MoonLuminance = SAMPLE_TEXTURE2D_LOD(_MoonMap, sampler_MoonMap, moonUV, 0).xyz * moon_illuminance * (NdotL * 0.95 + 0.05);
                const float SoftEdge = saturate(10.0f * (ViewDotLight - CosHalfApex) / (1.0f - CosHalfApex));
                return float4(MoonLuminance * SoftEdge, SoftEdge);
            }
        }
    #endif
    return 0;
}

float4 GetSkyLuminance(float3 WorldPos, float3 WorldDir, out float4 farTrans)
{
    AtmosphereParameters Atmosphere = GetAtmosphereParameters();
    float viewHeight = length(WorldPos);
    float3 UpVector = WorldPos / viewHeight;
    //为了方便阴影计算，我们就取lightVector为x轴了，不随太阳位置改变
    float3 LightVector = float3(1, 0, 0);
    float3 ViewVector = normalize(float3(WorldDir.xy, 0.0));

    float2 uv;
    float viewZenithCosAngle = dot(UpVector, WorldDir);
    float lightViewCosAngle = dot(LightVector, ViewVector);
    float lightViewSinAngle = dot(UpVector, cross(ViewVector, LightVector));
    SkyViewLutParamsToUv(Atmosphere, false, viewZenithCosAngle, lightViewCosAngle, lightViewSinAngle, viewHeight, uv);
    float4 color = SAMPLE_TEXTURE2D_LOD(_SkyViewLut, sampler_SkyViewLut, uv, 0);
    farTrans = SAMPLE_TEXTURE2D_LOD(_SkyViewTransLut, sampler_SkyViewLut, uv, 0);
    return color;
}

float3 GetGroundColor(float3 localPos)
{
    AtmosphereParameters Atmosphere = GetAtmosphereParameters();
    float NdotL = dot(sun_direction, localPos);
    float3 shadow = getShadow(Atmosphere, localPos * Atmosphere.BottomRadius);

    //这边都是UE坐标系，z轴向上的左手系，我们是面向x轴正方向
    float3 EarthPos = TransformLocalToEarth(localPos);

    //重新还原经纬度，可以得到我们正在渲染的点是地球的什么经纬度
    //经纬度坐标中间点是(0,0)，对应坐标方向(1,0,0)，即朝向x轴正方向
    float2 earthUV;
    SphericalToUv(EarthPos, earthUV);
    //return float3(earthUV,0);
    
    float3 earthColor = SAMPLE_TEXTURE2D_LOD(_EarthMap, sampler_EarthMap, earthUV, 0).xyz * earth_map_illuminance;
    float3 earthNightColor = SAMPLE_TEXTURE2D_LOD(_EarthNightMap, sampler_EarthNightMap, earthUV, 0).xyz * earth_night_map_illuminance;
    float3 earthCloudColor = SAMPLE_TEXTURE2D_LOD(_EarthCloudMap, sampler_EarthCloudMap, earthUV, 0).xyz * earth_cloud_map_illuminance;

    //caution: hard-coded color blend option
    float3 earthLight = saturate(NdotL) * shadow * 0.98 + 0.02;
    earthColor = earthColor * earthLight + earthNightColor * (1 - smoothstep(0, 0.1, NdotL + 0.05));
    return earthColor * (1 - saturate(earthCloudColor)) + earthCloudColor * earthLight;
}

//用视线方向和太阳角度采样skylut
//因为skylut是用viewZenith和lightView角度采样的，先转换一下坐标
float3 GetBlendedColor(float2 pixPos, float3 WorldDir, float Height)
{
    AtmosphereParameters Atmosphere = GetAtmosphereParameters();
    float3 WorldPos = float3(0, 0, Atmosphere.BottomRadius + Height);
    float viewHeight = length(WorldPos);
    float3 UpVector = WorldPos / viewHeight;
    float viewZenithCosAngle = dot(UpVector, WorldDir);
    //////////////////////////////////////////////////
    //星空加太阳月亮颜色
    //////////////////////////////////////////////////
    //caution: hard-coded color blend option
    //如果在大气层内部且太阳比较高的时候，就不显示星星
    float fade = (1 - saturate(Height / (Atmosphere.TopRadius - Atmosphere.BottomRadius))) * saturate(sun_direction.z * 10 + 0.1);
    float3 farColor = GetFarLuminance(pixPos, WorldDir) * (1 - fade);
    float4 moonColor = GetMoonLuminance(WorldPos, WorldDir, Atmosphere.BottomRadius);
    float4 sunColor = GetSunLuminance(WorldPos, WorldDir);
    //这边顺序加上太阳和月亮
    farColor = farColor * (1 - sunColor.a) + sunColor.xyz * sunColor.a;
    farColor = farColor * (1 - moonColor.a) + moonColor.xyz * moonColor.a;
    
    //////////////////////////////////////////////////
    //天空颜色
    //////////////////////////////////////////////////
    float4 farTrans;
    float4 skyColor = GetSkyLuminance(WorldPos, WorldDir, farTrans);
    
    //////////////////////////////////////////////////
    //最后根据观察点与视线方向决定如何混合颜色
    //////////////////////////////////////////////////
    float4 color;
    float tBottom = raySphereIntersectNearest(WorldPos, WorldDir, float3(0.0f, 0.0f, 0.0f), Atmosphere.BottomRadius);
    //如果与地面相交，那么就在天空color的基础上画上地面texture
    if (tBottom > 0) //below the horizon
    {
        //localPos是视线与地球表面相交的坐标
        float3 localPos = normalize(WorldPos + (tBottom) * WorldDir);
        float3 groundColor = GetGroundColor(localPos);
        color.xyz = groundColor * farTrans.xyz + skyColor.xyz;
    }
    else
    {
        color.xyz = skyColor.xyz + farColor.xyz * farTrans.xyz;
    }

    return color.xyz;
}

//渲染天空盒，用视线方向还原世界方向，采样lut
float4 SkyPassFragment(Varyings input) : SV_TARGET
{
    float2 pixPos = input.positionCS.xy;
    float2 uv = pixPos / gResolution;

    float4 ClipSpace = float4(uv * float2(2.0, 2.0) - float2(1.0, 1.0), 1.0, 1.0);
    if (_ProjectionParams.x < 0.0)
    {
        ClipSpace.y *= -1;
    }
    float4 positionWS = mul(gSkyInvViewProjMat, ClipSpace);
    positionWS = positionWS / positionWS.w;
    float3 WorldDir = normalize(positionWS.xyz);
    WorldDir = UnityToUE(WorldDir);
    //修改这边，同时使用_AtmosphereInfo的camera可以方便看到所有球面渲染的天空
    // float scaleDivide = 4;
    // float2 fovDivide = scaleDivide * float2(2 * _ScreenParams.y / _ScreenParams.x, 1);
    // WorldDir = float3(
    //     sin(ClipSpace.x * PI / fovDivide.x) * cos(ClipSpace.y * PI / 2 / fovDivide.y),
    //     cos(ClipSpace.x * PI / fovDivide.x) * cos(ClipSpace.y * PI / 2 / fovDivide.y),
    //     sin(ClipSpace.y * PI / 2 / fovDivide.y));

    //根据每一个pixel的视线方向和当前高度，开始画天空
    float3 color = GetBlendedColor(pixPos, WorldDir, camera.z);
    return float4(color, 1.0);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

float4 RenderPassFragment(Varyings input) : SV_TARGET
{
    float2 pixPos = input.positionCS.xy;
    float2 uv = pixPos / gResolution;
    float4 sceneColor = SAMPLE_TEXTURE2D_LOD(_CustomColorTexture, sampler_CustomColorTexture, uv, 0);
    float alpha = saturate(sceneColor.a);
    //float depth = SAMPLE_DEPTH_TEXTURE_LOD(_CustomDepthTexture, sampler_CustomDepthTexture, uv, 0);
    float3 sky = SAMPLE_TEXTURE2D_LOD(_SkyMap, sampler_SkyMap, uv, 0).xyz;
    //depth = LinearEyeDepth(depth, _ZBufferParams);
    //float depth01 = Linear01Depth(depth, _ZBufferParams);
    float3 color = sceneColor.xyz * alpha + sky * (1 - alpha);

    return float4(color, 1.0);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

StructuredBuffer<starData> _Stars;
StructuredBuffer<int> _Constellations;

Varyings StarsPassVertex(uint vertexID : SV_VertexID)
{
    Varyings output;
    int starIndex = vertexID / 4;
    int quadIndex = vertexID - starIndex * 4;
    const float amount = star_size;
    const float2 delta = float2(amount * gResolution.y / gResolution.x, amount);
    const float2 offsets[] = {
        float2(-delta.x, delta.y), float2(-delta.x, -delta.y),
        float2(delta.x, -delta.y), float2(delta.x, delta.y)
    };
    const float2 uvs[] = {
        float2(0, 1), float2(0, 0),
        float2(1, 0), float2(1, 1)
    };
    float2 offset = offsets[quadIndex];
    output.baseUV = uvs[quadIndex];

    starData data = _Stars[starIndex];
    starResult result = ProcessStarData(data);

    //caution: hard-coded flash
    float intensety = 0.9 + 0.2 * sin(sin(data.RAdeg * 123456 + data.DEdeg * 654321) + frac(_Time.y) * 2 * PI);

    output.positionCS = result.positionCS + float4(offset, 0, 0) * result.positionCS.w;
    output.color = float4(result.color, 1) * intensety;

    if (data.HIP == 11767)
    {
        output.color = float4(0, 1, 0, 1);
    }
    return output;
}

float4 StarsPassFragment(Varyings input) : SV_TARGET
{
    float2 temp = input.baseUV * 2 - 1;
    float intensity = 1 - dot(temp, temp);
    intensity *= star_illuminance;
    float4 color = input.color * intensity;
    return color;
}

Varyings ConstellationsPassVertex(uint vertexID : SV_VertexID)
{
    Varyings output = (Varyings)0;

    int starIndex = _Constellations[vertexID];
    starData data = _Stars[starIndex];
    starResult result = ProcessStarData(data);

    output.positionCS = result.positionCS;
    output.baseUV = frac(vertexID / 2.0f) * 2;
    return output;
}

float4 ConstellationsPassFragment(Varyings input) : SV_TARGET
{
    float intensity = saturate((1 - abs(input.baseUV.x - 0.5) * 2) * 2);
    intensity *= constellation_illuminance;
    return intensity;
}

#endif