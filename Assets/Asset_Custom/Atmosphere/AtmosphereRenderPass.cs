using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;
using static AtmosphereRenderFeature;
class AtmosphereFinalPass : ScriptableRenderPass
{
    AtmosphereRenderFeature renderFeature;
    Atmosphere atmosphere;
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    CommandBuffer buffer;
    Camera camera;

    static int colorTextureId = Shader.PropertyToID("_CustomColorTexture"),
        depthTextureId = Shader.PropertyToID("_CustomDepthTexture");
    public AtmosphereFinalPass(AtmosphereRenderFeature renderFeature){
        this.renderFeature = renderFeature;
        this.atmosphere = renderFeature.atmosphere;
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
    }

    // Here you can implement the rendering logic.
    // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
    // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
    // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        buffer.BeginSample("Atmosphere");
        buffer.BeginSample("Final");
        buffer.SetGlobalTexture(colorTextureId, "_AccumulateBuffer");
        buffer.SetGlobalTexture(depthTextureId, "_DepthBuffer");
        // buffer.SetGlobalTexture(colorTextureId, "_CameraOpaqueTexture");
        // buffer.SetGlobalTexture(depthTextureId, "_CameraDepthTexture");
        if(atmosphere.settings.useAtmosphere){
            buffer.DrawProcedural(
                Matrix4x4.identity, atmosphere.MaterialAtmosphere, (int)AtmospherePass.RenderAtmosphere,
                MeshTopology.Triangles, 3
            );
        }
        buffer.EndSample("Final");
        buffer.EndSample("Atmosphere");
        context.ExecuteCommandBuffer(buffer);
		buffer.Clear();
    }

    // Cleanup any allocated resources that were created during the execution of this render pass.
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
    }
}