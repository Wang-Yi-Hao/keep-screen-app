# 常亮小助手 · 安卓源码与打包指南

> 一款一键让安卓屏幕保持常亮的小工具（科技风 UI）。基于 Flutter 框架，仅支持安卓平台。
> 核心机制：开启时给窗口加 `FLAG_KEEP_SCREEN_ON` + 启动**前台服务**（保活）+ 添加**透明悬浮窗**（退到后台也常亮）。
> 配套需求文档见同目录 `需求规格说明书.md`。本项目以 [MIT 许可证](LICENSE) 开源。

## 功能特性

- **手动常亮**：点中央发光开关一键点亮/关闭。
- **定时关闭**：手动开启后按设定分钟数（5/10/30/60）到点自动撤销。
- **充电时常亮**：插电即亮、拔电即灭；静态广播接收，App 退到后台也响应。
- **指定 App 前台时常亮**：选定某个 App，仅当它处于前台时保持常亮（内置应用选择器，含图标）。
- **多原因统一管理**：任一原因成立即常亮，全部撤销则自动停止服务，互不冲突。
- **首次启动权限引导（全部可选）**：列出电池优化白名单、悬浮窗、使用情况访问三项，均可跳过；不授予也能进入应用并使用基础常亮，权限可稍后在设置中开启。
- **定时降低亮度（防烧屏）**：开关 + 1–30 分钟下拉，常亮持续到点自动调暗系统背光（需授予“修改系统设置”权限）；关闭开关或取消常亮立即恢复原亮度。

---

## 一、本目录里有什么

```
常亮小助手/
├── pubspec.yaml                         # Flutter 工程描述（应用名 keep_screen）
├── pubspec.lock                         # 依赖锁定（保证可复现构建）
├── .metadata                           # Flutter 工程标识
├── build.cmd                            # ★★ 双击构建：默认执行「真机」脚本
├── 一键构建（真机）.ps1                  # ★ 构建 Release 包（真机安装 / 发布用）
├── 一键构建（测试）.ps1                  # ★ 构建 Debug 包（快速测试用）
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

> 说明：本仓库是**自包含工程**，已包含完整的 Flutter + Gradle 工程骨架（Gradle Wrapper、`build.gradle.kts`、`settings.gradle.kts`、启动图标 `mipmap-*` 等）。克隆到**纯英文路径**后，直接 `flutter build apk --release` 即可构建，无需先跑 `flutter create`；`一键构建（真机）.ps1` / `一键构建（测试）.ps1` 仍可作为带国内镜像加速的一键入口。

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

- **A-1 双击运行（默认构建真机/发布版）**：双击本目录下的 **`build.cmd`**。它会以 `-ExecutionPolicy Bypass` 调用 `一键构建（真机）.ps1`，不受执行策略限制，出错窗口也会停留显示。
- **A-2 构建真机/发布版**：
  ```powershell
  & ".\一键构建（真机）.ps1"
  ```
- **A-3 构建测试/Debug 版**：
  ```powershell
  & ".\一键构建（测试）.ps1"
  ```
  > 若提示脚本被禁用，先执行一次：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`（输 `Y` 确认）。

跑完 APK 落在仓库根目录：
- 默认**拆分 ABI 小包**：`常亮小助手-arm64-v8a-release.apk`（主流机型）、`常亮小助手-armeabi-v7a-release.apk`（老旧设备）、`常亮小助手-x86_64-release.apk`（模拟器），单包约 15MB；手机按架构选一个安装即可。
- 如需包含全部架构的**胖包**单文件（约 45MB），把脚本顶部的 `$BuildFatApk` 改为 `$true` 再跑，会生成 `常亮小助手-release.apk`。

> 所有 APK 均已被 `.gitignore` 忽略，不会误提交。

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
#    默认拆分 ABI 出小包（单包约 15MB）；要出含全部架构的胖包用：flutter build apk --release
flutter build apk --release --split-per-abi

# 5) 复制成品 APK 到仓库目录（拆分小包示例，按需复制对应架构）
Copy-Item "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" "$src\常亮小助手-arm64-v8a-release.apk" -Force
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
2. 首次打开会进入**权限引导页**：列出电池优化白名单、悬浮窗、使用情况访问三项，均**可跳过**；不授予也能进入应用并使用基础常亮，需要时在设置中再开启。悬浮窗授权后 App 退到后台仍可常亮；未授权则仅前台常亮。
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

