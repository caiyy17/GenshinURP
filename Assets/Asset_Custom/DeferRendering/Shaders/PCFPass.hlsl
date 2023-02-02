#include "PCSSSample.hlsl"

TEXTURE2D(_GBufferC);
SAMPLER(sampler_GBufferC);
TEXTURE2D(_DepthBuffer);
SAMPLER(sampler_DepthBuffer);

float3 _LightDirection;

float2 frag(Varyings input) : SV_TARGET
{
    float2 sampleUV = input.baseUV;

    float depth = SAMPLE_DEPTH_TEXTURE_LOD(_DepthBuffer, sampler_DepthBuffer, sampleUV, 0);
    depth = LinearEyeDepth(depth, _ZBufferParams);
    float4 normal = SAMPLE_TEXTURE2D_LOD(_GBufferC, sampler_GBufferC, sampleUV, 0) * 2 - 1;
    float3 origin = GetCameraPositionWS();
    float4 positionWS = GetPositionWS(sampleUV, depth, origin);

    //先采样正常的shadow
    float2 shadowCurrent = GetShadow(depth, positionWS.xyz, normal.xyz, _LightDirection);
    return shadowCurrent;
}