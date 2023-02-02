#include "Functions.hlsl"

////////////////////////////////////////////////////////////////////////////////
//frag
////////////////////////////////////////////////////////////////////////////////

float4 frag(Varyings IN):SV_Target
{
    processedVaryings input = processingVar(IN);
    float3 color = 0;
    Light light = GetMainLight();
    //基础色
    float3 baseMap = _Color.xyz * SAMPLE_TEXTURE2D(_base, sampler_base, input.uv).xyz * light.color;
    //clip(SAMPLE_TEXTURE2D(_base, sampler_base, IN.uv).a - 0.1);
    color = baseMap;

    //其他光源
    float3 indirect = GetIndirect(input.normalWS, input.positionWS);
    color = color + indirect * SAMPLE_TEXTURE2D(_base, sampler_base, input.uv).xyz;

    return float4(color, 1);
}