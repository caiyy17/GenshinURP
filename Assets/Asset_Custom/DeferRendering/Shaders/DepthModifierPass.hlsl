TEXTURE2D(_GBufferC);
SAMPLER(sampler_GBufferC);

float4 frag(Varyings input, out float depth : SV_DEPTH) : SV_TARGET
{
    depth = SAMPLE_TEXTURE2D_LOD(_GBufferC, sampler_GBufferC, input.baseUV, 0).a;
    return 0;
}