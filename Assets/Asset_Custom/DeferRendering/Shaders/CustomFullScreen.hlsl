#ifndef CUSTOM_FULLSCREEN_INCLUDED
#define CUSTOM_FULLSCREEN_INCLUDED

#include "../ShaderLibrary/Core.hlsl"

uint _FrameNum;

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 baseUV : VAR_BASE_UV;
    float4 color : TEXCOORD0;
};

//后处理统一的Vertex函数，覆盖全屏
Varyings DefaultPassVertex(uint vertexID : SV_VertexID)
{
    Varyings output = (Varyings)0;
    output.positionCS = float4(
        vertexID <= 1 ? - 1.0 : 3.0,
        vertexID == 1 ? 3.0 : - 1.0,
        0.0, 1.0
    );
    output.baseUV = float2(
        vertexID <= 1 ? 0.0 : 2.0,
        vertexID == 1 ? 2.0 : 0.0
    );
    if (_ProjectionParams.x < 0.0)
    {
        output.baseUV.y = 1 - output.baseUV.y;
    }
    return output;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

float4 GetPositionWS(float2 UV, float depth, float3 origin)
{
    float4 viewClip = float4(UV * 2 - 1, 1, 1);
    if (_ProjectionParams.x < 0)
    {
        viewClip.y = -viewClip.y;
    }
    #if UNITY_REVERSED_Z
        //设置在远平面
        viewClip.z = 0;
    #else
        viewClip.z = 1;
    #endif
    float4x4 InvVP = UNITY_MATRIX_I_VP;
    float4 viewDirW = mul(InvVP, viewClip);
    float3 viewDir = (viewDirW.xyz / viewDirW.w - origin) * _ProjectionParams.w;
    float4 positionWS = float4(origin + viewDir * depth, 1);
    return positionWS;
}

#endif