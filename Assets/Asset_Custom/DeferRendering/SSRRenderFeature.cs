using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

public class SSRRenderFeature : ScriptableRendererFeature
{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    [SerializeField]
    public SSRSettings settings;
    public static int frameNumId = Shader.PropertyToID("_FrameNum"),
        mipCountId = Shader.PropertyToID("_MipCount"),
        lastViewProjId = Shader.PropertyToID("matrix_LastViewProj");
    public static int GBufferAId = Shader.PropertyToID("_GBufferA"),
        GBufferBId = Shader.PropertyToID("_GBufferB"),
        GBufferCId = Shader.PropertyToID("_GBufferC"),
        GBufferDId = Shader.PropertyToID("_GBufferD"),
        GBufferEId = Shader.PropertyToID("_GBufferE"),
        GBufferFId = Shader.PropertyToID("_GBufferF"),
        GBufferGId = Shader.PropertyToID("_GBufferG"),
        motionBufferId = Shader.PropertyToID("_MotionBuffer"),
        colorBufferId = Shader.PropertyToID("_ColorBuffer"),
        depthBufferId = Shader.PropertyToID("_DepthBuffer"),
        colorHistoryId = Shader.PropertyToID("_ColorHistory"),
        depthHistoryId = Shader.PropertyToID("_DepthHistory"),
        accumulateBufferId = Shader.PropertyToID("_AccumulateBuffer");
    public static int depthPyramidId, 
        depthPyramidMinId = Shader.PropertyToID("_DepthPyramidMin"),
        froxelBufferId = Shader.PropertyToID("_FroxelBuffer"),
        lightIndexBufferId = Shader.PropertyToID("_LightIndexBuffer"),
        lightBufferId = Shader.PropertyToID("_LightBuffer"),
        lightCounterId = Shader.PropertyToID("_LightCounter"),
        froxelXYId = Shader.PropertyToID("_FroxelXY"),
        froxelZId = Shader.PropertyToID("_FroxelZ"),
        froxelInfoId = Shader.PropertyToID("_FroxelInfo"),
        lightInfoId = Shader.PropertyToID("_LightInfo");
    public static int coarseShadowBufferId = Shader.PropertyToID("_CoarseShadowBuffer"),
        dilationBufferId = Shader.PropertyToID("_DilationBuffer"),
        PCSSShadowBufferId = Shader.PropertyToID("_PCSSShadowBuffer"),
        texelSizeId = Shader.PropertyToID("_TexelSize"),
        shadowInfoId = Shader.PropertyToID("_ShadowInfo");
    public Dictionary<int, HistoryInfo> m_HistoryCaches = new Dictionary<int, HistoryInfo>();
    public int frameNum = 0;
    public bool onceEveryFrame = false;
    GbufferSetupPass m_setupPass;
    HierarchicalDepthPass m_HiZPass;
    DeferRenderingPass m_deferRenderingPass;
    ShadowPass m_shadowPass;

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

    /// <inheritdoc/>
    public override void Create()
    {
        depthPyramidId = Shader.PropertyToID("_DepthPyramid");
		for (int i = 1; i <= settings.mipCountMax; i++) {
			Shader.PropertyToID("_DepthPyramidTemp" + i);
		}

        m_setupPass = new GbufferSetupPass(this);
        m_HiZPass = new HierarchicalDepthPass(this);
        m_deferRenderingPass = new DeferRenderingPass(this);
        m_shadowPass = new ShadowPass(this);
        
        // Configures where the render pass should be injected.
        m_setupPass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
        m_HiZPass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
        m_shadowPass.renderPassEvent = RenderPassEvent.AfterRenderingPrePasses;
        m_deferRenderingPass.renderPassEvent = RenderPassEvent.AfterRenderingSkybox;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_setupPass);
        renderer.EnqueuePass(m_HiZPass);
        renderer.EnqueuePass(m_shadowPass);
        renderer.EnqueuePass(m_deferRenderingPass);
    }

    protected override void Dispose(bool disposing){
        foreach (var historyCache in m_HistoryCaches)
        {
            historyCache.Value.color.Release();
            historyCache.Value.depth.Release();
        }
        m_HistoryCaches.Clear();

        m_HiZPass.Dispose();
    }

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    public static int GetCameraID(Camera camera)
    {
        int cameraId = camera.GetHashCode();
        if (camera.cameraType == CameraType.Preview)
        {
            if (camera.pixelHeight == 64)
            {
                cameraId += 1;
            }
            // Unity will use one PreviewCamera to draw Material icon and Material Preview together, this will cause resources identity be confused.
            // We found that the Material preview can not be less than 70 pixel, and the icon is always 64, so we use this to distinguish them.
        }
        return cameraId;
    }

    public static void DrawFullScreen(CommandBuffer buffer, in RenderTargetIdentifier dsc, 
    Material mat, int passIndex, 
    RenderBufferLoadAction load = RenderBufferLoadAction.DontCare,
    RenderBufferStoreAction store = RenderBufferStoreAction.Store){
        buffer.SetRenderTarget(dsc, load, store);
        buffer.DrawProcedural(
            Matrix4x4.identity, mat, passIndex,
            MeshTopology.Triangles, 3
        );
    }

    public static void SafeRelease(ComputeBuffer c){
        if (c != null){
			//Debug.Log("buffer released");
			c.Release();
		}
    }
}


