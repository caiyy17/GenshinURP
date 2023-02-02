#ifndef CUSTOM_ATMOSPHERE_COMPUTE_INCLUDED
#define CUSTOM_ATMOSPHERE_COMPUTE_INCLUDED

//CS中好像不能用CBUFFER？
//反正先这么用着了，很多shader中写的东西这边不能用
//主要是CBUFFER和sampler，所以就重新copy一遍了

// CBUFFER_START(_Atmosphere)
float4 _LutInfo;
float4 _VolumeInfo;
float4 _AtmosphereInfo[9];
float4 _StarInfo;
float4 _JdInfo;
float4 _SolarInfo[13];
// CBUFFER_END

// Create a RenderTexture with enableRandomWrite flag and set it
// with cs.SetTexture
RWTexture2D<float4> _MultiScat;
Texture2D<float4> _TransmittanceLut;
SamplerState sampler_TransmittanceLut;

#define gResolution float2(_VolumeInfo.x, _VolumeInfo.x)
#define ILLUMINANCE_IS_ONE 1

#define customSample(tex, sampler, uv) tex.SampleLevel(sampler, uv, 0)
#include "AtmosphereInput.hlsl"

////////////////////////////////////////////////////////////////////////////////
//MultiScatt
////////////////////////////////////////////////////////////////////////////////

groupshared float3 MultiScatAs1SharedMem[64];
groupshared float3 LSharedMem[64];

//这边主要是积分多重散射，uv是高度和太阳角度，所以这也是一张不变大气参数不用更新的表
//记录了在(H,theta)的情况下，这一点受到的所有方向的一次散射的总和
//注意，这个一次散射认为phaseFunction各向同性，
//但是UE没做，说明区别不大，因为后面也都是当作各向同性处理，这个二级散射考虑了地面的影响

//但也可以试试用各项异性计算？

//我们回顾一下，大气散射一般分为两个阶段，gather和scatter
//G1一级gather（太阳照到空气中一个点）
//S1一级scatter（太阳照到一个点然后散射出去，这一级各向异性）
//G2二级gather（一级scatter照到空气中一个点，UE在这一步认为这时候的一级scatter是各向同性的，也就是这个时候
//对于(H,theta)的每个点的64个方向积分，每个方向采样的20个点光照求和的TST中的S是1/4PI）
//二级scatter（这一步也是认为每个方向散射出去的L都是1/4PI * G2 * 密度）

