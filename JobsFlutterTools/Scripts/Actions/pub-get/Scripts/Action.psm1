# Action.psm1
# JobsFlutterPubGet
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'SdkDownloadOutput.ps1')

function Write-JobsWorkerMessage {
    param([string]$Message, [switch]$AuditOnly)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)(authorization\s*[:=]\s*)[^\r\n]+', '$1[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    if (-not $AuditOnly) { Write-Host $safe }
    Write-JobsLog $safe
}

function Assert-JobsOrdinaryDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) {
        throw "目标必须是已存在的绝对目录：$Path"
    }
    $directory = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $directory
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接、目录联接或其它重解析目录：$($current.FullName)"
        }
        $current = $current.Parent
    }
    return $directory.FullName
}

function Assert-JobsOrdinaryFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw "缺少文件：$Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "不处理重解析文件：$Path"
    }
}

function Invoke-JobsFlutterProcess {
    param([string]$Flutter, [string[]]$Arguments, [string]$Directory, [int]$TimeoutSeconds = 30)
    # cmd 只接收受控的工具路径和固定参数，项目路径始终通过 WorkingDirectory 传递。
    if ($Flutter -match '["\r\n]' -or @($Arguments | Where-Object { $_ -notin @('--version', 'pub', 'get') }).Count -gt 0) {
        throw 'Flutter 安装路径含非法控制字符或双引号，或请求了未允许的参数。'
    }
    $cmd = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $cmd
    $start.Arguments = '/d /v:off /s /c ""%JOBS_FLUTTER_EXECUTABLE%" ' + ($Arguments -join ' ') + '"'
    $start.EnvironmentVariables['JOBS_FLUTTER_EXECUTABLE'] = $Flutter
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    Write-JobsWorkerMessage ("执行：Flutter {0}；目录：{1}" -f ($Arguments -join ' '), $Directory)
    if ($Arguments -contains '--version') { $result = Invoke-JobsSdkAcquireProcess $start ([Math]::Max(120,$TimeoutSeconds)) -Sanitize -Label 'Flutter/Dart 首次初始化' }
    else { $result = Invoke-JobsSdkLiveProcess $start $TimeoutSeconds -Sanitize }
    if ($result.StdOut) { Write-JobsWorkerMessage $result.StdOut.TrimEnd() -AuditOnly }
    if ($result.StdErr) { Write-JobsWorkerMessage $result.StdErr.TrimEnd() -AuditOnly }
    if ($result.ExitCode -ne 0) { throw "Flutter 操作失败（退出码 $($result.ExitCode)）。" }
}

function Invoke-JobsFlutterAction {
    param([string]$Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsOrdinaryFile $pubspec
    [void](Assert-JobsOrdinaryDirectory (Join-Path $Directory 'lib'))
    if ((Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8) -notmatch '(?m)^\s+sdk\s*:\s*flutter\s*(?:#.*)?$') {
        throw '当前同层 pubspec.yaml 未声明 sdk: flutter。'
    }
    $fvm = Join-Path $Directory '.fvm\flutter_sdk\bin\flutter.bat'
    if (Test-Path -LiteralPath $fvm -PathType Leaf) { $flutter = $fvm }
    else { throw '项目 FVM SDK 缺失；不会回退全局 Flutter。' }
    if (-not $flutter) {
        Write-JobsWorkerMessage '缺少现成 Flutter SDK；请先按官方说明安装，扩展不会自动下载 Flutter。'
        Start-Process -FilePath 'https://docs.flutter.dev/get-started/install/windows'
        throw 'Flutter SDK 未就绪。'
    }
    Write-JobsWorkerMessage "Flutter SDK：$flutter"
    Invoke-JobsFlutterProcess $flutter @('--version') $Directory
    Write-JobsWorkerMessage "即将在此目录安装/更新 pubspec 依赖：$Directory"
    if ((Read-Host '按回车执行 flutter pub get；输入任意字符取消') -ne '') { throw '已取消。' }
    [void](Assert-JobsOrdinaryDirectory $Directory)
    Invoke-JobsFlutterProcess $flutter @('pub', 'get') $Directory 900
    Write-JobsWorkerMessage 'Flutter 依赖处理完成。'
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $setup = Import-Module (Join-Path $PSScriptRoot '../../../ProjectSetup.psm1') -PassThru -DisableNameChecking
    & $setup { param($p) Invoke-JobsProjectDependencyAction -Target $p -Action 'pub-get' } $Target
}

Export-ModuleMember -Function Invoke-JobsFeature
