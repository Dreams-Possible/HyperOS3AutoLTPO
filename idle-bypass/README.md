# ishtar / madrid OS4：保持 AUTO，绕过软件强制 IDLE

## 仓库版本与示例

硬件底包明确为小米13 Ultra / ishtar **OS3.0.308.0.WMACNXM（Android16）**，双AUTO DTBO见 `../dtbo/OS3.0.308.0.WMACNXM/`。本目录SO来自移植框架 **madrid OS4.0.17.0.XEOCNXM**，不是308原厂SO，不能照这里的偏移修改OS3库。本目录独立于KSU模块，未向模块加入SO、属性或安装逻辑。

实物示例：`examples/original/libsurfaceflinger.so` 是原件；`examples/patched/libsurfaceflinger.so` 是四点合并版。两者均14241456字节，哈希见下文。固件部署位置为 `system_ext/lib64/libsurfaceflinger.so`，示例目录不是可安装模块。

## 调试过程及最终配置

同时观察SurfaceFlinger的mode/group、MI-SF/HWC切换日志及面板扫描节点。区分软件请求模式、HWC执行模式、DDIC在AUTO内自行降频：目标是拦截静止后AUTO变独立IDLE或normal30，AUTO内扫描降到1/10/30属于预期LTPO行为。

第一阶段拦截三个 `MiSurfaceFlingerStub::setIdleFps` 候选调用。部署后仍回普通30，日志出现 `Can't find min refresh rate by policy with the same mode group as the mode group ...`，随后选id9/group0普通30。本次normal候选仅30/40/60/90/120，缺少AUTO同组候选；AUTO120 group41434112、AUTO60 group37486848的同组最低模式查找失败后回退。ID随版本变化，必须读取当前模式表。

第二阶段确认GlobalSignals布局后跳过排序器idle最低模式分支。合并版仍曾在松手约111/112ms后回normal30，原软件idle timer为110ms。继续追踪 `Scheduler::idleTimerCallback`（本版0x4c5bdc）向MI-SF `setIsIdleState`传递状态，及 `createIdleTimer`（0x4ad18c）在timeout<1时不创建计时器。改0并重新加载SF后dump确认 `idleTimer interval=nullopt`。初次短测仍有normal30；后续重新加载0ms、采样与用户日用反馈未再出现，按基本修复继续观察记录，保留历史反例。

最终固件在 `product/etc/build.prop` 末尾配置：

```properties
# BEGIN ISHTAR PORT OPTIONAL MI-SF IDLE BYPASS
ro.vendor.mi_sf.support_gradient_idleframerate=false
persist.vendor.mi_sf.force_skip_idle_fps=true
# END ISHTAR PORT OPTIONAL MI-SF IDLE BYPASS

# BEGIN ISHTAR PORT EXPERIMENTAL DUAL AUTO LTPO
ro.vendor.mi_sf.supported_automode_maxfps_list=60,120
persist.vendor.disable_idle_fps.threshold=0
# END ISHTAR PORT EXPERIMENTAL DUAL AUTO LTPO

# BEGIN ISHTAR PORT OPTIONAL SF SOFTWARE IDLE TIMER
debug.sf.set_idle_timer_ms=0
# END ISHTAR PORT OPTIONAL SF SOFTWARE IDLE TIMER
```

gradient=false抑制亮度相关渐变idle入口；force_skip=true作用于部分强制idle路径，两者均不是单独关闭所有idle的保证。automode列表配合DTBO支持双档；threshold=0取消原528低亮度退出AUTO限制。idle_timer原308 ODM为110，0使本版软件定时器不创建。通过product默认值覆盖目标vendor/odm，部署后核对实际有效属性；persist值可能被userdata覆盖。

成功上下文中 `ro.vendor.display.touch.idle.enable=true`、`ro.vendor.display.video_or_camera_fps.support=true`，`ro.vendor.mi_sf.video_or_camera_fps.support`为空。这次没有新增三个false开关。`ro.hwui.use_vulkan=true` 是玻璃效果修复，不属于idle方案。

只读定位可使用 `adb shell dumpsys SurfaceFlinger`、`adb logcat -d -v threadtime`、`adb shell getprop <上述属性键>`、`adb shell sha256sum /system_ext/lib64/libsurfaceflinger.so`。在电脑保存输出，搜索 `setIdleFps`、`setTpIdleFps`、`setVideoFps`、`setDesiredMode`、`fixedMode_group`、同组最低模式警告及 `idleTimer`。面板dynamic_fps/hw_vsync_info按实际sysfs路径读取，单看开发者角标不足以区分模式切换和AUTO内部降频。

