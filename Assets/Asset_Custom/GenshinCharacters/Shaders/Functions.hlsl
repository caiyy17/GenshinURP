////////////////////////////////////////////////////////////////////////////////
//标准顶点函数
////////////////////////////////////////////////////////////////////////////////
struct Attributes
{
    float3 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float4 tangentOS : TANGENT;
    float4 uv : TEXCOORD0;
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

Varyings vert(Attributes IN)
{
    Varyings OUT = (Varyings)0;
    processedAttributes input = processingAttr(IN);

    OUT.uv.xy = input.uv;
    OUT.uv.zw = input.uv2;
    OUT.positionCS = input.positionInputs.positionCS;
    OUT.positionWS = input.positionInputs.positionWS;
    OUT.normalWS = input.normalInputs.normalWS;
    OUT.tangentWS = input.normalInputs.tangentWS;
    
    // float3 originWS = TransformObjectToWorld(float3(0,0,0));
    // float originDepth = mul(UNITY_MATRIX_V, float4(originWS,1)).z;
    // float3 positionVS = mul(UNITY_MATRIX_V, float4(OUT.positionWS,1)).xyz;
    // float4 positionCS = OUT.positionCS;
    // positionVS.z = originDepth;

    // OUT.positionCS = mul(UNITY_MATRIX_P, float4(positionVS,1));
    // OUT.positionCS.z = positionCS.z / positionCS.w * OUT.positionCS.w;

    float2 TAAJitter = GetPoissonSample(_FrameNum) / _ScreenParams.xy / 2;
    OUT.positionCS += OUT.positionCS.w * float4(TAAJitter, 0, 0);

    return OUT;
}

struct processedVaryings
{
    float2 pixPos;
    float2 screenUV;
    float2 uv;
    float2 uv2;
    float3 positionWS;
    float3 normalWS;
    float3 tangentWS;
};

processedVaryings processingVar(Varyings IN)
{
    processedVaryings OUT = (processedVaryings)0;
    OUT.pixPos = IN.positionCS.xy;
    OUT.screenUV = OUT.pixPos / _ScreenParams.xy;
    OUT.uv = IN.uv.xy;
    OUT.uv2 = IN.uv.zw;
    OUT.positionWS = IN.positionWS;
    OUT.normalWS = normalize(IN.normalWS);
    OUT.tangentWS = normalize(IN.tangentWS);
    return OUT;
}

////////////////////////////////////////////////////////////////////////////////
//Ramp采样，其他光源
////////////////////////////////////////////////////////////////////////////////

float GetRampY(float rampValue)
{
    
    float offset = 0.5 / _rampInfo0[1] / 2;
    float rampChannel = 0;
    float rampSample = rampValue + offset;
    if (rampSample > _rampInfo12[0])
    {
        rampChannel = _rampInfo12[1];
    }
    if (rampSample > _rampInfo12[2])
    {
        rampChannel = _rampInfo12[3];
    }
    if (rampSample > _rampInfo34[0])
    {
        rampChannel = _rampInfo34[1];
    }
    if (rampSample > _rampInfo34[2])
    {
        rampChannel = _rampInfo34[3];
    }
    if (rampSample > _rampInfo0[2])
    {
        rampChannel = _rampInfo0[3];
    }

    float rampY = (rampChannel + 0.5) * 0.5 / _rampInfo0[1] + _rampInfo0[0] * 0.5;
    return rampY;
}

float3 GetRampColor(float rampX, float rampY)
{
    if (rampX >= 1)
    {
        return 1;
    }
    else
    {
        float2 rampUV = float2(rampX, rampY);
        float3 rampColor = SAMPLE_TEXTURE2D(_ramp, sampler_ramp, rampUV).xyz;
        return rampColor;
    }
}

float3 GetIndirect(float3 normal, float3 position)
{
    float3 indirect = 0;
    //光照探针
    float3 probe = max(0.0, SampleSH(normal));
    indirect = indirect + probe;
    //点光源
    int otherLightCount = GetAdditionalLightsCount();
    for (int lightIndex = 0; lightIndex < otherLightCount; lightIndex++)
    {
        Light light = GetAdditionalLight(lightIndex, position);
        indirect += light.distanceAttenuation * light.color / 3;
    }
    return indirect;
}
