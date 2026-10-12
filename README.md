# 常亮小助手 · 安卓源码与打包指南

> 一款一键让安卓屏幕保持常亮的小工具（科技风 UI）。Flutter 跨端框架，仅安卓。
> 核心机制：开启时给窗口加 `FLAG_KEEP_SCREEN_ON` + 启动**前台服务**（保活）+ 添加**透明悬浮窗**（退到后台也常亮）。
> 配套需求文档见同目录 `需求规格说明书.md`。本项目以 [MIT 许可证](LICENSE) 开源。

## 功能特性

- **手动常亮**：点中央发光开关一键点亮/关闭。
- **定时关闭**：手动开启后按设定分钟数（5/10/30/60）到点自动撤销。
- **充电时常亮**：插电即亮、拔电即灭；静态广播接收，App 退到后台也响应。
- **指定 App 前台时常亮**：选定某个 App，仅当它处于前台时保持常亮（内置应用选择器，含图标）。
- **多原因统一管理**：任一原因成立即常亮，全部撤销则自动停止服务，互不冲突。
- **首次启动权限引导**：电池优化白名单、悬浮窗为必选；使用情况访问为可选（指定 App 功能需要）。

---

## 一、本目录里有什么

```
常亮小助手/
├── pubspec.yaml                         # Flutter 工程描述（应用名 keep_screen）
├── build.cmd                            # ★★ 双击即可构建（推荐入口）
├── 一键构建.ps1                         # ★ 一键构建脚本（被 build.cmd 调用）
├── LICENSE                              # MIT 许可证
├── .gitignore                           # 已忽略 APK / build / 本地配置等
├── 需求规格说明书.md                     # 需求文档
├── lib/
│   └── main.dart                        # 科技风主界面 + MethodChannel 调用原生
└── android/app/src/main/
    ├── AndroidManifest.xml              # 权限 + 前台服务声明 + 主 Activity
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

> 说明：本仓库包含**全部应用层自定义源码**，但未包含 Flutter 自动生成的 **Gradle 工程配置**（gradle wrapper、`build.gradle`、`settings.gradle`、mipmap 启动图标、`MainApplication` 等）。构建脚本会在你本机用 `flutter create` 一次性生成这些骨架，再用仓库源码覆盖——无需你手动处理。

---

## 二、前置要求（构建 APK 必需，只装 Flutter 不够）

构建安卓 APK 还需要 **Android 工具链**：
- **JDK 17**（Android Studio 自带，无需单独装）
- **Android SDK**：至少包含 Platform（建议 API 34/35）、Build-Tools、Android SDK Command-line Tools、Platform-Tools
- 接受协议：`sdkmanager --licenses`

最省心做法：**安装 Android Studio**（自带 JDK + SDK + 模拟器），首次打开按向导把 SDK 装好。Flutter 会自动在默认路径 `%LOCALAPPDATA%\Android\Sdk` 找到 SDK；若装到别的盘，请在系统环境变量设 `ANDROID_HOME` 指向 SDK 目录。

验证工具链是否齐全（把 `flutter` 换成本机 Flutter 路径，或先把它加入 PATH）：
```powershell
flutter doctor -v
```
确认 Android 相关项都是绿色勾（√），没有红叉（✗）。有红叉就按提示装对应组件。

---

## 三、构建（三种方式，选一个）

### 方式 A · 一键脚本（推荐，最简单）

本目录已附脚本，它会自动：定位 Flutter → `flutter create` 生成工程骨架 → 覆盖源码 → 切国内镜像 → `pub get` → 构建 APK → 复制成品到仓库根目录。

- **A-1 双击运行（最省事）**：双击本目录下的 **`build.cmd`**。它会以 `-ExecutionPolicy Bypass` 调用脚本，不受执行策略限制，出错窗口也会停留显示。
- **A-2 在 PowerShell 里运行**：
  ```powershell
  & ".\一键构建.ps1"
  ```
  > 若提示脚本被禁用，先执行一次：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`（输 `Y` 确认）。

跑完 APK 落在仓库根目录的 `常亮小助手-release.apk`（已被 `.gitignore` 忽略）。

> ⚠️ **构建工程必须放在纯英文路径**：Windows 下 AGP 会拒绝含中文的工程路径（报 `Your project path contains non-ASCII characters`）。脚本已自动把构建目录设到系统临时目录下的纯英文路径，无需你操心。
> Gradle 发行包与依赖缓存在用户主目录（`~/.gradle`、`~/.pub-cache`），与工程目录无关，因此用临时目录不会导致每次重新下载。

### 方式 B · 手动命令（想自己掌控每一步）

