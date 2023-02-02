Shader "Hidden/Custom RP/Atmosphere"
{
    

    //这个是postFX用的shader
    SubShader
    {
        Cull Off
        ZTest Always
        ZWrite Off
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        ENDHLSL

        Pass
        {
            Name "RenderAtmosphere"
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex DefaultPassVertex
            #pragma fragment RenderPassFragment
            #define gResolution _ScreenParams.xy
            #include "Atmosphere.hlsl"
            ENDHLSL

        }

        Pass
        {
            Name "TransmittanceLut"
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex DefaultPassVertex
            #pragma fragment TransmittanceLutPS
            #define gResolution _LutInfo.xy
            #include "Atmosphere.hlsl"
            ENDHLSL

        }

        Pass
        {
            Name "SkyViewLut"
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex DefaultPassVertex
            #pragma fragment SkyViewLutPS
            #define gResolution _LutInfo.zw
            #define MULTISCATAPPROX_ENABLED 1
            #include "Atmosphere.hlsl"
            ENDHLSL

        }

        Pass
        {
            Name "CameraVolume"
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex DefaultPassVertex
            #pragma fragment CameraVolumePS
            #define gResolution float2(_VolumeInfo.x * _VolumeInfo.x, _VolumeInfo.x)
            #define MULTISCATAPPROX_ENABLED 1
            #include "Atmosphere.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "Stars"
            BlendOp Max
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex StarsPassVertex
            #pragma fragment StarsPassFragment
            #define gResolution _ScreenParams.xy
            #include "Atmosphere.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "ConstellationLines"
            BlendOp Max
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex ConstellationsPassVertex
            #pragma fragment ConstellationsPassFragment
            #define gResolution _ScreenParams.xy
            #include "Atmosphere.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "RenderSky"
            HLSLPROGRAM

            #pragma target 3.5
            #pragma vertex DefaultPassVertex
            #pragma fragment SkyPassFragment
            #define gResolution _ScreenParams.xy
            #define RENDER_SUN_DISK 1
            #define RENDER_MOON_DISK 1
            #include "Atmosphere.hlsl"
            ENDHLSL

        }
    }
}