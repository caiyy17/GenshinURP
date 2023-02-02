using UnityEngine;
using Unity.Collections;
using System.Collections.Generic;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;
using static UnityEngine.Mathf;
using static SSRRenderFeature;

class HierarchicalDepthPass : ScriptableRenderPass
{
//这边生成HiZ，并依此来生成froxel的lightList
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    SSRSettings settings;
    SSRRenderFeature renderFeature;
    static ComputeBuffer froxelBuffer, lightIndexBuffer, lightBuffer, lightCounter;
    struct PointLight {
        public Vector3 color;
        public float inensity;
        public Vector4 sphere;
    };
    int MipResX , MipResY;

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    CommandBuffer buffer;
	Camera camera;
    RenderTextureFormat colorTextureFormat;
    public HierarchicalDepthPass(SSRRenderFeature renderFeature){
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
        RenderTextureDescriptor DepthDesc = new RenderTextureDescriptor(
            MipResX, MipResY, RenderTextureFormat.RHalf, 0
            );
        DepthDesc.useMipMap = true;
        DepthDesc.autoGenerateMips = false;
        buffer.GetTemporaryRT(depthPyramidId, DepthDesc, FilterMode.Point);
        ConfigureTarget(depthPyramidId);
    }

    // Here you can implement the rendering logic.
    // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
    // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
    // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        buffer.BeginSample("CustomDeferSetup");
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
        buffer.BeginSample("DepthPyrimid");
        ComputeShader PyramidDepthShader = settings.PyramidDepthShader;
        int kernelHandle = PyramidDepthShader.FindKernel("HiZ_Generation_max");

        Vector2Int PrevHiZPyramidSize = new Vector2Int(camera.pixelWidth, camera.pixelHeight);
        Vector2Int HiZPyramidSize = new Vector2Int(MipResX, MipResY);
        int PrevHiZPyramId = depthBufferId;
        int mipCount = 0;
        
        for (int i = 1; i <= settings.mipCountMax; ++i) 
        {
            
            if (HiZPyramidSize.x > 0 && HiZPyramidSize.y > 0){
                mipCount += 1;
            } else {
                break;
            }
            RenderTextureDescriptor DepthDesc = new RenderTextureDescriptor(
                HiZPyramidSize.x, HiZPyramidSize.y, RenderTextureFormat.RHalf, 0
                );
            DepthDesc.enableRandomWrite = true;
            buffer.GetTemporaryRT(depthPyramidId + i, DepthDesc, FilterMode.Point);
            buffer.SetComputeTextureParam(PyramidDepthShader, kernelHandle, "_PrevMipDepth", PrevHiZPyramId);
            buffer.SetComputeTextureParam(PyramidDepthShader, kernelHandle, "_HierarchicalDepth", depthPyramidId + i);
            buffer.SetComputeVectorParam(PyramidDepthShader, "_PrevCurr_Inverse_Size", new Vector4(1.0f / PrevHiZPyramidSize.x, 1.0f / PrevHiZPyramidSize.y, 1.0f / HiZPyramidSize.x, 1.0f / HiZPyramidSize.y));
            buffer.DispatchCompute(PyramidDepthShader, kernelHandle, Mathf.CeilToInt(HiZPyramidSize.x / 8.0f), Mathf.CeilToInt(HiZPyramidSize.y / 8.0f), 1);
            buffer.CopyTexture(depthPyramidId + i, 0, 0, depthPyramidId, 0, i - 1);
            PrevHiZPyramId = depthPyramidId + i;
            PrevHiZPyramidSize = HiZPyramidSize;
            HiZPyramidSize.x /= 2;
            HiZPyramidSize.y /= 2;
        }
        buffer.SetGlobalInt(mipCountId, mipCount);
        //用完把临时申请的texture给释放了
        for (int i = 1; i <= mipCount; ++i) 
        {
            buffer.ReleaseTemporaryRT(depthPyramidId + i);
        }
        buffer.EndSample("DepthPyrimid");
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
        buffer.BeginSample("FroxelLighting");
        ComputeShader FroxelComputeShader = settings.FroxelComputeShader;
        //我们将froxel的大小和depth的某一级对齐
        //并设定一个最远的距离，超过这个值的可以使用其他方法处理空间，比如raymarch
        int froxelMipLevel = Min(mipCount, settings.froxelMipLevel);
        int countX = FloorToInt(MipResX / Pow(2, froxelMipLevel));
        int countY = FloorToInt(MipResY / Pow(2, froxelMipLevel));
        int count = countX * countY * settings.froxelSlice;

