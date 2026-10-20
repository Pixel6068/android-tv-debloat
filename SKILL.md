---
name: android-tv-debloat
description: Use when 精简 Android 电视/盒子的预装、广告与卡顿。
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [android, tv, adb, debloat, xiaomi]
    related_skills: [tool-deployment]
---

# Android 电视精简（去预装 / 去广告 / 减卡顿）

## When to Use

用户说“电视/盒子装了一堆没用的东西”“开机广告”“卡顿想清理”“能不能删预装”，或直接贴一个“用 ADB 删 25 个预装包”的教程问“能不能做”。

**不适用**：需要 root/刷机的深度修改；运营商锁死的定制机（ADB 可能直接不可用）。

给小米电视、Android TV 盒子做"动手术"的完整流程。核心不是命令，是**先判断这台机器能不能删、能删哪些**——网上教程直接甩 `pm uninstall` 列表，但在厂商收紧了权限的固件上会全线失败。

## 一、先用 30 秒判断可行性

不要一上来就连。先扫局域网找设备：

```bash
grep '^IP address' <(networksetup -getinfo Wi-Fi)     # Mac 的 IP 和网段
# 扫 5555(ADB) 和 6095(小米 miIO) —— 6095 开放基本可判定是小米设备
python3 - <<'EOF'
import socket, concurrent.futures as cf
BASE = "192.168.1."   # 换成你的网段前三位
for p in (5555, 6095):
    def probe(i):
        s = socket.socket(); s.settimeout(0.35)
        try:
            if s.connect_ex((BASE+str(i), p)) == 0: return (BASE+str(i), p)
        except Exception: pass
        finally: s.close()
    with cf.ThreadPoolExecutor(max_workers=200) as ex:
        hits = [r for r in ex.map(probe, range(1, 255)) if r]
    print(p, hits)
EOF
```

**5555 通 = ADB 已开**；**只有 6095 通 = 设备在但 ADB 没开**。

## 二、打开 ADB（各品牌路径不同）

| 系统 | 路径 |
|---|---|
| MIUI TV（小米 4A/4C 等老机） | 设置 → 账号与安全 → **ADB 调试**（没有"开发者选项"这个菜单） |
| 小米新机 / Android TV 原生 | 设置 → 系统 → 关于 → 连点"版本号"7 次 → 退回去 → 开发者选项 → **USB 调试** |
| 通用 Android TV | 设置 → 关于 → 连点内部版本号 → 开发者选项 → USB 调试 |

**开关名字会变**：ADB 调试 / USB 调试 / 网络调试，都是同一个东西。

**老固件的坑**：打开开关后退出设置页或电视待机，开关可能自动弹回去。开完**不要退出那个页面**，立刻让电脑连。

## 三、授权弹窗必须反复触发（关键技巧）

典型场景：端口通了但一直是 `unauthorized`，电视上不弹窗，或者弹了被误点掉。

**原因**：adb 只在新公钥第一次出现时弹窗，且窗口十几秒就消失。

**解法——每轮换新身份，连续触发，给足点击时间：**

```bash
ADB=/path/to/platform-tools/adb
for round in 1 2 3 4 5 6; do
  $ADB kill-server >/dev/null 2>&1
  rm -f ~/.android/adbkey ~/.android/adbkey.pub   # 全新身份 → 每次都是"新设备" → 每次弹窗
  $ADB start-server >/dev/null 2>&1
  $ADB connect <IP>:5555
  for t in $(seq 15); do
    sleep 1
    S=$($ADB devices | grep <IP> | awk '{print $2}')
    [ "$S" = "device" ] && echo "授权成功" && break 2
  done
done
```

同时让用户**守在电视前**，弹窗一出现就点"允许"，有"一律允许"就勾上。

**不要用 adb root 硬来**：`adb root` 在生产版固件一律返回 `adbd cannot run as root in production builds`，别浪费时间。老版 platform-tools（28.x）也试过，不是版本兼容问题，是设备端不给弹窗窗口。

## 四、装 adb（mac 无 brew 时的静态包方案）

```bash
mkdir -p ./tools && cd ./tools
curl -sL -o pt.zip "https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
unzip -oq pt.zip   # → ./tools/platform-tools/adb
codesign -dv platform-tools/adb 2>&1 | grep TeamIdentifier   # macOS 下应为 EQHXZ8M8AV（Google）
```

## 五、先备份，再动手（不可跳过）

```bash
mkdir -p ./tv_backup
$ADB shell pm list packages -f > ./tv_backup/packages_backup_$(date +%Y%m%d_%H%M).txt
```

`-f` 带 APK 路径，这个路径决定了后面能不能恢复（见第七节）。

## 六、权限三道关卡（核心判断）

按顺序试，别跳步：

**关卡 1：`pm disable-user --user 0 <pkg>`**

```
SecurityException: Permission Denial: attempt to change component state from pid=... uid=2000
```

→ 厂商收走了 shell 用户的包管理权限。**小米 4A 固件就是这种**。继续关卡 2。

**关卡 2：试 `pm uninstall --user 0 <pkg>`**

对不同包结果不同，这就是分水岭：

| 包的类型 | 结果 |
|---|---|
| 系统核心包（settings/systemui/launcher） | `SecurityException` |
| **白名单内系统预装** | **Success** |
| **第三方预装应用（`pm list packages -3`）** | **Success** |

**关卡 3：查系统白名单**

```bash
$ADB shell settings get system can_be_deleted | tr ';' '\n'
```

这个键列出了**厂商允许卸载**的应用。里面有名字的，`pm uninstall --user 0` 一定成功；不在里面的系统包，怎么都删不掉。

**这是整个流程里最关键的一步**——先查白名单，就知道天花板在哪，不用一个个试。

