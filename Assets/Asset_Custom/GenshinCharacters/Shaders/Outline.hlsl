struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float2 uv : TEXCOORD0;
};
struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
};

Varyings vert(Attributes IN)
{
    Varyings OUT;
    VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS.xyz);
    float3 positionWS = positionInputs.positionWS;
    positionWS += TransformObjectToWorldNormal(IN.normalOS) * 0.001 * min(_outlineThickness, _outlineThickness * - positionInputs.positionVS.z);
    float ViewDepth = abs(mul(UNITY_MATRIX_V, float4(positionWS, 1)).z);
    OUT.positionCS = TransformWorldToHClip(positionWS);
    OUT.positionCS.z -= OUT.positionCS.w * 0.00001 / ViewDepth;

    float2 TAAJitter = GetPoissonSample(_FrameNum) / _ScreenParams.xy / 2;
    OUT.positionCS += OUT.positionCS.w * float4(TAAJitter, 0, 0);

    // float3 originWS = TransformObjectToWorld(float3(0,0,0));
    // float originDepth = mul(UNITY_MATRIX_V, float4(originWS,1)).z;
    // float3 positionVS = mul(UNITY_MATRIX_V, float4(positionWS,1)).xyz;
    // float4 positionCS = OUT.positionCS;
    // positionVS.z = originDepth;
    
    // OUT.positionCS = mul(UNITY_MATRIX_P, float4(positionVS,1));
    // OUT.positionCS.z = positionCS.z / positionCS.w * OUT.positionCS.w;

    OUT.uv = IN.uv;
    return OUT;
}

float4 frag(Varyings IN) : SV_Target
{
    float4 baseMap = SAMPLE_TEXTURE2D(_base, sampler_base, IN.uv);
    return float4(baseMap.xyz * _outlineColor.xyz, 1);
}