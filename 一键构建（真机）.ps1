# ============================================================
# 常亮小助手 - 一键构建 Release APK（真机/发布版）
# 适用：已安装 Flutter 3.x + Android SDK（含 JDK 17）的电脑
# 用法：在 PowerShell 里执行：
#   & ".\一键构建（真机）.ps1"
# 若被策略拦截，先执行一次（仅需一次）：
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
# ============================================================

$ErrorActionPreference = "Continue"   # 不让单步错误直接杀掉窗口

# 默认拆分 ABI 出小包（arm64-v8a / armeabi-v7a / x86_64 分别打包，单包约 15MB，手机按需安装）；
# 若需要包含全部架构的“胖包”（单文件、约 45MB、兼容性最好），把下面改为 $true。
$BuildFatApk = $false

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
        Write-Host ">>> [1/6] 工程已就绪，跳过 flutter create" -ForegroundColor DarkGray
    } else {
        Write-Host ">>> [1/6] flutter create 生成工程骨架 ..." -ForegroundColor Cyan
        Set-Location $buildRoot
        & flutter create --org com.keepscreen --project-name app keep_screen_app
        if ($LASTEXITCODE -ne 0) { Pause-Exit "!!! flutter create 失败，见上方错误。"; exit 1 }
    }

    # 5) 用仓库源码覆盖（只覆盖作者文件，保留 Flutter 生成的 mipmap 图标与 MainApplication）
    Write-Host ">>> [2/6] 覆盖源码 ..." -ForegroundColor Cyan
    Copy-Item "$productDir\lib\main.dart" "$projDir\lib\main.dart" -Force
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

    # 5.1) 同步 Gradle 工程配置（含 release 签名配置、国内镜像、wrapper 版本）
    Copy-Item "$productDir\android\build.gradle.kts"     "$projDir\android\build.gradle.kts" -Force
    Copy-Item "$productDir\android\settings.gradle.kts"  "$projDir\android\settings.gradle.kts" -Force
    Copy-Item "$productDir\android\app\build.gradle.kts" "$projDir\android\app\build.gradle.kts" -Force
    Copy-Item "$productDir\android\gradle.properties"     "$projDir\android\gradle.properties" -Force
    Copy-Item "$productDir\android\gradlew"               "$projDir\android\gradlew" -Force
    Copy-Item "$productDir\android\gradlew.bat"           "$projDir\android\gradlew.bat" -Force
    Copy-Item "$productDir\android\gradle\wrapper\gradle-wrapper.properties" "$projDir\android\gradle\wrapper\gradle-wrapper.properties" -Force
    if (Test-Path "$productDir\android\key.properties") {
        Copy-Item "$productDir\android\key.properties" "$projDir\android\key.properties" -Force
        Write-Host "    已同步发布签名配置 key.properties" -ForegroundColor Green
    }
    if (Test-Path "$productDir\android\release-key.jks") {
        Copy-Item "$productDir\android\release-key.jks" "$projDir\android\release-key.jks" -Force
        Write-Host "    已同步发布密钥库 release-key.jks" -ForegroundColor Green
    } elseif (Test-Path "$productDir\android\*.keystore") {
        $ks = Get-ChildItem "$productDir\android\*.keystore" | Select-Object -First 1
        Copy-Item $ks.FullName "$projDir\android\$($ks.Name)" -Force
        Write-Host "    已同步发布密钥库 $($ks.Name)" -ForegroundColor Green
    }

    # 6) 【加速关键】把 Gradle 下载源与 Maven 仓库切到国内镜像
    #    官方 services.gradle.org 在国内实测仅 ~20KB/s；腾讯云镜像实测 6MB/s，
    #    且改用体积减半的 -bin 包。镜像不可用时依赖会自动回退官方源。
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

    # 8) 构建 Release APK
    if ($BuildFatApk) {
        Write-Host ">>> [5/6] flutter build apk --release（胖包：含全部 CPU 架构，单文件约 45MB）..." -ForegroundColor Cyan
        & flutter build apk --release
    } else {
        Write-Host ">>> [5/6] flutter build apk --release --split-per-abi（拆分 ABI 小包：单包约 15MB）..." -ForegroundColor Cyan
        & flutter build apk --release --split-per-abi
    }
    if ($LASTEXITCODE -ne 0) { Pause-Exit "!!! flutter build apk 失败，见上方错误。常见：缺 Android SDK / JDK / 协议未接受，先跑 flutter doctor -v 排查。"; exit 1 }

    # 9) 复制产物到源码目录（APK 已被 .gitignore 忽略，不会误提交）
    $outDir = "build\app\outputs\flutter-apk"
    if ($BuildFatApk) {
        $apk = "$outDir\app-release.apk"
        if (Test-Path $apk) {
            Copy-Item $apk "$productDir\常亮小助手-release.apk" -Force
            Write-Host ">>> [6/6] 完成！胖包位于：$productDir\常亮小助手-release.apk" -ForegroundColor Green
        } else {
            Pause-Exit "!!! 未找到 APK，构建可能失败，请查看上方错误。"
            exit 1
        }
    } else {
        $apks = Get-ChildItem "$outDir\app-*-release.apk" -ErrorAction SilentlyContinue
        if ($apks -and $apks.Count -gt 0) {
            foreach ($a in $apks) {
                $dstName = $a.Name -replace "^app-", "常亮小助手-"
                Copy-Item $a.FullName "$productDir\$dstName" -Force
            }
            Write-Host ">>> [6/6] 完成！拆分 APK 位于：$productDir\常亮小助手-<abi>-release.apk" -ForegroundColor Green
            Write-Host "    按手机架构选择安装：arm64-v8a（主流机型）/ armeabi-v7a（老旧设备）/ x86_64（模拟器）" -ForegroundColor White
        } else {
            Pause-Exit "!!! 未找到拆分 APK，构建可能失败，请查看上方错误。"
            exit 1
        }
    }

    Write-Host ""
    Write-Host "后续：把 APK 传到手机安装；首次启动会引导授予权限（电池优化白名单、悬浮窗为必选）；" -ForegroundColor White
    Write-Host "      并在系统设置里给本 App 允许后台运行，防止被国产 ROM 杀后台。" -ForegroundColor White
    Pause-Exit
}
catch {
    Pause-Exit "!!! 脚本异常：$($_.Exception.Message)"
    exit 1
}
