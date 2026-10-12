# 常亮小助手 · 安卓源码与打包指南（V1）

> 一款一键让安卓屏幕保持常亮的小工具（科技风 UI）。Flutter 跨端框架，V1 仅安卓。
> 核心机制：开启时给窗口加 `FLAG_KEEP_SCREEN_ON` + 启动**前台服务**（保活）+ 添加**透明悬浮窗**（退到后台也常亮）。
> 配套需求文档见同目录 `需求规格说明书.md`。

---

## 一、本目录里有什么

```
常亮小助手/
├── pubspec.yaml                         # Flutter 工程描述（应用名 keep_screen）
├── build.cmd                            # ★★ 双击即可构建（推荐入口）
├── 一键构建.ps1                         # ★ 一键整合+构建脚本（被 build.cmd 调用）
├── 需求规格说明书.md                     # 需求文档（已确认 V1）
├── lib/
│   └── main.dart                        # 科技风主界面 + MethodChannel 调用原生
└── android/app/src/main/
    ├── AndroidManifest.xml              # 权限 + 前台服务声明 + 主 Activity（已用全限定类名）
    ├── kotlin/com/keepscreen/app/
    │   ├── MainActivity.kt              # MethodChannel 命令 + EventChannel 状态 + 权限引导 + 取应用列表
    │   ├── KeepScreenService.kt         # 前台服务：多原因常亮(手动/充电/前台App) + 定时关闭 + 持久化
    │   ├── OverlayWindow.kt             # 透明悬浮窗：后台常亮核心
    │   ├── KeepEvents.kt                # EventChannel 事件桥（原生→Flutter 状态推送）
    │   └── PowerEventReceiver.kt        # 静态充电广播：插拔电触发“充电时常亮”
    └── res/
        ├── values/styles.xml            # 深色启动主题
        ├── values/strings.xml
        └── drawable/{launch_background.xml, ic_keep.xml}
```

> 说明：因打包环境未安装 Flutter，**Gradle 工程配置**（gradle wrapper、build.gradle、settings.gradle、mipmap 启动图标）需在你本机用 `flutter create` 一次性生成（脚本已自动处理）。本目录已包含**全部应用层自定义源码**，覆盖即可。

---

## 二、前置要求（构建 APK 必需，只装 Flutter 不够）

构建安卓 APK 还需要 **Android 工具链**：
- **JDK 17**（Flutter 3.47 要求；Android Studio 自带，无需单独装）
- **Android SDK**：至少包含 Platform（建议 API 34/35）、Build-Tools、Android SDK Command-line Tools、Platform-Tools
- 接受协议：`sdkmanager --licenses`

最省心做法：**安装 Android Studio**（自带 JDK + SDK + 模拟器），首次打开按向导把 SDK 装好即可。装完后 Flutter 会自动在默认路径 `%LOCALAPPDATA%\Android\Sdk` 找到 SDK；若装到了别的盘，请在系统环境变量里设 `ANDROID_HOME` 指向 SDK 目录。

验证工具链是否齐全（在本机 PowerShell 跑）：
```powershell
C:\Users\wyh17\flutter\bin\flutter.bat doctor -v
```
确认 Android 相关项都是绿色勾（√），没有红色叉（✗）。有红叉就按提示装对应组件。

---

## 三、首次整合 + 构建（两种方式，选一个）

### 方式 A · 一键脚本（推荐，最简单）
本目录已附脚本，它会自动：把 Flutter 加入 PATH → `flutter create` 生成工程 → 覆盖源码 → `pub get` → 构建 APK → 复制成品到产物目录。

**A-1 双击运行（最省事）**：直接双击本目录下的 **`build.cmd`**。它会自动以 `-ExecutionPolicy Bypass` 调用脚本，不受执行策略限制，窗口出错也会停留显示。

