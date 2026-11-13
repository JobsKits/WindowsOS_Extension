# StartVirtualDevice.ps1 | JobsFlutterRunner
# Created by Jobs on 2026年11月12日，星期四.
# 启动已有虚拟设备；环境获取与一次启动分开，不创建、重置或替换设备。

function Select-JobsRunnerTextChoice {
    param([string]$Title, [string[]]$Items, [switch]$Back)
    while ($true) {
        Write-Host $Title
        for ($index=0; $index -lt $Items.Count; $index++) { Write-Host (('{0}  {1}' -f ($index+1), $Items[$index])) }
        $prompt = '输入序号；q 取消'
        if ($Back) { $prompt += '；b / ← 返回上一层' }
        $value = Read-JobsRunnerInput $prompt
        if ($null -eq $value -or $value -in @('q','Q','取消')) { return $null }
        if ($Back -and $value -in @('b','B','←','返回')) { return [pscustomobject]@{Kind='Back';Index=-1} }
        $number=0
        if ([int]::TryParse($value,[ref]$number) -and $number -ge 1 -and $number -le $Items.Count) { return [pscustomobject]@{Kind='Selected';Index=$number-1} }
        Write-Host '未选择有效项目；可重选、返回或取消。' -ForegroundColor Yellow
    }
}

