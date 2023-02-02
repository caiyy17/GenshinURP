#include "TestSample.hlsl"

TEXTURE2D(_TestBufferB);
SAMPLER(sampler_TestBufferB);

TEXTURE2D(_DepthBuffer);
SAMPLER(sampler_DepthBuffer);

float3 _LightDirection;

#define TESTCOUNT 32

float4 frag(Varyings input) : SV_TARGET
{
    float2 sampleUV = input.baseUV;
    float depth = SAMPLE_DEPTH_TEXTURE_LOD(_DepthBuffer, sampler_DepthBuffer, sampleUV, 0);
    depth = LinearEyeDepth(depth, _ZBufferParams);
    if (depth >= 0.9 * _ProjectionParams.z)
    {
        return float4(1, 0, 0, 0);
    }
    int k = frac(input.baseUV.x + input.baseUV.y * 123) * 4233 + _FrameNum;
    float2 laststep = SAMPLE_TEXTURE2D_LOD(_TestBufferB, sampler_TestBufferB, input.baseUV, 0).xy;
    int testcount = 1;
    float gather = laststep.x;
    for (int i = 0; i < TESTCOUNT; i++)
    {
        float2 offset = GetPoissonSample(i + k, k) * 5 / _ScreenParams.xy;
        float2 teststep = SAMPLE_TEXTURE2D_LOD(_TestBufferB, sampler_TestBufferB, input.baseUV + offset, 0).xy;
        float testdepth = SAMPLE_DEPTH_TEXTURE_LOD(_DepthBuffer, sampler_DepthBuffer, input.baseUV + offset, 0);
        testdepth = LinearEyeDepth(testdepth, _ZBufferParams);
        if (abs(testdepth - depth) < 0.2)
        {
            testcount += 1;
            gather += teststep.x;
        }
    }
    gather /= testcount;
    gather = smoothstep(0.4, 0.6, gather);
    return float4(gather, 0, 0, 0);
}