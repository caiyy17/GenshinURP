using System;
using UnityEngine;

[CreateAssetMenu(menuName = "Rendering/Custom SSR")]
public class SSRSettings : ScriptableObject {
	public enum FilterMode {
		PCF2x2, PCF3x3, PCF5x5, PCF7x7
	}

    [Space(20)]
	[Header("SSRSettings")]
	[Space(20)]
	[Header("Shader")]
	[SerializeField]
    public Shader deferShader = default;
	[SerializeField]
    public Shader PCSSShader = default;
	[SerializeField]
	public ComputeShader PyramidDepthShader = default;
	[SerializeField]
	public ComputeShader FroxelComputeShader = default;

    Material deferMatertial;
	public Material DeferMatertial {
		get {
			if (deferMatertial == null && deferShader != null) {
				deferMatertial = new Material(deferShader);
				deferMatertial.hideFlags = HideFlags.HideAndDontSave;
			}
			return deferMatertial;
		}
	}
	Material pcssMatertial;
	public Material PCSSMatertial {
		get {
			if (pcssMatertial == null && PCSSShader != null) {
				pcssMatertial = new Material(PCSSShader);
				pcssMatertial.hideFlags = HideFlags.HideAndDontSave;
			}
			return pcssMatertial;
		}
	}
	[Space(20)]
	[Header("HiZ and Froxel")]
	public int mipCountMax = 12;
    public int froxelMipLevel = 7,
        froxelSlice = 32,
		maxLightCount = 1024,
		maxFroxelLightAve = 4;
	public float froxelMaxDepth = 500;
	[Space(20)]
	[Header("PCSS")]
	public bool enablePCSS = true;
	public FilterMode shadowFilter = FilterMode.PCF3x3;
	public int shadowMipLevel = 2;
	public float depthTestAngle = 2,
		PCSSAngle = 5;
	public float maxSoftDepth = 10;
	public int testCount = 16;
	[Space(20)]
	[Header("TAA")]
	public bool enableJitter = true;

}