        Vector4 froxelInfo = new Vector4(countX, countY, settings.froxelSlice, settings.froxelMaxDepth);
        buffer.SetGlobalVector(froxelInfoId, froxelInfo);
        buffer.SetComputeVectorParam(FroxelComputeShader, froxelInfoId, froxelInfo);
        //我们用一张2X,2Y的贴图存放每个锥体的四个面（4个float4）
        //用Z,2的贴图存放前后两个面，2个float4
        RenderTextureDescriptor froxelXYDesc = new RenderTextureDescriptor(
            2 * countX, 2 * countY, RenderTextureFormat.ARGBFloat, 0
            );
        froxelXYDesc.enableRandomWrite = true;
        buffer.GetTemporaryRT(froxelXYId, froxelXYDesc, FilterMode.Point);
        RenderTextureDescriptor froxelZDesc = new RenderTextureDescriptor(
            settings.froxelSlice, 2, RenderTextureFormat.ARGBFloat, 0
            );
        froxelZDesc.enableRandomWrite = true;
        buffer.GetTemporaryRT(froxelZId, froxelZDesc, FilterMode.Point);
        kernelHandle = FroxelComputeShader.FindKernel("FroxelXY");
        buffer.SetComputeTextureParam(FroxelComputeShader, kernelHandle, froxelXYId, froxelXYId);
        buffer.DispatchCompute(FroxelComputeShader, kernelHandle, Mathf.CeilToInt(countX / 8.0f), Mathf.CeilToInt(countY / 8.0f), 1);
        kernelHandle = FroxelComputeShader.FindKernel("FroxelZ");
        buffer.SetComputeTextureParam(FroxelComputeShader, kernelHandle, froxelZId, froxelZId);
        buffer.DispatchCompute(FroxelComputeShader, kernelHandle, 1, 1, Mathf.CeilToInt(settings.froxelSlice / 8.0f));
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
        //有了6个面的数据，就可以把光源分别塞进去了
        //先把light存入lightbuffer
        NativeArray<VisibleLight> visibleLights = renderingData.lightData.visibleLights;
        int lightLength = visibleLights.Length;
        List<PointLight> lightList = new List<PointLight>{};
        //跳过主光源
        PointLight tempLight = new PointLight();
        for (int i = 1; i < lightLength; i++)
        {
            var l = visibleLights[i];
            if (l.lightType == LightType.Directional)
            {
            }
            else if (l.lightType == LightType.Point)
            {
                tempLight.color = (Vector4)l.light.color;
                tempLight.inensity = l.light.intensity;
                Vector3 position = l.light.transform.position;
                tempLight.sphere = new Vector4(position.x, position.y, position.z, l.light.range);
            }
            else if (l.lightType == LightType.Spot)
            {
            }
            lightList.Add(tempLight);
        }
        int lightCount = lightList.Count;

        // if(lightCounter != null){
        //     int[] temp = new int[4]{0,0,0,0};
        //     lightCounter.GetData(temp);
        //     Debug.Log(temp[0]);
        // }

        SafeRelease(froxelBuffer);
        SafeRelease(lightIndexBuffer);
        SafeRelease(lightBuffer);
        SafeRelease(lightCounter);
        froxelBuffer = new ComputeBuffer(count, 2 * sizeof(int));
		buffer.SetGlobalBuffer(froxelBufferId, froxelBuffer);
        lightIndexBuffer = new ComputeBuffer(count, settings.maxFroxelLightAve * sizeof(int));
		buffer.SetGlobalBuffer(lightIndexBufferId, lightIndexBuffer);
        if(lightCount > 0){
            lightBuffer = new ComputeBuffer(lightCount, 8 * sizeof(float));
		    buffer.SetBufferData(lightBuffer, lightList);
		    buffer.SetGlobalBuffer(lightBufferId, lightBuffer);
        }else{
            lightBuffer = new ComputeBuffer(1, 8 * sizeof(float));
		    buffer.SetBufferData(lightBuffer, new float[8]);
		    buffer.SetGlobalBuffer(lightBufferId, lightBuffer);
        }
        lightCounter = new ComputeBuffer(4, sizeof(int));
        buffer.SetBufferData(lightCounter, new int[4]{0,0,0,0});
        
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
        //设定好贴图资源后，建立froxel信息
        Vector4 lightInfo = new Vector4(lightCount, settings.maxFroxelLightAve, froxelMipLevel,0);
        buffer.SetGlobalVector(lightInfoId, lightInfo);
        buffer.SetComputeVectorParam(FroxelComputeShader, lightInfoId, lightInfo);
        kernelHandle = FroxelComputeShader.FindKernel("Froxel");
        buffer.SetComputeBufferParam(FroxelComputeShader, kernelHandle, froxelBufferId, froxelBuffer);
        buffer.SetComputeBufferParam(FroxelComputeShader, kernelHandle, lightIndexBufferId, lightIndexBuffer);
        buffer.SetComputeBufferParam(FroxelComputeShader, kernelHandle, lightBufferId, lightBuffer);
        buffer.SetComputeBufferParam(FroxelComputeShader, kernelHandle, lightCounterId, lightCounter);
        buffer.SetComputeTextureParam(FroxelComputeShader, kernelHandle, "_HierarchicalDepth", depthPyramidId);
        buffer.SetComputeTextureParam(FroxelComputeShader, kernelHandle, froxelXYId, froxelXYId);
        buffer.SetComputeTextureParam(FroxelComputeShader, kernelHandle, froxelZId, froxelZId);
        buffer.DispatchCompute(FroxelComputeShader, kernelHandle, Mathf.CeilToInt(countX / 8.0f), Mathf.CeilToInt(countY / 8.0f), settings.froxelSlice);
        //视锥信息只在计算cluster光照的时候用到，然后就可以释放了
        buffer.ReleaseTemporaryRT(froxelXYId);
        buffer.ReleaseTemporaryRT(froxelZId);
        buffer.EndSample("FroxelLighting");
        buffer.EndSample("CustomDeferSetup");
        context.ExecuteCommandBuffer(buffer);
		buffer.Clear();
    }

    // Cleanup any allocated resources that were created during the execution of this render pass.
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
        buffer.ReleaseTemporaryRT(depthPyramidId);
    }

    public void Dispose(){
        SafeRelease(froxelBuffer);
        SafeRelease(lightIndexBuffer);
        SafeRelease(lightBuffer);
        SafeRelease(lightCounter);
    }

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

    int RoundUpToPowerOfTwo(int a){
        int near = ClosestPowerOfTwo(a);
        if (near < a){
            near *= 2;
        }
        return near;
    }
}