#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

struct pointLight
{
    float3 color;
    float intensity;
    float4 sphere;
};

StructuredBuffer<uint2> _FroxelBuffer;
StructuredBuffer<uint> _LightIndexBuffer;
StructuredBuffer<pointLight> _LightBuffer;
float4 _FroxelInfo;
float4 _LightInfo;

struct BSDFContext
{
    float NoL;
    float NoV;
    float NoH;
    float LoH;
    float VoL;
    float VoH;
};

void Init(inout BSDFContext LightData, float3 N, float3 V, float3 L, float3 H)
{
    LightData.NoL = max(dot(N, L), 0);
    LightData.NoV = max(dot(N, V), 0);
    LightData.NoH = max(dot(N, H), 0);
    LightData.LoH = max(dot(L, H), 0);
    LightData.VoL = max(dot(V, L), 0);
    LightData.VoH = max(dot(V, H), 0);
}

float3 GetOtherLight(float3 normal, float3 position, float2 baseUV, float depth)
{
    float farDepth = min(_ProjectionParams.z, _FroxelInfo.w);
    float lerpValue = (depth - _ProjectionParams.y) / (farDepth - _ProjectionParams.y);
    int3 froxelID = int3(
        floor(saturate(baseUV) * _FroxelInfo.xy),
        floor(saturate(lerpValue) * _FroxelInfo.z)
    );
    if (froxelID.z >= _FroxelInfo.z)
    {
        return 0;
    }
    uint ID = _FroxelInfo.x * _FroxelInfo.y * froxelID.z + _FroxelInfo.x * froxelID.y + froxelID.x;
    uint2 range = _FroxelBuffer[ID];

    float3 temp = 0;
    int lightIndex = 0;
    pointLight currentLight = (pointLight)0;
    UNITY_LOOP
    for (uint i = range.x; i < range.y; i++)
    {
        lightIndex = _LightIndexBuffer[i];
        currentLight = _LightBuffer[lightIndex];
        float3 lightVec = currentLight.sphere.xyz - position;
        float r = length(lightVec);
        float r2 = r * r + 0.1;

        float attenuation = min(rcp(r2), 10);
        float fac = r2 * rcp(currentLight.sphere.w * currentLight.sphere.w);
        float smoothFac = saturate(1 - fac);
        smoothFac *= smoothFac;
        float NdotL = saturate(dot(normal, normalize(lightVec)));
        temp += currentLight.color * currentLight.intensity * attenuation * smoothFac * NdotL;
    }
    // float front = lerp(_ProjectionParams.y, farDepth, froxelID.z / _FroxelInfo.z);
    // int level = _LightInfo.z;
    // float depthMax = SAMPLE_TEXTURE2D_LOD(_DepthPyramid, sampler_DepthPyramid, baseUV, level).r;
    //temp.y += step(LinearEyeDepth(depthMax, _ZBufferParams), front) / 10;
    //temp.x += LinearEyeDepth(depthMax, _ZBufferParams) / farDepth;
    // temp = (float)froxelID.z / _FroxelInfo.z;
    //temp = float3((float2)froxelID.xy / _FroxelInfo.xy, (float)froxelID.z / _FroxelInfo.z);
    return temp;
}

#endif