## 七、恢复能力判断（决定敢不敢删）

看备份里 APK 路径的第一段：

| 路径 | 卸载后能否恢复 |
|---|---|
| `/system/priv-app/...`、`/system/app/...` | **能**。APK 在只读系统分区，`pm install -r --user 0 /system/priv-app/X/X.apk` 装回来 |
| `/data/app/...` | **不能**。APK 和数据一起被删，除了重新下载安装包没别的办法 |

**Android 6.0 没有 `pm install-existing`**（那是 Android 7+ 的命令），别指望用它恢复。

⚠️ **动手前必须查一遍要删的包在哪个路径**，`/data/app/` 的位置删了就是真没了。

## 八、绝对不能删的包

删之前逐条核对，缺一个电视就废了：

```
com.android.systemui                        系统 UI（删了黑屏）
com.xiaomi.mitv.systemui                    小米系统 UI
com.xiaomi.mitv.remotecontroller.service    遥控器服务（删了遥控器失灵）
com.mitv.tvhome                             桌面/主页（删了没有界面）
com.sohu.inputmethod.sogou.tv               输入法（删了打不了字）
mitv.service                                小米电视核心服务
com.xiaomi.mitv.settings                    设置（删了进不去设置）
com.droidlogic / .tvinput                   晶晨芯片硬件抽象 + 电视输入
com.google.android.webview                  WebView（大量应用依赖）
com.mitv.codec.update                       解码器更新（删了视频解码可能坏）
com.android.packageinstaller                装 APK 要用
com.android.providers.*                     数据提供者（settings/media/downloads/tv）
```

## 九、可删清单（以 MiTV4-ANSM0 为例）

**以下清单仅在该型号上核对过。** 其他型号包名可能不同，删前用 `pm list packages` 逐条确认存在再动手。

**广告/无用系统预装（`/data/app`，删了不可恢复）：**
```
com.xiaomi.tv.gallery              小米画报（屏保/画报广告主要来源）
com.duokan.videodaily              多看视频日报（内容推荐）
com.xiaomi.mitv.handbook           使用手册
com.mitv.shoplugin                 购物插件（广告）
com.xm.webcontent                  网页内容广告位
com.xiaomi.mitv.tvvideocall        视频通话
```

**第三方预装（可从应用市场重装）：**
```
com.changba.sd                     唱吧
com.dangbei.health.fitness.mibox   当贝健身
com.xiaodianshi.tv.yst             小电视
cn.miguvideo.migutv                咪咕视频
com.cibn.tv                        未来电视 CNTV
com.hunantv.license                芒果 TV
com.tencent.qqmusictv              QQ音乐 TV
```

**这类通常建议保留（内容/功能类，看机主需不需要）：**
```
com.gitvdemo.video                 银河奇异果（视频）
com.ktcp.video                     腾讯视频 TV（视频）
com.lutongnet.nldmxXiaomiChildren  儿童乐园（有小孩的家庭）
```

## 十、删不掉的那部分

以下几个通常**禁不掉也删不掉**（固件锁死），以下命令全部会失败：

```
com.miui.systemAdSolution      系统广告组件
com.miui.tv.analytics          行为分析
com.xiaomi.statistic           统计上报
```

`pm disable-user` / `pm disable` / `pm hide` / `adb root` / `pm block` 全试过：
- disable → `SecurityException: Permission Denial ... uid=2000`
- hide → `SecurityException: Neither user 2000 nor current process has MANAGE_USERS`
- block → `Error: unknown command 'block'`（Android 6 没这命令）
- adb root → `cannot run as root in production builds`
- su → `/system/bin/sh: su: not found`

**唯一还能做的：`am force-stop`**（有权限，但重启后失效，不持久）。

要根治只能去路由器层拦广告域名。

## 十一、开机广告先查再谈

别假设有。先读系统设置：

```bash
$ADB shell settings get system boot_ad            # 0 = 已关
$ADB shell settings get system boot_ad_sound_enable
$ADB shell settings get system boot_ad_switch_show
$ADB shell settings get secure screensaver_enabled   # 0 = 屏保已关
```

部分机型出厂 `boot_ad` 就是 0，本来就没有开机广告。先查能省一堆无用功。

## 十二、收尾验证

删完必须核对关键组件还在：

```bash
for P in com.android.systemui com.xiaomi.mitv.remotecontroller.service \
         com.mitv.tvhome com.sohu.inputmethod.sogou.tv mitv.service \
         com.xiaomi.mitv.settings com.droidlogic.tvinput com.google.android.webview; do
  E=$($ADB shell pm list packages | grep -c "$P")
  [ "$E" = "1" ] && echo "ok  $P" || echo "MISSING $P"
 done
```

然后**重启电视**，确认能正常开机、遥控器能用、能进设置、能播视频。

## 十三、OTA 升级后会回来

系统更新会把删掉的预装重新装上。把第八、九节的删除列表存成一个脚本，每次系统升级后重跑一遍即可。

## 十四、给别人用之前必须先说的三句话

1. **删 `/data/app/` 位置的包不可恢复**，动手前查路径。
2. **只有白名单 + 第三方包能删**，系统核心包在这类固件上删不掉，别承诺"全删干净"。
3. **判断由操作者下、后果由机主担**。按"只删第三方、一次删一批、删完立刻验证"的保守路径走，不要一次清空。

## 附：其他品牌

流程通用，差异在：
- **包名**：每台机器 `pm list packages` 现查，不要照抄别人的列表
- **白名单键**：`settings get system can_be_deleted` 是小米的，其他品牌未必有；没有的话直接试 `pm uninstall --user 0`，成功就说明允许
- **权限**：原生 Android TV 通常 `pm disable-user` 直接可用，比小米宽松
