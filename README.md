# HyperOS3AutoLTPO

为 Xiaomi 13 Ultra（代号 `ishtar`）补全 HyperOS 3 的 1–120Hz LTPO 能力。

作者：[Dreams-Possible](https://github.com/Dreams-Possible)

本仓库包含两个彼此独立的部分：

```text
Auto模块：允许系统在60Hz和120Hz档启用AUTO刷新率策略
实验DTBO：补全面板AUTO120的DDIC命令，使真实扫描范围达到1–120Hz
```

## 实测环境

```text
设备：Xiaomi 13 Ultra
代号：ishtar
地区：中国版
系统：HyperOS 3.0
系统版本：OS3.0.306.0.WMACNXM
Android：16
面板节点：mdss_dsi_m1_42_02_0a_dsc_cmd
Panel build ID：0x90
物理分辨率：1440 x 3200
```

系统设置中的1080p属于 Android 渲染尺寸 override，仍使用同一套1440 × 3200物理面板时序，因此不需要单独制作FHD版DTBO。

## Auto模块

模块通过 `system.prop` 设置：

```properties
# 允许60Hz和120Hz档启用系统自动刷新率策略
ro.vendor.mi_sf.supported_automode_maxfps_list=60,120
```

模块本身不会修改或刷写DTBO，也不会在运行时发送MIPI命令。它只负责允许小米修改版 SurfaceFlinger 在60Hz、120Hz两个系统档位使用AUTO策略。

模块源文件位于独立目录：

```text
HyperOS3AutoLTPO/module.prop
HyperOS3AutoLTPO/system.prop
HyperOS3AutoLTPO/META-INF/com/google/android/update-binary
HyperOS3AutoLTPO/META-INF/com/google/android/updater-script
```

仓库根目录同时提供已经打包好的模块：

```text
HyperOS3AutoLTPO.zip
```

ZIP内部直接以 `module.prop`、`system.prop` 和 `META-INF/` 为根，没有额外嵌套模块文件夹，可由 Magisk/KernelSU 模块管理器直接安装。模块仍不会自动刷写DTBO。

## 实验DTBO

```text
文件：dtbo/ishtar_OS3.0.306.0.WMACNXM_AUTO_1-120Hz_dtbo_a.img
大小：25165824 bytes
SHA-256：c121a59d66668d93e5504cdacc0ba9846244fe80a5aa4391e2513fb91c435189
```

该文件是完整 `dtbo_a` 分区镜像，不是通用补丁。它以 `OS3.0.306.0.WMACNXM` 当前槽位的原始DTBO为基础，只修改 ishtar M1 面板所在的 DTBO 条目06和07。

不要用于其他机型、其他面板、其他系统版本或未经核对的另一槽位。系统升级后不得默认继续刷入，应重新提取新版DTBO并核对面板节点及原始字节。

## 原厂限制

原厂AUTO节点为：

```text
timing@wqhd_auto_mode_60_1hz_index_08
```

原厂虽然允许面板最低下降到1Hz，但AUTO模式的真实最高扫描率被DDIC命令限制在60Hz。单独把以下元数据从60改成120，只会让 SurfaceFlinger 显示 `AUTO 120`，面板硬件仍只能达到60Hz：

```text
mi,mdss-dsi-sf-framerate
qcom,mdss-dsi-panel-framerate
```

因此必须同时修改模式元数据和面板 `26/2F/BA/BC` 命令。

## 成功方案

目标节点在 DTBO 条目06、07中各修改一次：

```text
timing@wqhd_auto_mode_60_1hz_index_08
```

### 模式元数据

```text
mi,mdss-dsi-sf-framerate：60 -> 120
qcom,mdss-dsi-panel-framerate：60 -> 120
mi,mdss-dsi-ddic-min-framerate：1 -> 60
qcom,mdss-dsi-h-sync-skew：0x9e01 -> 0xbc3c
```

该驱动使用 `h-sync-skew` 同时编码模式类型、SurfaceFlinger刷新率和最低刷新率：

```text
(AUTO << 14) | (120 << 7) | 60 = 0xbc3c
```

### 主DDIC命令

`qcom,mdss-dsi-on-command` 和 `qcom,mdss-dsi-timing-switch-command` 同步修改：

```text
# 使用M1自身普通120Hz的非flat基准
26 03 -> 26 02

# AUTO刷新参数
保留第一条 2F 00
第二条 2F 30 -> 2F 00

# 自适应刷新参数表
BA 91 0B 03 00 11 77 77 00 05
->
BA 91 01 01 00 01 01 01 00 00

# timing-switch中的原厂BA略有不同，也单独替换
BA 91 0B 01 00 11 77 77 00 05
->
BA 91 01 01 00 01 01 01 00 00

# TE基准由60Hz切换为120Hz
BC 20 -> BC 00
```

最终工作的核心组合为：

```text
26 02
2F 00
2F 00
BA 91 01 01 00 01 01 01 00 00
BC 00
```

### Flat模式

系统切换flat状态时可能重新写入 `26`，因此同步修改：

```text
flat关闭：26 03 -> 26 02
flat开启：26 01 -> 26 00
Gamma 26映射：<1 3> -> <0 2>
```

## 生成方式

使用原位二进制补丁，而不是反编译后重新编译整个DTBO：

```text
1. 校验Android DTBO头和条目表
2. 只进入条目06、07
3. 解析条目内部FDT结构块和字符串表
4. 只匹配目标AUTO节点及指定属性
5. 每个原值必须精确命中一次
6. 所有替换保持相同字节长度
7. 保持条目偏移、条目大小和完整镜像大小不变
8. 重新提取条目并通过DTC反编译校验
```

成功镜像相对原始DTBO：

```text
修改字节总数：52 bytes
条目06：26 bytes
条目07：26 bytes
其他55个条目：完全不变
镜像大小：完全不变
```

之所以采用原位补丁，是为了避免重新编译改变属性顺序、字符串表偏移、padding、phandle或DTBO条目布局。

## 真机结果

刷入后 SurfaceFlinger：

```text
activeMode id=0
vsyncRate=120Hz
ddic_mode=2
sf_fps=120
ddic_min_fps=60
```

滑动屏幕时硬件采样：

```text
dynamic_fps=120
hw_vsync_info约120Hz
vsync_period约8.32ms
```

停止触摸并静止后，开发者刷新率显示确认面板可继续下降到1Hz。因此实际表现是：

```text
SurfaceFlinger/HWC可见范围：120 -> 60Hz
DDIC面板实际扫描范围：120 -> 60 -> 1Hz
```

`ddic_min_fps=60` 是系统/HWC可见的策略下限，不是DDIC面板物理扫描率的硬下限。

## 刷写警告

DTBO是启动链关键分区。错误镜像可能导致黑屏、闪烁、显示异常或无法正常开机。

在进行任何刷写前，必须确认：

```text
Bootloader已经解锁
设备确实是ishtar
面板节点和build ID一致
当前系统版本一致
当前活动槽位
fastboot能够识别并写入设备
已经备份当前槽位的原始DTBO
原始镜像与待刷镜像SHA-256正确
具备明确且可执行的fastboot回滚方案
```

本仓库不提供自动刷写脚本。请勿把这里的 `dtbo_a` 文件盲目写入 `dtbo_b`，也不要在未确认活动槽位时直接执行命令。

## 参考

寄存器组合参考了小米公开的同属 `42-02-0a` 命令族面板配置，并结合 ishtar M1 原厂普通120Hz、AUTO60、flat模式命令交叉推导：

```text
https://github.com/MiCode/vendor_qcom_proprietary_display-devicetree
分支：bsp-zorn-v-oss
参考：display/dsi-panel-n1-42-02-0a-dsc-cmd.dtsi
```

最终参数以 Xiaomi 13 Ultra `OS3.0.306.0.WMACNXM` 真机验证结果为准。

## License

[GPL-3.0](LICENSE)
