TEXTURE2D(_DilationBuffer);
SAMPLER(sampler_DilationBuffer);

float4 _TexelSize;

#define MAX_OFFSET 13

float frag(Varyings input) : SV_TARGET
{
    float dilated = SAMPLE_TEXTURE2D_LOD(_DilationBuffer, sampler_DilationBuffer, input.baseUV, 0).r;
    float scaleV = _TexelSize.w;
    for (int i = - (MAX_OFFSET / 2); i <= (MAX_OFFSET / 2); i++)
    {
        float rangeTest = SAMPLE_TEXTURE2D_LOD(_DilationBuffer, sampler_DilationBuffer,
        input.baseUV + float2(0, i * _TexelSize.y), 0).r;
        int threshold = max(0, abs(i) - 1);
        float rangeSize = rangeTest.r * scaleV;
        if (step(0.05, rangeSize - threshold))
        {
            dilated = max(dilated, 1);
        }
    }
    return dilated;
}