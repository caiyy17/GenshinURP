# 大气以及星空

## 大气部分

大气部分为 UE 的代码，使用散射的近似计算，要注意 UE 坐标系与 Unity 坐标系的转换，同时也要注意千米坐标与常用的米坐标的转换。

## 星空部分

星空部分使用 HIP 的星表，存在 star structure 中，暂时只用了六等星的数据，一共 5000 颗左右，星座使用 stellarium 的数据，只画了十二星座。为了方便观察，标绿了北斗星，添加了猎户座。

1. 支持使用日期，地球经纬坐标计算星星，日月的位置。支持使用星表数据的星等和 BV 颜色计算 RGB 颜色。星星使用贴片方式进行渲染，大小设置单位为可视夹角。

2. 支持日食的效果，会在地球上投下阴影，这时太阳颜色会变为设定好的 shadow color

3. 支持延时摄影效果，可以绘制星轨

（TODO）若想使用不同形状的星星，给星星 shader 添加贴图即可，同时可以对星等小于某个值的星星绘制更大的贴图。

（TODO）添加关于太阳系行星位置的计算与渲染，使用与星星相同的贴片方式。

（TODO）添加日冕的渲染，添加月食的渲染，添加极光的渲染

## 贴图部分

月亮以及行星贴图取自 stellarium，月亮贴图包括了 normal。地球贴图来自 NASA 的 visible Earth 计划，包括白天和晚上。并且支持根据时间在白天与晚上的地球贴图切换。

（TODO）对于超大型贴图建立 VirtualTexture 的结构，使得每个分辨率都可以正常显示

（TODO）根据高度融合带有云层的地球表面与没有云层的地球表面，根据 specular 贴图渲染地球材质，根据高度图建立地球表面建模