把下面命令里的 `<仓库目录>` 换成本仓库克隆后的**纯英文路径**（例如 `C:\src\keep-screen-app`）；若仓库路径含中文，请先把仓库放到纯英文目录再执行。

```powershell
# 0) 把 Flutter 加入本次会话 PATH（按本机实际路径修改；已在 PATH 可跳过）
$env:PATH += ";$env:USERPROFILE\flutter\bin"

$src = "<仓库目录>"
$build = "$env:TEMP\keep_screen_build\keep_screen_app"   # 纯英文构建目录

# 1) 生成标准 Flutter 安卓工程骨架
#    --org + --project-name 组合必须让 applicationId/namespace = com.keepscreen.app
#    这与源码包名 com.keepscreen.app 严格一致，否则 R 类与类解析会失败
New-Item -ItemType Directory -Path (Split-Path $build) -Force | Out-Null
cd (Split-Path $build)
flutter create --org com.keepscreen --project-name app keep_screen_app

# 2) 用仓库源码精确覆盖（只覆盖作者文件，保留 Flutter 生成的 mipmap 与 MainApplication）
Copy-Item "$src\lib\main.dart" "$build\lib\main.dart" -Force
Copy-Item "$src\android\app\src\main\AndroidManifest.xml" "$build\android\app\src\main\AndroidManifest.xml" -Force
$srcK="$src\android\app\src\main\kotlin\com\keepscreen\app"; $dstK="$build\android\app\src\main\kotlin\com\keepscreen\app"
if(!(Test-Path $dstK)){New-Item -ItemType Directory -Path $dstK -Force|Out-Null}
Copy-Item "$srcK\*.kt" "$dstK" -Force
Copy-Item "$src\android\app\src\main\res\values\styles.xml"      "$build\android\app\src\main\res\values\styles.xml" -Force
Copy-Item "$src\android\app\src\main\res\values\strings.xml"     "$build\android\app\src\main\res\values\strings.xml" -Force
Copy-Item "$src\android\app\src\main\res\drawable\launch_background.xml" "$build\android\app\src\main\res\drawable\launch_background.xml" -Force
Copy-Item "$src\android\app\src\main\res\drawable\ic_keep.xml"   "$build\android\app\src\main\res\drawable\ic_keep.xml" -Force

# 3) 切国内镜像（Gradle 下载源 + Maven 仓库），否则首次要等很久
$wf="$build\android\gradle\wrapper\gradle-wrapper.properties"
$c=[System.IO.File]::ReadAllText($wf)
$c=[regex]::Replace($c,'https\\://services\.gradle\.org/distributions/gradle-([\d\.]+)(-\w+)?\.zip','https\://mirrors.cloud.tencent.com/gradle/gradle-$1-bin.zip')
[System.IO.File]::WriteAllText($wf,$c,(New-Object System.Text.UTF8Encoding($false)))

# 4) 拉依赖并构建 APK
cd $build
flutter pub get
flutter build apk --release

# 5) 复制成品 APK 到仓库目录
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$src\常亮小助手-release.apk" -Force
```

### 方式 C · 连真机直接运行（跳过 APK，最快看到效果）

手机开 **USB 调试**，数据线连电脑，在构建工程目录执行：
```powershell
cd <上面的 $build 目录>
flutter devices        # 确认手机出现在列表
flutter run --release  # 编译并直接装到手机运行
```

> 修复记录：早期版本 Manifest 用了相对类名 `.MainActivity`；现改为**全限定类名 `com.keepscreen.app.MainActivity`**，并用 `--project-name app` 使 namespace 与源码包严格一致，彻底避免 `ClassNotFound` / `找不到符号 R` 两类编译失败。

---

## 四、安装与测试

1. 把 `常亮小助手-release.apk` 拷到手机，点击安装（允许“未知来源”）。
2. 首次打开会进入**权限引导页**：电池优化白名单、悬浮窗为**必选**；使用情况访问为可选（“指定 App 前台时常亮”需要）。
3. 进入后点中央发光开关。
4. 验证：
   - 前台：屏幕一直亮，状态显示“屏幕常亮中”。
   - 后台：按 Home 回到桌面，屏幕仍亮（悬浮窗生效）；下拉通知栏可见“常亮小助手运行中”。
   - 关闭：回 App 点开关，或点通知栏通知进 App 关闭。关闭后不会立刻息屏，而是按系统设定的休眠时间到点熄灭。

---

## 五、防后台被杀（重要！）

即使有前台服务，国产 ROM（小米/华为/OPPO/vivo/荣耀）仍可能杀后台。请引导用户在系统里设置：

