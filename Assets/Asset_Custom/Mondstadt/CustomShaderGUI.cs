using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;

public class CustomShaderGUI : ShaderGUI {

    //我们需要的内容有
    //editor是unity可以修改材质的接口
    //materials是所有共享这个material的material，这样改一个，这个mat会同步更新
    //properties是这个shader里面存的所有property的列表
    MaterialEditor editor;
	Object[] materials;
	MaterialProperty[] properties;

	public override void OnGUI (
		MaterialEditor materialEditor, MaterialProperty[] properties
	) {
		//默认的onGUI，理论上这个函数会把所有shader的控制参数显示在GUI里
		base.OnGUI(materialEditor, properties);
        editor = materialEditor;
		materials = materialEditor.targets;
		this.properties = properties;
        MaterialProperty mainTex = FindProperty("_MainTex", properties, false);
		MaterialProperty baseMap = FindProperty("_BaseMap", properties, false);
		baseMap.textureValue = mainTex.textureValue;
		baseMap.textureScaleAndOffset = mainTex.textureScaleAndOffset;
    }

}
