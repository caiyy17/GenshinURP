using UnityEngine;
using Unity.Collections;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;
using static SSRRenderFeature;

class GbufferSetupPass : ScriptableRenderPass
{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//GBuffer设定
    SSRSettings settings;
    SSRRenderFeature renderFeature;
    RenderTargetIdentifier[] gbufferID = new RenderTargetIdentifier[8];
    static ShaderTagId 
        DepthTagId = new ShaderTagId("Depth"),
		GBufferTagId = new ShaderTagId("GBuffer"),
        MotionBufferTagId = new ShaderTagId("MotionBuffer");

    static ShaderTagId 
        ForwardDepthNormalTagId = new ShaderTagId("ForwardDepthNormal");
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    CommandBuffer buffer;
	Camera camera;
    RenderTextureFormat colorTextureFormat;
    public GbufferSetupPass(SSRRenderFeature renderFeature){
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
        //Debug.Log("setup1");
        this.buffer = cmd;
		this.camera = renderingData.cameraData.camera;
        bool useHDR = renderingData.cameraData.isHdrEnabled;
        camera.depthTextureMode |= DepthTextureMode.MotionVectors | DepthTextureMode.Depth;
        
        if (!renderFeature.onceEveryFrame){
            renderFeature.onceEveryFrame = true;
            buffer.SetGlobalInteger(frameNumId, renderFeature.frameNum);
            if(settings.enableJitter){
                renderFeature.frameNum = (renderFeature.frameNum + 1) % 1024;
            }
            
        }
        colorTextureFormat = useHDR ?
			RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default;
        SetupBuffer();
        SetupLightFroxel(ref renderingData.lightData.visibleLights);
        SetupLastFrame();
        gbufferID[0] = GBufferAId;
        gbufferID[1] = GBufferBId;
        gbufferID[2] = GBufferCId;
        gbufferID[3] = GBufferDId;
        gbufferID[4] = GBufferEId;
        gbufferID[5] = GBufferFId;
        gbufferID[6] = GBufferGId;
        gbufferID[7] = motionBufferId;
        ConfigureTarget(gbufferID, depthBufferId);
    }

    // Here you can implement the rendering logic.
    // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
    // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
    // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        //Debug.Log("execute1");
        buffer.BeginSample("CustomDeferSetup");
        buffer.BeginSample("Depth");
        RenderBufferLoadAction load = RenderBufferLoadAction.DontCare;
        RenderBufferStoreAction store = RenderBufferStoreAction.Store;
        buffer.SetRenderTarget(depthBufferId, load, store);
        buffer.ClearRenderTarget(true, false, Color.clear);
        context.ExecuteCommandBuffer(buffer);
		buffer.Clear();
        var sortingSettings = new SortingSettings(camera){
			//非透明物体从前向后
			criteria = SortingCriteria.CommonOpaque
		    };
        var drawingSettings = new DrawingSettings(DepthTagId, sortingSettings){
            enableInstancing = true
            };
        var filteringSettings = new FilteringSettings(RenderQueueRange.opaque);
        context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
        buffer.EndSample("Depth");

        buffer.BeginSample("GBuffer");
        //绑定所有的GBuffer
        RenderTargetBinding binding = new RenderTargetBinding(gbufferID,
            new RenderBufferLoadAction[8]{load, load, load, load, load, load, load, load},
            new RenderBufferStoreAction[8]{store, store, store, store, store, store, store, store},
            depthBufferId, RenderBufferLoadAction.Load, RenderBufferStoreAction.Store
            );
        buffer.SetRenderTarget(binding);
        buffer.ClearRenderTarget(false, true, Color.clear);
        context.ExecuteCommandBuffer(buffer);
		buffer.Clear();
        drawingSettings = new DrawingSettings(GBufferTagId, sortingSettings){
            perObjectData =
				PerObjectData.ReflectionProbes | PerObjectData.LightProbe |
                //PerObjectData.LightData | PerObjectData.LightIndices |
                PerObjectData.MotionVectors,
            enableInstancing = true
            };
        context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
        buffer.EndSample("GBuffer");

