using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

public class AtmosphereRenderFeature : ScriptableRendererFeature
{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    [SerializeField]
    public Atmosphere atmosphere;
    public enum AtmospherePass {
        RenderAtmosphere,
        TransmittanceLut,
        SkyViewLut,
        CameraVolume,
        Stars,
        ConstellationLines,
        Sky
    }
    public static int transmittanceLutId = Shader.PropertyToID("_TransmittanceLut"),
        skyViewLutId = Shader.PropertyToID("_SkyViewLut"),
        skyViewTransLutId = Shader.PropertyToID("_SkyViewTransLut"),
        skyViewDepthLutId = Shader.PropertyToID("_SkyViewDepthLut"),
        cameraVolumeId = Shader.PropertyToID("_CameraVolume"),
        multiScatId = Shader.PropertyToID("_MultiScat"),
        skyMapId = Shader.PropertyToID("_SkyMap"),
        starMapId = Shader.PropertyToID("_StarMap"),
        starHistoryId = Shader.PropertyToID("_StarHistoryMap");
    public static int lutInfoId = Shader.PropertyToID("_LutInfo"),
        volumeInfoId = Shader.PropertyToID("_VolumeInfo"),
        atmosphereInfoId = Shader.PropertyToID("_AtmosphereInfo");
    public static int earthMapId = Shader.PropertyToID("_EarthMap"),
        earthCloudMapId = Shader.PropertyToID("_EarthCloudMap"),
        earthNightMapId = Shader.PropertyToID("_EarthNightMap"),
        moonMapId = Shader.PropertyToID("_MoonMap"),
        farMapId = Shader.PropertyToID("_FarMap"),
        starInfoId = Shader.PropertyToID("_StarInfo"),
        starsId = Shader.PropertyToID("_Stars"),
        constellationsId = Shader.PropertyToID("_Constellations"),
        jdInfoId = Shader.PropertyToID("_JdInfo"),
        solarInfoId = Shader.PropertyToID("_SolarInfo");
    public static int inverseViewAndProjectionMatrix = Shader.PropertyToID("custom_MatrixInvVP"),
        ViewAndProjectionMatrix = Shader.PropertyToID("custom_MatrixVP");
    public Dictionary<int, StarHistory> m_HistoryCaches = new Dictionary<int, StarHistory>();
    public int frameNum = 0;
    public bool onceEveryFrame = false;
    AtmosphereSetupPass m_setupPass;
    AtmosphereFinalPass m_atmosphereFinalPass;

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

    /// <inheritdoc/>
    public override void Create()
    {
        m_setupPass = new AtmosphereSetupPass(this);
        m_atmosphereFinalPass = new AtmosphereFinalPass(this);

        // Configures where the render pass should be injected.
        m_setupPass.renderPassEvent = RenderPassEvent.BeforeRendering;
        m_atmosphereFinalPass.renderPassEvent = RenderPassEvent.BeforeRenderingTransparents;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_setupPass);
        renderer.EnqueuePass(m_atmosphereFinalPass);
    }

    protected override void Dispose(bool disposing){
        m_setupPass.Dispose();
        foreach (var historyCache in m_HistoryCaches)
        {
            historyCache.Value.color.Release();
        }
        m_HistoryCaches.Clear();
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

    public static void DrawFullScreen(CommandBuffer buffer, in RenderTargetIdentifier dsc, Material mat, int passIndex){
        RenderBufferLoadAction load = RenderBufferLoadAction.DontCare;
        RenderBufferStoreAction store = RenderBufferStoreAction.Store;
        buffer.SetRenderTarget(dsc, load, store);
        buffer.DrawProcedural(
            Matrix4x4.identity, mat, passIndex,
            MeshTopology.Triangles, 3
        );
    }
}


