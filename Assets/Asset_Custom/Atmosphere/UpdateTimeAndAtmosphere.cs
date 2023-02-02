using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteAlways]
public class UpdateTimeAndAtmosphere : MonoBehaviour
{
    [SerializeField]
    public Atmosphere atmosphere;
    [Header("Time")]
    public bool updatetime = false;
    public bool realtime = false;
    public bool proceedtime = false;
    public float speed = 1;
    [Range(0,24)]
    public float TOD24 = 0;
    [Header("Light")]

    [SerializeField]
    public Light mainlight;
    public bool updatelight = false;
    public float SunIntensity = 1;
    public Color SunColor = Color.white;
    public float MoonIntensity = 0.5f;
    public Color MoonColor = Color.white;
    
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        if(updatelight){
            Vector3 SunVec = atmosphere.settings.SunVec;
            Vector3 MoonVec = atmosphere.settings.MoonVec;
            float lightTestSun = SunVec.y;
            float lightTestMoon = MoonVec.y;
            float SdotM = SunVec.x * MoonVec.x + SunVec.y * MoonVec.y + SunVec.z * MoonVec.z;

            float SunMoonInteract = 1;
            if(lightTestSun > -0.05f){
                //日食
                float halfRad = (atmosphere.settings.sun_angle + atmosphere.settings.moon_angle) * Mathf.Deg2Rad / 2;
                float fade = atmosphere.settings.shadow_color_sun_intensity;
                fade = Mathf.Clamp01((Mathf.Acos(SdotM)) / halfRad) * (1 - fade) + fade;
                mainlight.transform.forward = -atmosphere.settings.SunVec;
                mainlight.intensity = SunIntensity * Mathf.Clamp01(1 + lightTestSun / 0.05f) * fade;
                mainlight.color = SunColor * fade + (1 - fade) * atmosphere.settings.shadow_color_sun;
            }
            else if(lightTestMoon > -0.05f){
                //盈满
                float fade = 0.15f + 0.85f * ((-SdotM + 1.0f) / 2.0f);
                SunMoonInteract = Mathf.Clamp01((-lightTestSun - 0.05f) / 0.05f);
                mainlight.transform.forward = -atmosphere.settings.MoonVec;
                mainlight.intensity = MoonIntensity * Mathf.Clamp01(1 + lightTestMoon / 0.05f) * SunMoonInteract * fade;
                mainlight.color = MoonColor;
            }
            else{
                mainlight.transform.forward = new Vector3(0,-1,0);
                mainlight.intensity = 0.01f;
                mainlight.color = MoonColor;
            }
        }
        // Debug.Log("update");
        if(updatetime){
            if(realtime){ //使用UTC时间并加上时区
                System.DateTime time = System.DateTime.UtcNow;
                time = time.AddHours(atmosphere.settings.timezone);
                TOD24 = Mathf.Clamp01((float)time.TimeOfDay.TotalDays) * 24;
                atmosphere.settings.Day = new Vector3Int(time.Year, time.Month, time.Day);
                atmosphere.settings.Time = new Vector3Int(time.Hour, time.Minute, time.Second);
            } else if (proceedtime) { //现有的时间上进行更改
                System.DateTime time = new System.DateTime(atmosphere.settings.Day.x, atmosphere.settings.Day.y, atmosphere.settings.Day.z,
                    0,0,0);
                time = time.AddSeconds(speed * Time.deltaTime);
                time = time.AddDays(TOD24 / 24);
                TOD24 = Mathf.Clamp01((float)time.TimeOfDay.TotalDays) * 24;
                atmosphere.settings.Day = new Vector3Int(time.Year, time.Month, time.Day);
                atmosphere.settings.Time = new Vector3Int(time.Hour, time.Minute, time.Second);
                //atmosphere.settings.camera_position_on_earth.x += 20 * Time.deltaTime;
            }
            atmosphere.settings.TOD24 = TOD24;
        }
        else {
            TOD24 = atmosphere.settings.TOD24;
        }
    }
    void OnDrawGizmos()
   {
      // Your gizmo drawing thing goes here if required...
#if UNITY_EDITOR
      // Ensure continuous Update calls.
      if (!Application.isPlaying)
      {
         UnityEditor.EditorApplication.QueuePlayerLoopUpdate();
         UnityEditor.SceneView.RepaintAll();
      }
#endif
   }
}