        buffer.BeginSample("ForwardDepthNormal");
        context.ExecuteCommandBuffer(buffer);
        buffer.Clear();
        drawingSettings = new DrawingSettings(ForwardDepthNormalTagId, sortingSettings){
            perObjectData =
				PerObjectData.ReflectionProbes | PerObjectData.LightProbe |
                //PerObjectData.LightData | PerObjectData.LightIndices |
                PerObjectData.MotionVectors,
            enableInstancing = true
            };
        context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref filteringSettings);
        buffer.EndSample("ForwardDepthNormal");

        buffer.BeginSample("DepthModifier");
        buffer.SetRenderTarget(depthBufferId, load, store);
        buffer.DrawProcedural(
            Matrix4x4.identity, settings.DeferMatertial, 3,
            MeshTopology.Triangles, 3
        );
        buffer.EndSample("DepthModifier");

        buffer.EndSample("CustomDeferSetup");
        context.ExecuteCommandBuffer(buffer);
		buffer.Clear();
    }

    // Cleanup any allocated resources that were created during the execution of this render pass.
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        //Debug.Log("cleanup1");
        renderFeature.onceEveryFrame = false;
        buffer.ReleaseTemporaryRT(GBufferAId);
        buffer.ReleaseTemporaryRT(GBufferBId);
        buffer.ReleaseTemporaryRT(GBufferCId);
        buffer.ReleaseTemporaryRT(GBufferDId);
        buffer.ReleaseTemporaryRT(GBufferEId);
        buffer.ReleaseTemporaryRT(GBufferFId);
        buffer.ReleaseTemporaryRT(GBufferGId);
        buffer.ReleaseTemporaryRT(depthBufferId);
        buffer.ReleaseTemporaryRT(motionBufferId);
    }

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    void SetupBuffer(){
        buffer.GetTemporaryRT(GBufferAId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Point, RenderTextureFormat.ARGB32);
        buffer.GetTemporaryRT(GBufferBId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Point, RenderTextureFormat.ARGBHalf);
        buffer.GetTemporaryRT(GBufferCId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Point, RenderTextureFormat.ARGBHalf);
        buffer.GetTemporaryRT(GBufferDId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Point, RenderTextureFormat.ARGB32);
        buffer.GetTemporaryRT(GBufferEId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Point, colorTextureFormat);
        buffer.GetTemporaryRT(GBufferFId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Point, RenderTextureFormat.R8);
        buffer.GetTemporaryRT(GBufferGId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Point, RenderTextureFormat.R8);
        buffer.GetTemporaryRT(depthBufferId, camera.pixelWidth, camera.pixelHeight, 32, FilterMode.Point, RenderTextureFormat.Depth);
        buffer.GetTemporaryRT(motionBufferId, camera.pixelWidth, camera.pixelHeight, 0, FilterMode.Point, RenderTextureFormat.RGFloat);
    }

    void SetupLightFroxel(ref NativeArray<VisibleLight> lightList){

    }
    bool SetupLastFrame(){
        int cameraId = GetCameraID(camera);
        var m_HistoryCaches = renderFeature.m_HistoryCaches;
        if (!m_HistoryCaches.ContainsKey(cameraId) || m_HistoryCaches[cameraId] == null)
        {
            HistoryInfo his = new HistoryInfo();
            his.color = RenderTexture.GetTemporary(camera.pixelWidth, camera.pixelHeight, 0, colorTextureFormat);
            his.color.name = "_ColorHistory";
            his.depth = RenderTexture.GetTemporary(camera.pixelWidth, camera.pixelHeight, 0, RenderTextureFormat.RFloat);
            his.depth.name = "_DepthHistory";
            his.hasHistory = false;
            m_HistoryCaches.Add(cameraId, his);
            return false;
        } else {
            HistoryInfo his = m_HistoryCaches[cameraId];
            if(his.color == null || his.color.width != camera.pixelWidth || his.color.height != camera.pixelHeight){
                his.color.Release();
                his.color = RenderTexture.GetTemporary(camera.pixelWidth, camera.pixelHeight, 0, colorTextureFormat);
                his.color.name = "_ColorHistory";
                his.depth.Release();
                his.depth = RenderTexture.GetTemporary(camera.pixelWidth, camera.pixelHeight, 0, RenderTextureFormat.RFloat);
                his.depth.name = "_DepthHistory";
                his.hasHistory = false;
                return false;
            } else {
                his.hasHistory = true;
                buffer.SetGlobalTexture(colorHistoryId, his.color);
                buffer.SetGlobalTexture(depthHistoryId, his.depth);
                buffer.SetGlobalMatrix(lastViewProjId, his.matrix_LastViewProj);
                return true;
            }
        }
    }
}