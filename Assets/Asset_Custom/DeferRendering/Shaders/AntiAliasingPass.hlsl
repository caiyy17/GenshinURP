TEXTURE2D(_ColorBuffer);
SAMPLER(sampler_ColorBuffer);
TEXTURE2D(_MotionBuffer);
SAMPLER(sampler_MotionBuffer);
TEXTURE2D(_ColorHistory);
SAMPLER(sampler_ColorHistory);

static const int2 SampleOffsets[9] = {
    int2(-1, -1), int2(0, -1), int2(1, -1),
    int2(-1, 0), int2(0, 0), int2(1, 0),
    int2(-1, 1), int2(0, 1), int2(1, 1)
};

float4 ClipAABB(float4 prevData, float4 aabbMin, float4 aabbMax)
{
    float4 p_clip = 0.5 * (aabbMax + aabbMin);
    float4 e_clip = 0.5 * (aabbMax - aabbMin);

    float4 v_clip = prevData - p_clip;
    float4 v_unit = v_clip / e_clip;
    float4 a_unit = abs(v_unit);
    float ma_unit = max(a_unit.x, max(a_unit.y, a_unit.z));

    [branch]
    if (ma_unit > 1)
    {
        return p_clip + v_clip / ma_unit;
    }
    else
    {
        return prevData;
    }
}

float4 frag(Varyings input) : SV_TARGET
{
    float4 color;
    //采样周围的9个像素
    float totalWeight = 0;
    float sampleWeights[9];
    float4 sampleColors[9];
    for (uint i = 0; i < 9; ++i)
    {
        float2 offset = SampleOffsets[i] * (_ScreenParams.zw - 1);
        sampleColors[i] = SAMPLE_TEXTURE2D_LOD(_ColorBuffer, sampler_ColorBuffer, input.baseUV + offset, 0);
    }

    float4 m1 = 0;
    float4 m2 = 0;
    float4 minColor = sampleColors[4];
    float4 maxColor = sampleColors[4];

    //这边计算一下方差
    [unroll]
    for (uint x = 0; x < 9; ++x)
    {
        minColor = min(minColor, sampleColors[x]);
        maxColor = max(maxColor, sampleColors[x]);
        m1 += sampleColors[x];
        m2 += sampleColors[x] * sampleColors[x];
    }
    float4 mean = m1 / 9;
    float4 stddev = sqrt(max(0.0, (m2 / 9) - mean * mean));
    minColor = min(minColor, mean - 1 * stddev);
    maxColor = max(maxColor, mean + 1 * stddev);
    float4 currColor = sampleColors[4];
    minColor = min(minColor, currColor);
    maxColor = max(maxColor, currColor);

    float2 motion = SAMPLE_TEXTURE2D_LOD(_MotionBuffer, sampler_MotionBuffer, input.baseUV, 0).xy;
    if (_ProjectionParams.x < 0)
    {
        motion.y = -motion.y;
    }

    float4 prevColor = SAMPLE_TEXTURE2D_LOD(_ColorHistory, sampler_ColorHistory, input.baseUV - motion, 0);
    prevColor = ClipAABB(prevColor, minColor, maxColor);
    prevColor.a = max(min(prevColor.a, maxColor.a), minColor.a);
    
    float currFac = 0.05 * currColor.a;
    float prevFac = 0.95 * prevColor.a;
    float sumFac = saturate(currFac + prevFac);
    if (sumFac <= 0.001)
    {
        return 0;
    }
    color.xyz = (currColor.xyz * currFac + prevColor.xyz * prevFac) / sumFac;
    color.a = sumFac;
    //return currColor;
    return color;
}

