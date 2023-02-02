#ifndef CUSTOM_PCSS_INCLUDED
#define CUSTOM_PCSS_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Shadow/ShadowSamplingTent.hlsl"
#include "../ShaderLibrary/Core.hlsl"

#define MAX_SHADOW_CASCADES 4

#if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE)
    #define MAIN_LIGHT_CALCULATE_SHADOWS
#endif

#if defined(_DIRECTIONAL_PCF3)
    #define DIRECTIONAL_FILTER_SAMPLES 4
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_3x3
    #define TEXEL_SCALE 1.5f
#elif defined(_DIRECTIONAL_PCF5)
    #define DIRECTIONAL_FILTER_SAMPLES 9
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_5x5
    #define TEXEL_SCALE 2.0f
#elif defined(_DIRECTIONAL_PCF7)
    #define DIRECTIONAL_FILTER_SAMPLES 16
    #define DIRECTIONAL_FILTER_SETUP SampleShadow_ComputeSamples_Tent_7x7
    #define TEXEL_SCALE 2.5f
#else
    #define TEXEL_SCALE 1
#endif

TEXTURE2D_SHADOW(_MainLightShadowmapTexture);
SAMPLER_CMP(sampler_linear_clamp_compare);
SAMPLER(sampler_MainLightShadowmapTexture);

CBUFFER_START(MainLightShadows)
    // Last cascade is initialized with a no-op matrix. It always transforms
    // shadow coord to half3(0, 0, NEAR_PLANE). We use this trick to avoid
    // branching since ComputeCascadeIndex can return cascade index = MAX_SHADOW_CASCADES
    float4x4 _MainLightWorldToShadow[MAX_SHADOW_CASCADES + 1];
    float4 _CascadeShadowSplitSpheres0;
    float4 _CascadeShadowSplitSpheres1;
    float4 _CascadeShadowSplitSpheres2;
    float4 _CascadeShadowSplitSpheres3;
    float4 _CascadeShadowSplitSphereRadii;
    half4 _MainLightShadowOffset0;
    half4 _MainLightShadowOffset1;
    half4 _MainLightShadowOffset2;
    half4 _MainLightShadowOffset3;
    half4 _MainLightShadowParams;   // (x: shadowStrength, y: 1.0 if soft shadows, 0.0 otherwise, z: main light fade scale, w: main light fade bias)
    float4 _MainLightShadowmapSize;  // (xy: 1/width and 1/height, zw: width and height)
CBUFFER_END

float4 _ShadowBias; // x: depth bias, y: normal bias
#define BEYOND_SHADOW_FAR(shadowCoord) shadowCoord.z <= 0.0 || shadowCoord.z >= 1.0

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//unity自带函数

// ShadowParams
// x: ShadowStrength
// y: 1.0 if shadow is soft, 0.0 otherwise
half4 GetMainLightShadowParams()
{
    return _MainLightShadowParams;
}

half ComputeCascadeIndex(float3 positionWS)
{
    float3 fromCenter0 = positionWS - _CascadeShadowSplitSpheres0.xyz;
    float3 fromCenter1 = positionWS - _CascadeShadowSplitSpheres1.xyz;
    float3 fromCenter2 = positionWS - _CascadeShadowSplitSpheres2.xyz;
    float3 fromCenter3 = positionWS - _CascadeShadowSplitSpheres3.xyz;
    float4 distances2 = float4(dot(fromCenter0, fromCenter0), dot(fromCenter1, fromCenter1), dot(fromCenter2, fromCenter2), dot(fromCenter3, fromCenter3));

    half4 weights = half4(distances2 < _CascadeShadowSplitSphereRadii);
    weights.yzw = saturate(weights.yzw - weights.xyz);

    return half(4.0) - dot(weights, half4(4, 3, 2, 1));
}

float4 TransformWorldToShadowCoord(float3 positionWS)
{
    #ifdef _MAIN_LIGHT_SHADOWS_CASCADE
        half cascadeIndex = ComputeCascadeIndex(positionWS);
    #else
        half cascadeIndex = half(0.0);
    #endif

    float4 shadowCoord = mul(_MainLightWorldToShadow[cascadeIndex], float4(positionWS, 1.0));

    return float4(shadowCoord.xyz, 0);
}

