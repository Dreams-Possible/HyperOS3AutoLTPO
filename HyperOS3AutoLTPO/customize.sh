SKIPUNZIP=1

on_install() {
  # 解压模块正文，但不把安装器目录复制进模块运行目录
  ui_print "- 正在释放模块文件"
  unzip -o "$ZIPFILE" -x 'META-INF/*' 'customize.sh' -d "$MODPATH" >&2

  ui_print "*******************************"
  ui_print "  请选择刷新率策略"
  ui_print "  音量+：保留小米场景切换（默认）"
  ui_print "  音量-：始终保持完整AUTO模式"
  ui_print "  10秒无输入将自动选择音量+"
  ui_print "*******************************"

  choice="plus"
  elapsed=0

  # 每次最多监听1秒，只响应音量键按下事件；超时不会阻塞安装
  while [ "$elapsed" -lt 10 ]; do
    key_event="$(timeout 1 getevent -qlc 1 2>/dev/null | grep -i 'KEY_VOLUME' | grep -iw 'DOWN' | head -n 1)"

    case "$key_event" in
      *KEY_VOLUMEDOWN*)
        choice="minus"
        break
        ;;
      *KEY_VOLUMEUP*)
        choice="plus"
        break
        ;;
    esac

    elapsed=$((elapsed + 1))
  done

  if [ "$choice" = "minus" ]; then
    ui_print "- 已选择音量-：关闭小米物理模式强制切换"

    # 禁止MI-SF按视频或相机场景切换到固定物理刷新率
    echo "ro.vendor.display.video_or_camera_fps.support=false" >> "$MODPATH/system.prop"
    echo "ro.vendor.mi_sf.video_or_camera_fps.support=false" >> "$MODPATH/system.prop"

    # 禁止MI-SF在停止触摸后通过setTpIdleFps切换到固定60Hz
    echo "ro.vendor.display.touch.idle.enable=false" >> "$MODPATH/system.prop"
  else
    ui_print "- 已选择音量+：保留小米视频和触摸空闲策略"
  fi
}

set_permissions() {
  # 模块脚本使用0755，其余配置文件使用0644
  set_perm_recursive "$MODPATH" 0 0 0755 0644
}
