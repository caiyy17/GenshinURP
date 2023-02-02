Shader "CustomDefer/DeferRendering"
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
            Name "DeferRendering"
            Tags { "LightMode" = "DeferRendering" }

            Cull Off
            ZTest Always
            ZWrite Off

            HLSLPROGRAM

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "DeferRenderingPass.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "AntiAliasing"
            Tags { "LightMode" = "AntiAliasing" }

            Cull Off
            ZTest Always
            ZWrite Off

            HLSLPROGRAM

            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "AntiAliasingPass.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "CopyAttachment"
            Tags { "LightMode" = "CopyAttachment" }

            Cull Off
            ZTest Always
            ZWrite Off

            HLSLPROGRAM

            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "CopyAttachmentPass.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "DepthModifier"
            Tags { "LightMode" = "DepthModifier" }

            Cull Off
            ZTest Always
            ZWrite On

            HLSLPROGRAM

            #pragma vertex DefaultPassVertex
            #pragma fragment frag

            #include "DepthModifierPass.hlsl"
            ENDHLSL

        }
    }
}