half GetMainLightShadowFade(float3 positionWS)
{
    float3 camToPixel = positionWS - _WorldSpaceCameraPos;
    float distanceCamToPixel2 = dot(camToPixel, camToPixel);

    float fade = saturate(distanceCamToPixel2 * float(_MainLightShadowParams.z) + float(_MainLightShadowParams.w));
    return half(fade);
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//补充函数

void GetTexelSize(out float texelsize[MAX_SHADOW_CASCADES + 1])
{
    texelsize[0] = (2 * _CascadeShadowSplitSpheres0.w) * (_MainLightShadowmapSize.x * 2);
    texelsize[1] = (2 * _CascadeShadowSplitSpheres1.w) * (_MainLightShadowmapSize.x * 2);
    texelsize[2] = (2 * _CascadeShadowSplitSpheres2.w) * (_MainLightShadowmapSize.x * 2);
    texelsize[3] = (2 * _CascadeShadowSplitSpheres3.w) * (_MainLightShadowmapSize.x * 2);
    texelsize[4] = 1 / _MainLightShadowmapSize.x;
}

float SampleDirectionalShadowAtlas(float3 positionSTS)
{
    return SAMPLE_TEXTURE2D_SHADOW(
        _MainLightShadowmapTexture, sampler_linear_clamp_compare, positionSTS
    );
}

float FilterDirectionalShadow(float3 positionSTS)
{
    #if defined(DIRECTIONAL_FILTER_SETUP)
        float weights[DIRECTIONAL_FILTER_SAMPLES];
        float2 positions[DIRECTIONAL_FILTER_SAMPLES];
        float4 size = _MainLightShadowmapSize;

        DIRECTIONAL_FILTER_SETUP(size, positionSTS.xy, weights, positions);
        float shadow = 0;
        for (int i = 0; i < DIRECTIONAL_FILTER_SAMPLES; i++)
        {
            shadow += weights[i] * SampleDirectionalShadowAtlas(
                float3(positions[i].xy, positionSTS.z)
            );
        }
        return BEYOND_SHADOW_FAR(positionSTS) ? 1.0 : shadow;
    #else
        return BEYOND_SHADOW_FAR(positionSTS) ? 1.0 : SampleDirectionalShadowAtlas(positionSTS);
    #endif
}

float4 TransformWorldToShadowCoord(float3 positionWS, float3 normal, float3 lightDir, out float unit)
{
    #ifdef _MAIN_LIGHT_SHADOWS_CASCADE
        half cascadeIndex = ComputeCascadeIndex(positionWS);
    #else
        half cascadeIndex = half(0.0);
    #endif
    float texelsize[MAX_SHADOW_CASCADES + 1];
    GetTexelSize(texelsize);

    float3 normalBias = normal * texelsize[cascadeIndex] * TEXEL_SCALE * 1.414;
    float4 shadowCoord = mul(_MainLightWorldToShadow[cascadeIndex], float4(positionWS + normalBias, 1.0));
    unit = abs(mul((float3x3)_MainLightWorldToShadow[cascadeIndex], lightDir).z);

    return float4(shadowCoord.xyz, 0);
}

half MainLightRealtimeShadow(float4 shadowCoord)
{
    #if !defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        return half(1.0);
    #else
        return FilterDirectionalShadow(shadowCoord.xyz);
    #endif
}

half MainLightShadow(float4 shadowCoord, float3 positionWS)
{
    half realtimeShadow = MainLightRealtimeShadow(shadowCoord);

    #ifdef MAIN_LIGHT_CALCULATE_SHADOWS
        half shadowFade = GetMainLightShadowFade(positionWS);
    #else
        half shadowFade = half(1.0);
    #endif
    return realtimeShadow * (1 - shadowFade) + shadowFade;
}

float4 _ShadowInfo;
#define BLOCKER_TEST_DISTANCE _ShadowInfo.z
#define BLOCKER_COUNT _ShadowInfo.w
#define FILTER_COUNT _ShadowInfo.w

half MainLightShadowDepth(float4 shadowCoord, float unit)
{
    #if !defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        return half(0.0);
    #else
        float depth = shadowCoord.z - SAMPLE_TEXTURE2D_LOD(_MainLightShadowmapTexture, sampler_MainLightShadowmapTexture, shadowCoord.xy, 0).r;
        if (_ProjectionParams.x < 0)
        {
            depth = -depth;
        }
        depth = depth / unit;
        depth = min(_ShadowInfo.z, depth);
        return max(0, depth);
    #endif
}

half MainLightPCSSShadow(float4 shadowCoord, float3 positionWS, float unit, float minDepth, float Zoffset, float maxSoftShadow, float2 screenUV)
{
    #if !defined(MAIN_LIGHT_CALCULATE_SHADOWS)
        return half(1.0);
    #else
        float texelsize[MAX_SHADOW_CASCADES + 1];
        GetTexelSize(texelsize);
        #ifdef _MAIN_LIGHT_SHADOWS_CASCADE
            half cascadeIndex = ComputeCascadeIndex(positionWS);
        #else
            half cascadeIndex = half(0.0);
        #endif
        //blocker detection
        float blokerSize = min(maxSoftShadow, BLOCKER_TEST_DISTANCE * DegToRad(_ShadowInfo.x));
        float blokerRange = blokerSize / 2 / texelsize[cascadeIndex];
        float ZBoffset = Zoffset * unit * blokerSize / 2;
        ZBoffset = 0;
        float aveDepth = 0;
        float blockerCount = 0;
        int k = frac(screenUV.x + screenUV.y) * 32458 + _FrameNum;
        UNITY_LOOP
        for (int i = 0; i < BLOCKER_COUNT; i++)
        {
            float4 offset = float4(GetPoissonSample(i + k, k) * blokerRange * _MainLightShadowmapSize.xy, ZBoffset, 0);
            float testDepth = MainLightShadowDepth(shadowCoord + offset, unit);
            aveDepth += step(0.05, testDepth) * testDepth;
            blockerCount += step(0.05, testDepth);
        }
        if (blockerCount == 0)
        {
            return 1;
        }
        else
        {
            aveDepth = aveDepth / blockerCount;
        }
        //filter pass
        float filterSize = min(blokerSize, aveDepth * DegToRad(_ShadowInfo.y));
        float filterRange = filterSize / 2 / texelsize[cascadeIndex];
        float ZFoffset = Zoffset * unit * filterSize / 2;
        ZFoffset = 0;
        float aveShadow = 0;
        k = frac(screenUV.x + screenUV.y) * 31233 + _FrameNum;
        UNITY_LOOP
        for (int j = 0; j < FILTER_COUNT; j++)
        {
            float4 offset = float4(GetPoissonSample(j + k, k) * filterRange * _MainLightShadowmapSize.xy, ZFoffset, 0);
            float testShadow = MainLightRealtimeShadow(shadowCoord + offset);
            aveShadow += testShadow / FILTER_COUNT;
        }
        float realtimeShadow = aveShadow;

        #ifdef MAIN_LIGHT_CALCULATE_SHADOWS
            half shadowFade = GetMainLightShadowFade(positionWS);
        #else
            half shadowFade = half(1.0);
        #endif
        return realtimeShadow * (1 - shadowFade) + shadowFade;
    #endif
}

float2 GetShadow(float depth, float3 positionWS, float3 normal, float3 lightDir)
{
    if (depth >= 0.9 * _ProjectionParams.z)
    {
        return float2(1, 0);
    }
    else if (dot(normal, lightDir) < 0)
    {
        return float2(0, 0);
    }

    //先采样正常的shadow
    float unit = 1;
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS, normal, lightDir, unit);
    float shadowCurrent = MainLightShadow(shadowCoord, positionWS.xyz);
    float shadowDepth = MainLightShadowDepth(shadowCoord, unit);
    return float2(shadowCurrent, shadowDepth);
}
#endif
