# ============================================================
# 常亮小助手 - 一键构建 Debug APK（测试版）
# 适用：已安装 Flutter 3.x + Android SDK（含 JDK 17）的电脑
# 用法：在 PowerShell 里执行：
#   & ".\一键构建（测试）.ps1"
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
    # 1) 定位 Flutter：优先用 PATH 里已有的，其次尝试常见安装位置
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        $candidates = @(
            "$env:USERPROFILE\flutter\bin",
            "$env:USERPROFILE\fvm\default\bin",
            "$env:LOCALAPPDATA\flutter\bin",
            "C:\flutter\bin",
            "C:\src\flutter\bin"
        )
        foreach ($c in $candidates) { if (Test-Path $c) { $env:PATH += ";$c"; break } }
    }

    Write-Host ">>> 检查 Flutter ..." -ForegroundColor Cyan
    $ver = & flutter --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Pause-Exit "!!! 找不到 flutter 命令。请先安装 Flutter 并加入 PATH，或修改脚本顶部的 candidates 路径。"
        exit 1
    }
    Write-Host ($ver | Select-Object -First 2)

    # 2) 源码目录 = 本脚本所在目录（即仓库根目录）
    $productDir = $PSScriptRoot

    # 3) 构建工作区：统一放到系统临时目录下的纯英文路径。
    #    原因：Windows 下 AGP 会拒绝含中文/非 ASCII 的工程路径
    #    （报 Your project path contains non-ASCII characters）。
    #    Gradle 发行包与依赖缓存在用户主目录(~/.gradle、~/.pub-cache)，与工程目录无关，
    #    所以用临时目录不会导致每次重新下载。
    $buildRoot = Join-Path $env:TEMP "keep_screen_build"
    $projDir   = Join-Path $buildRoot "keep_screen_app"
    if (-not (Test-Path $buildRoot)) { New-Item -ItemType Directory -Path $buildRoot -Force | Out-Null }

    # 4) 生成标准 Flutter 安卓工程骨架
    #    --org + --project-name => applicationId/namespace = com.keepscreen.app
    #    必须与源码包名 com.keepscreen.app 完全一致，否则 R 类与类名解析失败
    if (Test-Path "$projDir\android\app\build.gradle.kts") {
        Write-Host ">>> [1/5] 工程已就绪，跳过 flutter create" -ForegroundColor DarkGray
    } else {
        Write-Host ">>> [1/5] flutter create 生成工程骨架 ..." -ForegroundColor Cyan
        Set-Location $buildRoot
        & flutter create --org com.keepscreen --project-name app keep_screen_app
        if ($LASTEXITCODE -ne 0) { Pause-Exit "!!! flutter create 失败，见上方错误。"; exit 1 }
    }

    # 5) 用仓库源码覆盖（只覆盖作者文件，保留 Flutter 生成的 mipmap 图标与 MainApplication）
    Write-Host ">>> [2/5] 覆盖源码 ..." -ForegroundColor Cyan
    Copy-Item "$productDir\lib\main.dart" "$projDir\lib\main.dart" -Force
    # pubspec.yaml 决定 APK 的 versionName/versionCode（经 flutter.versionName/Code 写入 gradle），
    # 必须同步；否则 flutter create 生成的默认 1.0.0+1 会被打进包里，导致"改了版本号打包后仍显示 1.0.0"。
    Copy-Item "$productDir\pubspec.yaml" "$projDir\pubspec.yaml" -Force
    Write-Host "    已同步 pubspec.yaml（version=$((Select-String -Path "$projDir\pubspec.yaml" -Pattern '^version:\s*(\S+)').Matches.Groups[1].Value)）" -ForegroundColor DarkGray
    Copy-Item "$productDir\android\app\src\main\AndroidManifest.xml" "$projDir\android\app\src\main\AndroidManifest.xml" -Force

    $srcK = "$productDir\android\app\src\main\kotlin\com\keepscreen\app"
    $dstK = "$projDir\android\app\src\main\kotlin\com\keepscreen\app"
    if (-not (Test-Path $dstK)) { New-Item -ItemType Directory -Path $dstK -Force | Out-Null }
    # 直接按目录整体同步所有 Kotlin 文件，新增 .kt 也不会漏拷
    Copy-Item "$srcK\*.kt" "$dstK" -Force

    Copy-Item "$productDir\android\app\src\main\res\values\styles.xml"          "$projDir\android\app\src\main\res\values\styles.xml" -Force
    Copy-Item "$productDir\android\app\src\main\res\values\strings.xml"         "$projDir\android\app\src\main\res\values\strings.xml" -Force
    Copy-Item "$productDir\android\app\src\main\res\drawable\launch_background.xml" "$projDir\android\app\src\main\res\drawable\launch_background.xml" -Force
    Copy-Item "$productDir\android\app\src\main\res\drawable\ic_keep.xml"       "$projDir\android\app\src\main\res\drawable\ic_keep.xml" -Force

    # 5.1) 同步 Gradle 工程配置（含国内镜像、wrapper 版本）
    Copy-Item "$productDir\android\build.gradle.kts"     "$projDir\android\build.gradle.kts" -Force
    Copy-Item "$productDir\android\settings.gradle.kts"  "$projDir\android\settings.gradle.kts" -Force
    Copy-Item "$productDir\android\app\build.gradle.kts" "$projDir\android\app\build.gradle.kts" -Force
    Copy-Item "$productDir\android\gradle.properties"     "$projDir\android\gradle.properties" -Force
    Copy-Item "$productDir\android\gradlew"               "$projDir\android\gradlew" -Force
    Copy-Item "$productDir\android\gradlew.bat"           "$projDir\android\gradlew.bat" -Force
    Copy-Item "$productDir\android\gradle\wrapper\gradle-wrapper.properties" "$projDir\android\gradle\wrapper\gradle-wrapper.properties" -Force
    # Debug 包不需要 release 签名 key.properties

    # 6) 【加速关键】把 Gradle 下载源与 Maven 仓库切到国内镜像
    Write-Host ">>> [3/5] 配置国内镜像加速 ..." -ForegroundColor Cyan

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
    Write-Host ">>> [4/5] flutter pub get ..." -ForegroundColor Cyan
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { Pause-Exit "!!! flutter pub get 失败，见上方错误。"; exit 1 }

    # 8) 构建 Debug APK（编译更快，带调试信息，适合本地测试）
    Write-Host ">>> [5/5] flutter build apk --debug ..." -ForegroundColor Cyan
    & flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { Pause-Exit "!!! flutter build apk 失败，见上方错误。常见：缺 Android SDK / JDK / 协议未接受，先跑 flutter doctor -v 排查。"; exit 1 }

    # 9) 复制产物到源码目录（APK 已被 .gitignore 忽略，不会误提交）
    $apk = "build\app\outputs\flutter-apk\app-debug.apk"
    if (Test-Path $apk) {
        Copy-Item $apk "$productDir\常亮小助手-debug.apk" -Force
        Write-Host ">>> 完成！测试包位于：$productDir\常亮小助手-debug.apk" -ForegroundColor Green
    } else {
        Pause-Exit "!!! 未找到 APK，构建可能失败，请查看上方错误。"
        exit 1
    }

    Write-Host ""
    Write-Host "后续：把 APK 传到手机/模拟器安装即可测试。" -ForegroundColor White
    Pause-Exit
}
catch {
    Pause-Exit "!!! 脚本异常：$($_.Exception.Message)"
    exit 1
}
