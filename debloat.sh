#!/bin/bash
# 小米电视去预装脚本
# 用法：bash debloat.sh <电视IP>
# 前提：电视和电脑同一 WiFi、ADB 调试已开、已授权

ADB="${ADB:-adb}"
IP="${1}"

if [ -z "$IP" ]; then
  echo "用法: bash debloat.sh <电视IP>"
  echo "例:   bash debloat.sh 192.168.1.100"
  exit 1
fi

echo "=== 连接 $IP:5555 ==="
$ADB connect "$IP:5555"
sleep 2

STATE=$($ADB devices | grep "$IP" | awk '{print $2}')
if [ "$STATE" != "device" ]; then
  echo ""
  echo "❌ 连接失败，状态：${STATE:-无}"
  echo ""
  echo "如果显示 unauthorized，说明电视上没有点授权弹窗。"
  echo "让弹窗重新出现的方法："
  echo "  $ADB kill-server"
  echo "  rm -f ~/.android/adbkey ~/.android/adbkey.pub"
  echo "  $ADB start-server && $ADB connect $IP:5555"
  echo "每轮换新密钥，弹窗就会反复出现。请守在电视前准备点\"允许\"。"
  exit 1
fi
echo "✅ 已连接"
echo ""

# ---- 备份 ----
mkdir -p ./tv_backup
BK="./tv_backup/packages_backup_$(date +%Y%m%d_%H%M).txt"
$ADB shell pm list packages -f > "$BK"
echo "=== 已备份到 $BK ==="
echo ""

# ---- 先查白名单 ----
echo "=== 厂商允许卸载的白名单 ==="
WL=$($ADB shell settings get system can_be_deleted 2>/dev/null | tr -d '\r' | tr ';' '\n')
if [ -n "$WL" ] && [ "$WL" != "null" ]; then
  echo "$WL" | grep -v '^$' | sed 's/^/  /'
  echo ""
  echo "（以上这些系统预装包可以卸载，其余系统包删不掉）"
else
  echo "  该设备没有这个白名单键，直接尝试卸载即可"
fi
echo ""

# ---- 检查恢复能力 ----
echo "=== 即将卸载的应用位置检查 ==="
echo "（/data/app/ 位置的删除后不可恢复；/system/ 位置的可以装回来）"
echo ""

# ---- 卸载清单 ----
# 广告/无用系统预装
SYSTEM_PRELOAD="
com.xiaomi.tv.gallery
com.duokan.videodaily
com.xiaomi.mitv.handbook
com.mitv.shoplugin
com.xm.webcontent
com.xiaomi.mitv.tvvideocall
"

# 第三方预装（可以从应用市场重装）
THIRD_PARTY="
com.changba.sd
com.dangbei.health.fitness.mibox
com.xiaodianshi.tv.yst
cn.miguvideo.migutv
com.cibn.tv
com.hunantv.license
com.tencent.qqmusictv
"

echo "=== 开始卸载 ==="
for P in $SYSTEM_PRELOAD $THIRD_PARTY; do
  # 先看这个包是否存在
  EXISTS=$($ADB shell pm list packages 2>/dev/null | tr -d '\r' | grep -c "^package:$P$")
  if [ "$EXISTS" != "1" ]; then
    echo "  - $P （不存在，跳过）"
    continue
  fi

  PATH_LINE=$($ADB shell pm list packages -f 2>/dev/null | tr -d '\r' | grep "^package:.*=$P$" | sed 's/^package://;s/=.*//')
  R=$($ADB shell pm uninstall --user 0 "$P" 2>&1 | tr -d '\r')

  if [ "$R" = "Success" ]; then
    echo "  ✓ $P"
    echo "      APK: $PATH_LINE"
  else
    echo "  ✗ $P → $R"
  fi
done

echo ""
echo "=== 完检：关键组件是否都还在 ==="
OK=1
for P in com.android.systemui com.xiaomi.mitv.remotecontroller.service \
         com.mitv.tvhome com.sohu.inputmethod.sogou.tv mitv.service \
         com.xiaomi.mitv.settings com.droidlogic.tvinput com.google.android.webview; do
  E=$($ADB shell pm list packages 2>/dev/null | tr -d '\r' | grep -c "$P")
  if [ "$E" = "1" ]; then
    echo "  ✓ $P"
  else
    echo "  ✗ 缺失！$P"
    OK=0
  fi
done

echo ""
echo "=== 当前包总数 ==="
$ADB shell pm list packages 2>/dev/null | tr -d '\r' | wc -l

echo ""
if [ "$OK" = "1" ]; then
  echo "✅ 全部关键组件正常。请重启电视让改动生效。"
else
  echo "⚠️  有组件缺失，请立即检查电视功能是否正常。"
fi
echo ""
echo "提示：系统 OTA 升级后预装会回来，重跑本脚本即可。"