function Get-JobsRunnerVirtualEnvironment {
    $result=@{}
    foreach ($name in @('PATH','JAVA_HOME','TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','OHOS_SDK_HOME')) { $result[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
    return $result
}

# 完整正式清单才可判定无更新，未知/半成品输出不能绕过启动门禁。
function Get-JobsRunnerAndroidStableUpdates {
    param([string]$Listing)
    if ([string]::IsNullOrWhiteSpace($Listing) -or $Listing -match '(?im)^\s*(?:warning|error)(?:[:\s])|Failed to (?:download|fetch|parse)|Errors during XML parse|IOException|UnknownHostException|Read timed out|Still waiting') {
        throw 'Android 正式更新目录为空或包含获取错误，未报告启动环境就绪。'
    }
    $titles=@('Installed packages:','Available Packages:','Available Updates:')
    $columns=@(@('Path','Version','Description','Location'),@('Path','Version','Description'),@('ID','Installed','Available'))
    $tables=@(@{},@{},@{})
    $section=-1; $phase=0
    $revision='^\d+(?:\.\d+){0,3}(?:[ -]?(?:rc|alpha|beta|preview|canary|dev)[ .-]?\d*)?$'
    foreach ($raw in ($Listing -split '\r?\n')) {
        $line=$raw.Trim()
        if (-not $line) { continue }
        $next=-1
        for ($index=0; $index -lt $titles.Count; $index++) { if ($line -ieq $titles[$index]) { $next=$index; break } }
        if ($next -ge 0) {
            if ($next -ne $section+1 -or ($section -ge 0 -and ($phase -ne 2 -or $tables[$section].Count -eq 0))) { throw 'Android 正式更新目录章节重复、错序或截断。' }
            $section=$next; $phase=0; continue
        }
        if ($section -lt 0) {
            if ($line -match '^(?:\[[^\r\n]*\]\s*\d+%|Loading |Fetching |Computing )') { continue }
            throw 'Android 正式更新目录包含未知前导输出。'
        }
        $fields=@($line.Split('|') | ForEach-Object { $_.Trim() })
        if ($fields.Count -ne $columns[$section].Count) { throw 'Android 正式更新目录表格列数无效或截断。' }
        if ($phase -eq 0) {
            if (($fields -join '|') -cne ($columns[$section] -join '|')) { throw 'Android 正式更新目录表头无法核验。' }
            $phase=1; continue
        }
        if ($phase -eq 1) {
            foreach ($value in $fields) { if ($value -cnotmatch '^-+$') { throw 'Android 正式更新目录表格分隔线缺失。' } }
            $phase=2; continue
        }
        $key=$fields[0]
        if ($key -cnotmatch '^[a-zA-Z0-9_.;+-]+$' -or $tables[$section].ContainsKey($key)) { throw 'Android 正式更新目录包标识无效或重复。' }
        foreach ($target in @('emulator','platform-tools')) { if ($key -ieq $target -and $key -cne $target) { throw 'Android 启动组件标识大小写无法核验。' } }
        if ($fields[1] -notmatch $revision -or ($section -eq 2 -and $fields[2] -notmatch $revision)) { throw 'Android 正式更新目录版本格式无法核验。' }
        foreach ($value in $fields) { if ([string]::IsNullOrWhiteSpace($value)) { throw 'Android 正式更新目录字段为空。' } }
        $tables[$section][$key]=$fields
    }
    if ($section -lt 1 -or $phase -ne 2 -or $tables[$section].Count -eq 0) { throw 'Android 正式更新目录未完整返回。' }
    $updates=@()
    foreach ($target in @('emulator','platform-tools')) {
        if (-not $tables[0].ContainsKey($target) -or -not $tables[1].ContainsKey($target)) { throw ('Android 启动组件缺少完整本地／远端版本：'+$target) }
        $installed=$tables[0][$target][1]; $available=$tables[1][$target][1]
        if ($installed -cnotmatch '^\d+(?:\.\d+){1,3}$' -or $available -cnotmatch '^\d+(?:\.\d+){1,3}$') { throw ('启动组件不是可核验正式版本：'+$target) }
        if ([version]$available -gt [version]$installed) {
            if (-not $tables[2].ContainsKey($target) -or $tables[2][$target][1] -cne $installed -or $tables[2][$target][2] -cne $available) { throw ('Android 启动组件更新表缺失或版本不一致：'+$target) }
            $updates+=$target
        } elseif ($tables[2].ContainsKey($target)) { throw ('Android 启动组件更新表与正式版本矛盾：'+$target) }
    }
    foreach ($key in $tables[2].Keys) {
        if (-not $tables[0].ContainsKey($key) -or -not $tables[1].ContainsKey($key) -or $tables[2][$key][1] -cne $tables[0][$key][1] -or $tables[2][$key][2] -cne $tables[1][$key][1]) { throw 'Android 正式更新目录各表之间不完整或不一致。' }
    }
    return $updates
}

# 只更新本次SDK的模拟器/ADB正式组件；不运行sdkmanager --update或改动平台/镜像版本。
function Initialize-JobsRunnerVirtualAndroid {
    param([string]$Project)
    [void](Get-JobsAndroidArchitecture)
    $sdk=Get-JobsAndroidSdk
    if (-not $env:ANDROID_HOME -and -not $env:ANDROID_SDK_ROOT) {
        $configured=Get-JobsRunnerAndroidEmulator
        if ($configured) { $sdk=Split-Path -Parent (Split-Path -Parent $configured) }
    }
    $env:ANDROID_HOME=$sdk; $env:ANDROID_SDK_ROOT=$sdk
    $java=Get-JobsAndroidJava
    $tools=Get-JobsAndroidHealthyTools $sdk $java
    $env:JAVA_HOME=Split-Path -Parent (Split-Path -Parent $java)
    $env:PATH=(Split-Path -Parent $java)+[IO.Path]::PathSeparator+$env:PATH
    Repair-JobsAndroidComponents $sdk $java $tools
    $listing=Invoke-JobsAndroidTool $java $tools 'sdkmanager' @('--list','--channel=0',('--sdk_root='+$sdk)) -IncludeStandardError
    $updates=@(Get-JobsRunnerAndroidStableUpdates $listing)
    if ($updates.Count) {
        Write-Host ('更新当前 Android SDK 的正式启动组件：'+($updates -join '、')+'；来源：https://dl.google.com/android/repository/')
        Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root='+$sdk),'--licenses') -Interactive
        [void](Invoke-JobsAndroidTool $java $tools 'sdkmanager' (@('--install','--channel=0',('--sdk_root='+$sdk))+$updates) -Interactive)
        $remaining=Invoke-JobsAndroidTool $java $tools 'sdkmanager' @('--list','--channel=0',('--sdk_root='+$sdk)) -IncludeStandardError
        if (@(Get-JobsRunnerAndroidStableUpdates $remaining).Count) { throw '正式启动组件更新后复检仍显示可更新项，未启动设备。' }
    }
    [void](Invoke-JobsRunnerReadOnlyTool (Join-Path $sdk 'emulator/emulator.exe') @('-accel-check') $Project 20)
    if (@(Get-JobsAndroidUnhealthyComponents $sdk).Count) { throw 'Android 启动工具复检未通过，未启动设备。' }
    return $sdk
}

# NTFS创建时间会被同名文件缓存复用，实例文件必须用卷号和原生File ID固定对象。
function Get-JobsRunnerFileIdentity {
    param([string]$Path)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '当前宿主不能核验Windows原生文件对象，未报告实例就绪。' }
    if (-not ('JobsRunnerNative.FileIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace JobsRunnerNative {
    public static class FileIdentity {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileIdInfo {
            public ulong Volume;
            public ulong Low;
            public ulong High;
        }
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int fileInfoClass, out FileIdInfo info, uint size);
        public static string Read(string path) {
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
                FileIdInfo info;
                if (!GetFileInformationByHandleEx(stream.SafeFileHandle, 18, out info, (uint)Marshal.SizeOf(typeof(FileIdInfo)))) {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot verify the selected instance file object.");
                }
                if (info.Low == 0 && info.High == 0) { throw new IOException("The selected instance returned an empty file ID."); }
                return info.Volume.ToString("X16") + ":" + info.Low.ToString("X16") + info.High.ToString("X16");
            }
        }
    }
}
'@
    }
    return [JobsRunnerNative.FileIdentity]::Read($Path)
}