- **关闭电池优化**：设置 → 应用 → 常亮小助手 → 电池 → 无限制 / 不允许电池优化。
- **加白名单/自启动**：设置 → 应用启动管理 → 允许常亮小助手自启动、关联启动、后台运行。

> 这是系统层级限制，无法 100% 保证不被杀，但按上面设置可大幅降低概率。

---

## 六、已知限制与边界

- **仅安卓**：iOS 受系统限制无法做到全局常亮，本项目未做。
- **后台常亮依赖悬浮窗权限**：Android 10+ 需用户手动授权“显示在其他应用上”；若被撤销，App 内开启时会重新引导授予。
- **烧屏/掉电**：长期常亮有风险，建议用完即关；通知栏常驻可随时关闭。
- **签名**：默认 `flutter build apk --release` 用调试证书签名，自己安装没问题，但**不能上应用商店**。正式分发需用自有 keystore（在 `android/app/build.gradle.kts` 配 `signingConfigs`）。
- **体积**：APK 约 40MB，因为 3 套 CPU 架构的 `libflutter.so` 全打进去了。只发真机可只保留 arm 架构降到约 20MB：`flutter build apk --release --target-platform android-arm64`。

---

## 七、常见报错排查

| 报错 | 原因 | 处理 |
|---|---|---|
| **卡在 `Running Gradle task 'assembleRelease'...` 十几分钟无进展** | 首次构建要从 `services.gradle.org` 下载 Gradle 发行包，国内很慢，不是死机 | 脚本已默认切到**腾讯云镜像 + `-bin` 包**，见第八节 |
| **`Your project path contains non-ASCII characters`** | 工程路径含中文，Windows 下 AGP 拒绝构建 | 把构建目录放到纯英文路径（脚本已自动处理）；不要用 `android.overridePathCheck=true` 硬绕过 |
| `cmdline-tools not found` | 未装 SDK 命令行工具 | Android Studio → SDK Manager 安装 Command-line Tools |
| `Android Gradle plugin / Kotlin 版本不匹配` | Flutter 版本差异 | 用 `flutter create` 生成的标准配置即可，不要手改 gradle 版本 |
| 开启后后台仍息屏 | 未授予悬浮窗权限 / 被电池优化杀 | 按第五节设置 |
| `Manifest merger failed` | 清单冲突 | 确认只覆盖了仓库的 `android/app/src/main`，未重复声明权限 |
| 真机安装被拦截 | 未知来源未开 | 设置 → 安全 → 允许未知来源安装 |
| `java.lang.ClassNotFoundException: com.keepscreen.app.MainActivity` | applicationId/namespace 与源码包不一致 | 必须用 `--org com.keepscreen --project-name app`；不要改源码包名 |
| `error: cannot find symbol R` | Kotlin 文件包名与 Gradle namespace 不一致 | 保持 `com.keepscreen.app` 一致；不要手改 build.gradle 的 namespace |
| `MissingForegroundServiceTypeException`（Android 14+） | 前台服务未声明类型 | 已用 `specialUse` 类型声明，正常；勿删除 manifest 中 service 的 `foregroundServiceType` |

---

## 八、卡在 Gradle 下载？——国内镜像加速（脚本已默认开启）

### 现象
首屏停在 `Running Gradle task 'assembleRelease'...` 十几分钟甚至更久，看起来像卡死。

### 真实原因
首次构建必须先从 `services.gradle.org` 下载 Gradle 发行包，国内速度很慢。判断方法：看 `%USERPROFILE%\.gradle\wrapper\dists\gradle-*\*\*.zip.part` 这个文件的大小是否还在涨——在涨就是在下，不是死机。

### 脚本已做的加速改动
1. **`android/gradle/wrapper/gradle-wrapper.properties`**：`distributionUrl` 由官方 `-all.zip` 改为 `https://mirrors.cloud.tencent.com/gradle/gradle-<版本>-bin.zip`（换腾讯云镜像 + 改用 `-bin` 包，体积减半）。
2. **`android/settings.gradle.kts`** 与 **`android/build.gradle.kts`**：前置阿里云 Maven 镜像（加速 AGP / Kotlin / AndroidX 依赖下载；镜像不可用时自动回退官方源）。

### 如果想换回官方源
把 `distributionUrl` 改回 `https://services.gradle.org/distributions/gradle-<版本>-all.zip` 即可。

---

## 开源许可

本项目基于 [MIT License](LICENSE) 开源，你可自由使用、修改和分发，需保留版权与许可声明。

## 免责声明

长期屏幕常亮可能导致烧屏、加速电池老化，请谨慎使用并自行承担风险。
