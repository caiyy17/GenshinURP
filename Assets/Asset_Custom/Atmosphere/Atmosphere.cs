using System;
using UnityEngine;

[CreateAssetMenu(menuName = "Rendering/Custom Atmosphere")]
public class Atmosphere : ScriptableObject {

	//大气渲染需要shader和compute shader，都在这边定义一下
	[Space(20)]
	[Header("AtmosphereSettings")]
	[SerializeField]
	Shader atmosphereShader = default;
	[SerializeField]
	public ComputeShader atmosphereComputeShader = default;

	[NonSerialized]
	Material materialAtmosphere;

	public Material MaterialAtmosphere {
		get {
			if (materialAtmosphere == null && atmosphereShader != null) {
				materialAtmosphere = new Material(atmosphereShader);
				materialAtmosphere.hideFlags = HideFlags.HideAndDontSave;
			}
			return materialAtmosphere;
		}
	}
	//这边是大气参数
	//把参数都在这边定义好，之后送到shader里去，这样就能实时更改了
	[Serializable]
	public struct AtmosphereSettings {
		public bool useAtmosphere;
		[Space(20)]
		[Header("Tex Resolution")]
		public int transmittanceWidth;
		public int transmittanceHeight;
		public int skyViewWidth;
		public int skyViewHeight;
		public int cameraVolumeRes;
		public int multiScatRes;
		[Space(20)]
		[Header("Env Constants")]
		public float MultipleScatteringFactor;
		public float top_radius;
		public float bottom_radius;
		public float sky_sun_illuminance;
		public float rayleigh_scale_height;
		public float mie_scale_height;
		public float mie_phase_function_g;
		public float ozone_width;
		public Vector4 ozone_info;


		//单位是 1/km
		[ColorUsage(false)]
		public Color rayleigh_scattering;
		[Range(0f, 0.1f)]
		public float rayleigh_scattering_intensity;
		[ColorUsage(false)]
		public Color mie_scattering;
		[Range(0f, 0.1f)]
		public float mie_scattering_intensity;
		[ColorUsage(false)]
		public Color mie_absorption;
		[Range(0f, 0.1f)]
		public float mie_absorption_intensity;
		[ColorUsage(false)]
		public Color absorption_extinction;
		[Range(0f, 0.1f)]
		public float absorption_extinction_intensity;
		[ColorUsage(false)]
		public Color ground_albedo;
		[ColorUsage(false)]
		public Color shadow_color_sun;
		[Range(0f, 1f)]
		public float shadow_color_sun_intensity;
		public bool use_custom_direction;
		public Vector2 sun_direction;
		public Vector2 moon_direction;
		public Vector2 camera_position_on_earth;

		[Space(20)]
		[Header("StarAndTimeSettings")]
		public bool useJD;
		public int jd_time_n;
		[Range(0f, 1f)]
		public float jd_time_f;

		public bool autoTZ;
		public Vector3Int Day;
		public Vector3Int Time;
		[Range(0.0f, 24.0f)]
		public float TOD24;
		[Range(-12,12)]
		public int timezone;

		[Min(0.0f)]
		public float sun_illuminance;
		[Min(0.0f)]
		public float sun_angle;
		[Min(0.0f)]
		public float moon_illuminance;
		[Min(0.0f)]
		public float moon_angle;
		public bool long_exposure;
		[Min(0.0f)]
		public float star_size;
		[Min(0.0f)]
		public float star_illuminance;
		[Min(0.0f)]
		public float constellation_illuminance;

		[Space(20)]
		[Header("TextureSettings")]
		public Texture2D earth_map;
		[Min(0.0f)]
		public float earth_map_illuminance;
		public Texture2D earth_night_map;
		[Min(0.0f)]
		public float earth_night_map_illuminance;
		public Texture2D earth_cloud_map;
		[Min(0.0f)]
		public float earth_cloud_map_illuminance;
		public Texture2D moon_map;
		public Texture2D far_map;
		[Min(0.0f)]
		public float far_map_illuminance;
		[ColorUsage(false)]
		public Color far_color;
		[Range(0f,1f)]
		public float far_color_intensity;

		public StarStructure stars;
		
		
		[Space(20)]
		[Header("SunAndMoonDirection")]
		public Vector3 SunVec;
		public Vector3 MoonVec;

	}
	[SerializeField]
	public AtmosphereSettings settings = new AtmosphereSettings {
		useAtmosphere = true,
		transmittanceWidth = 256,
		transmittanceHeight = 64,
		skyViewWidth = 200,
		skyViewHeight = 100,
		cameraVolumeRes = 32,
		multiScatRes = 32,
		MultipleScatteringFactor = 1.0f,

		top_radius = 6420.0f,
		bottom_radius = 6360.0f,
		sky_sun_illuminance = 10.0f,
		rayleigh_scale_height = 8.0f,
		mie_scale_height = 1.2f,
		mie_phase_function_g = 0.8f,
		ozone_width = 25.0f,
		ozone_info = new Vector4(-2.0f/3, 1.0f/15, 8.0f/3, -1.0f/15),
		//单位是 1/km
		rayleigh_scattering = new Vector4(0.175287f, 0.409607f, 1.0f),
		rayleigh_scattering_intensity = 0.0331f,
		mie_scattering = new Vector4(1.0f, 1.0f, 1.0f, 1.0f),
		mie_scattering_intensity = 0.003996f,
		mie_absorption = new Vector4(1.0f, 1.0f, 1.0f, 1.0f),
		mie_absorption_intensity = 0.000444f,
		absorption_extinction = new Vector4(0.345561f, 1.0f, 0.045189f),
		absorption_extinction_intensity = 0.001881f,
		ground_albedo = new Vector4(0.6667f, 0.6667f, 0.6667f),
		shadow_color_sun = new Vector4(1.0f, 0.3333f, 0.1333f),
		shadow_color_sun_intensity = 0.15f,
		use_custom_direction = false,
		sun_direction = new Vector2(0,0),
		moon_direction = new Vector2(0,0),
		camera_position_on_earth = new Vector3(121,31),

        useJD = false,
		jd_time_n = 2451545,
		jd_time_f = 0,
		autoTZ = true,
		Day = new Vector3Int(2022,1,1),
		Time = new Vector3Int(0,0,0),
		TOD24 = 0,
		timezone = 8,

		sun_illuminance = 100,
		sun_angle = 0.505f,
		
		moon_illuminance = 5,
		moon_angle = 0.505f,

		stars = new StarStructure(),
		long_exposure = false,
		star_size = 0.5f,
		star_illuminance = 10,
		constellation_illuminance = 0.07f,
		far_map_illuminance = 1,
		far_color = new Vector4(0.08f,0.25f,1.0f),
		far_color_intensity = 0.3f,
		earth_map_illuminance = 1,
		earth_night_map_illuminance = 1,
		earth_cloud_map_illuminance = 1

	};
	//public AtmosphereSettings Atmosphere => atmosphere;
}