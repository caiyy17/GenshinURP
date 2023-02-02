#include "PCSSSample.hlsl"

TEXTURE2D(_GBufferC);
SAMPLER(sampler_GBufferC);
TEXTURE2D(_DepthBuffer);
SAMPLER(sampler_DepthBuffer);
TEXTURE2D(_CoarseShadowBuffer);
SAMPLER(sampler_CoarseShadowBuffer);

float3 _LightDirection;
float4 _TexelSize;

#define MAX_OFFSET 13
#define GATHER_SIZE 4

float2 frag(Varyings input) : SV_TARGET
{
    float depth = SAMPLE_DEPTH_TEXTURE_LOD(_DepthBuffer, sampler_DepthBuffer, input.baseUV, 0);
    depth = LinearEyeDepth(depth, _ZBufferParams);
    float4 normal = SAMPLE_TEXTURE2D_LOD(_GBufferC, sampler_GBufferC, input.baseUV, 0) * 2 - 1;
    float3 origin = GetCameraPositionWS();
    float4 positionWS = GetPositionWS(input.baseUV, depth, origin);
    float shadow = SAMPLE_TEXTURE2D_LOD(_CoarseShadowBuffer, sampler_CoarseShadowBuffer, input.baseUV, 0).r;
    //如果r通道为1，说明需要PCSS
    //shadow.r = 1;
    if (shadow.r == -1 || dot(normal, _LightDirection) < 0)
    {
        return float2(0, 0);
    }
    else if (shadow.r == -2)
    {
        return float2(1, 1);
    }
    else if (shadow.r == 1)
    {
        //先初始化一下画面基础信息，因为我们软阴影最多就只有扩张的那么大
        float maxSoftScale = min(_TexelSize.y, _TexelSize.x * _ScreenParams.x / _ScreenParams.y);
        float maxSoftShadow = float(MAX_OFFSET * maxSoftScale) * depth / abs(UNITY_MATRIX_P._m11) * 2;
        float unit = 0;
        float4 shadowCoord = TransformWorldToShadowCoord(positionWS.xyz, normal.xyz, _LightDirection, unit);
        float Zoffset = 1 / tan(asin(saturate(abs(dot(normal.xyz, _LightDirection)))));
        return float2(saturate(MainLightPCSSShadow(shadowCoord, positionWS.xyz, unit, shadow.r, Zoffset, maxSoftShadow, input.baseUV)), 0.5);
    }
    //此区块有混合阴影，但不需要PCSS，按单次PCF处理
    float2 shadowCurrent = GetShadow(depth, positionWS.xyz, normal.xyz, _LightDirection);
    return float2(shadowCurrent.r, 0.75);
}