Shader "CustomDefer/PCSS"
{
    Properties
    {
        _BaseMap ("Texture", 2D) = "white" { }
    }
    SubShader
    {
        HLSLINCLUDE
        #include "CustomFullScreen.hlsl"
        #pragma exclude_renderers gles gles3 glcore
        #pragma target 4.5
        ENDHLSL

        Pass
        {
            Name "GatherPass"
            Tags { "LightMode" = "GatherPass" }

            Cull Off
            ZTest Always
            ZWrite Off

            HLSLPROGRAM

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _DIRECTIONAL_PCF3 _DIRECTIONAL_PCF5 _DIRECTIONAL_PCF7
            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "PCFGatherPass.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "DilationH"
            Tags { "LightMode" = "DilationH" }

            Cull Off
            ZTest Always
            ZWrite Off

            HLSLPROGRAM

            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "DilationH.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "DilationV"
            Tags { "LightMode" = "DilationV" }

            Cull Off
            ZTest Always
            ZWrite Off

            HLSLPROGRAM

            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "DilationV.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "PCSS"
            Tags { "LightMode" = "PCSS" }

            Cull Off
            ZTest Always
            ZWrite Off

            HLSLPROGRAM

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _DIRECTIONAL_PCF3 _DIRECTIONAL_PCF5 _DIRECTIONAL_PCF7
            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "PCSSPass.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "PCFPrePass"
            Tags { "LightMode" = "PCFPrePass" }

            Cull Off
            ZTest Always
            ZWrite Off

            HLSLPROGRAM

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _DIRECTIONAL_PCF3 _DIRECTIONAL_PCF5 _DIRECTIONAL_PCF7
            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "PCFPass.hlsl"
            ENDHLSL

        }
        // Pass
        // {
        //     Name "TestA"
        //     Tags { "LightMode" = "TestA" }

        //     Cull Off
        //     ZTest Always
        //     ZWrite Off

        //     HLSLPROGRAM

        //     #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
        //     #pragma multi_compile_fragment _ _SHADOWS_SOFT
        //     #pragma multi_compile _ _DIRECTIONAL_PCF3 _DIRECTIONAL_PCF5 _DIRECTIONAL_PCF7
        //     #pragma vertex DefaultPassVertex
        //     #pragma fragment frag

        //     #include "Test/TestA.hlsl"
        //     ENDHLSL

        // }
        // Pass
        // {
        //     Name "TestA"
        //     Tags { "LightMode" = "TestB" }

        //     Cull Off
        //     ZTest Always
        //     ZWrite Off

        //     HLSLPROGRAM

        //     #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
        //     #pragma multi_compile_fragment _ _SHADOWS_SOFT
        //     #pragma multi_compile _ _DIRECTIONAL_PCF3 _DIRECTIONAL_PCF5 _DIRECTIONAL_PCF7
        //     #pragma vertex DefaultPassVertex
        //     #pragma fragment frag

        //     #include "Test/TestB.hlsl"
        //     ENDHLSL

        // }
        // Pass
        // {
        //     Name "TestC"
        //     Tags { "LightMode" = "TestC" }

        //     Cull Off
        //     ZTest Always
        //     ZWrite Off

        //     HLSLPROGRAM

        //     #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
        //     #pragma multi_compile_fragment _ _SHADOWS_SOFT
        //     #pragma multi_compile _ _DIRECTIONAL_PCF3 _DIRECTIONAL_PCF5 _DIRECTIONAL_PCF7
        //     #pragma vertex DefaultPassVertex
        //     #pragma fragment frag

        //     #include "Test/TestC.hlsl"
        //     ENDHLSL

        // }

    }
}
