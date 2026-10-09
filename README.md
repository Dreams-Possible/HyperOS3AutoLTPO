# HyperOS3AutoLTPO

为 Xiaomi 13 Ultra（ishtar）补全AUTO/LTPO能力。作者：[Dreams-Possible](https://github.com/Dreams-Possible)

## 当前方案入口

| 部分 | 基线与用途 |
| --- | --- |
| Auto模块 | 许可AUTO60/120和可选场景策略；模块源码与ZIP保持现状 |
| [308双AUTO DTBO](dtbo/OS3.0.308.0.WMACNXM/README.md) | OS3.0.308.0.WMACNXM硬件底包，保留AUTO60并新增AUTO120 |
| [关闭自动idle](idle-bypass/README.md) | 308硬件底包＋madrid OS4.0.17.0.XEOCNXM框架，SO补丁及属性，独立于模块 |

308双档已在移植实机确认工作；合并SO补丁＋0ms计时器按基本修复、继续日用观察维护。模块源码与ZIP均保持现状，idle方案未加入KSU模块。

本仓库包含模块、版本化DTBO和独立idle方案。以下是现有模块的作用：

```text
Auto模块：在保留原厂60Hz AUTO兼容路径的基础上启用120Hz AUTO
实验DTBO：补全面板AUTO120的DDIC命令，使真实扫描范围达到1–120Hz
```

## 当前移植实测环境

```text
设备：Xiaomi 13 Ultra
代号：ishtar
地区：中国版
系统：HyperOS 4移植
硬件底包：OS3.0.308.0.WMACNXM
上层框架：madrid OS4.0.17.0.XEOCNXM
底包Android：16
面板节点：mdss_dsi_m1_42_02_0a_dsc_cmd
物理分辨率：1440 x 3200
```

系统设置中的1080p属于 Android 渲染尺寸 override，仍使用同一套1440 × 3200物理面板时序，因此不需要单独制作FHD版DTBO。

## Auto模块

该模块负责系统策略层，不负责创建面板模式。完整1–120Hz AUTO物理模式由本仓库提供的实验DTBO实现；模块负责让小米修改版 SurfaceFlinger 使用该模式，并允许用户决定是否保留原厂的场景强制切换。

需要区分两种容易混淆的帧率：

```text
应用渲染帧率：应用实际生成画面的速度，例如视频通常为24/30fps
面板物理刷新率：DDIC驱动屏幕扫描的速度，例如AUTO模式可在1–120Hz变化
```

理想状态下，30fps视频可以继续以30fps渲染，而面板留在AUTO物理模式并自行适配；没有必要仅因为应用以30fps渲染，就把面板切换到普通固定60Hz。

### 公共AUTO配置

两个安装档位都会通过 `system.prop` 设置：

```properties
# 在兼容原厂60Hz AUTO的基础上启用120Hz AUTO
ro.vendor.mi_sf.supported_automode_maxfps_list=60,120

# 取消低亮度下退出AUTO并锁定普通120Hz的亮度阈值
persist.vendor.disable_idle_fps.threshold=0
```

该属性是小米 MI-SF 的 AUTO 最高帧率许可列表。模块的新增目标是启用 `120Hz AUTO`；列表中继续保留 `60`，是为了兼容系统原有的 AUTO60 逻辑：

```text
120：模块新增的主要功能，允许系统120Hz档进入AUTO策略
60：保留原厂兼容路径，不移除系统已有的60Hz AUTO能力
```

模块遵循“增加功能、不破坏原有功能”的原则，因此没有把该属性直接改成单独的 `120`。对于只安装模块、没有刷入匹配 DTBO 的用户，保留 `60` 可以继续使用原厂 AUTO60 路径，避免原有自动刷新能力因许可列表被覆盖而丢失。

该属性只告诉系统哪些最高刷新率档位允许使用AUTO，不会创建新的面板时序，不会直接指定最低刷新率，也不会修改DDIC命令。因此，仅安装模块但没有匹配的DTBO时，即使系统显示 `AUTO 120`，面板真实上限仍受原厂AUTO60命令限制；刷入匹配DTBO后，新增的 `120` 许可才会配合面板命令实现真实1–120Hz。

### 低亮度AUTO配置

MI-SF通过内部面板亮度阈值决定是否允许AUTO。目标底包原阈值为528，模块两档均设置 `persist.vendor.disable_idle_fps.threshold=0`，取消低亮度退出AUTO的限制。该值不关闭LTPO、内容检测或触摸升频。

该属性在SurfaceFlinger初始化时读取，安装后应重启设备。对于这里的KSU模块属性覆盖，卸载模块并重启即可恢复ROM自身配置；如果ROM本身已加入同名属性，则恢复的是该ROM配置。固件product内的修改需按对应文档回退。

### 安装档位

安装时可以通过音量键选择是否保留小米原厂的视频和停止触摸场景切换：

```text
音量+：保留小米场景切换
音量-：关闭小米场景切换，尽量始终保持完整AUTO模式（默认）
10秒内没有按键：自动选择音量-
```

#### 音量+：保留小米场景切换

音量+档不会添加其他刷新率属性，保留ROM或其他模块的有效开关；它不会主动把开关写为 `true`。小米系统可以根据视频、相机和停止触摸等场景，主动离开AUTO模式并选择普通固定60Hz。

优点：

```text
带弹幕或持续动画的视频页面可能始终被AUTO判断为动态内容
如果AUTO因此长期保持120Hz，原厂强制60Hz可以降低这类场景的功耗
保留小米对相机预览、视频节奏和部分白名单应用的原厂调度
```

缺点：

```text
普通24/30fps视频也可能被同一策略切换到普通固定60Hz
固定60Hz不再是1–120Hz AUTO，面板无法在该模式内继续向30/10/1Hz下降
系统依据应用类型和触摸状态决策，而不完全依据画面是否真的发生变化
```

该档位适合更看重弹幕、持续动画视频场景功耗，以及希望保留原厂兼容策略的用户。

#### 音量-：尽量始终保持完整AUTO

音量-档会在基础配置后追加：

```properties
# 禁止MI-SF按视频或相机场景切换到固定物理刷新率
ro.vendor.display.video_or_camera_fps.support=false
ro.vendor.mi_sf.video_or_camera_fps.support=false

# 禁止MI-SF在停止触摸后通过setTpIdleFps切换到固定60Hz
ro.vendor.display.touch.idle.enable=false
```

前两项控制视频/相机场景的旧、新入口，第三项控制停止触摸策略。这些开关不覆盖全部软件idle路径，308＋OS4另需参考独立idle方案。

真机日志中确认过两条独立调用链：

```text
视频场景：setVideoFps → id=1 normal 60Hz
停止触摸：setTpIdleFps → id=1 normal 60Hz
```

关闭上述入口后，实测画面刷新表现主要由是否存在真实动态元素决定，而不再仅由“当前是否为视频应用”决定。普通视频可以按内容降到30/40附近；滑动或持续动画仍可升高刷新率。

优点：

```text
物理面板尽量留在完整1–120Hz AUTO模式
普通视频不会仅因视频白名单或停止触摸被覆盖成固定60Hz
应用渲染帧率和面板物理刷新率可以分别决策
更接近由实际画面动态程度驱动的LTPO行为
```

缺点：

```text
弹幕、悬浮动画或其他持续变化元素可能使AUTO长时间保持较高刷新率
不再使用小米针对部分视频和相机应用设计的固定模式匹配
不同系统版本的MI-SF实现可能变化，需要重新核对属性和日志
```

该档位适合更看重完整LTPO能力，并愿意让面板根据实际动态内容自行调节的用户。

### Android通用内容检测不受模块影响

以下属性与音量+、音量−两个档位都没有关系，模块不会写入或覆盖它：

```properties
ro.surface_flinger.use_content_detection_for_refresh_rate=true
```

上面的 `true` 是当前实测系统的原厂值，只用于说明测试环境，不是模块配置。无论安装时选择音量+、音量−还是10秒超时，模块生成的 `system.prop` 都不会包含这项属性，系统将继续使用ROM自身的原始值。

该属性用于 Android SurfaceFlinger 分析图层内容和渲染节奏，与小米私有的 `setVideoFps`、`setTpIdleFps` 物理模式强制切换不是同一个入口。

保留它的目的：

```text
应用仍可按24/30/60fps等真实内容节奏渲染
SurfaceFlinger仍可进行正常的合成与帧率匹配
只移除已经确认会覆盖AUTO模式的小米私有切换路径
```

只有在确认没有触发 `setVideoFps` 和 `setTpIdleFps`，系统仍由通用内容检测直接切换到普通固定模式时，才有必要另外研究是否将其设为 `false`。这不属于当前模块的音量键选项，当前实测也不需要关闭。

### 适用边界

模块本身不会修改或刷写DTBO，也不会在运行时发送MIPI命令。

```text
只安装模块：修改系统使用AUTO模式的策略许可
只刷实验DTBO：提供真实1–120Hz AUTO面板命令，但系统策略仍可能离开AUTO
模块与匹配DTBO同时使用：获得完整AUTO物理模式，并按安装档位选择系统策略
```

模块源文件位于独立目录：

```text
HyperOS3AutoLTPO/module.prop
HyperOS3AutoLTPO/system.prop
HyperOS3AutoLTPO/customize.sh
HyperOS3AutoLTPO/META-INF/com/google/android/update-binary
HyperOS3AutoLTPO/META-INF/com/google/android/updater-script
```

仓库根目录同时提供已经打包好的模块：

```text
HyperOS3AutoLTPO.zip
```

ZIP内部直接以 `module.prop`、`system.prop` 和 `META-INF/` 为根，没有额外嵌套模块文件夹，可由 Magisk/KernelSU 模块管理器直接安装。模块仍不会自动刷写DTBO。

## DTBO资料与部署

[308双AUTO构建及镜像](dtbo/OS3.0.308.0.WMACNXM/README.md)为当前308底包方案，保留AUTO60并新增AUTO120。旧版本说明由Git历史保留，当前文档只呈现现行方案。

刷写前备份当前活动槽位原DTBO并记录哈希，核对版本和面板，确认fastboot回退路径。部署后结合SurfaceFlinger mode/group、MI-SF/HWC日志及面板扫描节点判定；角标单独不足以证明物理扫描范围。idle补丁、属性与回退方法见[独立文档](idle-bypass/README.md)。

## License

[GPL-3.0](LICENSE)
