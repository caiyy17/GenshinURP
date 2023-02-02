#ifndef SSR_INCLUDED
#define SSR_INCLUDED

float3 GetUVZ(float3 positionWS)
{
    float4 positionCS = TransformWorldToHClip(positionWS);
	float depth = positionCS.w;
    if(positionCS.w > _ProjectionParams.z){
        return float3(0, 0, -1);
    }
    float4 screenUV = ComputeScreenPos(positionCS);
    screenUV = screenUV / screenUV.w;
    return float3(screenUV.xy, depth);
}

float ScreenFade(float3 sampleUVZ){
    if(sampleUVZ.x < 0 || sampleUVZ.x > 1 || sampleUVZ.y < 0 || sampleUVZ.y > 1){
        return -1;
    }
    return 1;
    float xFade = min(5 * sampleUVZ.x, 5 * (1 - sampleUVZ.x));
    xFade = min(xFade, 1);
    float yFade = min(5 * sampleUVZ.y, 5 * (1 - sampleUVZ.y));
    yFade = min(yFade, 1);
    return min(xFade, yFade);
}

#define PixelGap 1

void GetSSRColor(float3 viewDir, float3 positionWS, float3 normalWS, float4 screenUV, out float3 ssrColor){

    ssrColor = 0;
    float VdotN = dot(viewDir, normalWS);
    if(VdotN < 0){
        return;
    }

    float3 reflectDir = 2 * VdotN * normalWS - viewDir;
    float3 reflectDirEndWS = positionWS + reflectDir;
    float3 startPosUVZ = GetUVZ(positionWS);
    float3 reflectPosUVZ = GetUVZ(reflectDirEndWS);
    float3 reflectDirUVZ = reflectPosUVZ - startPosUVZ;
    if(reflectDirUVZ.z < 0){
        return;
    }
    float UVZScale = PixelGap / length(reflectDirUVZ.xy * _ScreenParams.xy);
    UVZScale = 0.1;
    float previousDepth = startPosUVZ.z;

    for (int i = 1; i <= 32; i++){

        float3 sampleUVZ = GetUVZ(positionWS + i * i * reflectDir * UVZScale);
        if(sampleUVZ.z < 0){
            //超过远平面
            ssrColor = float3(0,1,0);
            return;
        }
        float sceneDepth = SAMPLE_TEXTURE2D(_CameraDepthTexture, sampler_CameraDepthTexture, sampleUVZ.xy).r;
        sceneDepth = LinearEyeDepth(sceneDepth, _ZBufferParams);
		float sampleDepth = sampleUVZ.z;
		float differenceDepth = sampleDepth - sceneDepth;

        float screenFade = ScreenFade(sampleUVZ);
        if(screenFade < 0){
            //追出边界
            ssrColor = float3(0.5,0,0);
            return;
        }

        if(differenceDepth > 0 && differenceDepth < 1){
            ssrColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, sampleUVZ.xy).rgb / 2 * screenFade;
            ssrColor = float(i)/float(64);
            return;
        }
    }
    //将reay match次数用完也没追踪到
    ssrColor = float3(1,0,0);

    //这边需要调用unity自己的api来采样屏幕
    //ssrColor = SHADERGRAPH_SAMPLE_SCENE_COLOR(screenUV.xy).rgb;
    //ssrColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, screenUV.xy).rgb;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
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

float4 frag(Varyings IN):SV_Target
{
    processedVaryings input = processingVar(IN);
    float3 color = 0;
    float3 viewDir = normalize(GetCameraPositionWS() - input.positionWS);
    float4 screenUV = ComputeScreenPos(TransformWorldToHClip(input.positionWS));
    screenUV = screenUV / screenUV.w;
    GetSSRColor(viewDir, input.positionWS, input.normalWS, screenUV, color);

    return float4(color, 1);
}

#endif