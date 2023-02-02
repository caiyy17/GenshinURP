using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;
using static UnityEngine.Mathf;
using static SSRRenderFeature;

class ShadowPass : ScriptableRenderPass
{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    SSRSettings settings;
    SSRRenderFeature renderFeature;
    static ShaderTagId 
        ShadowCasterTagId = new ShaderTagId("ShadowCaster");
    static string[] directionalFilterKeywords = {
		"_DIRECTIONAL_PCF3",
		"_DIRECTIONAL_PCF5",
		"_DIRECTIONAL_PCF7",
	};
    int MipResX , MipResY;

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

    public static int TestBufferAId = Shader.PropertyToID("_TestBufferA");
    public static int TestBufferBId = Shader.PropertyToID("_TestBufferB");
    public static int TestBufferCId = Shader.PropertyToID("_TestBufferC");

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    CommandBuffer buffer;
	Camera camera;
    RenderTextureFormat colorTextureFormat;
    public ShadowPass(SSRRenderFeature renderFeature){
        this.renderFeature = renderFeature;
        this.settings = renderFeature.settings;
    }
    // This method is called before executing the render pass.
    // It can be used to configure render targets and their clear state. Also to create temporary render target textures.
    // When empty this render pass will render to the active camera render target.
    // You should never call CommandBuffer.SetRenderTarget. Instead call <c>ConfigureTarget</c> and <c>ConfigureClear</c>.
    // The render pipeline will ensure target setup and clearing happens in a performant manner.
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        this.buffer = cmd;
		this.camera = renderingData.cameraData.camera;
        MipResX = RoundUpToPowerOfTwo(camera.pixelWidth / 2);
        MipResY = RoundUpToPowerOfTwo(camera.pixelHeight / 2);
        int shadowMipLevel = Min((int)Log(Min(MipResX, MipResY), 2), settings.shadowMipLevel);
        int countX = FloorToInt(MipResX / Pow(2, shadowMipLevel));
        int countY = FloorToInt(MipResX / Pow(2, shadowMipLevel));
        buffer.SetGlobalVector(texelSizeId, new Vector4(1.0f / countX, 1.0f / countY, countX, countY));
        RenderTextureDescriptor coarseShadowDesc = new RenderTextureDescriptor(
            countX, countY, RenderTextureFormat.RHalf, 0
            );
        buffer.GetTemporaryRT(coarseShadowBufferId, coarseShadowDesc, FilterMode.Point);
        RenderTextureDescriptor dilationDesc = new RenderTextureDescriptor(
            countX, countY, RenderTextureFormat.RHalf, 0
            );
        buffer.GetTemporaryRT(dilationBufferId, dilationDesc, FilterMode.Point);
        RenderTextureDescriptor shadowDesc = new RenderTextureDescriptor(
            camera.pixelWidth, camera.pixelHeight, RenderTextureFormat.RGHalf, 0
            );
        buffer.GetTemporaryRT(PCSSShadowBufferId, shadowDesc, FilterMode.Point);
        ConfigureTarget(coarseShadowBufferId);

        // buffer.GetTemporaryRT(TestBufferAId, shadowDesc, FilterMode.Point);
        // buffer.GetTemporaryRT(TestBufferBId, shadowDesc, FilterMode.Point);
        // buffer.GetTemporaryRT(TestBufferCId, shadowDesc, FilterMode.Point);
    
    }

    // Here you can implement the rendering logic.
    // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
    // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
    // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        buffer.BeginSample("CustomDeferSetup");
        buffer.BeginSample("SSShadow");
        SetKeywords(directionalFilterKeywords, (int)settings.shadowFilter - 1);
        buffer.SetGlobalVector(shadowInfoId, new Vector4(settings.depthTestAngle, settings.PCSSAngle, settings.maxSoftDepth, settings.testCount));
        if(settings.enablePCSS){
            DrawFullScreen(buffer, coarseShadowBufferId, settings.PCSSMatertial, 0);
            DrawFullScreen(buffer, dilationBufferId, settings.PCSSMatertial, 1);
            DrawFullScreen(buffer, coarseShadowBufferId, settings.PCSSMatertial, 2);
            DrawFullScreen(buffer, PCSSShadowBufferId, settings.PCSSMatertial, 3);
        }
        else{
            DrawFullScreen(buffer, PCSSShadowBufferId, settings.PCSSMatertial, 4);
        }
        
        
        buffer.EndSample("SSShadow");
        buffer.EndSample("CustomDeferSetup");
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
    }

    // Cleanup any allocated resources that were created during the execution of this render pass.
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        buffer.ReleaseTemporaryRT(coarseShadowBufferId);
        buffer.ReleaseTemporaryRT(dilationBufferId);
        buffer.ReleaseTemporaryRT(PCSSShadowBufferId);

        // buffer.ReleaseTemporaryRT(TestBufferAId);
        // buffer.ReleaseTemporaryRT(TestBufferBId);
        // buffer.ReleaseTemporaryRT(TestBufferCId);
    }

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    void SetKeywords (string[] keywords, int enabledIndex) {
		//int enabledIndex = (int)settings.directional.filter - 1;
		for (int i = 0; i < keywords.Length; i++) {
			if (i == enabledIndex) {
				buffer.EnableShaderKeyword(keywords[i]);
			}
			else {
				buffer.DisableShaderKeyword(keywords[i]);
			}
		}
	}
    int RoundUpToPowerOfTwo(int a){
        int near = ClosestPowerOfTwo(a);
        if (near < a){
            near *= 2;
        }
        return near;
    }


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

    // void Test(){
    //     buffer.BeginSample("Test");
    //     DrawFullScreen(buffer, TestBufferAId, settings.PCSSMatertial, 5);
    //     DrawFullScreen(buffer, TestBufferBId, settings.PCSSMatertial, 6);
    //     DrawFullScreen(buffer, PCSSShadowBufferId, settings.PCSSMatertial, 7);
    //     buffer.EndSample("Test");
    // }

}