//我们对于每一个点的高级散射，在计算这个点的积分时，都认为其他所有点和自己相同
//这样G3就可以基于当前点的G2得到，我们假设所有点向这个点发出的L为1（一个单位）
//那么对于这个点的64个方向，我们沿着采样的20个点累计一下（transmittance*密度）即可，假设总和为fms
//那么G3 = G2 * fms，于是S3 = S2 * fms（这边就不再考虑地面的影响了）
//于是S(2-inf) = S2/(1-fms)（只和高度和当前太阳角度有关，每个点的次级散射和向每个方向是一个定值）
[numthreads(1, 1, 64)]
void MultiScattCS(uint3 ThreadId : SV_DispatchThreadID)
{
    float2 pixPos = float2(ThreadId.xy) + 0.5f;
    float2 uv = pixPos / MultiScatteringLUTRes;
    uv = float2(fromSubUvsToUnit(uv.x, MultiScatteringLUTRes), fromSubUvsToUnit(uv.y, MultiScatteringLUTRes));

    AtmosphereParameters Atmosphere = GetAtmosphereParameters();

    float cosSunZenithAngle = uv.x * 2.0 - 1.0;
    float3 sunDir = float3(0.0, sqrt(saturate(1.0 - cosSunZenithAngle * cosSunZenithAngle)), cosSunZenithAngle);
    // We adjust again viewHeight according to PLANET_RADIUS_OFFSET to be in a valid range.
    float viewHeight = Atmosphere.BottomRadius + saturate(uv.y + PLANET_RADIUS_OFFSET) * (Atmosphere.TopRadius - Atmosphere.BottomRadius - PLANET_RADIUS_OFFSET);

    float3 WorldPos = float3(0.0f, 0.0f, viewHeight);
    float3 WorldDir = float3(0.0f, 0.0f, 1.0f);

    const bool ground = true;
    const float SampleCountIni = 20;// a minimum set of step is required for accuracy unfortunately
    const float DepthBufferValue = -1.0;
    const bool VariableSampleCount = false;
    const bool MieRayPhase = false;

    const float SphereSolidAngle = 4.0 * PI;
    const float IsotropicPhase = 1.0 / SphereSolidAngle;


    // Reference. Since there are many sample, it requires MULTI_SCATTERING_POWER_SERIE to be true for accuracy and to avoid divergences (see declaration for explanations)
    #define SQRTSAMPLECOUNT 8
    const float sqrtSample = float(SQRTSAMPLECOUNT);
    float i = 0.5f + float(ThreadId.z / SQRTSAMPLECOUNT);
    float j = 0.5f + float(ThreadId.z - float((ThreadId.z / SQRTSAMPLECOUNT) * SQRTSAMPLECOUNT));
    {
        float randA = i / sqrtSample;
        float randB = j / sqrtSample;
        float theta = 2.0f * PI * randA;
        float phi = PI * randB;
        float cosPhi = cos(phi);
        float sinPhi = sin(phi);
        float cosTheta = cos(theta);
        float sinTheta = sin(theta);
        WorldDir.x = cosTheta * sinPhi;
        WorldDir.y = sinTheta * sinPhi;
        WorldDir.z = cosPhi;
        SingleScatteringResult result = IntegrateScatteredLuminance(pixPos, WorldPos, WorldDir, sunDir, Atmosphere, ground, SampleCountIni, DepthBufferValue, VariableSampleCount, MieRayPhase);

        //float3 test = IntegrateScatteredLuminance(pixPos, WorldPos, WorldDir, sunDir, Atmosphere, ground, SampleCountIni, DepthBufferValue, VariableSampleCount, true).L;
        //result.L -= test;
        MultiScatAs1SharedMem[ThreadId.z] = result.MultiScatAs1 * SphereSolidAngle / (sqrtSample * sqrtSample);
        LSharedMem[ThreadId.z] = result.L * SphereSolidAngle / (sqrtSample * sqrtSample);
    }
    #undef SQRTSAMPLECOUNT
    {
        GroupMemoryBarrierWithGroupSync();

        // 64 to 32
        if (ThreadId.z < 32)
        {
            MultiScatAs1SharedMem[ThreadId.z] += MultiScatAs1SharedMem[ThreadId.z + 32];
            LSharedMem[ThreadId.z] += LSharedMem[ThreadId.z + 32];
        }
        GroupMemoryBarrierWithGroupSync();

        // 32 to 16
        if (ThreadId.z < 16)
        {
            MultiScatAs1SharedMem[ThreadId.z] += MultiScatAs1SharedMem[ThreadId.z + 16];
            LSharedMem[ThreadId.z] += LSharedMem[ThreadId.z + 16];
        }
        GroupMemoryBarrierWithGroupSync();

        // 16 to 8 (16 is thread group min hardware size with intel, no sync required from there)
        if (ThreadId.z < 8)
        {
            MultiScatAs1SharedMem[ThreadId.z] += MultiScatAs1SharedMem[ThreadId.z + 8];
            LSharedMem[ThreadId.z] += LSharedMem[ThreadId.z + 8];
        }
        GroupMemoryBarrierWithGroupSync();
        if (ThreadId.z < 4)
        {
            MultiScatAs1SharedMem[ThreadId.z] += MultiScatAs1SharedMem[ThreadId.z + 4];
            LSharedMem[ThreadId.z] += LSharedMem[ThreadId.z + 4];
        }
        GroupMemoryBarrierWithGroupSync();
        if (ThreadId.z < 2)
        {
            MultiScatAs1SharedMem[ThreadId.z] += MultiScatAs1SharedMem[ThreadId.z + 2];
            LSharedMem[ThreadId.z] += LSharedMem[ThreadId.z + 2];
        }
        GroupMemoryBarrierWithGroupSync();
        if (ThreadId.z < 1)
        {
            MultiScatAs1SharedMem[ThreadId.z] += MultiScatAs1SharedMem[ThreadId.z + 1];
            LSharedMem[ThreadId.z] += LSharedMem[ThreadId.z + 1];
        }
        GroupMemoryBarrierWithGroupSync();
        if (ThreadId.z > 0)
            return;
    }

    float3 MultiScatAs1 = MultiScatAs1SharedMem[0] * IsotropicPhase;	// Equation 7 f_ms
    float3 InScatteredLuminance = LSharedMem[0] * IsotropicPhase;				// Equation 5 L_2ndOrder

    // MultiScatAs1 represents the amount of luminance scattered as if the integral of scattered luminance over the sphere would be 1.
    //  - 1st order of scattering: one can ray-march a straight path as usual over the sphere. That is InScatteredLuminance.
    //  - 2nd order of scattering: the inscattered luminance is InScatteredLuminance at each of samples of fist order integration. Assuming a uniform phase function that is represented by MultiScatAs1,
    //  - 3nd order of scattering: the inscattered luminance is (InScatteredLuminance * MultiScatAs1 * MultiScatAs1)
    //  - etc.
    #if	MULTI_SCATTERING_POWER_SERIE == 0
        float3 MultiScatAs1SQR = MultiScatAs1 * MultiScatAs1;
        float3 L = InScatteredLuminance * (1.0 + MultiScatAs1 + MultiScatAs1SQR + MultiScatAs1 * MultiScatAs1SQR + MultiScatAs1SQR * MultiScatAs1SQR);
    #else
        // For a serie, sum_{n=0}^{n=+inf} = 1 + r + r^2 + r^3 + ... + r^n = 1 / (1.0 - r), see https://en.wikipedia.org/wiki/Geometric_series
        const float3 r = MultiScatAs1;
        const float3 SumOfAllMultiScatteringEventsContribution = 1.0f / (1.0 - r);
        float3 L = InScatteredLuminance * SumOfAllMultiScatteringEventsContribution;// Equation 10 Psi_ms
    #endif

    _MultiScat[ThreadId.xy] = float4(MultipleScatteringFactor * L, 1.0f);
    //_MultiScat[ThreadId.xy] = 0;

}

#endif