#ifndef SSR_INCLUDED
#define SSR_INCLUDED

// TEXTURE2D(_CameraOpaqueTexture);
// SAMPLER(sampler_CameraOpaqueTexture);
// TEXTURE2D_FLOAT(_CameraDepthTexture);
// SAMPLER(sampler_CameraDepthTexture);

float3 GetUVZ(float3 positionWS)
{
    float4 positionCS = TransformWorldToHClip(positionWS);
	float depth = positionCS.w;
    if(positionCS.w > _ProjectionParams.z){
        return float3(0, 0, -1);
    }
    float4 screenUV = ComputeScreenPos(positionCS, _ProjectionParams.x);
    screenUV = screenUV / screenUV.w;
    return float3(screenUV.xy, depth);
}

float ScreenFade(float3 sampleUVZ){
    if(sampleUVZ.x < 0 || sampleUVZ.x > 1 || sampleUVZ.y < 0 || sampleUVZ.y > 1){
        return -1;
    }
    //return 1;
    float xFade = min(5 * sampleUVZ.x, 5 * (1 - sampleUVZ.x));
    xFade = min(xFade, 1);
    float yFade = min(5 * sampleUVZ.y, 5 * (1 - sampleUVZ.y));
    yFade = min(yFade, 1);
    return min(xFade, yFade);
}

#define PixelGap 1
#define SampleCount 256

void GetSSRColor_float(float3 viewDir, float3 positionWS, float3 normalWS, float4 screenUV, out float3 ssrColor){

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
    float UVZScale = PixelGap / sqrt(length(reflectDirUVZ.xy * _ScreenParams.xy));
    UVZScale = PixelGap;
    float previousDepth = startPosUVZ.z;

    UNITY_LOOP
    for (int i = 1; i <= SampleCount; i++){

        float3 sampleUVZ = GetUVZ(positionWS + i * i / SampleCount * reflectDir * UVZScale);
        if(sampleUVZ.z < 0){
            //超过远平面
            ssrColor = float3(0,1,0);
            return;
        }
        float sceneDepth = SHADERGRAPH_SAMPLE_SCENE_DEPTH(sampleUVZ.xy).r;
        sceneDepth = LinearEyeDepth(sceneDepth, _ZBufferParams);
		float sampleDepth = sampleUVZ.z;
		float differenceDepth = sampleDepth - sceneDepth;

        float screenFade = ScreenFade(sampleUVZ);
        if(screenFade < 0){
            //追出边界
            ssrColor = float3(0,0,0);
            return;
        }

        if(differenceDepth > 0 && differenceDepth < sampleUVZ.z * 0.02){
            ssrColor = SHADERGRAPH_SAMPLE_SCENE_COLOR(sampleUVZ.xy).rgb * screenFade;
            //ssrColor = float(i)/float(64);
            return;
        }
    }
    //将reay match次数用完也没追踪到
    ssrColor = float3(0,0,0);

    //这边需要调用unity自己的api来采样屏幕
    //ssrColor = SHADERGRAPH_SAMPLE_SCENE_COLOR(screenUV.xy).rgb;
    //ssrColor = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, screenUV.xy).rgb;
}

#endif