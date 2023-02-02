using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using UnityEngine.Experimental.Rendering;
using static AtmosphereRenderFeature;

using static UnityEngine.Mathf;

class AtmosphereSetupPass : ScriptableRenderPass
{
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//这边是大气设定，主要是定义一些RT和参数
	AtmosphereRenderFeature renderFeature;
    Atmosphere atmosphere;
    StarStructure Stars;
    static Matrix4x4 inverseViewProjection;
    static Vector4 lutInfo, volumeInfo;
    static Vector4[] atmosphereInfo = new Vector4[9];
    static ComputeBuffer starBuffer, constellationBuffer;
    static Vector4 starInfo, jdInfo;
    static Vector4[] solarInfo = new Vector4[20];
    

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
    CommandBuffer buffer;
	Camera camera;
	RenderTextureFormat colorTextureFormat;
	public AtmosphereSetupPass(AtmosphereRenderFeature renderFeature){
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
		bool useHDR = renderingData.cameraData.isHdrEnabled;
		colorTextureFormat = useHDR ?
			RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default;

		if (!renderFeature.onceEveryFrame){
			renderFeature.frameNum = (renderFeature.frameNum + 1) % 1024;
            renderFeature.onceEveryFrame = true;
        }
		
		ProcessDateAndPosition(ref renderingData);
		SetupLastFrame();
        SetupAtmosphere(ref renderingData);
		ConfigureTarget(starMapId);
    }