**A-2 在已打开的 PowerShell 里运行**：
```powershell
& "D:\WYH-副\常亮小助手\一键构建.ps1"
```
> 提示：出现 `>>` 续行符说明命令没输完（多是复制时夹带换行），按 `Ctrl+C` 回到正常提示符再重试。
> 若提示脚本被禁用，先执行一次：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`（输 `Y` 确认）。**注意：这一步只是解锁权限，不会执行构建**，之后仍需再运行上面的脚本命令。

跑完 APK 落在 `D:\WYH-副\常亮小助手\常亮小助手-release.apk`。

> ⚠️ **构建工程必须放在纯英文路径**：Windows 下 AGP 会拒绝含中文的工程路径（报 `Your project path contains non-ASCII characters`）。因此：
> - 构建工作区：`D:\WYH_build\keep_screen_app`（**纯英文**）
> - 产物目录：`D:\WYH-副\常亮小助手`（可含中文，只放源码/文档/APK）
>
> 脚本已内置该路径与 ASCII 校验，无需你操心。

### 方式 B · 手动命令（想自己掌控每一步）
> 你的 Flutter 装在 `C:\Users\wyh17\flutter`，先把它加入当前终端 PATH。

```powershell
# 0) 把 Flutter 加入本次会话 PATH（仅当前窗口有效）
$env:PATH += ";C:\Users\wyh17\flutter\bin"

# 1) 生成标准 Flutter 安卓工程骨架（★ 必须是纯英文路径！）
#    --org + --project-name 组合必须让 applicationId/namespace = com.keepscreen.app
#    这与源码包名 com.keepscreen.app 严格一致，否则 R 类与类解析会失败
New-Item -ItemType Directory -Path D:\WYH_build -Force | Out-Null
cd D:\WYH_build
flutter create --org com.keepscreen --project-name app keep_screen_app

# 2) 用本交付包源码精确覆盖（只覆盖作者文件，保留 Flutter 生成的 mipmap 与 MainApplication）
Copy-Item "D:\WYH-副\常亮小助手\lib\main.dart" "D:\WYH_build\keep_screen_app\lib\main.dart" -Force
Copy-Item "D:\WYH-副\常亮小助手\android\app\src\main\AndroidManifest.xml" "D:\WYH_build\keep_screen_app\android\app\src\main\AndroidManifest.xml" -Force
$srcK="D:\WYH-副\常亮小助手\android\app\src\main\kotlin\com\keepscreen\app"; $dstK="D:\WYH_build\keep_screen_app\android\app\src\main\kotlin\com\keepscreen\app"
if(!(Test-Path $dstK)){New-Item -ItemType Directory -Path $dstK -Force|Out-Null}
Copy-Item "$srcK\MainActivity.kt","$srcK\KeepScreenService.kt","$srcK\OverlayWindow.kt" "$dstK" -Force
Copy-Item "D:\WYH-副\常亮小助手\android\app\src\main\res\values\styles.xml"      "D:\WYH_build\keep_screen_app\android\app\src\main\res\values\styles.xml" -Force
Copy-Item "D:\WYH-副\常亮小助手\android\app\src\main\res\values\strings.xml"     "D:\WYH_build\keep_screen_app\android\app\src\main\res\values\strings.xml" -Force
Copy-Item "D:\WYH-副\常亮小助手\android\app\src\main\res\drawable\launch_background.xml" "D:\WYH_build\keep_screen_app\android\app\src\main\res\drawable\launch_background.xml" -Force
Copy-Item "D:\WYH-副\常亮小助手\android\app\src\main\res\drawable\ic_keep.xml"   "D:\WYH_build\keep_screen_app\android\app\src\main\res\drawable\ic_keep.xml" -Force

# 3) 切国内镜像（Gradle 下载源 + Maven 仓库），否则首次要等 2 小时以上
#    官方源换腾讯云镜像 + bin 包
$wf="D:\WYH_build\keep_screen_app\android\gradle\wrapper\gradle-wrapper.properties"
$c=[System.IO.File]::ReadAllText($wf)
$c=[regex]::Replace($c,'https\\://services\.gradle\.org/distributions/gradle-([\d\.]+)(-\w+)?\.zip','https\://mirrors.cloud.tencent.com/gradle/gradle-$1-bin.zip')
[System.IO.File]::WriteAllText($wf,$c,(New-Object System.Text.UTF8Encoding($false)))

# 4) 拉依赖并构建 APK
cd D:\WYH_build\keep_screen_app
flutter pub get
flutter build apk --release

