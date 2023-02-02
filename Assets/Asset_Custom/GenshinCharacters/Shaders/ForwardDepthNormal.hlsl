float4x4 matrix_LastViewProj;

struct Attributes
{
    float4 positionOS : POSITION;
    float4 tangentOS : TANGENT;
    float2 texcoord : TEXCOORD0;
    float3 normal : NORMAL;
    float3 positionOSLast : TEXCOORD4;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD1;
    float3 normalWS : TEXCOORD2;
    float4 custom1 : TEXCOORD5;
    float4 custom2 : TEXCOORD6;
};

Varyings DepthNormalsVertex(Attributes input)
{
    Varyings output = (Varyings)0;

    output.uv = input.texcoord;
    output.positionCS = TransformObjectToHClip(input.positionOS.xyz);

    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normal, input.tangentOS);
    output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);

    float2 TAAJitter = GetPoissonSample(_FrameNum) / _ScreenParams.xy / 2;
    output.positionCS += output.positionCS.w * float4(TAAJitter, 0, 0);
    float4 ClipCurrent = TransformWorldToHClip(TransformObjectToWorld(input.positionOS.xyz));
    float3 WSLast = unity_MotionVectorsParams.x > 0 ? input.positionOSLast : input.positionOS;
    float4 ClipLast = mul(matrix_LastViewProj, (mul(GetPrevObjectToWorldMatrix(), float4(WSLast, 1))));

    output.custom1 = ClipCurrent;
    output.custom2 = ClipLast;

    return output;
}

void DepthNormalsFragment(Varyings input,
out float4 GT0 : SV_Target0,
out float4 GT1 : SV_Target1,
out float4 GT2 : SV_Target2,
out float4 GT3 : SV_Target3,
out float4 GT4 : SV_Target4,
out float4 GT5 : SV_Target5,
out float4 GT6 : SV_Target6,
out float4 GT7 : SV_Target7
)
{
    GT0 = 0;
    GT1 = 0;
    GT2 = 0;
    GT3 = 0;
    GT4 = 0;
    GT5 = 0;
    GT6 = 0;
    GT7 = 0;
    GT2 = float4(input.normalWS, input.positionCS.z);
    GT7 = float4((input.custom1 / input.custom1.w - input.custom2 / input.custom2.w).xy * 0.5, 0, 0);
}
