# ============================================================
# 常亮小助手 - 上传更新包到服务器（与一键构建脚本相互独立）
# 用途：把本地构建好的 APK（及可选的 version.json）通过 scp 上传到自建服务器，
#       供 App 的「检查更新」直接下载。运行前提：本机已安装 OpenSSH 客户端
#       （Windows 10+ 在“设置→应用→可选功能”里添加“OpenSSH 客户端”）。
#
# 用法（推荐在 PowerShell 窗口里执行，便于看到输出）：
#   & ".\上传更新包到服务器.ps1"
# 若被策略拦截，先执行一次（仅需一次）：
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#
# 提示：本脚本只负责“上传”，请先用「一键构建（真机）.ps1」构建出 APK，再跑本脚本。
# ============================================================

# —— 错误兜底：任何异常都停在窗口里显示，避免“打开就闪退”看不到原因 ——
$ErrorActionPreference = "Stop"
trap {
    Write-Host ""
    Write-Host "!!! 脚本出错（第 $($_.InvocationInfo.ScriptLineNumber) 行）：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "（按回车关闭窗口）" -ForegroundColor Yellow
    Read-Host | Out-Null
    exit 1
}

# ------------------- ↓↓↓ 按需修改下面这些参数 ↓↓↓ -------------------
# 服务器 SSH 信息
$SshUser          = "root"            # 服务器 SSH 用户名（腾讯云 Lighthouse 默认 root）
$ServerIP          = "106.53.120.233" # 服务器公网 IP（即 App 检查地址里的 IP）
$SshPort           = 22               # SSH 端口（被改过就改这里）
$IdentityFile      = ""               # 私钥文件路径，如 "C:\Users\wyh17\.ssh\id_rsa"；
                                       # 留空则用密码登录（运行时需手动输入密码）
# 服务器目录（需与你的网站根目录对应；App 访问的是 http://IP/apks/ 与 http://IP/version.json）
# 本仓库的 Lighthouse 实例（广州）实际部署：Nginx 以 /var/www/keep-screen 为根目录、
# 开启 autoindex，所以 APK 放 /var/www/keep-screen/apks、version.json 放 /var/www/keep-screen/version.json。
# 若你以后改了服务器目录，改下面两行即可。
$RemoteApksDir     = "/var/www/keep-screen/apks"        # 服务器上 APK 存放目录
$RemoteVersionJson = "/var/www/keep-screen/version.json" # 服务器上 version.json 路径
# 本地源
$LocalDir          = $PSScriptRoot     # 本地 APK / version.json 所在目录（默认脚本同目录=项目根目录）
$UploadVersionJson = $true             # 是否一并上传本地 version.json（让服务器版本信息同步更新）
# ------------------- ↑↑↑ 参数结束 ↑↑↑ -------------------

function Pause-Exit {
    param($msg)
    if ($msg) { Write-Host $msg -ForegroundColor Red }
    Write-Host ""
    Write-Host "（按回车关闭窗口）" -ForegroundColor Yellow
    Read-Host | Out-Null
    exit 1
}

function Pause-Only {
    Write-Host ""
    Write-Host "（按回车关闭窗口）" -ForegroundColor Yellow
    Read-Host | Out-Null
    exit 0
}

# 定位 scp / ssh
$scp = Get-Command scp -ErrorAction SilentlyContinue
$ssh = Get-Command ssh -ErrorAction SilentlyContinue
if (-not $scp -or -not $ssh) {
    Pause-Exit "未找到 OpenSSH 客户端（scp/ssh）。请先安装：设置→应用→可选功能→添加“OpenSSH 客户端”。"
}

$sshTarget = "${SshUser}@${ServerIP}"
Write-Host ">>> 目标服务器：$sshTarget :$SshPort" -ForegroundColor Cyan

# 收集本地的 3 个架构 APK
$archFiles = @("keep-screen-arm64-v8a-release.apk",
               "keep-screen-armeabi-v7a-release.apk",
               "keep-screen-x86_64-release.apk")
$localApks = @()
foreach ($f in $archFiles) {
    $p = Join-Path $LocalDir $f
    if (Test-Path $p) {
        $localApks += $p
        Write-Host "    找到：$f" -ForegroundColor White
    } else {
        Write-Host "    [警告] 未找到：$f （请先运行一键构建脚本）" -ForegroundColor Yellow
    }
}
if ($localApks.Count -eq 0) {
    Pause-Exit "在 $LocalDir 下未找到任何 APK，请先构建。"
}

# 组装公共 scp/ssh 选项
$opts = @("-P", "$SshPort", "-o", "StrictHostKeyChecking=accept-new")
if ($IdentityFile -and (Test-Path $IdentityFile)) {
    $opts += @("-i", $IdentityFile)
}

# 1) 确保服务器目录存在
Write-Host ">>> [1/2] 在服务器创建目录 $RemoteApksDir ..." -ForegroundColor Cyan
$sshArgs = $opts + @($sshTarget, "mkdir -p '$RemoteApksDir'")
& ssh @sshArgs
if ($LASTEXITCODE -ne 0) { Pause-Exit "无法连接服务器或创建目录，请检查 IP/端口/账号/密钥（ssh 退出码 $LASTEXITCODE）。" }

# 2) 上传 APK（逐个，便于看清进度）
Write-Host ">>> [2/2] 上传 $($localApks.Count) 个 APK 到 $RemoteApksDir ..." -ForegroundColor Cyan
foreach ($apk in $localApks) {
    Write-Host "    上传：$(Split-Path $apk -Leaf)" -ForegroundColor White
    $scpArgs = $opts + @($apk, "${sshTarget}:${RemoteApksDir}/")
    & scp @scpArgs
    if ($LASTEXITCODE -ne 0) { Pause-Exit "上传 $(Split-Path $apk -Leaf) 失败（scp 退出码 $LASTEXITCODE）。" }
}

# 3) （可选）上传 version.json
if ($UploadVersionJson) {
    $vj = Join-Path $LocalDir "version.json"
    if (Test-Path $vj) {
        Write-Host ">>> [附加] 上传 version.json 到 $RemoteVersionJson ..." -ForegroundColor Cyan
        $scpArgs = $opts + @($vj, "${sshTarget}:${RemoteVersionJson}")
        & scp @scpArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    [警告] version.json 上传失败，可手动上传（不影响 APK）。" -ForegroundColor Yellow
        } else {
            Write-Host "    已同步服务器 version.json（versionCode 以本地为准）。" -ForegroundColor Green
        }
    } else {
        Write-Host "    [提示] 未找到本地 version.json，跳过。" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host ">>> 完成！App 的「检查更新」现在会到服务器拉取最新 APK。" -ForegroundColor Green
Write-Host "    若要让 App 真正弹出“发现新版本”，请确保服务器 version.json 的 versionCode 比本机大。" -ForegroundColor White
Pause-Only
