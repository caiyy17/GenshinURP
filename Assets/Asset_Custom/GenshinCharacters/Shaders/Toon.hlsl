#include "Functions.hlsl"

////////////////////////////////////////////////////////////////////////////////
//shadow，hightlight，rim
////////////////////////////////////////////////////////////////////////////////

float GetToonShadow(float3 lightDir, float3 normalWS, float3 positionWS, float3 tangentWS, float4 ilm)
{
    float3 viewDir = normalize(GetCameraPositionWS() - positionWS);
    float3 normal = normalWS;
    normal = normal * sign(dot(viewDir, normal));
    float NdotL = dot(normal, lightDir);
    float shadowOut = NdotL + 1;
    return shadowOut;
}

float GetGlossy(float3 normalWS, float3 positionWS, float3 tangentWS)
{
    float glossy = 0;

    float3 viewDir = normalize(GetCameraPositionWS() - positionWS);
    float3 normal = normalWS;
    normal = normal * sign(dot(viewDir, normal));

    float3 tangent = tangentWS;
    //注意这URP算的TtoW的矩阵用法是反的......很奇葩
    float3x3 TangentToWorld = CreateTangentToWorld(normal, tangent, 1);

    float3 normalVS = mul((float3x3)UNITY_MATRIX_V, normalWS);
    float glossyU = normalize(float3(normalVS.x, 0, normalVS.z)).x;
    float glossyV = normalize(float3(0, normalVS.y, normalVS.z)).y;
    float2 glossyUV = saturate(float2(glossyU, glossyV) * 0.5 + 0.5);
    glossy = SAMPLE_TEXTURE2D(_glossy, sampler_glossy, glossyUV).r;

    return glossy;
}

float GetHighlight(float3 lightDir, float3 normalWS, float3 positionWS, float3 tangentWS, float4 ilm)
{
    float intensity = 0;

    float3 viewDir = normalize(GetCameraPositionWS() - positionWS);
    float3 normal = normalWS;
    normal = normal * sign(dot(viewDir, normal));

    float NdotL = dot(normal, lightDir);
    float NdotV = dot(normal, viewDir);
    float3 reflectDir = 2 * NdotV * normal - viewDir;
    float RdotL = saturate(dot(reflectDir, lightDir));

    float power = _highlightPow * ilm.r + 1;
    intensity = pow(RdotL, power) * _highlightIntensity;
    return intensity;
}

float GetRimlight(float3 normalWS, float3 positionWS, float2 uv)
{
    float3 normalVS = normalize(mul(UNITY_MATRIX_V, float4(normalWS, 0)).xyz);
    float2 offset = _rimWidth / _ScreenParams.xy * normalVS.xy;

    float depth0 = SAMPLE_DEPTH_TEXTURE_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, uv, 0);
    float depth1 = SAMPLE_DEPTH_TEXTURE_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, uv + offset, 0);
    depth0 = LinearEyeDepth(depth0, _ZBufferParams);
    depth1 = LinearEyeDepth(depth1, _ZBufferParams);

    float diff = depth1 - depth0;
    if (diff > _rimThreshold)
    {
        return 1 + 0.5;
    }
    return 1;
}

////////////////////////////////////////////////////////////////////////////////
//frag
////////////////////////////////////////////////////////////////////////////////

float4 frag(Varyings IN) : SV_Target
{
    processedVaryings input = processingVar(IN);

    float3 color = 0;
    //光照信息
    float4 shadowCoords = TransformWorldToShadowCoord(input.positionWS);
    Light light = GetMainLight(shadowCoords);
    //Light light = GetMainLight();
    float4 ilm = SAMPLE_TEXTURE2D(_ilm, sampler_ilm, input.uv);
    //基础色
    float3 baseMap = _Color.xyz * SAMPLE_TEXTURE2D(_base, sampler_base, input.uv).xyz * light.color;
    float3 colorDark = _shadowColor.xyz * baseMap;
    //shadow
    float shadowOut = GetToonShadow(light.direction, input.normalWS, input.positionWS, input.tangentWS, ilm);
    //shadowOut = shadowOut * light.shadowAttenuation;
    //ramp
    float rampX = shadowOut;
    float rampY = GetRampY(ilm.a);
    float3 rampColor = GetRampColor(rampX, rampY);
    float3 colorDiffuse = rampColor * baseMap;
    //glossy matcap
    if (ilm.r > 0.9)
    {
        float glossy = GetGlossy(input.normalWS, input.positionWS, input.tangentWS);
        colorDiffuse = colorDiffuse * (glossy * 0.5 + 0.2);
    }
    //hightlight
    float highlightIntensity = GetHighlight(light.direction, input.normalWS, input.positionWS, input.tangentWS, ilm);
    float3 hightlight = highlightIntensity * baseMap;
    //rimlight
    float rim = GetRimlight(input.normalWS, input.positionWS, input.screenUV);

    //ilm混合
    float rate = saturate(ilm.g * 2);
    float3 d = rate * colorDiffuse;
    float3 dark = (1 - rate) * colorDark;
    float3 s = hightlight * ilm.b;
    color = (d + dark + s) * rim;

    //color = color * light.shadowAttenuation;
    //其他光源
    float3 indirect = GetIndirect(input.normalWS, input.positionWS);
    color = color + indirect * SAMPLE_TEXTURE2D(_base, sampler_base, input.uv).xyz;

    return float4(color, 1);
}