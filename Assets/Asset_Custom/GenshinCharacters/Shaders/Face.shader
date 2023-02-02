Shader "Genshin/Face"
{
    //Credit: CYY
    Properties
    {
        [NoScaleOffset]_base ("base", 2D) = "white" { }
        _Color ("Color", Color) = (1, 0.8627451, 0.8235294, 0)
        // _shadowColor ("shadowColor", Color) = (0.8901961, 0.5960785, 0.627451, 0)
        [NoScaleOffset]_ramp ("ramp", 2D) = "white" { }
        _rampInfo0 ("rampInfo0", Vector) = (0, 5, 1.0, 1)
        _rampInfo12 ("rampInfo12", Vector) = (0.0, 0, 0.3, 3)
        _rampInfo34 ("rampInfo34", Vector) = (0.5, 2, 0.7, 4)
        [NoScaleOffset]_shadow ("shadow", 2D) = "white" { }
        _shadowGate ("shadowGate", Float) = 1.01
        _shadowGradiant ("shadowGradiant", Float) = 0
        _outlineThickness ("outlineThickness", Float) = 1.8
        _outlineColor ("outlineColor", Color) = (0.4, 0.2, 0.3, 1)
    }
    SubShader
    {
        HLSLINCLUDE

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            // float4 _shadowColor;
            float4 _rampInfo0;
            float4 _rampInfo12;
            float4 _rampInfo34;
            
            float _shadowGate;
            float _shadowGradiant;

            float4 _base_TexelSize;
            float4 _ramp_TexelSize;
            float4 _shadow_TexelSize;

            float _outlineThickness;
            float4 _outlineColor;
        CBUFFER_END

        TEXTURE2D(_base);
        SAMPLER(sampler_base);
        TEXTURE2D(_ramp);
        SAMPLER(sampler_ramp);
        TEXTURE2D(_shadow);
        SAMPLER(sampler_shadow);

        TEXTURE2D(_CameraDepthTexture);
        SAMPLER(sampler_CameraDepthTexture);

        #include "Sample.hlsl"
        uint _FrameNum;

        ENDHLSL

        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        Pass
        {
            Name "ForwardPlus"
            Tags { "LightMode" = "ForwardPlus" }
            
            // Render State
            Cull Back
            Blend One Zero
            ZTest LEqual
            ZWrite On
            
            HLSLPROGRAM

            // Pragmas
            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma vertex vert
            #pragma fragment frag

            #include "Face.hlsl"

            ENDHLSL

        }
        Pass
        {
            Name "Outline"
            Tags { "LightMode" = "Outline" }

            // Render State
            Cull Front
            Blend One Zero
            ZTest LEqual
            ZWrite On

            HLSLPROGRAM

            #pragma target 4.5
            #pragma exclude_renderers gles gles3 glcore
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma vertex vert
            #pragma fragment frag

            #include "outline.hlsl"

            ENDHLSL

        }
        // Pass
        // {
        //     Name "DepthOnly"
        //     Tags { "LightMode" = "DepthOnly" }

        //     // Render State
        //     Cull Off
        //     ZTest LEqual
        //     ZWrite On
        //     ColorMask 0
        
        //     HLSLPROGRAM

        //     #pragma target 4.5
        //     #pragma exclude_renderers gles gles3 glcore
        //     #pragma multi_compile_instancing
        //     #pragma multi_compile_fog
        //     #pragma vertex vert
        //     #pragma fragment frag

        //     struct Attributes
        //     {
        //         float3 positionOS : POSITION;
        //         float3 normalOS : NORMAL;
        //         float4 tangentOS : TANGENT;
        //         float2 uv : TEXCOORD0;
        //     };
        //     struct Varyings
        //     {
        //         float4 positionCS : SV_POSITION;
        //         float2 uv : TEXCOORD0;
        //     };

        //     Varyings vert(Attributes IN)
        //     {
        //         Varyings OUT;
        //         VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS.xyz);
        //         OUT.positionCS = positionInputs.positionCS;
        //         OUT.uv = IN.uv;
        //         return OUT;
        //     }

        //     float4 frag(Varyings IN) : SV_Target
        //     {
        //         return 0;
        //     }

        //     ENDHLSL

        // }
        // Pass
        // {
        //     Name "DepthNormals"
        //     Tags { "LightMode" = "DepthNormals" }

        //     // Render State
        //     Cull Off
        //     ZTest LEqual
        //     ZWrite On
        
        //     HLSLPROGRAM

        //     #pragma exclude_renderers gles gles3 glcore
        //     #pragma target 4.5

        //     #pragma vertex DepthNormalsVertex
        //     #pragma fragment DepthNormalsFragment

        //     struct Attributes
        //     {
        //         float4 positionOS : POSITION;
        //         float4 tangentOS : TANGENT;
        //         float2 texcoord : TEXCOORD0;
        //         float3 normal : NORMAL;
        //     };

        //     struct Varyings
        //     {
        //         float4 positionCS : SV_POSITION;
        //         float2 uv : TEXCOORD1;
        //         float3 normalWS : TEXCOORD2;
        //     };

        //     Varyings DepthNormalsVertex(Attributes input)
        //     {
        //         Varyings output = (Varyings)0;

        //         output.uv = input.texcoord;
        //         output.positionCS = TransformObjectToHClip(input.positionOS.xyz);

        //         VertexNormalInputs normalInput = GetVertexNormalInputs(input.normal, input.tangentOS);
        //         output.normalWS = NormalizeNormalPerVertex(normalInput.normalWS);
        //         return output;
        //     }

        //     float4 DepthNormalsFragment(Varyings input) : SV_TARGET
        //     {
        //         return float4(PackNormalOctRectEncode(TransformWorldToViewDir(input.normalWS, true)), 0.0, 0.0);
        //     }
        //     ENDHLSL

        // }
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
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float3 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = positionInputs.positionCS;
                OUT.uv = IN.uv;
                return OUT;
            }

            float4 frag(Varyings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL

        }
        ////////////////////////////////////////////////////////////////////////////////
        ////////////////////////////////////////////////////////////////////////////////
        ////////////////////////////////////////////////////////////////////////////////
        //为了ForwardPlus加的pass
        Pass
        {
            Name "ForwardDepthNormal"
            Tags { "LightMode" = "ForwardDepthNormal" }

            // Render State
            Cull Off
            ZTest LEqual
            ZWrite On
            
            HLSLPROGRAM

            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            #include "ForwardDepthNormal.hlsl"
            ENDHLSL

        }
    }
}