完整组合部署需重打system_ext和product并重启，随后核对SO哈希、有效属性、timer状态、mode/group和HWC时序。下文“仅SO补丁重打system_ext”指单独二进制部分，不包含product属性部署。无需为此改KSU模块。

本文是纯文字复现说明，不要求使用补丁脚本。仅适用于下列哈希锁定的 ARM64 库；对其他版本必须重新逆向，不能照抄偏移。所有修改在电脑工作副本进行，手机只用于部署后的验证。

## 1. 目标与已知结论

目标是避免正常亮屏静止时，软件把 AUTO 模式反复切成独立 IDLE 或普通 normal30；不是禁止面板自行降低扫描率，也不是把屏幕锁死120Hz。

历史实机有两种不同路径：

1. MI-SF 的 `setIdleFps` 返回独立 IDLE 候选，造成 AUTO↔IDLE 切换。
2. 仅绕过该候选后，Android 排序器的静止分支仍按升序选最低模式。实际候选表 `mPrimaryFrameRates` 只有normal30/40/60/90/120，没有AUTO组，于是出现同组最低模式找不到的警告并回退normal30。

第一阶段只处理路径1，单独部署后路径2仍存在。第二阶段跳过静止专用最低模式分支，保留第一阶段三个修改。用户在部署叠加版本后确认原问题消失；工作包及手机读取到的最终库哈希一致。此确认不等于已经完成全部亮度、视频、指纹或长期功耗测试。

**已确认的是两阶段叠加版。仅第二阶段4字节的简化版没有单独测试，不能作为已验证方案发布。**

后续统一按合并方案维护，不再安排单独4字节验证。合并SO曾仍有AUTO60松手后normal30的残余；再配合软件idle定时器0ms后，近期采样没有新30Hz事件，用户反馈这次未再复现，当前收口为**已基本修复，继续日常观察**。可复现组合是四点SO＋product的0ms配置，保留已有AUTO/IDLE BYPASS配置，不继续自动叠加修改。这不是完全根治或长期功耗结论，AOD/指纹等未覆盖场景仍按验收清单检查；后续复现应记录版本、应用、模式和投票再重开诊断。

最终补充验证（用户2026-10-09明确反馈）：此前idle/normal30问题未再次出现，按本固件组合记为**已验证恢复，继续长期观察**。采用的仍是四点合并SO＋0ms配置，不是单独4字节版本，也没有进一步删掉30Hz模式。不能把“截至反馈未再出现”扩大成永不复现、所有显示场景或省电收益已全面验证。

## 2. 精确修改范围与原件

- 官方源框架：madrid / OS4.0.17.0.XEOCNXM。本次使用的待修改库以原件哈希为最终依据。
- 工作路径：`work/system_ext/lib64/libsurfaceflinger.so`。
- 手机路径：`/system_ext/lib64/libsurfaceflinger.so`。
- 类型：ELF64、little-endian、AArch64，原长度 **14241456字节**。
- 不修改32位同名库、libmisurfaceflinger.so、services.jar、DTBO、DDIC、显示XML或其他分区。
- 不新增prop来启用这个SO补丁，不删除普通30/40/90等模式。
- 不涉及APK签名，不需要给SO重新签名。

三个版本的SHA-256：

| 状态 | SHA-256 |
| --- | --- |
| 无这两阶段修改的原件 | `2ed1a4827066ef453c7890d4ee86da4aa468398bca301d797afeff6f57d65994` |
| 仅第一阶段 | `f7e02c9b46342da775f0c0523f7f3f60ad144ae01360cb7341e899dfd4d0440b` |
| 第一＋第二阶段 | `1b15f52fc3eae08486a3708e41d8636c058378b7fa71844d30b3b7833a7e4317` |

当前输入若是第三种，已经打好，不要重复修改；若是第二种，仅执行第二阶段；若是第一种，依次执行两阶段。任何其他哈希都停止，不能强行套补丁。ELF GNU build-id不能替代整个文件SHA-256，原位改指令通常不会自动更新build-id。

## 3. 备份与并行编辑边界

先记录库大小、SHA-256，复制原库和 `work/config/system_ext_fs_config`、`system_ext_file_contexts` 到项目专用备份目录，不放进work或手机。每阶段分别保留输入版本；二阶段回退到三点版，完整回退到原件。

已有本次操作的回退位置：项目 `diagnostics/backups/idle-selector-20261008/libsurfaceflinger.so` 是原件；`diagnostics/backups/idle-signal-branch-20261008/libsurfaceflinger.so` 是第一阶段版。使用前核对上述哈希，而不是仅信任目录名称。

有其他agent修改时，在实际写入前再次核对输入哈希和四个旧指令。不要整体恢复旧工作目录、旧build.prop或旧元数据来打这份补丁。

