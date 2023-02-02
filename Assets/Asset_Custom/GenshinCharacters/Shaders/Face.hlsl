#include "Functions.hlsl"

////////////////////////////////////////////////////////////////////////////////
//SDFshadow
////////////////////////////////////////////////////////////////////////////////

float GetSDFShadow(float3 lightDir, float2 UV){
    float3 lightDirOS = normalize(TransformWorldToObjectDir(lightDir));
    float3 flatDir = normalize(float3(lightDirOS.x, 0, lightDirOS.z));

    float RdotL = flatDir.x;
    float FdotL = flatDir.z;

    float shadowLevel = (1 - FdotL * _shadowGate) * 0.5;
    float2 shadowUV = UV;
    if(RdotL > 0){
        shadowUV.x = 1 - shadowUV.x;
    }
    float shadowSample = SAMPLE_TEXTURE2D(_shadow, sampler_shadow, shadowUV).x;
    float shadowOut = smoothstep(-_shadowGradiant, _shadowGradiant, shadowSample - shadowLevel);
    return shadowOut;
}

////////////////////////////////////////////////////////////////////////////////
//frag
////////////////////////////////////////////////////////////////////////////////

float4 frag(Varyings IN):SV_Target
{
    processedVaryings input = processingVar(IN);
    float3 color = 0;
    //光照信息
    //float4 shadowCoords = TransformWorldToShadowCoord(TransformObjectToWorld(float3(0,0,0)));
    //Light light = GetMainLight(shadowCoords);
    Light light = GetMainLight();
    //基础色
    float3 baseMap = _Color.xyz * SAMPLE_TEXTURE2D(_base, sampler_base, input.uv).xyz * light.color;
    color = baseMap;
    //shadow的强度
    float shadowOut = GetSDFShadow(light.direction, input.uv);
    //shadowOut = shadowOut * light.shadowAttenuation;
    //ramp的颜色
    float rampX = shadowOut;
    float rampY = GetRampY(1.0);
    float3 rampColor = GetRampColor(rampX, rampY);
    color = color * rampColor;

    //其他光源
    float3 indirect = GetIndirect(input.normalWS, input.positionWS);
    color = color + indirect * SAMPLE_TEXTURE2D(_base, sampler_base, input.uv).xyz;

    return float4(color, 1);
}