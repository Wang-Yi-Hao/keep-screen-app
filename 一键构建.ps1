# ============================================================
# 常亮小助手 - 一键整合 + 构建 Release APK
# 适用：已安装 Flutter 3.x + Android SDK（含 JDK 17）的 Windows 电脑
# 推荐在本机“已打开的 PowerShell 窗口”里执行本脚本：
#   & "D:\WYH-副\常亮小助手\一键构建.ps1"
# 若被策略拦截，先执行一次（仅需一次）：
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# ============================================================

$ErrorActionPreference = "Continue"   # 不让单步错误直接杀掉窗口

function Pause-Exit {
    param($msg)
    if ($msg) { Write-Host $msg -ForegroundColor Red }
    Write-Host ""
    Write-Host "（窗口将保持打开，按回车退出）" -ForegroundColor Yellow
    Read-Host | Out-Null
}

try {
    # 1) 把 Flutter 加入当前会话 PATH（如你本机路径不同，请改这一行）
    $flutterDir = "C:\Users\wyh17\flutter\bin"
    if ($env:PATH -notlike "*$flutterDir*") { $env:PATH += ";$flutterDir" }

    # 2) 确认 flutter 可用
    Write-Host ">>> 检查 Flutter ..." -ForegroundColor Cyan
    $ver = & flutter --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Pause-Exit "!!! 找不到 flutter 命令。请确认 C:\Users\wyh17\flutter\bin 存在，或修改脚本里的 flutterDir 路径。"
        exit 1
    }
    Write-Host ($ver | Select-Object -First 2)

    # 3) 路径
    #    ⚠️ 关键：Windows 下 AGP/Gradle 会拒绝「含非 ASCII(中文)字符」的工程路径，
    #    报 "Your project path contains non-ASCII characters" 直接构建失败。
    #    所以：构建工程放纯英文目录，最终 APK 依然复制到中文产物目录。
    $productDir = "D:\WYH-副\常亮小助手"      # 产物目录（可含中文，只用来放源码/文档/APK）
    $parentDir  = "D:\WYH_build"              # 构建工作区（必须是纯英文！）
    $projDir    = "$parentDir\keep_screen_app"

    if (-not (Test-Path $productDir)) {
        Pause-Exit "!!! 产品目录不存在：$productDir"
        exit 1
    }

    if ($parentDir -match '[^\x00-\x7F]') {
        Pause-Exit "!!! 构建路径含中文/非英文字符：$parentDir`n    请把本脚本里的 `$parentDir 改成纯英文路径（例如 D:\WYH_build）后再运行。"
        exit 1
    }
    if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }

    if (Test-Path "D:\WYH-副\keep_screen_app") {
        Write-Host "    提示：旧的中文路径工程 D:\WYH-副\keep_screen_app 已废弃，可手动删除释放空间。" -ForegroundColor DarkYellow
    }

    # 4) 生成标准 Flutter 安卓工程骨架
    #    --org + --project-name 组合 => applicationId/namespace = com.keepscreen.app
    #    必须与源码包名 com.keepscreen.app 完全一致，否则 R 类与类名解析失败
    if (-not (Test-Path $projDir)) {
        Write-Host ">>> [1/6] flutter create 生成工程 ..." -ForegroundColor Cyan
        Set-Location $parentDir
        & flutter create --org com.keepscreen --project-name app keep_screen_app
        if ($LASTEXITCODE -ne 0) { Pause-Exit "!!! flutter create 失败，见上方错误。"; exit 1 }
    } else {
        Write-Host ">>> [1/6] 工程已存在，跳过 flutter create（如需重建请先删除 $projDir）" -ForegroundColor Yellow
    }

    # 5) 用交付源码覆盖（只覆盖我们作者文件，保留 Flutter 生成的 mipmap 图标与 MainApplication）
    Write-Host ">>> [2/6] 覆盖源码 ..." -ForegroundColor Cyan
    Copy-Item "$productDir\lib\main.dart" "$projDir\lib\main.dart" -Force
    Copy-Item "$productDir\android\app\src\main\AndroidManifest.xml" "$projDir\android\app\src\main\AndroidManifest.xml" -Force

    $srcK = "$productDir\android\app\src\main\kotlin\com\keepscreen\app"
    $dstK = "$projDir\android\app\src\main\kotlin\com\keepscreen\app"
    if (-not (Test-Path $dstK)) { New-Item -ItemType Directory -Path $dstK -Force | Out-Null }
    # V2 起新增了 KeepEvents.kt / PowerEventReceiver.kt，直接按目录整体同步所有 Kotlin 文件，避免漏拷
    Copy-Item "$srcK\*.kt" "$dstK" -Force

    Copy-Item "$productDir\android\app\src\main\res\values\styles.xml"          "$projDir\android\app\src\main\res\values\styles.xml" -Force
    Copy-Item "$productDir\android\app\src\main\res\values\strings.xml"         "$projDir\android\app\src\main\res\values\strings.xml" -Force
    Copy-Item "$productDir\android\app\src\main\res\drawable\launch_background.xml" "$projDir\android\app\src\main\res\drawable\launch_background.xml" -Force
    Copy-Item "$productDir\android\app\src\main\res\drawable\ic_keep.xml"       "$projDir\android\app\src\main\res\drawable\ic_keep.xml" -Force

    # 6) 【加速关键】把 Gradle 下载源与 Maven 仓库切到国内镜像
    #    官方 services.gradle.org 在国内实测仅 ~20KB/s，gradle-9.3.1-all.zip(约230MB) 要下 2 小时以上；
    #    腾讯云镜像实测 6MB/s，且改用体积减半的 -bin 包，通常 30 秒左右下完。
    Write-Host ">>> [3/6] 配置国内镜像加速 ..." -ForegroundColor Cyan

    $wrapperFile = "$projDir\android\gradle\wrapper\gradle-wrapper.properties"
    if (Test-Path $wrapperFile) {
        $c = [System.IO.File]::ReadAllText($wrapperFile)
        if ($c -notmatch 'mirrors\.cloud\.tencent\.com') {
            $c = [regex]::Replace($c, 'https\\://services\.gradle\.org/distributions/gradle-([\d\.]+)-all\.zip', 'https\://mirrors.cloud.tencent.com/gradle/gradle-$1-bin.zip')
            $c = [regex]::Replace($c, 'https\\://services\.gradle\.org/distributions/gradle-([\d\.]+)-bin\.zip', 'https\://mirrors.cloud.tencent.com/gradle/gradle-$1-bin.zip')
            [System.IO.File]::WriteAllText($wrapperFile, $c, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "    已切换 Gradle 下载源 -> 腾讯云镜像（bin 包）" -ForegroundColor Green
        } else {
            Write-Host "    Gradle 镜像已配置，跳过" -ForegroundColor DarkGray
        }
    }

    $mirrorLines = @(
        '        maven { url = uri("https://maven.aliyun.com/repository/google") }',
        '        maven { url = uri("https://maven.aliyun.com/repository/public") }',
        '        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }',
        '        google()'
    ) -join "`r`n"

    foreach ($gf in @("$projDir\android\settings.gradle.kts", "$projDir\android\build.gradle.kts")) {
        if (Test-Path $gf) {
            $g = [System.IO.File]::ReadAllText($gf)
            if ($g -notmatch 'maven\.aliyun\.com') {
                $g = $g.Replace("        google()", $mirrorLines)
                [System.IO.File]::WriteAllText($gf, $g, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "    已为 $(Split-Path $gf -Leaf) 添加阿里云 Maven 镜像" -ForegroundColor Green
            }
        }
    }

    # 7) 拉取依赖
    Set-Location $projDir
    Write-Host ">>> [4/6] flutter pub get ..." -ForegroundColor Cyan
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { Pause-Exit "!!! flutter pub get 失败，见上方错误。"; exit 1 }

    # 7) 构建 Release APK
    Write-Host ">>> [5/6] flutter build apk --release（首次会下载 Gradle 与依赖，走国内镜像通常 1-5 分钟）..." -ForegroundColor Cyan
    & flutter build apk --release
    if ($LASTEXITCODE -ne 0) { Pause-Exit "!!! flutter build apk 失败，见上方错误。常见：缺 Android SDK / JDK / 协议未接受，先跑 flutter doctor -v 排查。"; exit 1 }

    # 8) 复制到产品目录
    $apk = "build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $apk) {
        Copy-Item $apk "$productDir\常亮小助手-release.apk" -Force
        Write-Host ">>> [6/6] 完成！APK 位于：$productDir\常亮小助手-release.apk" -ForegroundColor Green
    } else {
        Pause-Exit "!!! 未找到 APK，构建可能失败，请查看上方错误。"
        exit 1
    }

    Write-Host ""
    Write-Host "后续：把 APK 传到手机安装；首次开启常亮会跳设置页，请允许“显示在其他应用上”；" -ForegroundColor White
    Write-Host "      并在系统设置里给本 App“关闭电池优化 + 允许后台运行”，防止被国产 ROM 杀后台。" -ForegroundColor White
    Pause-Exit
}
catch {
    Pause-Exit "!!! 脚本异常：$($_.Exception.Message)"
    exit 1
}
