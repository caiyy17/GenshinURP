using System;
using UnityEngine;
public class HistoryInfo {
    public bool hasHistory = false;
    public RenderTexture color, depth;
    public Matrix4x4 matrix_LastViewProj = Matrix4x4.identity;
}