TEXTURE2D(_AccumulateBuffer);
SAMPLER(sampler_AccumulateBuffer);

float4 frag(Varyings input) : SV_TARGET
{
    float4 color = SAMPLE_TEXTURE2D_LOD(_AccumulateBuffer, sampler_AccumulateBuffer, input.baseUV, 0);
    return color * color.a;
}