## 4. VA必须换算成文件偏移

使用反汇编工具（例如llvm-objdump）核对方法和指令，使用ELF program headers确认包含目标地址的可执行PT_LOAD。换算公式：

`file_offset = p_offset + (VA - p_vaddr)`，且VA须位于该段的文件数据范围 `p_vaddr .. p_vaddr+p_filesz`。

本版四处VA与文件偏移恰好相等。这个相等关系不是通用规则，不能把其他版本的反汇编地址直接当十六进制编辑器偏移。用按字节原位覆盖的方式修改，不插入/删除字节，不调整ELF节、段或文件长度。

## 5. 第一阶段：三个IDLE候选调用

目标函数是 `android::scheduler::RefreshRateSelector::getRankedFrameRatesLocked`；三处原指令均调用 `MiSurfaceFlingerStub::setIdleFps`。

| VA／本版文件偏移 | 原指令字 | 文件中原小端字节 | 新小端字节 |
| --- | --- | --- | --- |
| `0x4a428c` | `0x94206349` | `49 63 20 94` | `1F 7D 00 A9` |
| `0x4a4388` | `0x9420630a` | `0A 63 20 94` | `1F 7D 00 A9` |
| `0x4a8638` | `0x9420525e` | `5E 52 20 94` | `1F 7D 00 A9` |

新指令是 `stp xzr, xzr, [x8]`，指令字 `0xa9007d1f`，将间接返回区的16字节shared_ptr置为空。每处调用前已有 `strb wzr` 把skip标志置false；x8指向本次返回结构。Stub原本也会先初始化空返回区，随后有实现才复制候选返回。因此这里构造的是合法空候选，不是向调用者返回未初始化数据。

**不能简单NOP BL**：调用者随后读取返回结构和skip标志，省略调用却不初始化返回区可能把栈上的旧数据当指针。也不能把整个Stub或Impl无条件返回，因为电源路径还调用它。

第一阶段改3个4字节指令槽位，保持文件长度与其他字节完全不变；计算哈希应得到上表第一阶段值。这一阶段不是完整解决方案，不停在这里宣称成功。

## 6. 第二阶段：跳过静止最低模式分支

同一排序函数在 `0x4a393c` 检查packed GlobalSignals的touch位。无touch进入 `0x4a3960` 检查idle位。已结合本版反汇编与GlobalSignals布局确认bit0为touch、bit8为idle；不是根据函数名猜测。

原逻辑：`tbz w22, #8, 0x4a3aa8`，即idle=false跳到已有非idle路径，idle=true继续静止最低模式处理。修改如下：

| VA／本版文件偏移 | 原小端字节 | 新小端字节 | 语义 |
| --- | --- | --- | --- |
| `0x4a3960` | `56 0A 40 36` | `52 00 00 14` | `b 0x4a3aa8` |

新指令字 `0x14000052`。AArch64 B使用PC相对偏移：目标减当前地址为 `0x148` 字节，除4为 `0x52`，再与B编码 `0x14000000` 合成。它跳到已有的idle=false分支，不伪造触摸、不修改传入GlobalSignals，也不使整个函数返回空。

第二阶段只增加一个4字节槽位修改，保留前三处新指令。最终相对原件共四个指令槽位、16字节覆盖范围；不是说16个字节的数值全部发生变化。

## 7. 不动的电源调用与属性

`SurfaceFlinger::setPowerMode` 内 `0x528120` 的setIdleFps调用必须保持原字节。不修改LTPO识别字段或全局关掉 `idle_default_fps.support`：该属性与 `ro.vendor.mi_sf.ltpo.support` 合入同一字段，而isLtpoPanel直接读取该字段。

本次SO两阶段不新增/修改prop。此前product末尾保留的两项为gradient=false和force_skip=true；AUTO许可60,120和低亮度阈值0也保留，不能把它们与二进制四点修改混称同一补丁。它们各自用途见operations.md对应章节。

读到的成功上下文中touch.idle.enable=true、display.video_or_camera_fps.support=true，mi_sf.video_or_camera_fps.support未声明；不要凭此前某轮false的实机值，虚构本次在work新增了三个false属性。其他用户的成功与否应同时记录实际props和模块覆盖情况。

保留电源调用不意味着已经证明所有AOD/指纹路径无影响；排序器也可能参与低功耗模式选择，仍必须验收。

## 8. 完整性与静态验收

### 补充可选配置：软件idle计时器0ms

初期0ms测试仍抓到偶发normal30；后续重新加载0ms并观察时未再复现，用户选择按合并SO＋0ms收口为已基本修复、继续日常观察。保留初期反例，不把后续短期无事件写成所有场景根治。本项与SO四点修改分开记录；停计时器不是禁止DDIC自身AUTO降频，也不等同删除所有最低候选请求。

