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

    return OUT;
}

void frag(Varyings IN,
out float4 GT0 : SV_Target
)
{
    GT0 = 0;
    GT0 = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv.xy) * _BaseColor;
    #if defined(_CLIPPING)
        clip(GT0.a - _Cutoff);
    #endif
}