Shader "CustomDefer/GBuffer"
{
    Properties
    {
        [Header(Base)]
        [MainTexture][NoScaleOffset] _BaseMap ("Albedo", 2D) = "white" { }
        [MainColor] _BaseColor ("Color", Color) = (1, 1, 1, 1)
        
        [Header(Normal)]
        [Toggle(_C_NORMAL)] _C_NORMAL ("Use NormalMap", Float) = 1
        _NormalScale ("Normal Scale", Float) = 0
        [Toggle] _FlipTangent ("Flip Tangent", Float) = 0
        [NoScaleOffset]_NormalMap ("Normal", 2D) = "black" { }

        [Header(SMBE)]
        [Toggle(_C_SMBE)] _C_SMBE ("Use SMBE", Float) = 1
        [Toggle] _Emissive ("Emissive", Float) = 0
        [Toggle] _EmissiveOnAlbedo ("Emissive On Albedo", Float) = 0
        _EmissiveColor ("Emissive Color", Color) = (1, 1, 1, 1)
        _EmissiveIntensity ("Emissive Intensity", Float) = 15
        [NoScaleOffset]_SMBE ("SMBE", 2D) = "white" { }

        [Header(Height)]
        [Toggle(_C_HEIGHT)] _C_HEIGHT ("Use HeightMap", Float) = 0
        _HeightScale ("Height Scale", Float) = 0
        _HeightOffset ("Height Offset", Float) = 0.5
        [NoScaleOffset]_HeightMap ("Height", 2D) = "white" { }

        [Header(RenderState)]
        [Toggle(_RECEIVE_SHADOWS)] _ReceiveShadows ("Receive Shadows", Float) = 1
        [Toggle(_CLIPPING)] _Clipping ("Alpha Clipping", Float) = 0
        _Cutoff ("Alpha Cutoff", Range(0.0, 1.0)) = 0.5
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 1
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 0
        [Enum(Off, 0, On, 1)] _ZWrite ("Z Write", Float) = 1

        [HideInInspector] _MainTex ("Texture for Lightmap", 2D) = "white" { }
        [HideInInspector] _Color ("Color for Lightmap", Color) = (0.5, 0.5, 0.5, 1.0)
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" }

        HLSLINCLUDE
        #include "CustomInput.hlsl"

        ENDHLSL

        Pass
        {
            Name "Depth"
            Tags { "LightMode" = "Depth" }

            Cull[_Cull]
            ZWrite On
            ColorMask 0

            HLSLPROGRAM

            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore
            #pragma shader_feature_local_fragment _CLIPPING
            #pragma multi_compile_instancing
            #pragma vertex vert
            #pragma fragment frag
            
            #include "DepthPass.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "GBuffer"
            Tags { "LightMode" = "GBuffer" }

            Cull[_Cull]
            ZWrite Off

            HLSLPROGRAM

            //#pragma enable_d3d11_debug_symbols

            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore
            #pragma shader_feature_local_fragment _CLIPPING
            #pragma shader_feature_local_fragment _C_NORMAL
            #pragma shader_feature_local_fragment _C_SMBE
            #pragma shader_feature_local_fragment _C_HEIGHT
            #pragma shader_feature_local_fragment _RECEIVE_SHADOWS
            #pragma multi_compile_instancing
            #pragma vertex vert
            #pragma fragment frag
            
            #include "GBufferPass.hlsl"
            ENDHLSL

        }
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            // Render State
            Cull Off
            ZTest LEqual
            ZWrite On
            ColorMask 0
            
            HLSLPROGRAM

            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore
            #pragma shader_feature_local_fragment _CLIPPING
            #pragma multi_compile_instancing
            #pragma vertex vert
            #pragma fragment frag

            #include "../ShaderLibrary/Shadows.hlsl"
            
            float3 _LightDirection;

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
                if (dot(_LightDirection, OUT.normalWS) < 0)
                {
                    OUT.normalWS = -OUT.normalWS;
                }
                OUT.positionCS = TransformWorldToHClip(ApplyShadowBias(OUT.positionWS, OUT.normalWS, _LightDirection));

                //shadow pancaking
                #if UNITY_REVERSED_Z
                    OUT.positionCS.z = min(OUT.positionCS.z, OUT.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    OUT.positionCS.z = max(OUT.positionCS.z, OUT.positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif
                return OUT;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                processedVaryings input = processingVar(IN);
                float4 GT0 = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, input.uv, 0) * _BaseColor;
                #if defined(_CLIPPING)
                    clip(GT0.a - _Cutoff);
                #endif
                return 0;
            }
            ENDHLSL

        }
    }
    //CustomEditor "CustomShaderGUI"

}
