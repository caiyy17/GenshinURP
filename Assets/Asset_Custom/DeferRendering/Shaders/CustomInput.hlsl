#ifndef CUSTOM_INPUT_INCLUDED
#define CUSTOM_INPUT_INCLUDED

#include "../ShaderLibrary/Core.hlsl"

UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
UNITY_DEFINE_INSTANCED_PROP(float4, _BaseColor)
UNITY_DEFINE_INSTANCED_PROP(float, _Cutoff)
UNITY_DEFINE_INSTANCED_PROP(float, _NormalScale)
UNITY_DEFINE_INSTANCED_PROP(float, _FlipTangent)
UNITY_DEFINE_INSTANCED_PROP(float, _HeightScale)
UNITY_DEFINE_INSTANCED_PROP(float, _Emissive)
UNITY_DEFINE_INSTANCED_PROP(float, _EmissiveOnAlbedo)
UNITY_DEFINE_INSTANCED_PROP(float4, _EmissiveColor)
UNITY_DEFINE_INSTANCED_PROP(float, _EmissiveIntensity)
UNITY_DEFINE_INSTANCED_PROP(float, _HeightOffset)
UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);
TEXTURE2D(_NormalMap);
SAMPLER(sampler_NormalMap);
TEXTURE2D(_SMBE);
SAMPLER(sampler_SMBE);
TEXTURE2D(_HeightMap);
SAMPLER(sampler_HeightMap);

uint _FrameNum;
float4x4 matrix_LastViewProj;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float4 uv : TEXCOORD0;
    UNITY_VERTEX_INPUT_INSTANCE_ID

    float2 staticLightmapUV : TEXCOORD1;
    float2 dynamicLightmapUV : TEXCOORD2;
    //蒙皮骨骼会在这边存上一帧的positionOS
    float3 positionOSLast : TEXCOORD4;
};
struct processedAttributes
{
    float2 uv;
    float2 uv2;
    VertexPositionInputs positionInputs;
    VertexNormalInputs normalInputs;
};
struct Varyings
{
    float4 positionCS : SV_POSITION;
    float4 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    float3 tangentWS : TEXCOORD3;
    float3 bitangentWS : TEXCOORD4;
    UNITY_VERTEX_INPUT_INSTANCE_ID

    float4 custom1 : TEXCOORD5;
    float4 custom2 : TEXCOORD6;
    float4 custom3 : TEXCOORD7;
};
struct processedVaryings
{
    float2 pixPos;
    float2 screenUV;
    float2 uv;
    float2 uv2;
    float3 positionWS;
    float3 normalWS;
    float3 tangentWS;
    float3 bitangentWS;
    float3x3 tangentToWorld;
    float3 viewDir;
    float4 viewDistance;
};
processedAttributes processingAttr(Attributes IN)
{
    processedAttributes OUT = (processedAttributes)0;
    OUT.positionInputs = GetVertexPositionInputs(IN.positionOS);
    OUT.normalInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
    OUT.uv = IN.uv.xy;
    OUT.uv2 = IN.uv.zw;
    return OUT;
}
processedVaryings processingVar(Varyings IN)
{
    processedVaryings OUT = (processedVaryings)0;
    OUT.pixPos = IN.positionCS.xy;
    OUT.screenUV = OUT.pixPos / _ScreenParams.xy;
    OUT.uv = IN.uv.xy;
    OUT.uv2 = IN.uv.zw;
    OUT.positionWS = IN.positionWS;

    float3 view = OUT.positionWS - GetCameraPositionWS();
    OUT.viewDir = normalize(view);
    OUT.viewDistance = length(view);

    OUT.normalWS = normalize(IN.normalWS);
    OUT.tangentWS = normalize(IN.tangentWS);
    OUT.bitangentWS = normalize(IN.bitangentWS);
    if (dot(OUT.viewDir, OUT.normalWS) > 0)
    {
        OUT.normalWS = -OUT.normalWS;
    }
    OUT.tangentToWorld = float3x3(OUT.tangentWS, OUT.bitangentWS, OUT.normalWS);

    return OUT;
}

#endif