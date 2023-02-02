#include "TestSample.hlsl"

TEXTURE2D(_GBufferC);
SAMPLER(sampler_GBufferC);
TEXTURE2D(_DepthBuffer);
SAMPLER(sampler_DepthBuffer);
float3 _LightDirection;

float4 frag(Varyings input) : SV_TARGET
{
    float2 sampleUV = input.baseUV;
    float4 normal = SAMPLE_TEXTURE2D_LOD(_GBufferC, sampler_GBufferC, input.baseUV, 0) * 2 - 1;
    normal.xyz = normal.xyz * 2 - 1;
    float depth = SAMPLE_DEPTH_TEXTURE_LOD(_DepthBuffer, sampler_DepthBuffer, input.baseUV, 0);
    depth = LinearEyeDepth(depth, _ZBufferParams);
    float3 origin = GetCameraPositionWS();
    float4 positionWS = GetPositionWS(input.baseUV, depth, origin);
    if (depth >= 0.9 * _ProjectionParams.z)
    {
        return float4(0, 0, 0, 0);
    }

    //先采样正常的shadow
    float unit = 1;
    float currentTexel = 0;
    float4 shadowCoord = TransformWorldToShadowCoord(positionWS.xyz, normal.xyz, _LightDirection, unit, currentTexel);
    currentTexel = currentTexel / 2 / depth * abs(UNITY_MATRIX_P._m11) / 2;
    float shadowCurrent = MainLightShadow(shadowCoord, positionWS.xyz);
    float shadowDepth = MainLightShadowDepth(shadowCoord, unit);
    //return float4(shadowCurrent, 0, 0, 0);
    return float4(shadowCurrent, currentTexel, 0, 0);
}