function Get-JobsRunnerAvdStableConfigHash {
    param([string]$Config)
    $text=[IO.File]::ReadAllText($Config)
    [string[]]$lines=@($text -split '\r?\n' | Where-Object {$_ -cmatch '^(?:AvdId|avd\.ini\.displayname|image\.sysdir\.1|abi\.type|tag\.id|hw\.cpu\.arch)='})
    if (-not $lines.Count) { throw '原AVD缺少稳定实例字段，未运行。' }
    [Array]::Sort($lines,[StringComparer]::Ordinal)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))).Replace('-','') }
    finally { $sha.Dispose() }
}

function Get-JobsRunnerAndroidAvdIdentity {
    param([string]$Name)
    if ($Name -cnotmatch '^[a-zA-Z0-9_.-]+$') { throw '原AVD名称无效。' }
    $avdHome=Get-JobsAndroidAvdHome
    $ini=Join-Path $avdHome ($Name+'.ini')
    Assert-JobsRunnerPlainFile $ini
    $text=[IO.File]::ReadAllText($ini)
    $paths=@([regex]::Matches($text,'(?m)^path=([^\r\n]+)\r?$'))
    if ($paths.Count -ne 1 -or -not[IO.Path]::IsPathRooted($paths[0].Groups[1].Value)) { throw '原AVD缺少唯一绝对实例路径。' }
    $directory=[IO.Path]::GetFullPath($paths[0].Groups[1].Value)
    [void](Assert-JobsRunnerDirectory $directory)
    $config=Join-Path $directory 'config.ini'
    Assert-JobsRunnerPlainFile $config
    $iniObject=Get-JobsRunnerFileIdentity $ini
    $configObject=Get-JobsRunnerFileIdentity $config
    $iniHash=(Get-FileHash $ini -Algorithm SHA256).Hash
    $configHash=(Get-FileHash $config -Algorithm SHA256).Hash
    $stableHash=Get-JobsRunnerAvdStableConfigHash $config
    if ((Get-JobsRunnerFileIdentity $ini) -cne $iniObject -or (Get-JobsRunnerFileIdentity $config) -cne $configObject) { throw '读取期间原AVD文件对象已改变，未运行。' }
    return [pscustomobject]@{Name=$Name;Path=$directory;Ini=$ini;Config=$config;IniObject=$iniObject;ConfigObject=$configObject;IniHash=$iniHash;ConfigHash=$configHash;StableConfigHash=$stableHash}
}

