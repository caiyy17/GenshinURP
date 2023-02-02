Shader "Hidden/Custom RP/Skybox"
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