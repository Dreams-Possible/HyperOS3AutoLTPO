# ishtar OS3.0.308.0.WMACNXM：AUTO60 + AUTO120

硬件底包明确为小米13 Ultra中国版 `OS3.0.308.0.WMACNXM`，Android 16。本次实机上层系统是移植的 madrid `OS4.0.17.0.XEOCNXM`；DTBO仍基于13U的308底包。原始解包system/product的版本属性均标明308。不要把本目录镜像理解为306或18PM的DTBO。

## 文件与结果

| 文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| 308官方解包原始dtbo.img（不在本目录附带） | 16777216 | `e8385b6119178d38ed2db28a263d2264227198534eb29af4557abd025889c67e` |
| `dtbo_AUTO60_AUTO120.img` | 16777216 | `d7cec624530ca7b5bf489109666de92749c99f6f88fc49dc8e968441ecbe459d` |

**现在DTBO同时提供AUTO60和AUTO120两种档位。** 原AUTO60、普通固定60/120及其他原节点全部保留，新增AUTO120兄弟节点。已在本次移植实机确认60/120两档LTPO工作。DTBO提供面板模式，系统能否选中还受MI-SF许可列表和软件策略影响；自动idle另见仓库 `idle-bypass/`。

## 定位与修改方法

先校验Android DTBO头和条目表，解析每个条目的FDT结构/字符串块。该基线共57个条目，只处理匹配ishtar的条目6、7中的面板 `qcom,mdss_dsi_m1_42_02_0a_dsc_cmd`。实机panel_info为M1，设备树board-id对应ishtar，msm-id对应条目7。条目32有相似面板名但板级匹配不同，未修改。其他版本必须重新确认匹配条件，不能仅依赖条目编号。

找到原节点 `timing@wqhd_auto_mode_60_1hz_index_08`，复制完整节点作为同级新增节点 `timing@wqhd_auto_mode_120_60hz_index_09`。原节点保持原样。新节点不带默认timing标记或重复phandle。只在新节点中修改以下内容：

| 属性 | 原AUTO60复制值 | 新AUTO120值 |
| --- | --- | --- |
| `mi,mdss-dsi-sf-framerate` | 60 | 120 |
| `qcom,mdss-dsi-panel-framerate` | 60 | 120 |
| `mi,mdss-dsi-ddic-min-framerate` | 1 | 60 |
| `qcom,mdss-dsi-h-sync-skew` | `0x9e01` | `0xbc3c` |

`h-sync-skew`的新值按 `(AUTO << 14) | (120 << 7) | 60` 编码。这里系统可见的最低60与DDIC面板自身的低频扫描不是同一概念，不能从字段60推断物理面板无法降到1。

新节点的 `qcom,mdss-dsi-on-command` 和 `qcom,mdss-dsi-timing-switch-command` 解析为DSI数据包后，按完整payload精确替换，保留包头和其他命令：

```text
26 03 -> 26 02
第一条2F 00保留；第二条2F 30 -> 2F 00
on中的 BA 91 0B 03 00 11 77 77 00 05
switch中的 BA 91 0B 01 00 11 77 77 00 05
两者均改成 BA 91 01 01 00 01 01 01 00 00
BC 20 -> BC 00
```

同时更新新节点的flat/gamma配置，避免切flat后重新写回60Hz基准：

```text
mi,mdss-dsi-flat-mode-off-command：26 03 -> 26 02
mi,mdss-dsi-flat-mode-on-command：26 01 -> 26 00
mi,mdss-flat-status-control-gamma-26-cfg：<1 3> -> <0 2>
```

新增节点会增长FDT，不能沿用旧306方案的等长52字节修改。保留原FDT token和字符串表内容，插入克隆节点后更新FDT总大小、结构块大小、字符串表偏移；按DTBO头声明的alignment重新排列payload，更新条目大小/偏移与头部total_size，保持所有匹配ID/custom字段不变。利用原镜像padding，最终完整文件仍为16MiB。

## 校验

`verification.json`保留两条目每个属性修改前后完整十六进制。构建时重新解析输出，确认原节点/属性序列一致、仅各新增一个节点，另外55条目payload逐字节不变，所有匹配元数据不变。两份修改FDT已通过DTC反编译检查。条目6由451521增长到462929字节；条目7由486551增长到497959字节。

## 系统配套与实机判定

本次固件在 `product/etc/build.prop` 末尾使用独立注释块配置：

```properties
# BEGIN ISHTAR PORT EXPERIMENTAL DUAL AUTO LTPO
ro.vendor.mi_sf.supported_automode_maxfps_list=60,120
persist.vendor.disable_idle_fps.threshold=0
# END ISHTAR PORT EXPERIMENTAL DUAL AUTO LTPO
```

OS4 `libmisurfaceflinger.so`的 `init_property` 读取许可列表并交给 `parseAutomodeFps`。列表保留60并许可120；阈值0取消原528低亮度退出AUTO的限制。本次不更改现有KSU模块，属性通过固件product部署。重启后核对实际getprop及MI-SF缓存值，persist属性可能被userdata已有值覆盖。

分别选60/120，检查SurfaceFlinger活动mode/group、HWC的ddic_mode与sf_fps，再结合dynamic_fps/hw_vsync_info判断真实扫描。AUTO内部自行降扫描率是预期行为。开发者角标单独不足以证明模式切换或物理上限。低亮度、flat、唤醒、分辨率、视频/AOD/指纹仍应逐项验收；不把60/120成功扩大成所有场景或功耗已量化。

## 部署与恢复

诊断时手机DTBO分区容量为25165824字节，生成镜像16777216字节；镜像容量可容纳不等于可跨版本通用。刷写由用户完成，先备份当前活动槽位完整DTBO并记录哈希，再在bootloader fastboot中刷明确的dtbo_a或dtbo_b。不要根据本文件名猜活动槽位，也不要顺带改另一个槽位。

回退应刷回同槽位实机原始备份；官方16MiB解包镜像不自动等同于当前分区完整转储。若同时回退软件许可/阈值，恢复原属性并部署product，核对persist有效值。无需为DTBO方案清除userdata。