    // Here you can implement the rendering logic.
    // Use <c>ScriptableRenderContext</c> to issue drawing commands or execute command buffers
    // https://docs.unity3d.com/ScriptReference/Rendering.ScriptableRenderContext.html
    // You don't have to call ScriptableRenderContext.submit, the render pipeline will call it at specific points in the pipeline.
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        buffer.BeginSample("Atmosphere");
		////////////////////////////////////////////////////////////////////////////////
		buffer.BeginSample("Star");
		StarHistory his = renderFeature.m_HistoryCaches[GetCameraID(camera)];
		if(!renderFeature.m_HistoryCaches.ContainsKey(GetCameraID(camera)) || renderFeature.m_HistoryCaches[GetCameraID(camera)] == null){
			Debug.Log("error");
		}
		buffer.SetRenderTarget(starMapId, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
		buffer.ClearRenderTarget(true, true, Color.clear);
        if(atmosphere.settings.long_exposure){
	        if(his.hasHistory){
				buffer.Blit(his.color, starMapId);
			}
			buffer.DrawProcedural(Matrix4x4.identity, atmosphere.MaterialAtmosphere, (int)AtmospherePass.Stars, MeshTopology.Quads, (int)Stars.starDatabase.Length * 4);
			buffer.Blit(starMapId, his.color);
			his.hasHistory = true;
		} else {
	        buffer.DrawProcedural(Matrix4x4.identity, atmosphere.MaterialAtmosphere, (int)AtmospherePass.Stars, MeshTopology.Quads, (int)Stars.starDatabase.Length * 4);
			his.hasHistory = false;
		}
		buffer.SetRenderTarget(starMapId, RenderBufferLoadAction.Load, RenderBufferStoreAction.Store);
		buffer.DrawProcedural(Matrix4x4.identity, atmosphere.MaterialAtmosphere, (int)AtmospherePass.ConstellationLines, MeshTopology.Lines, (int)Stars.constellationData.Length);
        buffer.EndSample("Star");
		////////////////////////////////////////////////////////////////////////////////
		buffer.BeginSample("TransmittanceLut");
		buffer.SetRenderTarget(transmittanceLutId, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
        buffer.DrawProcedural(
			Matrix4x4.identity, atmosphere.MaterialAtmosphere, (int)AtmospherePass.TransmittanceLut,
			MeshTopology.Triangles, 3
		);
        buffer.EndSample("TransmittanceLut");
		////////////////////////////////////////////////////////////////////////////////
        buffer.BeginSample("MultiScat");
        SetupCompute();
        buffer.EndSample("MultiScat");
		////////////////////////////////////////////////////////////////////////////////
		buffer.BeginSample("SkyViewLut");
		RenderBufferLoadAction load = RenderBufferLoadAction.DontCare;
		RenderBufferStoreAction store = RenderBufferStoreAction.Store;
		RenderTargetBinding binding = new RenderTargetBinding(new RenderTargetIdentifier[2]{skyViewLutId, skyViewTransLutId},
			new RenderBufferLoadAction[2]{load, load},
			new RenderBufferStoreAction[2]{store, store},
			skyViewDepthLutId, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.DontCare
		);
		buffer.SetRenderTarget(binding);
        buffer.DrawProcedural(
			Matrix4x4.identity, atmosphere.MaterialAtmosphere, (int)AtmospherePass.SkyViewLut,
			MeshTopology.Triangles, 3
		);
        buffer.EndSample("SkyViewLut");
		////////////////////////////////////////////////////////////////////////////////
		buffer.BeginSample("CameraVolume");
		buffer.SetRenderTarget(cameraVolumeId, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
        buffer.DrawProcedural(
			Matrix4x4.identity, atmosphere.MaterialAtmosphere, (int)AtmospherePass.CameraVolume,
			MeshTopology.Triangles, 3
		);
        buffer.EndSample("CameraVolume");
		////////////////////////////////////////////////////////////////////////////////
		buffer.BeginSample("Sky");
		buffer.SetRenderTarget(skyMapId, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store);
        buffer.DrawProcedural(
			Matrix4x4.identity, atmosphere.MaterialAtmosphere, (int)AtmospherePass.Sky,
			MeshTopology.Triangles, 3
		);
        buffer.EndSample("Sky");
		////////////////////////////////////////////////////////////////////////////////
        buffer.EndSample("Atmosphere");
        context.ExecuteCommandBuffer(buffer);
		buffer.Clear();
    }

    void ProcessDateAndPosition(ref RenderingData renderingData){
		double jd, jdc, jdc_star;
		if (atmosphere.settings.useJD == true) {
			jd = atmosphere.settings.jd_time_n + (double)atmosphere.settings.jd_time_f;
		} else {
			int timezone;
			if (atmosphere.settings.autoTZ){
				Vector2 positionOnEarth = atmosphere.settings.camera_position_on_earth;
				//将经度限制在[-180,180)
				positionOnEarth.x = positionOnEarth.x - Floor((positionOnEarth.x + 180) / 360) * 360;
				//360/24 = 15度一个时区
				timezone = FloorToInt((positionOnEarth.x + 7.5f) / 15);
				atmosphere.settings.timezone = timezone;
			} else {
				timezone = atmosphere.settings.timezone;
			}

			int year, month, day, hour, minute, second;
			Vector3Int Day = atmosphere.settings.Day;
			Vector3Int Time = atmosphere.settings.Time;
			//24小时时间完全按照TOD来
			float TOD = Mathf.Clamp01(atmosphere.settings.TOD24 / 24);
			year = Day.x; month = Day.y; day = Day.z;
			hour = Mathf.FloorToInt(TOD * 24);
			minute = Mathf.FloorToInt((TOD * 24 - hour) * 60);
			second = Mathf.FloorToInt(((TOD * 24 - hour) * 60 - minute) * 60);
			atmosphere.settings.Time = new Vector3Int(hour, minute, second);

			int a = ( month - 14 ) / 12;
			int jdnum =  ( 1461 * (year + 4800 + a)) / 4 +
                    ( 367 * ( month - 2 - 12 *  a ) ) / 12 - 
                    ( 3 * ( ( year + 4900 + a ) / 100 ) ) / 4 +
                    day - 32075;
			double jdfrac = TOD - ((timezone + 12.0) / 24.0);
			jd = jdnum + jdfrac;
			//我们计算mjd来避免一些数值精度的问题
			double mjd = jd - 2451545.0;
			atmosphere.settings.jd_time_n = Mathf.FloorToInt((float)mjd) + 2451545;
			atmosphere.settings.jd_time_f = (float)(mjd - Mathf.FloorToInt((float)mjd));
		}
		//我们的星表数据使用的时间基点是J1991.25，用于算恒星自行
		//而地球自转以及系内行星数据使用的基点是标准的J2000
		//由于shader不支持double，我们再这边先处理数据然后传入shader
		jdc = (jd - 2451545.0) / 36525;
		jdc_star = (jd - atmosphere.settings.stars.jd) / 36525;

		//同样由于数值精度，我们把一些复杂的计算也放在这边进行，同样全都限制在2PI范围内
		double LMST = 4.894961 + 230121.675315 * jdc;
		LMST = LimitedInWholeCircle(LMST);
		double epsilon = 0.409093 - 0.000227 * jdc;
		epsilon = LimitedInWholeCircle(epsilon);

		//这边也计算一下太阳和月亮的坐标，因为都涉及到数值精度
		float M = (float)(LimitedInWholeCircle(6.24 + 628.302 * jdc));
		double lambda_sun, beta_sun, lambda_moon, beta_moon, r_sun, pi_moon;
		lambda_sun = 4.895048 + 628.331951 * jdc + (0.033417 - 0.000084 * jdc) * Sin(M) + 0.000351 * Sin(2*M);
		beta_sun = 0;
		r_sun = 1.000140 - (0.016708 - 0.000042 * jdc) * Cos(M) - 0.000141 * Cos(2*M);
		lambda_sun = LimitedInWholeCircle(lambda_sun);
		beta_sun = LimitedInWholeCircle(beta_sun);
		float ll, mm, m, d, f;
		ll = (float)(LimitedInWholeCircle(3.8104 + 8399.7091 * jdc));
		mm = (float)(LimitedInWholeCircle(2.3554 + 8328.6911 * jdc));
		m = (float)(LimitedInWholeCircle(6.2300 + 628.3019 * jdc));
		d = (float)(LimitedInWholeCircle(5.1985 + 7771.3772 * jdc));
		f = (float)(LimitedInWholeCircle(1.6280 + 8433.4663 * jdc));
		lambda_moon = ll + 0.1098 * Sin(mm) + 0.0222 * Sin(2*d-mm) + 0.0115 * Sin(2*d) + 0.0037 * Sin(2*mm) - 0.0032 * Sin(m)
			- 0.0020 * Sin(2*f) + 0.0010 * Sin(2*d-2*mm) + 0.0010 * Sin(2*d-m-mm) + 0.0009 * Sin(2*d+mm) + 0.0008 * Sin(2*d-m)
			+ 0.0007 * Sin(mm-m) - 0.0006 * Sin(d) - 0.0005 * Sin(m+mm);
		beta_moon = 0.0895 * Sin(f) + 0.0049 * Sin(mm+f) + 0.0048 * Sin(mm-f) + 0.0030 * Sin(2*d-f) + 0.0010 * Sin(2*d+f-mm)
			+ 0.0008 * Sin(2*d-f-mm) + 0.0006 * Sin(2*d+f);
		pi_moon = 0.016593 + 0.000904 * Cos(mm) + 0.000166 * Cos(2*d-mm) + 0.000137 * Cos(2*d) + 0.000049 * Cos(2*mm)
			+ 0.000015 * Cos(2*d+mm) + 0.000009 * Cos(2*d-m);
		lambda_moon = LimitedInWholeCircle(lambda_moon);
		beta_moon = LimitedInWholeCircle(beta_moon);

		//shader这边用的UE坐标系，但是settings里的方向要用Unity坐标
		Vector3 SunVecUE, MoonVecUE;
		if(atmosphere.settings.use_custom_direction){
			float theta, phi;
			theta = atmosphere.settings.sun_direction.x * Mathf.Deg2Rad;
			phi = atmosphere.settings.sun_direction.y * Mathf.Deg2Rad;
			SunVecUE = Spherical2Cartesian(theta, phi);
			theta = atmosphere.settings.moon_direction.x * Mathf.Deg2Rad;
			phi = atmosphere.settings.moon_direction.y * Mathf.Deg2Rad;
			MoonVecUE = Spherical2Cartesian(theta, phi);
			jdc = 0;
			LMST = 0;
			epsilon = 0;
			jdc_star = (jd - atmosphere.settings.stars.jd) / 36525;
		} else {
			SunVecUE = GetDirection((float)lambda_sun, (float)beta_sun);
			MoonVecUE = GetDirection((float)lambda_moon, (float)beta_moon);
		}
		atmosphere.settings.SunVec = UEToUnity(SunVecUE);
        atmosphere.settings.MoonVec = UEToUnity(MoonVecUE);
		atmosphere.settings.MoonVec.y -= (float)pi_moon;
		atmosphere.settings.MoonVec.Normalize();

		//向shader塞数据
		jdInfo = new Vector4(
			(float)jdc,
			(float)LMST,
			(float)epsilon,
			(float)jdc_star
			);
		buffer.SetGlobalVector(jdInfoId,jdInfo);
		//我们将太阳系数据全都传入solarInfo这个结构里
		//其中第一二三个是太阳和月亮
		//pi_moon是1/r_moon，单位为地球半径
		//后面10个分别是行星的位置信息和颜色
		Vector4 temp;
		temp = SunVecUE;
		solarInfo[0] = new Vector4(
			temp.x, temp.y, temp.z,
			0
			);
		temp = MoonVecUE;
		solarInfo[1] = new Vector4(
			temp.x, temp.y, temp.z,
			0
			);
		solarInfo[2] = new Vector4(
			(float)r_sun,
			atmosphere.settings.sun_illuminance,
			(float)pi_moon,
			atmosphere.settings.moon_illuminance
			);
		solarInfo[3] = new Vector4(
			ll,f,
			atmosphere.settings.sun_angle,
			atmosphere.settings.moon_angle
			);
		temp = atmosphere.settings.shadow_color_sun * atmosphere.settings.shadow_color_sun_intensity;
		solarInfo[4] = new Vector4(
			temp.x, temp.y, temp.z,
			0
			);
		temp = atmosphere.settings.far_color * atmosphere.settings.far_color_intensity;
		solarInfo[5] = new Vector4(
			temp.x, temp.y, temp.z,
			0
			);
		solarInfo[6] = new Vector4(
			atmosphere.settings.earth_map_illuminance,
			atmosphere.settings.earth_night_map_illuminance,
			atmosphere.settings.earth_cloud_map_illuminance,
			0
			);
		buffer.SetGlobalVectorArray(solarInfoId, solarInfo);

		//因为SRP中有些矩阵没有设置，我们需要自己传给shader
		Matrix4x4 View = renderingData.cameraData.GetViewMatrix();
        Matrix4x4 Project = renderingData.cameraData.GetGPUProjectionMatrix();
        //Debug.Log(renderingData.cameraData.IsCameraProjectionMatrixFlipped());
		//为了防止相机高度太高导致数值精度问题，我们将平移从View里面除去
		View.SetColumn(3,new Vector4(0,0,0,1));
		Matrix4x4 ViewProjection = Project * View;
        inverseViewProjection = Matrix4x4.Inverse(ViewProjection);
		buffer.SetGlobalMatrix(inverseViewAndProjectionMatrix, inverseViewProjection);
		buffer.SetGlobalMatrix(ViewAndProjectionMatrix, ViewProjection);
	}

	double LimitedInWholeCircle(double Angle){
		double WholeCircle = (double)(2 * Mathf.PI);
		Angle = Angle / WholeCircle;
		int cycles = Mathf.FloorToInt((float)Angle);
		Angle = Angle - cycles;
		Angle = Angle * WholeCircle;
		return Angle;
	}
    void SetupAtmosphere(ref RenderingData renderingData){
        buffer.SetGlobalTexture(earthMapId, atmosphere.settings.earth_map);
		buffer.SetGlobalTexture(earthCloudMapId, atmosphere.settings.earth_cloud_map);
		buffer.SetGlobalTexture(earthNightMapId, atmosphere.settings.earth_night_map);
		buffer.SetGlobalTexture(moonMapId, atmosphere.settings.moon_map);
		buffer.SetGlobalTexture(farMapId, atmosphere.settings.far_map);

		Vector4 temp;
		lutInfo = new Vector4(
			atmosphere.settings.transmittanceWidth,
			atmosphere.settings.transmittanceHeight,
			atmosphere.settings.skyViewWidth,
			atmosphere.settings.skyViewHeight
			);
		volumeInfo = new Vector4(
			atmosphere.settings.cameraVolumeRes,
			atmosphere.settings.multiScatRes,
			atmosphere.settings.MultipleScatteringFactor,
			0
			); 
		atmosphereInfo[0] = new Vector4(
			atmosphere.settings.top_radius,
			atmosphere.settings.bottom_radius,
			atmosphere.settings.sky_sun_illuminance,
			0
			);
		temp = atmosphere.settings.rayleigh_scattering;
		temp = temp * (atmosphere.settings.rayleigh_scattering_intensity);
		atmosphereInfo[1] = new Vector4(
			temp.x, temp.y, temp.z,
			atmosphere.settings.rayleigh_scale_height
			);
		temp = atmosphere.settings.mie_scattering;
		temp = temp * (atmosphere.settings.mie_scattering_intensity);
		atmosphereInfo[2] = new Vector4(
			temp.x, temp.y, temp.z,
			atmosphere.settings.mie_scale_height
			);
		temp = atmosphere.settings.mie_absorption;
		temp = temp * (atmosphere.settings.mie_absorption_intensity);
		atmosphereInfo[3] = new Vector4(
			temp.x, temp.y, temp.z,
			atmosphere.settings.mie_phase_function_g
			);
		temp = atmosphere.settings.absorption_extinction;
		temp = temp * (atmosphere.settings.absorption_extinction_intensity);
		atmosphereInfo[4] = new Vector4(
			temp.x, temp.y, temp.z,
			atmosphere.settings.ozone_width
			);
		atmosphereInfo[5] = atmosphere.settings.ozone_info;
		atmosphereInfo[6] = atmosphere.settings.ground_albedo.linear;
		atmosphereInfo[7] = atmosphere.settings.camera_position_on_earth / 180.0f * 3.14159265358f;
		atmosphereInfo[8] = new Vector4(
			(atmosphere.settings.sun_direction / 180.0f * Mathf.PI).x,
			(atmosphere.settings.sun_direction / 180.0f * Mathf.PI).y,
			(atmosphere.settings.moon_direction / 180.0f * Mathf.PI).x,
			(atmosphere.settings.moon_direction / 180.0f * Mathf.PI).y
			);
		buffer.SetGlobalVector(lutInfoId, lutInfo);
		buffer.SetGlobalVector(volumeInfoId, volumeInfo);
		buffer.SetGlobalVectorArray(atmosphereInfoId, atmosphereInfo);
		
		buffer.GetTemporaryRT(
			transmittanceLutId, (int)lutInfo.x, (int)lutInfo.y,
			0, FilterMode.Bilinear, colorTextureFormat
		);
		buffer.GetTemporaryRT(
			skyViewLutId, (int)lutInfo.z, (int)lutInfo.w,
			0, FilterMode.Bilinear, colorTextureFormat
		);
		buffer.GetTemporaryRT(
			skyViewTransLutId, (int)lutInfo.z, (int)lutInfo.w,
			0, FilterMode.Bilinear, colorTextureFormat
		);
		buffer.GetTemporaryRT(
			skyViewDepthLutId, (int)lutInfo.z, (int)lutInfo.w,
			32, FilterMode.Point, RenderTextureFormat.Depth
		);
		buffer.GetTemporaryRT(
			cameraVolumeId, (int)volumeInfo.x * (int)volumeInfo.x, (int)volumeInfo.x,
			0, FilterMode.Bilinear, colorTextureFormat
		);
		buffer.GetTemporaryRT(
			skyMapId, camera.pixelWidth, camera.pixelHeight,
			0, FilterMode.Bilinear, colorTextureFormat
		);
        //因为这张贴图要CS做，所以要设置RW
		RenderTextureDescriptor multiScatDesc = new RenderTextureDescriptor(
			(int)volumeInfo.y, (int)volumeInfo.y, colorTextureFormat, 0
			);
		multiScatDesc.enableRandomWrite = true;
		buffer.GetTemporaryRT(multiScatId, multiScatDesc, FilterMode.Bilinear);

		//这边设置star的参数，星星大小我们要用到fov的信息
		Stars = atmosphere.settings.stars;
		float size = Mathf.Tan(atmosphere.settings.star_size / 2 * Mathf.Deg2Rad) / Mathf.Tan(camera.fieldOfView / 2 * Mathf.Deg2Rad);
		starInfo = new Vector4(
			size,
			atmosphere.settings.star_illuminance,
			atmosphere.settings.constellation_illuminance,
			atmosphere.settings.far_map_illuminance
		);
		buffer.SetGlobalVector(starInfoId, starInfo);
		//这边比较特殊，在于没办法在buffer中申请computeBuffer
		//但是不使用buffer，那么所有命令就会立即执行，和buffer不同步，所以我们computeBuffer的release我们要拖到下一帧
		if (starBuffer != null){
			//Debug.Log("buffer released");
			starBuffer.Release();
		}
		starBuffer = new ComputeBuffer((int)Stars.starDatabase.Length, 8 * sizeof(float));
		buffer.SetBufferData(starBuffer, Stars.starDatabase);
		buffer.SetGlobalBuffer(starsId, starBuffer);
		//star图也通过CS来算，并且一开始需要将这张图置零
		//后来我换了一种方法，还是渲染星星的billboard
		RenderTextureDescriptor starMapDesc = new RenderTextureDescriptor(
			camera.pixelWidth, camera.pixelHeight, colorTextureFormat, 0
			);
		//starMapDesc.enableRandomWrite = true;
		buffer.GetTemporaryRT(starMapId, starMapDesc, FilterMode.Bilinear);

		if (constellationBuffer != null){
			//Debug.Log("buffer released");
			constellationBuffer.Release();
		}
		constellationBuffer = new ComputeBuffer((int)Stars.constellationData.Length, sizeof(int));
		buffer.SetBufferData(constellationBuffer, Stars.constellationData);
		buffer.SetGlobalBuffer(constellationsId, constellationBuffer);
    }

    void SetupCompute(){
		ComputeShader atmosphereComputeShader = atmosphere.atmosphereComputeShader;
		int kernelHandle = atmosphereComputeShader.FindKernel("MultiScattCS");
		buffer.SetComputeTextureParam(atmosphereComputeShader, kernelHandle, multiScatId, multiScatId);
		buffer.SetComputeTextureParam(atmosphereComputeShader, kernelHandle, transmittanceLutId, transmittanceLutId);
		buffer.SetComputeVectorParam(atmosphereComputeShader, lutInfoId, lutInfo);
		buffer.SetComputeVectorParam(atmosphereComputeShader, volumeInfoId, volumeInfo);
		buffer.SetComputeVectorArrayParam(atmosphereComputeShader, atmosphereInfoId, atmosphereInfo);
		buffer.DispatchCompute(atmosphereComputeShader, kernelHandle,(int)volumeInfo.y,(int)volumeInfo.y,1);
	}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

    public void Dispose(){
        if (starBuffer != null){
            //Debug.Log("buffer released");
            starBuffer.Release();
        }
        if (constellationBuffer != null){
            //Debug.Log("buffer released");
            constellationBuffer.Release();
        }
    }
    // Cleanup any allocated resources that were created during the execution of this render pass.
    public override void OnCameraCleanup(CommandBuffer cmd)
    {
		renderFeature.onceEveryFrame = false;
		buffer.ReleaseTemporaryRT(transmittanceLutId);
        buffer.ReleaseTemporaryRT(skyViewLutId);
        buffer.ReleaseTemporaryRT(skyViewTransLutId);
        buffer.ReleaseTemporaryRT(skyViewDepthLutId);
        buffer.ReleaseTemporaryRT(cameraVolumeId);
		buffer.ReleaseTemporaryRT(skyMapId);
        buffer.ReleaseTemporaryRT(multiScatId);
        buffer.ReleaseTemporaryRT(starMapId);
    }

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
	bool SetupLastFrame(){
        #region BeginStarSetup
        int cameraId = GetCameraID(camera);
        var m_HistoryCaches = renderFeature.m_HistoryCaches;
		//首先无论如何，如果没有历史信息，就新建一张历史贴图
        if (!m_HistoryCaches.ContainsKey(cameraId) || m_HistoryCaches[cameraId] == null)
        {
            StarHistory his = new StarHistory();
            his.color = RenderTexture.GetTemporary(camera.pixelWidth, camera.pixelHeight, 0, colorTextureFormat);
            his.color.name = "_LongExpStar";
            his.hasHistory = false;
            m_HistoryCaches.Add(cameraId, his);
            return false;
        } else {
            StarHistory his = m_HistoryCaches[cameraId];
			//如果大小不匹配历史信息，也新建一张历史贴图
            if(his.color == null || his.color.width != camera.pixelWidth || his.color.height != camera.pixelHeight){
                his.color.Release();
                his.color = RenderTexture.GetTemporary(camera.pixelWidth, camera.pixelHeight, 0, colorTextureFormat);
                his.color.name = "_LongExpStar";
                his.hasHistory = false;
                return false;
            } else {
				//如果有大小匹配的历史信息，但是没开长曝光，就擦除历史信息
				if(!atmosphere.settings.long_exposure){
					his.hasHistory = false;
					return false;
				} else {
					//如果有大小匹配的历史信息，就什么都不动，保持原来
					//有history就说明上一帧设置过了，没有那么就说明这是第一帧
					return his.hasHistory;
				}
            }
        }
        #endregion //SetupStar
    }

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//这边存一些空间转换函数，这批函数在shader中存了一份，但是我们因为要在unity中同步太阳坐标，这些计算在C#中也要算一份
//我这边不高兴优化了，就两边都算一遍

    Matrix4x4 GetCameraMatrix() {
        //经度
        float cosPhi = Cos(atmosphereInfo[7].x);
        float sinPhi = Sin(atmosphereInfo[7].x);
        //纬度
        float cosTheta = Cos(atmosphereInfo[7].y);
        float sinTheta = Sin(atmosphereInfo[7].y);
        return new Matrix4x4(
            new Vector4(-sinTheta * cosPhi, sinTheta * sinPhi, cosTheta),
            new Vector4(-sinPhi, -cosPhi, 0),
            new Vector4(cosTheta * cosPhi, -cosTheta * sinPhi, sinTheta),
            Vector4.zero
        );
    }

    Vector3 Spherical2Cartesian(float phi, float theta){
        return Vector3.Normalize(new Vector3(
            Cos(phi) * Cos(theta),
            -Sin(phi) * Cos(theta),
            Sin(theta)
        ));
    }

    Vector3 Rx(Vector3 input, float rad){
        float CosRad = Cos(rad);
        float SinRad = Sin(rad);
        Matrix4x4 rotate = new Matrix4x4(
            new Vector4(1,0,0),
            new Vector4(0,CosRad,-SinRad),
            new Vector4(0,-SinRad,CosRad),
            Vector4.zero
        );
        return rotate * input;
    }
    Vector3 Ry(Vector3 input, float rad){
        float CosRad = Cos(rad);
        float SinRad = Sin(rad);
        Matrix4x4 rotate = new Matrix4x4(
            new Vector4(CosRad,0,-SinRad),
            new Vector4(0,1,0),
            new Vector4(SinRad,0,CosRad),
            Vector4.zero
        );
        return rotate * input;
    }
    Vector3 Rz(Vector3 input, float rad){
        float CosRad = Cos(rad);
        float SinRad = Sin(rad);
        Matrix4x4 rotate = new Matrix4x4(
            new Vector4(CosRad,-SinRad,0),
            new Vector4(SinRad,CosRad,0),
            new Vector4(0,0,1),
            Vector4.zero
        );
        return rotate * input;
    }
    Vector3 TransformLocalToEarth(Vector3 input){
        return GetCameraMatrix() * input;
    }
    Vector3 TransformEarthToLocal(Vector3 input){
        return GetCameraMatrix().transpose * input;
    }
    Vector3 TransformICRSToEarth(Vector3 input){
        Vector3 output = input;
        float jdc = jdInfo.x;
        float LMST = jdInfo.y;
        //Precession
        output = Rz(output, 0.01118f * jdc);
        output = Ry(output, -0.00972f * jdc);
        output = Rz(output, 0.01118f * jdc);

        output = Rz(output, - LMST);
        return output;
    }
    Vector3 TransformEarthToICRS(Vector3 input){
        Vector3 output = input;
        float jdc = jdInfo.x;
        float LMST = jdInfo.y;
        output = Rz(output, LMST);
        //Precession
        output = Rz(output, -0.01118f * jdc);
        output = Ry(output, 0.00972f * jdc);
        output = Rz(output, -0.01118f * jdc);

        return output;
    }

    Vector3 TransformEclipticToICRS(Vector3 input){
        Vector3 output = input;
        float epsilon = jdInfo.z;
        output = Rx(output, epsilon);
        return output;
    }
    Vector3 TransformICRSToEcliptic(Vector3 input){
        Vector3 output = input;
        float epsilon = jdInfo.z;
        output = Rx(output, -epsilon);
        return output;
    }

    //(1,0,0)对应在uv的(0.5,0.5)
    //西经90线u为0，东经90线u为1
    //北极点v为1，南极点v为0
    void SphericalToUv(in Vector3 Spherical, out Vector2 uv){
        float Theta = Asin(Clamp(Spherical.z, -1, 1));
        float RAYDPOS = 0.0001f;
        Vector2 tempView = new Vector2(Spherical.x + RAYDPOS, Spherical.y + RAYDPOS);
        tempView.Normalize();
        float Phi = Acos(Clamp((tempView.x),-1,1));
        if (tempView.y > 0) {
            Phi = -Phi;
        }
        uv = new Vector2(Clamp01((Phi + PI) / (2 * PI)), Clamp01((Theta + PI / 2) / PI));
    }

    Vector3 UnityToUE(Vector3 unityPos){
        return new Vector3(unityPos.z,unityPos.x,unityPos.y);
    }
    Vector3 UEToUnity(Vector3 UEPos){
        return new Vector3(UEPos.y,UEPos.z,UEPos.x);
    }

    Vector3 GetDirection(float lambda,float beta){
        Vector3 Dir = Spherical2Cartesian(lambda, beta);
        Dir = TransformEclipticToICRS(Dir);
        Dir = TransformICRSToEarth(Dir);
        Dir = TransformEarthToLocal(Dir);
        return Dir;
    }
}