# 5) 复制成品 APK 到产物目录（中文目录只用来放产物，不参与构建）
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "D:\WYH-副\常亮小助手\常亮小助手-release.apk" -Force
```

### 方式 C · 连真机直接运行（跳过 APK，最快看到效果）
手机开 **USB 调试**，数据线连电脑，在工程目录执行：
```powershell
cd D:\WYH_build\keep_screen_app
flutter devices        # 确认手机出现在列表
flutter run --release  # 编译并直接装到手机运行
```

产物位置：
- 工程目录（纯英文）：`D:\WYH_build\keep_screen_app\`
- **APK 成品：`D:\WYH-副\常亮小助手\常亮小助手-release.apk`**（可直接拷到手机安装）

> 修复记录：早期版本 Manifest 用了相对类名 `.MainActivity`，并要求 `--org com.keepscreen.app`；现改为**全限定类名 `com.keepscreen.app.MainActivity`**，并用 `--project-name app` 使 namespace 与源码包严格一致，彻底避免 `ClassNotFound` / `找不到符号 R` 两类编译失败。

---

## 四点五、构建产物已验证（2026-10-10）

已在本机成功构建并逐项校验，结果如下（可用 `aapt2 dump badging` 自行复核）：

| 校验项 | 结果 |
|---|---|
| APK 路径 | `D:\WYH-副\常亮小助手\常亮小助手-release.apk` |
| 体积 | 41.6 MB（43,580,128 字节） |
| 包名 / 版本 | `com.keepscreen.app` / versionCode 1 · versionName 1.0.0 |
| 应用名 | 常亮小助手 |
| 启动 Activity | `com.keepscreen.app.MainActivity`（全限定名已解析成功，不会闪退） |
| 前台服务 | `com.keepscreen.app.KeepScreenService`（含 `foregroundServiceType`） |
| 权限 | FOREGROUND_SERVICE、FOREGROUND_SERVICE_SPECIAL_USE、POST_NOTIFICATIONS、WAKE_LOCK、SYSTEM_ALERT_WINDOW、PACKAGE_USAGE_STATS(使用情况访问·前台App检测用)、QUERY_ALL_PACKAGES(应用选择器用) |
| 原生 ABI | arm64-v8a · armeabi-v7a · x86_64（真机与模拟器均可装） |
| 签名 | **APK Signature Scheme v2 验证通过**，证书为 `CN=Android Debug` |
| targetSdk | 36 |

> **关于签名**：本次是 `flutter build apk --release` 且未配置正式签名，Flutter 自动用**调试证书**签名——自己装到手机上完全没问题，但**不能上应用商店**（商店要求正式 keystore 签名，且调试证书无法升级覆盖）。若将来要上架或做正式分发，需改用自有 keystore 重新打包（可在 `android/app/build.gradle.kts` 配 `signingConfigs`）。
>
> **体积说明**：APK 41.6 MB 是因为 3 套 CPU 架构的 `libflutter.so` 全打进去了。只发给安卓真机可只保留 arm 架构，体积能降到约 20 MB：`flutter build apk --release --target-platform android-arm64`。

---

## 四、安装与测试

1. 把 `常亮小助手-release.apk` 拷到手机，点击安装（允许“未知来源”）。
2. 打开 App → 点中央发光开关。
3. **首次会跳到系统设置**，请开启「常亮小助手 → 显示在其他应用上」（用于后台常亮悬浮窗），返回后再次点开关。
4. 验证：
   - 前台：屏幕一直亮，状态显示“屏幕常亮中”。
   - 后台：按 Home 回到桌面，屏幕仍亮（悬浮窗生效）；下拉通知栏可见“常亮小助手运行中”。
   - 关闭：回 App 点开关，或点通知栏通知进 App 关闭。

---

## 五、防后台被杀（重要！）

即使有前台服务，国产 ROM（小米/华为/OPPO/vivo/荣耀）仍会杀后台。请引导用户在系统里设置：

- **关闭电池优化**：设置 → 应用 → 常亮小助手 → 电池 → 无限制 / 不允许电池优化。
- **加白名单/自启动**：设置 → 应用启动管理 → 允许常亮小助手自启动、关联启动、后台运行。
- 不同品牌路径不同，App 内“屏幕常亮中”状态下可再次点开关旁提示引导。

> 这是系统层级限制，无法 100% 保证不被杀，但按上面设置可大幅降低概率。

---

## 六、已知限制与边界

- **仅安卓**：iOS 受系统限制无法做到全局常亮，V1 未做（需求文档已记录）。
- **悬浮窗权限**：Android 10+ 需用户手动授权，否则降级为“仅前台常亮”。
- **烧屏/掉电**：长期常亮有风险，建议用完即关；通知栏常驻可随时关闭。
- **不做商店上架**：本指南只到本地 APK，应用商店上架与资质需另行处理。

---

## 七、常见报错排查

| 报错 | 原因 | 处理 |
|---|---|---|
| **卡在 `Running Gradle task 'assembleRelease'...` 十几分钟无进展** | 首次构建要从 `services.gradle.org` 下载 Gradle 发行包（`gradle-9.3.1-all.zip` 约 230MB），国内实测仅 ~20KB/s，**需要 2 小时以上**；不是死机 | 已默认切到**腾讯云镜像 + `-bin` 包**（实测 6MB/s，约 30 秒下完），见下方"卡在 Gradle 下载"小节 |
| **`Your project path contains non-ASCII characters`**（`Failed to apply plugin 'com.android.application'`） | 工程路径含中文（如 `D:\WYH-副\keep_screen_app`），Windows 下 AGP 直接拒绝构建 | **已把构建工程迁到纯英文路径 `D:\WYH_build\keep_screen_app`**，产物仍复制到中文目录。不要用 `android.overridePathCheck=true` 硬绕过——后续 NDK/aapt2 仍可能出问题 |
| `cmdline-tools not found` | 未装 SDK 命令行工具 | Android Studio → SDK Manager 安装 Command-line Tools |
| `Android Gradle plugin / Kotlin 版本不匹配` | Flutter 版本差异 | 用 `flutter create` 生成的标准配置即可，不要手改 gradle 版本 |
| 开启后后台仍息屏 | 未授予悬浮窗权限 / 被电池优化杀 | 按第五节设置 |
| `Manifest merger failed` | 清单冲突 | 确认只覆盖了本交付包的 `android/app/src/main`，未重复声明权限 |
| 真机安装被拦截 | 未知来源未开 | 设置 → 安全 → 允许未知来源安装 |
| `java.lang.ClassNotFoundException: com.keepscreen.app.MainActivity` | applicationId/namespace 与源码包不一致 | 必须用 `--org com.keepscreen --project-name app`；不要改源码包名 |
| `error: cannot find symbol R` | Kotlin 文件包名与 Gradle namespace 不一致 | 同上，保持 `com.keepscreen.app` 一致；不要手改 build.gradle 的 namespace |
| `MissingForegroundServiceTypeException`（Android 14+） | 前台服务未声明类型 | 已用 `specialUse` 类型声明，正常；勿删除 manifest 中 service 的 `foregroundServiceType` |

---

## 八、卡在 Gradle 下载？——国内镜像加速（已默认开启）

### 现象
首屏停在 `Running Gradle task 'assembleRelease'...` 十几分钟甚至更久，看起来像卡死。

### 真实原因（实测数据）
首次构建必须先从 `services.gradle.org` 下载 Gradle 发行包。本机实测：

| 下载源 | 实测速度 | `gradle-9.3.1-all.zip`（约 230MB）预计耗时 |
|---|---|---|
| 官方 `services.gradle.org` | **约 19～25 KB/s** | **约 2.5～3 小时** |
| 腾讯云 `mirrors.cloud.tencent.com/gradle` | **约 6.3 MB/s** | 约 40 秒 |
| 华为云 `mirrors.huaweicloud.com/gradle` | 约 5.3 MB/s | 约 45 秒 |

所以那不是死机，是**在爬**。判断方法：看这个文件的大小是否还在涨——
`C:\Users\wyh17\.gradle\wrapper\dists\gradle-*\*\*.zip.part`

### 已做的加速改动（本工程已生效，重跑脚本会自动保持）
1. **`android/gradle/wrapper/gradle-wrapper.properties`**：`distributionUrl` 由官方 `-all.zip` 改为
   `https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-bin.zip`
   （换腾讯云镜像 + 改用 `-bin` 包，体积减半，构建功能完全一致）
2. **`android/settings.gradle.kts`**：`pluginManagement.repositories` 前置阿里云镜像
3. **`android/build.gradle.kts`**：`allprojects.repositories` 前置阿里云镜像
   （加速 AGP / Kotlin / AndroidX 依赖下载；镜像不可用时自动回退官方源）

### 如果哪天又想换回官方源
把 `distributionUrl` 改回 `https\://services.gradle.org/distributions/gradle-9.3.1-all.zip` 即可，其余不用动。

> 清理提示：切换镜像后，旧的半成品下载（约 9MB）留在
> `C:\Users\wyh17\.gradle\wrapper\dists\gradle-9.3.1-all\` 下，可手动删除，不影响使用。