function Initialize-JobsRunnerAndroidAvdImage {
    param([string]$Sdk,$Identity)
    $text=[IO.File]::ReadAllText($Identity.Config)
    $matches=@([regex]::Matches($text,'(?m)^image\.sysdir\.1=([^\r\n]+)\r?$'))
    if ($matches.Count -ne 1) { throw '原AVD缺少唯一镜像位置。' }
    $relative=$matches[0].Groups[1].Value.Replace('\','/').TrimEnd('/')
    if ($relative -cnotmatch '^system-images/android-[0-9]+/[a-zA-Z0-9_.-]+/(?:x86_64|x86|arm64-v8a|armeabi-v7a)$') { throw '原AVD镜像不是可核验正式包，未更换镜像版本。' }
    $path=Join-Path $Sdk $relative
    if ([IO.File]::Exists((Join-Path $path 'package.xml')) -and [IO.File]::Exists((Join-Path $path 'system.img'))) { return }
    $java=Get-JobsAndroidJava
    $tools=Get-JobsAndroidHealthyTools $Sdk $java
    $package=$relative.Replace('/',';')
    Write-Host ('补齐原AVD确切镜像：'+$package+'；来源：https://dl.google.com/android/repository/')
    Invoke-JobsAndroidTool $java $tools 'sdkmanager' @(('--sdk_root='+$Sdk),'--licenses') -Interactive
    [void](Invoke-JobsAndroidTool $java $tools 'sdkmanager' @('--install','--channel=0',('--sdk_root='+$Sdk),$package) -Interactive)
    if (-not[IO.File]::Exists((Join-Path $path 'package.xml')) -or -not[IO.File]::Exists((Join-Path $path 'system.img'))) { throw '原AVD镜像获取后复检失败，未创建设备。' }
}

function Start-JobsRunnerExistingAndroid {
    param([string]$Flutter, [string]$Project)
    $snapshot=Get-JobsRunnerTaskEnvironmentSnapshot @('PATH','JAVA_HOME','ANDROID_HOME','ANDROID_SDK_ROOT')
    try {
        $sdk=Initialize-JobsRunnerVirtualAndroid $Project
        $emulator=Join-Path $sdk 'emulator/emulator.exe'
        $names=@(Get-JobsRunnerAvds $emulator $Project)
        if (-not $names.Count) { Write-Host '暂无已有 Android 模拟器；可返回后另选“新建设备”。'; return [pscustomobject]@{Kind='Back'} }
        $identities=@{}; $identityErrors=@{}
        foreach ($listedName in $names) {
            if ($identities.ContainsKey($listedName) -or $identityErrors.ContainsKey($listedName)) { throw 'AVD清单名称不唯一，未启动。' }
            try { $identities[$listedName]=Get-JobsRunnerAndroidAvdIdentity $listedName }
            catch [Management.Automation.PipelineStoppedException] { throw }
            catch [OperationCanceledException] { throw }
            catch { $identityErrors[$listedName]=$_.Exception.Message }
        }
        $selection=Select-JobsRunnerChoice '启动Android模拟器' ($names+@('返回上一层')) -Back
        if ($null -eq $selection) { return $null }
        if ($selection.Kind -ceq 'Back' -or $selection.Index -ge $names.Count) { return [pscustomobject]@{Kind='Back'} }
        $name=$names[$selection.Index]
        if ($name -cnotin @(Get-JobsRunnerAvds $emulator $Project)) { throw '所选 AVD 已消失，未创建替代设备。' }
        if (-not $identities.ContainsKey($name)) { throw ('所选AVD在列出时无法核验实例身份：'+$identityErrors[$name]) }
        $identity=$identities[$name]
        $current=Get-JobsRunnerAndroidAvdIdentity $name
        foreach ($field in @('Path','IniObject','ConfigObject','IniHash','ConfigHash')) { if ($current.$field -cne $identity.$field) { throw '选择期间原AVD实例已被替换，未启动。' } }
        Initialize-JobsRunnerAndroidAvdImage $sdk $identity
        $current=Get-JobsRunnerAndroidAvdIdentity $name
        foreach ($field in @('Path','IniObject','ConfigObject','IniHash','ConfigHash')) { if ($current.$field -cne $identity.$field) { throw '所选AVD身份或配置已变化，未启动。' } }
        $serial=Start-JobsAndroidAvd $sdk $name
        $id=Wait-JobsRunnerSelectedDevice $Flutter $Project ([pscustomobject]@{Platform='Android';Id=$serial})
        if ($null -eq $id) { return [pscustomobject]@{Kind='Back'} }
        $current=Get-JobsRunnerAndroidAvdIdentity $name
        foreach ($field in @('Path','IniObject','ConfigObject','IniHash','StableConfigHash')) { if ($current.$field -cne $identity.$field) { throw '等待期间原AVD实例或配置已改变，未运行。' } }
        if ($id -cne $serial) { throw 'Android准备返回不同设备，未运行。' }
        if (-not (Test-JobsAndroidBoot (Join-Path $sdk 'platform-tools/adb.exe') $serial $name)) { throw '等待后原AVD未就绪或端口已由其它实例复用，未运行。' }
        return [pscustomobject]@{Kind='Ready';Id=$id;Sdk=$sdk;Platform='android';Environment=(Get-JobsRunnerVirtualEnvironment)}
    } finally { Restore-JobsRunnerTaskEnvironment $snapshot }
}

function Import-JobsRunnerHarmonyCreator {
    $path=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'SimulatorCreators/Harmony/Scripts/Action.psm1'
    $module=Import-Module $path -PassThru -DisableNameChecking
    & $module { $script:HarmonyLicensesConfirmed=$false }
    return $module
}

function Invoke-JobsRunnerHarmonyCore {
    param($Module, [string]$Command, [object[]]$Arguments)
    if ($Command -ceq 'Get-JobsHarmonyAvailableImages') { return & $Module {param($Tool)Get-JobsHarmonyImages $Tool -Available} $Arguments[0] }
    return & $Module { param($Command,$Arguments) & $Command @Arguments } $Command $Arguments
}

function Get-JobsRunnerHarmonyInstanceIdentity {
    param($Module, $Instance)
    foreach ($field in @('name','instancePath','uuid','deviceType')) {
        if ($null -eq $Instance.PSObject.Properties[$field] -or $Instance.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($Instance.$field) -or $Instance.$field -match '[\x00-\x1f]') { throw ('已有鸿蒙实例缺少可靠身份：'+$field) }
    }
    [void](Assert-JobsRunnerDirectory $Instance.instancePath)
    $config=Join-Path $Instance.instancePath 'config.ini'
    Assert-JobsRunnerPlainFile $config
    $version=Invoke-JobsRunnerHarmonyCore $Module 'Get-JobsHarmonyInstanceVersion' @($Instance)
    if (-not $version -or $version -match '(?i)beta|preview|canary|dev\b') { throw '已有鸿蒙实例未确认正式系统版本，未更换其镜像。' }
    if ($null -eq $Instance.PSObject.Properties['isRunning'] -or ($Instance.isRunning -isnot [bool] -and $Instance.isRunning -cnotin @('true','false'))) { throw '已有鸿蒙实例运行状态不明确。' }
    $running=$Instance.isRunning -ceq $true -or $Instance.isRunning -ceq 'true'
    $imageRoot=''
    if ($null -ne $Instance.PSObject.Properties['imageRoot'] -and $Instance.imageRoot) {
        if ($Instance.imageRoot -isnot [string] -or -not[IO.Path]::IsPathRooted($Instance.imageRoot) -or $Instance.imageRoot -match '[\x00-\x1f]') { throw '实例镜像目录无效。' }
        $imageRoot=[IO.Path]::GetFullPath($Instance.imageRoot)
    }
    return [pscustomobject]@{ImageRoot=$imageRoot;Name=$Instance.name;Path=[IO.Path]::GetFullPath($Instance.instancePath);Uuid=$Instance.uuid;DeviceType=$Instance.deviceType;Version=$version;Running=$running;Config=$config;Hash=(Get-FileHash $config -Algorithm SHA256).Hash}
}

function Assert-JobsRunnerHarmonyInstance {
    param($Module,[string]$Emulator,$Identity)
    $matches=@(Invoke-JobsRunnerHarmonyCore $Module 'Get-JobsHarmonyInstances' @($Emulator) | Where-Object {$_.name -ceq $Identity.Name})
    if ($matches.Count -ne 1) { throw '原鸿蒙实例已消失或不唯一，未选择其它实例。' }
    $current=Get-JobsRunnerHarmonyInstanceIdentity $Module $matches[0]
    foreach ($field in @('Name','Path','Uuid','DeviceType','Version','ImageRoot','Hash')) { if ($current.$field -cne $Identity.$field) { throw '所选鸿蒙实例身份或配置已改变，未启动其它实例。' } }
    return $matches[0]
}

# 仅补所选实例的缺失/失效SDK位置；先精确备份，原子替换，保留其它配置。
function Set-JobsRunnerHarmonyInstanceSdk {
    param($Identity, [string]$Sdk)
    $bytes=[IO.File]::ReadAllBytes($Identity.Config)
    if ((Get-FileHash $Identity.Config -Algorithm SHA256).Hash -cne $Identity.Hash) { throw '实例配置在准备期间改变，未写入。' }
    $text=(New-Object Text.UTF8Encoding($false,$true)).GetString($bytes).TrimStart([char]0xfeff)
    $name=@([regex]::Matches($text,'(?m)^name=([^\r\n]*)\r?$'))
    if ($name.Count -ne 1 -or $name[0].Groups[1].Value -cne $Identity.Name) { throw '实例配置名称不匹配，未写入。' }
    $paths=@([regex]::Matches($text,'(?m)^(?:sdkPath|harmonyos\.sdk\.path)=([^\r\n]*)\r?$'))
    if ($paths.Count -gt 1) { throw '实例存在重复SDK位置，未覆盖。' }
    if ($paths.Count -eq 1 -and [IO.Directory]::Exists($paths[0].Groups[1].Value) -and [IO.File]::Exists((Join-Path $paths[0].Groups[1].Value 'default/openharmony/toolchains/hdc.exe'))) { return }
    if ($Identity.Running) { throw '正在运行的鸿蒙实例缺少有效SDK位置，保留配置并停止；不自动重启或覆盖运行现场。' }
    if (-not [IO.File]::Exists((Join-Path $Sdk 'default/openharmony/toolchains/hdc.exe'))) { throw '准备后的SDK缺少HDC，未修改实例。' }
    $newline=if ($text.Contains("`r`n")) {"`r`n"} else {"`n"}
    $text=[regex]::Replace($text,'(?m)^(?:sdkPath|harmonyos\.sdk\.path)=[^\r\n]*\r?\n?','')
    if (-not $text.EndsWith("`n")) { $text+=$newline }
    $text+='sdkPath='+$Sdk+$newline
    $token=[guid]::NewGuid().ToString('N')
    $backup=$Identity.Config+'.jobs-backup-'+$token
    $temporary=$Identity.Config+'.jobs-stage-'+$token
    [IO.File]::WriteAllBytes($backup,$bytes)
    Write-Host ('所选鸿蒙实例SDK配置备份：'+$backup)
    try {
        [IO.File]::WriteAllText($temporary,$text,(New-Object Text.UTF8Encoding($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)))
        if ((Get-FileHash $Identity.Config -Algorithm SHA256).Hash -cne $Identity.Hash) { throw '备份后实例配置发生并发变化，未替换。' }
        [IO.File]::Replace($temporary,$Identity.Config,[NullString]::Value)
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Initialize-JobsRunnerHarmonyImage {
    param($Module,[string]$Emulator,$Identity)
    $images=@(Invoke-JobsRunnerHarmonyCore $Module 'Get-JobsHarmonyImages' @($Emulator) | Where-Object {$_.DeviceType -ieq $Identity.DeviceType -and $_.OsVersion -ceq $Identity.Version})
    if ($images.Count -eq 1) { return }
    $arguments=@('-install','-deviceType',$Identity.DeviceType,'-osVersion',$Identity.Version,'-force')
    if ($Identity.ImageRoot) { $arguments+=@('-imageRoot',$Identity.ImageRoot) }
    $available=@(Invoke-JobsRunnerHarmonyCore $Module 'Get-JobsHarmonyAvailableImages' @($Emulator) | Where-Object {$_.DeviceType -ieq $Identity.DeviceType -and $_.OsVersion -ceq $Identity.Version})
    if ($available.Count -ne 1) { throw '原鸿蒙实例的确切Release镜像不可获取，未换用其它镜像或重建设备。' }
    Write-Host ('补齐原实例确切Release镜像：'+$Identity.DeviceType+' · '+$Identity.Version+'；来源：官方Emulator。')
    [void](Invoke-JobsSdkAcquire -Label '原鸿蒙实例镜像' -Operation {
        Invoke-JobsRunnerHarmonyCore $Module 'Invoke-JobsHarmonyInteractive' @($Emulator,$arguments)
        $verified=@(Invoke-JobsRunnerHarmonyCore $Module 'Get-JobsHarmonyImages' @($Emulator) | Where-Object {$_.DeviceType -ieq $Identity.DeviceType -and $_.OsVersion -ceq $Identity.Version})
        if ($verified.Count -ne 1) { throw '原实例镜像获取后复检未通过。' }
    })
}

function Get-JobsRunnerHarmonyTarget {
    param($Module,[string]$Emulator,$Instance)
    $directory=Join-Path ([IO.Path]::GetTempPath()) ('JobsStartedHarmony-'+[guid]::NewGuid().ToString('N'))
    [void](New-JobsRunnerVirtualPrivateDirectory $directory)
    $receipt=Join-Path $directory 'target.tsv'
    $snapshot=Get-JobsRunnerTaskEnvironmentSnapshot @('JOBS_FLUTTER_CREATED_DEVICE_FILE')
    try {
        $env:JOBS_FLUTTER_CREATED_DEVICE_FILE=$receipt
        Invoke-JobsRunnerHarmonyCore $Module 'Write-JobsHarmonyFlutterTarget' @($Emulator,$Instance)
        if (-not [IO.File]::Exists($receipt)) { throw '已有鸿蒙实例未返回精确HDC目标。' }
        $text=[IO.File]::ReadAllText($receipt)
        if ($text -cnotmatch '^Harmony\t(127\.0\.0\.1:[0-9]{1,5})\r?\n?$') { throw '原实例HDC回执无效，未选择其它设备。' }
        $id=$Matches[1]
        $port=[int]($id.Split(':')[-1])
        if ($port -lt 1 -or $port -gt 65535) { throw '原实例HDC端口越界，未运行。' }
        return $id
    } finally {
        Restore-JobsRunnerTaskEnvironment $snapshot
        if ([IO.File]::Exists($receipt)) { [IO.File]::Delete($receipt) }
        [IO.Directory]::Delete($directory)
    }
}

# 官方-update刷新机型目录，不是CLT二进制升级；只能在运行时help确认能力后使用。
function Update-JobsRunnerHarmonyCatalog {
    param($Module,[string]$Emulator,[string]$Help)
    Write-Host '官方Windows正式CLT已核验；机型目录刷新与CLT二进制更新分别处理，不改变已有实例系统版本。'
    if($Help -match '(?<![A-Za-z0-9_-])-screenProfileList(?![A-Za-z0-9_-])' -and $Help -match '(?<![A-Za-z0-9_-])-update(?![A-Za-z0-9_-])') {
        [void](Invoke-JobsSdkAcquire -Label '官方Emulator机型目录刷新' -Operation {
            $output=Invoke-JobsRunnerHarmonyCore $Module 'Invoke-JobsHarmonyQuery' @($Emulator,@('-screenProfileList','-deviceType','phone','-details','-update'))
            if($output-match'(?i)\[(fail|error)\]'){throw '官方机型目录刷新失败，保留工具输出并停止。'}
        })
    } else {Write-Host '当前Emulator未在help公开机型目录刷新能力；保留已核验兼容工具，不猜测升级参数。'}
}

function Resolve-JobsRunnerHarmonyToolRoot {
    $root=''
    try{$root=Get-JobsRunnerHarmonyRoot}catch [Management.Automation.PipelineStoppedException]{throw}catch [OperationCanceledException]{throw}catch{}
    $current=if($root){Get-JobsRunnerHarmonyToolVersion $root}else{''}
    if($current-and$current-cnotmatch'^6\.1\.1\.\d+$'){throw '当前CLT不属于已核验6.1.1兼容系，未套用JDK17、降级或启动。'}
    $public=$null
    try{$public=Get-JobsRunnerHarmonyPublicRelease}
    catch [Management.Automation.PipelineStoppedException]{throw}
    catch [OperationCanceledException]{throw}
    catch{Write-Host ('官方公开兼容Release未能验证：'+$_.Exception.Message) -ForegroundColor Yellow}
    $minimum=if($public){$public.Version}else{''}
    $healthy=$root-and(Test-JobsPrepareToolFiles $root)-and[IO.File]::Exists((Join-Path $root 'emulator/Emulator.exe'))
    if($public-and$current-and[version]$current-ge[version]$public.Version-and$healthy){
        Write-Host ('本机CLT '+$current+' 满足官方公开兼容Release '+$public.Version+'，继续能力复检；无需获取下载授权。')
    }else{
        $package=Wait-JobsRunnerHarmonyOfficialUpdate $minimum
        if($null-eq$package){return $null}
        if($null-ne$package.PSObject.Properties['Kind']-and$package.Kind-ceq'Back'){return $package}
        if($current-cne$package.Version-or-not$healthy){$root=Install-JobsRunnerOfficialHarmonyTools $package}
    }
    return $root
}

function Initialize-JobsRunnerVirtualHarmony {
    param([string]$Flutter,[string]$Project)
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'PrepareHarmonyRun.ps1/PrepareHarmonyRun.ps1')
    $script:JobsPrepareCore=Import-JobsPrepareCore
    [void](& $script:JobsPrepareCore.Tools {Get-JobsHarmonyArchitecture})
    $resolved=Resolve-JobsRunnerHarmonyToolRoot
    if($null-eq$resolved){return $null}
    if($null-ne$resolved.PSObject.Properties['Kind']-and$resolved.Kind-ceq'Back'){return $resolved}
    $root=[string]$resolved
    $env:TOOL_HOME=$root;$env:DEVECO_STUDIO_HOME=$root
    $tools=Initialize-JobsPrepareTools $Project
    $module=Import-JobsRunnerHarmonyCreator
    $emulator=Join-Path $root 'emulator/Emulator.exe'
    $help=Invoke-JobsRunnerHarmonyCore $module 'Invoke-JobsHarmonyQuery' @($emulator,@('-help'))
    foreach($flag in @('-list','-details','-start','-instancePath','-imageList','-install')) {
        if($help-notmatch('(?<![A-Za-z0-9_-])'+[regex]::Escape($flag)+'(?![A-Za-z0-9_-])')){throw ('官方CLT安装后启动能力复检缺少：'+$flag)}
    }
    Update-JobsRunnerHarmonyCatalog $module $emulator $help
    return [pscustomobject]@{Flutter=$Flutter;Tools=$tools;Module=$module;Emulator=$emulator}
}

function Start-JobsRunnerExistingHarmony {
    param([string]$Flutter,[string]$Project)
    $snapshot=Get-JobsRunnerTaskEnvironmentSnapshot @('PATH','JAVA_HOME','FLUTTER_ROOT','TOOL_HOME','DEVECO_STUDIO_HOME','DEVECO_SDK_HOME','OHOS_SDK_HOME','FVM_CACHE_PATH','FVM_FLUTTER_URL','FVM_USE_GIT_CACHE')
    try {
        $environment=Initialize-JobsRunnerVirtualHarmony $Flutter $Project
        if($null-eq$environment){return $null}
        if($null-ne$environment.PSObject.Properties['Kind']-and$environment.Kind-ceq'Back'){return $environment}
        $module=$environment.Module; $tools=$environment.Tools; $emulator=$environment.Emulator
        $instances=@(Invoke-JobsRunnerHarmonyCore $module 'Get-JobsHarmonyInstances' @($emulator))
        if (-not $instances.Count) { Write-Host '暂无已有鸿蒙模拟器；可返回后另选“新建设备”。'; return [pscustomobject]@{Kind='Back'} }
        $identities=@{}; $identityErrors=@{}
        foreach ($listed in $instances) {
            if ($identities.ContainsKey($listed.name) -or $identityErrors.ContainsKey($listed.name)) { throw '鸿蒙实例清单名称不唯一，未启动。' }
            try { $identities[$listed.name]=Get-JobsRunnerHarmonyInstanceIdentity $module $listed }
            catch [Management.Automation.PipelineStoppedException] { throw }
            catch [OperationCanceledException] { throw }
            catch { $identityErrors[$listed.name]=$_.Exception.Message }
        }
        $selection=Select-JobsRunnerChoice '启动鸿蒙模拟器' (@($instances | ForEach-Object {$_.name})+@('返回上一层')) -Back
        if ($null -eq $selection) { return $null }
        if ($selection.Kind -ceq 'Back' -or $selection.Index -ge $instances.Count) { return [pscustomobject]@{Kind='Back'} }
        $instance=$instances[$selection.Index]
        if (-not $identities.ContainsKey($instance.name)) { throw ('所选鸿蒙实例在列出时无法核验身份：'+$identityErrors[$instance.name]) }
        $identity=$identities[$instance.name]
        $instance=Assert-JobsRunnerHarmonyInstance $module $emulator $identity
        Invoke-JobsRunnerHarmonyCore $module 'Confirm-JobsHarmonyLicenses' @($emulator)
        Initialize-JobsRunnerHarmonyImage $module $emulator $identity
        $instance=Assert-JobsRunnerHarmonyInstance $module $emulator $identity
        Set-JobsRunnerHarmonyInstanceSdk (Get-JobsRunnerHarmonyInstanceIdentity $module $instance) (Join-Path $tools.Root 'sdk')
        $instances=@(Invoke-JobsRunnerHarmonyCore $module 'Get-JobsHarmonyInstances' @($emulator))
        $matches=@($instances | Where-Object {$_.name -ceq $identity.Name})
        if ($matches.Count -ne 1) { throw '配置后原实例身份不唯一。' }
        $configured=Get-JobsRunnerHarmonyInstanceIdentity $module $matches[0]
        foreach ($field in @('Name','Path','Uuid','DeviceType','Version','ImageRoot')) { if ($configured.$field -cne $identity.$field) { throw '配置后原实例身份已改变，未启动。' } }
        $instance=Assert-JobsRunnerHarmonyInstance $module $emulator $configured
        Invoke-JobsRunnerHarmonyCore $module 'Confirm-JobsHarmonyLicenses' @($emulator)
        if (-not $configured.Running) {
            $latest=Get-JobsRunnerHarmonyInstanceIdentity $module (Assert-JobsRunnerHarmonyInstance $module $emulator $configured)
            $arguments=@('-start',$configured.Name,'-instancePath',$configured.Path)
            if ($configured.ImageRoot) { $arguments+=@('-imageRoot',$configured.ImageRoot) }
            if (-not $latest.Running) { Invoke-JobsRunnerHarmonyCore $module 'Invoke-JobsHarmonyInteractive' @($emulator,$arguments) }
        }
        $id=Get-JobsRunnerHarmonyTarget $module $emulator $instance
        # 官方启动可写端口等运行字段；核对原UUID等身份后固定启动完成的完整配置基线。
        $running=@(Invoke-JobsRunnerHarmonyCore $module 'Get-JobsHarmonyInstances' @($emulator) | Where-Object {$_.name -ceq $configured.Name})
        if ($running.Count -ne 1) { throw '启动后原鸿蒙实例身份不唯一。' }
        $postStart=Get-JobsRunnerHarmonyInstanceIdentity $module $running[0]
        foreach ($field in @('Name','Path','Uuid','DeviceType','Version','ImageRoot')) { if ($postStart.$field -cne $configured.$field) { throw '启动期间原鸿蒙实例已被替换，未运行应用。' } }
        $ready=Start-JobsRunnerHarmonyPreparation $environment.Flutter $Project $id -RefreshCompatible
        if ($ready -cne $id) { throw '鸿蒙准备返回不同设备，未运行应用。' }
        $verified=Assert-JobsRunnerHarmonyInstance $module $emulator $postStart
        $currentId=Get-JobsRunnerHarmonyTarget $module $emulator $verified
        if ($currentId -cne $id) { throw '准备后原鸿蒙实例HDC端口已改变，未运行应用。' }
        [void](Assert-JobsRunnerHarmonyInstance $module $emulator $postStart)
        return [pscustomobject]@{Kind='Ready';Id=$id;Platform=$script:RunnerSelectedPlatform;Environment=(Get-JobsRunnerVirtualEnvironment)}
    } finally { Restore-JobsRunnerTaskEnvironment $snapshot }
}
