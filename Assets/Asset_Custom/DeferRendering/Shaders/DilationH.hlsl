TEXTURE2D(_CoarseShadowBuffer);
SAMPLER(sampler_CoarseShadowBuffer);

float4 _TexelSize;

#define MAX_OFFSET 13

float frag(Varyings input) : SV_TARGET
{
    
    float dilated = SAMPLE_TEXTURE2D_LOD(_CoarseShadowBuffer, sampler_CoarseShadowBuffer, input.baseUV, 0).r;
    float scaleH = _TexelSize.z * _ScreenParams.y / _ScreenParams.x;
    for (int i = - (MAX_OFFSET / 2); i <= (MAX_OFFSET / 2); i++)
    {
        float rangeTest = SAMPLE_TEXTURE2D_LOD(_CoarseShadowBuffer, sampler_CoarseShadowBuffer,
        input.baseUV + float2(i * _TexelSize.x, 0), 0).r;
        int threshold = max(0, abs(i) - 1);
        float rangeSize = rangeTest.r * scaleH;
        if (step(0.05, rangeSize - threshold))
        {
            dilated = max(dilated, rangeTest.r);
        }
    }
    return dilated;
}