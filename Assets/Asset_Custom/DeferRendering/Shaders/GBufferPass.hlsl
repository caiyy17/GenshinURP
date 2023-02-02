#include "../ShaderLibrary/Lighting.hlsl"

#define MAX_STEP 32

void modifyUV(inout processedVaryings input)
{
    float3 viewDirTS = normalize(TransformWorldToTangent(input.viewDir, input.tangentToWorld));
    float3 cameraDirTS = normalize(TransformWorldToTangent(input.viewDir, input.tangentToWorld));
    float len = length(viewDirTS.xy);
    if (len < 0.0001 || _HeightScale <= 0)
    {
        return;
    }

    float deltaUV = length(ddx_fine(input.uv)) + length(ddy_fine(input.uv));
    float deltaPos = length(ddx_fine(input.positionWS)) + length(ddy_fine(input.positionWS));
    float UVratio = deltaUV / deltaPos;

    //caution: Hard coded value
    float parallaxHeight = _HeightScale * smoothstep(0.05, 0.1, (abs(viewDirTS.z)));
    float heightOffset = _HeightOffset;

    float tangent = abs(viewDirTS.z) / (len * UVratio);
    float currHeight = 0;
    float tracedHeight = 0;
    float2 currUV = input.uv;
    float2 UVDir = normalize(viewDirTS.xy);
    int i = 0;
    //确定一个粗略范围
    UNITY_LOOP
    for (i = 0; i <= MAX_STEP; i++)
    {
        tracedHeight = float(MAX_STEP - i) / float(MAX_STEP) * parallaxHeight;
        currUV = input.uv - (tracedHeight - heightOffset * parallaxHeight) / tangent * UVDir;
        currHeight = SAMPLE_TEXTURE2D_LOD(_HeightMap, sampler_HeightMap, currUV, 0).r * parallaxHeight;
        if (tracedHeight <= currHeight)
        {
            break;
        }
    }
    if (i > MAX_STEP)
    {
        //return;

    }
    //现在知道高度一定在(MAX_STEP - i)和(MAX_STEP - i + 1)之间
    //二分精细空间
    float High = float(MAX_STEP - i + 1) / float(MAX_STEP) * parallaxHeight;
    float Low = float(MAX_STEP - i) / float(MAX_STEP) * parallaxHeight;
    //UNITY_LOOP
    for (int j = 0; j < MAX_STEP; j++)
    {
        tracedHeight = (High + Low) / 2;
        currUV = input.uv - (tracedHeight - heightOffset * parallaxHeight) / tangent * UVDir;
        currHeight = SAMPLE_TEXTURE2D_LOD(_HeightMap, sampler_HeightMap, currUV, 0).r * parallaxHeight;
        if (tracedHeight <= currHeight)
        {
            Low = tracedHeight;
        }
        else
        {
            High = tracedHeight;
        }
    }
    input.uv = input.uv - (tracedHeight - heightOffset * parallaxHeight) / tangent * UVDir;
    input.positionWS = input.positionWS - (tracedHeight - heightOffset * parallaxHeight) * input.viewDir;
    return;
}

void modifyNormal(inout processedVaryings input)
{
    float3 normalTS = float3(0, 0, 1);
    if (_NormalScale > 0)
    {
        normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, input.uv), _NormalScale);
    }
    normalTS.y = -normalTS.y;
    input.normalWS = normalize(TransformTangentToWorld(normalTS, input.tangentToWorld));
    return;
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
    OUT.bitangentWS = input.normalInputs.bitangentWS;

    float2 TAAJitter = GetPoissonSample(_FrameNum) / _ScreenParams.xy / 2;
    OUT.positionCS += OUT.positionCS.w * float4(TAAJitter, 0, 0);

    float4 ClipCurrent = TransformWorldToHClip(TransformObjectToWorld(IN.positionOS.xyz));
    float3 WSLast = unity_MotionVectorsParams.x > 0 ? IN.positionOSLast : IN.positionOS;
    float4 ClipLast = mul(matrix_LastViewProj, (mul(GetPrevObjectToWorldMatrix(), float4(WSLast, 1))));

    OUT.custom1 = ClipCurrent;
    OUT.custom2 = ClipLast;

    return OUT;
}

void frag(Varyings IN,
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
    //0albedo, 1normal, 2normalGeo, 3SMBE, 4baked, 5motion
    GT0 = 0;
    GT1 = 0;
    GT2 = 0;
    GT3 = 0;
    GT4 = 0;
    GT5 = 0;
    GT6 = 0;
    GT7 = 0;
    processedVaryings input = processingVar(IN);
    GT2 = float4((input.normalWS + 1) / 2, IN.positionCS.z);

    #if defined(_C_HEIGHT)
        modifyUV(input);
        float4 modifiedClip = TransformWorldToHClip(input.positionWS);
        float depthDiff = modifiedClip.z / modifiedClip.w - IN.positionCS.z / IN.positionCS.w;
        GT2.a = modifiedClip.z / modifiedClip.w;
    #endif
    #if defined(_C_NORMAL)
        modifyNormal(input);
    #endif
    
    GT0 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor;
    #if defined(_CLIPPING)
        clip(GT0.a - _Cutoff);
    #endif
    GT0.a = 1;
    GT1 = float4((input.normalWS + 1) / 2, 1);
    #if defined(_C_SMBE)
        GT3 = SAMPLE_TEXTURE2D(_SMBE, sampler_SMBE, input.uv);
        if (!_Emissive)
        {
            GT3.a = 0;
        }
        else
        {
            if (_EmissiveOnAlbedo)
            {
                GT4.xyz = _EmissiveIntensity * GT0.xyz * _EmissiveColor.xyz * GT3.a;
            }
            else
            {
                GT4.xyz = _EmissiveIntensity * _EmissiveColor.xyz * GT3.a;
            }
        }
    #endif
    GT7 = float4((IN.custom1 / IN.custom1.w - IN.custom2 / IN.custom2.w).xy * 0.5, 0, 0);
}