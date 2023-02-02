#include "../ShaderLibrary/Lighting.hlsl"
#include "../ShaderLibrary/Shadows.hlsl"
TEXTURE2D(_GBufferA);
SAMPLER(sampler_GBufferA);
TEXTURE2D(_GBufferB);
SAMPLER(sampler_GBufferB);
TEXTURE2D(_GBufferC);
SAMPLER(sampler_GBufferC);
TEXTURE2D(_GBufferD);
SAMPLER(sampler_GBufferD);
TEXTURE2D(_GBufferE);
SAMPLER(sampler_GBufferE);
TEXTURE2D(_GBufferF);
SAMPLER(sampler_GBufferF);
TEXTURE2D(_GBufferG);
SAMPLER(sampler_GBufferG);
TEXTURE2D(_DepthBuffer);
SAMPLER(sampler_DepthBuffer);

TEXTURE2D(_DepthPyramid);
SAMPLER(sampler_DepthPyramid);
TEXTURE2D(_PCSSShadowBuffer);
SAMPLER(sampler_PCSSShadowBuffer);

float4 frag(Varyings input) : SV_TARGET
{
    //0albedo, 1normal, 2normalGeo, 3SMBE, 4baked, 56/, 7motion
    float depth = SAMPLE_DEPTH_TEXTURE_LOD(_DepthBuffer, sampler_DepthBuffer, input.baseUV, 0);
    depth = LinearEyeDepth(depth, _ZBufferParams);
    float4 albedo = SAMPLE_TEXTURE2D_LOD(_GBufferA, sampler_GBufferA, input.baseUV, 0);
    float4 normal = SAMPLE_TEXTURE2D_LOD(_GBufferB, sampler_GBufferB, input.baseUV, 0) * 2 - 1;
    float4 normalGeo = SAMPLE_TEXTURE2D_LOD(_GBufferC, sampler_GBufferC, input.baseUV, 0) * 2 - 1;
    
    float3 origin = GetCameraPositionWS();
    float4 positionWS = GetPositionWS(input.baseUV, depth, origin);

    float4 mask = SAMPLE_TEXTURE2D_LOD(_GBufferD, sampler_GBufferD, input.baseUV, 0);
    float4 baked = SAMPLE_TEXTURE2D_LOD(_GBufferE, sampler_GBufferE, input.baseUV, 0);
    float shadow = SAMPLE_TEXTURE2D_LOD(_PCSSShadowBuffer, sampler_PCSSShadowBuffer, input.baseUV, 0).r;
    //Light mainLight = GetMainLight(TransformWorldToShadowCoord(positionWS.xyz));
    Light mainLight = GetMainLight();
    float3 viewDir = normalize(positionWS.xyz - origin);
    float3 halfDir = normalize((mainLight.direction - viewDir));

    //这边BRDF的计算是为了现有一个效果，具体到时候再调整了，先让所有mask都起作用可以看到效果
    BSDFContext LightData = (BSDFContext)0;
    Init(LightData, normal.xyz, -viewDir, mainLight.direction, halfDir);

    float attenuation = min(smoothstep(0, 0.05, dot(normalGeo.xyz, mainLight.direction)), smoothstep(0, 0.05, LightData.NoL));
    attenuation = min(shadow, attenuation);
    float3 diffuse = albedo.rgb * (attenuation * 0.7 + 0.3);
    float3 specular = albedo.rgb * (1 - mask.b) + mask.b * 0.7;
    specular = specular * pow(LightData.NoH, 10) * mask.r * 4 * attenuation;

    float3 temp = diffuse + specular;
    temp *= mainLight.color;
    temp += baked.xyz;

    //获取froxel信息
    float3 additional = 0;
    if (_LightInfo.x > 0)
    {
        additional = GetOtherLight(normal.xyz, positionWS.xyz, input.baseUV, depth);
        additional *= albedo.xyz;
    }
    temp += additional;
    //temp *= 0.1;
    //temp += float3(shadow, mainLight.shadowAttenuation, 0);
    return float4(temp, albedo.a);
}