来源：13U官方odm/etc/build.prop有debug.sf.set_idle_timer_ms=110。work中不为此修改ODM，按用户要求在work/product/etc/build.prop末尾追加独立区块（其他区块保持）：

```properties
# BEGIN ISHTAR PORT OPTIONAL SF SOFTWARE IDLE TIMER
# Disable the software idle timer; this does not disable DDIC AUTO/LTPO.
# Residual normal30 mode selection still requires separate verification.
debug.sf.set_idle_timer_ms=0
# END ISHTAR PORT OPTIONAL SF SOFTWARE IDLE TIMER
```

先检查product中没有同名键；已有则原地处理避免重复。保留ODM的110作为原厂来源，不声称整个work绝无同名属性：此处是跨分区覆盖，部署后以有效值为准。只新增这一项，不改touch/视频/亮度表/DTBO/其他SO。product文件原权限标签不变，无新增打包路径。重新打包部署product并重启，核对getprop为0且dumpsys SurfaceFlinger的idleTimer interval=nullopt；仅运行中setprop值为0不能说明旧计时器已停。此版createIdleTimer在timeout<1时直接返回不创建。已有临时0ms测试曾配套重启显示服务验证，但复现固件建议随正常部署重启，不自动强杀服务。

回退删除完整BEGIN/END块（已有原键则恢复备份值），重打部署product并重启，核对原110及计时器；保持其他补丁不变。0ms仍需测试触摸响应、AUTO60/120、视频、AOD/指纹和功耗，不许把频率降低描述成完全消失。

反汇编四处新指令，确认没有写错小端字节。最终长度仍14241456字节，最终SHA-256必须严格等于第三种。逐字节对比：相对原件的所有差异仅允许落在四个4字节槽位，相对第一阶段仅允许落在0x4a3960的4字节槽位；0x528120电源调用完全相同。

此版没有 `lib64/libsurfaceflinger.so.fsv_meta` 或对应摘要元数据条目，所以实际没有删除任何摘要文件/条目。保留：

```text
system_ext/lib64/libsurfaceflinger.so 0 0 0644
/system_ext/lib64/libsurfaceflinger\.so u:object_r:system_lib_file:s0
```

若新固件出现辅助文件、fs-verity或其他完整性机制，另行核对并配套处理；不能照本例忽略，也不能删除全目录摘要或同名32位库。

## 9. 打包、部署与判定

只因本补丁需要重打system_ext.img，不需要因此重打vendor/odm/system/product或刷DTBO。若工作包另有尚未部署改动，它们按各自方案处理，不能由本补丁扩大授权。镜像校验偏移0x400的EROFS magic为E2 E1 F5 E0，确认输出时间、容量和文件名；不要用旧ZIP或同目录旧镜像当新版本。

由用户授权部署到正确槽位的system_ext；DSU也必须实际更新system_ext镜像，仅重启旧DSU不会替换。不要直接覆盖运行中的共享库、写进程内存或为测试反复强杀SurfaceFlinger。

重启后用ADB只读读取 `/system_ext/lib64/libsurfaceflinger.so` 的sha256sum，必须是叠加版哈希。再同时检查SurfaceFlinger活动mode/group、MI-SF/HWC切换日志和可用的dynamic_fps/hw_vsync_info，不能只看开发者帧率角标。观察正常亮屏静止，不应再次出现此次静止路径引发的AUTO→normal30或AUTO↔独立IDLE反复切换。AUTO内DDIC自降到30/10/1不等于失败；应用自身请求30fps也不是这个补丁承诺屏蔽的对象。

分别测试60/120设置、触摸恢复、滚动、低/高亮度、视频与相机、分辨率变化、锁屏、AOD智能熄灭/恢复、指纹/HBM。未测项目写未测，不用一句“全部正常”代替结果。省电收益未量化，不宣称改动必然更省电。

## 10. 回退与跨版本重新定位

只回退第二阶段：恢复第一阶段哈希的库。撤回全部SO修改：恢复原件哈希的库。仅替换这个文件，保留后续其他修改与权限/标签；重新打包、部署同槽位并重启，核对手机实际哈希。属性回退是另一独立事项，persist值可能留在userdata，不能仅删除镜像默认便声称恢复。无需清空userdata。

新版本须重新定位排序函数、GlobalSignals布局、静止分支目标、返回ABI和电源调用；先确认问题日志仍对应同一路径，重新算PT_LOAD映射和B距离，并产生新的原/补丁哈希。四处字节不匹配时停止，不搜索后全局替换相同字节序列。