- **仅支持安卓平台**：本工具专注于安卓系统的全局常亮能力，未做其他平台的适配。
- **后台常亮依赖悬浮窗权限（可选）**：Android 10+ 需用户手动授权“显示在其他应用上”；未授权时仅前台常亮，App 内开启主开关会有提示，可在设置中再开启。
- **烧屏/掉电**：长期常亮有风险，建议用完即关；通知栏常驻可随时关闭。
- **签名（正式分发）**：仓库已内置发布签名配置。当 `android/key.properties` + `android/release-key.jks` 存在时，自动用**你的自有密钥**签名（推荐，跨机器构建签名一致、用户可平滑更新）；缺失时回退到调试证书（仅本地自测、不能上应用商店）。生成密钥与填写方法见 `android/key.properties.example`。注意：调试证书签名的包**不能上应用商店**。
- **体积**：一键脚本默认 `--split-per-abi` 拆分 ABI，单包约 15MB（主流机型选 `arm64-v8a`）。若需要包含全部架构的胖包，把脚本顶部 `$BuildFatApk` 改为 `$true`，单文件约 45MB。

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

---

## 九、检查更新功能（V3 新增）

App 内置「检查更新」：设置卡片底部「检查更新」可手动点查；每次启动也会在后台静默检查一次，发现新版本才弹窗提醒（不影响正常使用）。

### 工作原理
- 本机版本号（`versionCode`）由原生 `getAppVersion` 读取，与 `pubspec.yaml` 的 `version: x.y.z+code` 中 `+` 后的 `code` 一致（已自动扣除拆分 ABI 打包加的 1000×ABI 偏移）。
- App 联网读取你托管的 `version.json`，比较其中的 `versionCode`：远程更大 → 判定有更新。
- 有更新时弹窗展示新版本号与更新说明，点「立即更新」**直接在应用内下载对应架构的 APK 并显示进度条**，下载完成后自动调起系统安装器安装（无需离开 App 去浏览器下载）。
  - 若远程未提供 `downloadTemplate`（或无法识别本机架构），则回退为打开浏览器跳转到 `url` 发布页，由用户手动下载。
  - Android 8.0+ 首次安装未知来源应用需在系统设置中允许本 App“安装未知应用”，App 会自动引导你到该设置项。

### 你需要做三件事
1. **托管 `version.json`**：把仓库根目录的 `version.json` 推到仓库即可（App 默认已配置本仓库的读取地址）。
   - 读取数据源列表在 `lib/main.dart` 顶部的 `_updateInfoUrls` 常量，依次尝试、任一成功即用：
     1. **GitHub Contents API**（返回实时内容，无 CDN 缓存问题，最可靠）；
     2. jsDelivr 主站镜像（国内可达，但有最长约 12 小时缓存）；
     3. jsDelivr Fastly 镜像；
     4. GitHub raw（兜底）。
   - 若仓库默认分支不是 `main`，把列表里的 `@main` 和 `/main/` 改成实际分支名。
   - 注意：jsDelivr 对分支文件有最长约 12 小时缓存；发版后想立即生效，可访问
     `https://purge.jsdelivr.net/gh/用户名/仓库@main/version.json` 手动刷新缓存。
2. **发布 APK 到 GitHub Releases**：用「一键构建（真机）.ps1」构建，产物为 `keep-screen-<架构>-release.apk`（纯 ASCII 文件名，供下载模板直接引用）。在 GitHub 上创建 Release（**tag 务必与下载模板里的版本号一致**，如 `v1.1.0`），把三个架构的 APK 一并上传为资产。
3. **发布新版本时同步两处**：
   - 改 `pubspec.yaml` 的 `version`（如 `1.1.0+2`，把 `+` 后的整数 `versionCode` 改大）；
   - 改 `version.json` 的 `version` / `versionCode` / `notes` / `downloadTemplate`（`{abi}` 会自动替换成设备架构，如 `arm64-v8a`），保证 `versionCode` 比旧版大且一致。

### `version.json` 字段说明
| 字段 | 含义 |
| --- | --- |
| `version` | 展示用的版本名，如 `1.1.0` |
| `versionCode` | 整数版本号，App 以此判断是否“有更新”（必须比旧版大） |
| `notes` | 更新说明（弹窗内展示，可用 `\n` 换行） |
| `url` | 回退用的发布页地址（无 `downloadTemplate` 或下载失败时打开） |
| `downloadTemplate` | 应用内下载地址模板，其中 `{abi}` 会被替换成设备架构（arm64-v8a / armeabi-v7a / x86_64）；缺失则回退打开 `url` |
| `mandatory` | `true` 时弹窗不可关闭（强制更新，且下载不可取消），默认 `false` |

> 说明：本功能支持“检测 + 应用内下载安装”；APK 分发仍由你自己打包并上传到 GitHub Releases（符合本工具“仅本地打包、不上架商店”的定位）。

---

## 开源许可

本项目基于 [MIT License](LICENSE) 开源，你可自由使用、修改和分发，需保留版权与许可声明。

## 免责声明

长期屏幕常亮可能导致烧屏、加速电池老化，请谨慎使用并自行承担风险。
