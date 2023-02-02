using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;
using static SSRRenderFeature;

class DeferRenderingPass : ScriptableRenderPass
{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    SSRSettings settings;
    SSRRenderFeature renderFeature;

    static ShaderTagId 
        ForwardPlusTagId = new ShaderTagId("ForwardPlus"),
        OutlineTagId = new ShaderTagId("Outline");

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    CommandBuffer buffer;
	Camera camera;
    RenderTextureFormat colorTextureFormat;
    public DeferRenderingPass(SSRRenderFeature renderFeature){
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
        //Debug.Log("setup2");
        this.buffer = cmd;
		this.camera = renderingData.cameraData.camera;
        bool useHDR = renderingData.cameraData.isHdrEnabled;
        colorTextureFormat = useHDR ?
			RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default;
        buffer.GetTemporaryRT(colorBufferId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Bilinear, colorTextureFormat);
        buffer.GetTemporaryRT(accumulateBufferId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Bilinear, colorTextureFormat);
        ConfigureTarget(colorBufferId);
        
    }

    // Here you can implement the rendering logic.
    // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
    // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
    // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        //Debug.Log("execute2");
        buffer.BeginSample("CustomDeferRendering");
        buffer.BeginSample("Defer");
        DrawFullScreen(buffer, colorBufferId, settings.DeferMatertial, 0);
        buffer.EndSample("Defer");

        buffer.BeginSample("ForwardPlus");
        buffer.SetRenderTarget(colorBufferId, RenderBufferLoadAction.Load, RenderBufferStoreAction.Store, 
        depthBufferId, RenderBufferLoadAction.Load, RenderBufferStoreAction.Store);
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
        var sortingSettings = new SortingSettings(camera){
			//非透明物体从前向后
			criteria = SortingCriteria.CommonOpaque
		    };
        var drawingSettings = new DrawingSettings(OutlineTagId, sortingSettings){
            //perObjectData =
				//PerObjectData.ReflectionProbes | PerObjectData.LightProbe |
                //PerObjectData.LightData | PerObjectData.LightIndices
            enableInstancing = true
            };
        var filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
        context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
        drawingSettings = new DrawingSettings(ForwardPlusTagId, sortingSettings){
            perObjectData =
				PerObjectData.ReflectionProbes | PerObjectData.LightProbe |
                PerObjectData.LightData | PerObjectData.LightIndices,
            enableInstancing = true
            };
        context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
        buffer.EndSample("ForwardPlus");

        buffer.BeginSample("AntiAliasing");
        if(renderFeature.m_HistoryCaches[GetCameraID(camera)].hasHistory){
            DrawFullScreen(buffer, accumulateBufferId, settings.DeferMatertial, 1);
        } else {
            buffer.CopyTexture(colorBufferId, accumulateBufferId);
        }
        buffer.EndSample("AntiAliasing");

        buffer.BeginSample("Copy");
        DrawFullScreen(buffer, renderingData.cameraData.renderer.cameraColorTarget, settings.DeferMatertial, 2);
        buffer.CopyTexture(depthBufferId, renderingData.cameraData.renderer.cameraDepthTarget);
        buffer.CopyTexture(depthBufferId, "_CameraDepthTexture");
        UpdateLastFrame();
        buffer.EndSample("Copy");
        buffer.EndSample("CustomDeferRendering");
        context.ExecuteCommandBuffer(buffer);
		buffer.Clear();
    }

    // Cleanup any allocated resources that were created during the execution of this render pass.
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        //Debug.Log("claenup2");
        buffer.ReleaseTemporaryRT(colorBufferId);
        buffer.ReleaseTemporaryRT(accumulateBufferId);
    }

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    void UpdateLastFrame(){
        int cameraId = GetCameraID(camera);
        HistoryInfo his = renderFeature.m_HistoryCaches[cameraId];
        buffer.CopyTexture(accumulateBufferId, his.color);
        buffer.Blit(depthBufferId, his.depth);
        his.matrix_LastViewProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, true) * camera.worldToCameraMatrix;
    }
}