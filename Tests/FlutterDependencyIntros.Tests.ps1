# FlutterDependencyIntros.Tests.ps1 | 两个独立入口的自述与首次确认顺序。
# Created by Jobs on 2026年10月29日，星期四.
# 在私有工程中取消真实入口；外部工具若提前运行会立即失败。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$count = 0
function Assert($Value,[string]$Message) { $script:count++; if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Body,[string]$Message) { $failed=$false; try { & $Body | Out-Null } catch { $failed=$true }; Assert $failed $Message }
$base = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [IO.Path]::GetTempPath() } else { '/private/tmp' }
$temp = Join-Path $base ('jobs-flutter-intros-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $temp '工程 空格'
[void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
[IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
$module = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
$savedColor = [Environment]::GetEnvironmentVariable('NO_COLOR','Process')
try {
    $env:NO_COLOR = '1'
    & $module {
        $script:introEvents = New-Object 'System.Collections.Generic.List[string]'
        $script:businessCalls = 0
        $script:colorCalls = 0
        function script:Write-Host { param($Object,$ForegroundColor) $script:introEvents.Add('line:'+ [string]$Object); if ($ForegroundColor) { $script:colorCalls++ } }
        function script:Read-Host { param($Prompt) $script:introEvents.Add('confirm:'+ $Prompt); return 'cancel' }
        function script:Test-JobsSetupInteractive { $true }
        function script:Get-JobsSetupFzf { $script:businessCalls++; throw 'fzf before confirmation' }
        function script:Get-JobsDependencyFlutter { $script:businessCalls++; throw 'SDK before confirmation' }
        function script:Invoke-JobsSetupProcess { $script:businessCalls++; throw 'external command before confirmation' }
    }
    $before = @(Get-ChildItem -LiteralPath $temp -Recurse -Force | ForEach-Object FullName) -join '|'
    foreach ($action in @('flutter-precache','native-dependencies')) {
        & $module { $script:introEvents.Clear() }
        Assert-Throws { & $module { param($p,$a) Invoke-JobsProjectDependencyAction -Target $p -Action $a } $project $action } ('首次确认取消：'+$action)
        $events = @(& $module { $script:introEvents.ToArray() })
        Assert ($events.Count -gt 8 -and $events[-1].StartsWith('confirm:')) ('完整自述在首次确认之前：'+$action)
        Assert (@($events | Where-Object { $_.StartsWith('confirm:') }).Count -eq 1) ('只有原有首次确认：'+$action)
        Assert ((& $module { $script:businessCalls }) -eq 0) ('确认前没有SDK、选择器或下载命令：'+$action)
        $lines = @($events | Where-Object { $_.StartsWith('line:') } | ForEach-Object { $_.Substring(5) })
        Assert (@($lines | Where-Object { $_ -match '^  [1-5]、' }).Count -eq 5) ('五条主说明独立成行且缩进：'+$action)
        Assert (-not (($lines -join "`n").Contains([string][char]27))) ('NO_COLOR纯文本无ANSI：'+$action)
        Assert ((& $module { $script:colorCalls }) -eq 0) ('NO_COLOR标题与正文都不请求彩色：'+$action)
        if ($action -ceq 'flutter-precache') {
            foreach ($text in @('flutter precache --所选目标','引擎二进制','android_maven','Web：对应的渲染资源','Flutter.xcframework','Windows 不提供 iOS','不解析工程全部 Maven','不替代 Pub / Pods','不等于安装完整 Android SDK 或 Xcode')) {
                Assert (($lines -join "`n").Contains($text)) ('precache范围准确：'+$text)
            }
            Assert (@($lines | Where-Object { $_.StartsWith('      ') }).Count -eq 3) '平台例子逐行分级缩进'
        } else {
            foreach ($text in @('组合操作','Pub 依赖','Android Maven','OpenHarmony OHPM','Web 工程包','flutter build','CMake、NuGet、FFI hooks','实际编译并生成产物','不安装或启动应用','不把所有平台全量都拉取')) {
                Assert (($lines -join "`n").Contains($text)) ('native组合范围准确：'+$text)
            }
            Assert (@($lines | Where-Object { $_.StartsWith('      ') }).Count -eq 1) '延迟制品说明单独缩进行'
        }
        & $module { $script:introEvents.Clear() }
        & $module { param($p,$a) Invoke-JobsProjectDependencyAction -Target $p -Action $a -Check } $project $action
        $checkEvents = @(& $module { $script:introEvents.ToArray() })
        Assert (@($checkEvents | Where-Object { $_.StartsWith('confirm:') }).Count -eq 0 -and (& $module { $script:businessCalls }) -eq 0) ('Check保持只读且不引入自述确认：'+$action)
    }
    Assert ((@(Get-ChildItem -LiteralPath $temp -Recurse -Force | ForEach-Object FullName) -join '|') -ceq $before) '初始取消与Check均未写日志、缓存或项目'
    Write-Host ('PASS: FlutterDependencyIntros.Tests.ps1 ('+$count+' assertions; isolated cancellation and check-only paths)')
} finally {
    if ($null -eq $savedColor) { Remove-Item Env:NO_COLOR -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable('NO_COLOR',$savedColor,'Process') }
    Remove-Module $module -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}
