#include "PCSSSample.hlsl"

TEXTURE2D(_GBufferC);
SAMPLER(sampler_GBufferC);
TEXTURE2D(_DepthBuffer);
SAMPLER(sampler_DepthBuffer);

float4 _TexelSize;
float3 _LightDirection;

#define TEST_COUNT 16

static float2 gatherOffset[TEST_COUNT] = {
    float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1),
    float2(-1, 0), float2(1, 0), float2(0, 1), float2(0, -1),
    float2(-0.5, -0.5), float2(0.5, -0.5), float2(-0.5, 0.5), float2(0.5, 0.5),
    float2(-0.25, -0.25), float2(0.25, -0.25), float2(-0.25, 0.25), float2(0.25, 0.25),
};

float frag(Varyings input) : SV_TARGET
{
    float shadowRange = 0;
    float shadow = 0;
    bool needPCSS = false;
    float3 origin = GetCameraPositionWS();
    //现在低分辨率图中随机采样一些sample
    for (int i = 0; i < TEST_COUNT; i++)
    {
        float2 jitter = gatherOffset[i] * _TexelSize.xy / 2;
        float2 sampleUV = input.baseUV + jitter;
        float depth = SAMPLE_DEPTH_TEXTURE_LOD(_DepthBuffer, sampler_DepthBuffer, sampleUV, 0);
        depth = LinearEyeDepth(depth, _ZBufferParams);
        float4 normal = SAMPLE_TEXTURE2D_LOD(_GBufferC, sampler_GBufferC, sampleUV, 0) * 2 - 1;
        float4 positionWS = GetPositionWS(sampleUV, depth, origin);
        float2 shadowCurrent = GetShadow(depth, positionWS.xyz, normal.xyz, _LightDirection);
        //if (shadowCurrent.r > 0.01 && shadowCurrent.r < 0.99)

        {
            shadowRange = max(shadowRange,
            shadowCurrent.g * DegToRad(_ShadowInfo.x) / depth * abs(UNITY_MATRIX_P._m11) / 2);
        }
        shadow += shadowCurrent.r / TEST_COUNT;
    }

    if (shadow < 0.001)
    {
        return -1;
    }
    else if (shadow > 0.999)
    {
        return -2;
    }
    return shadowRange;
}