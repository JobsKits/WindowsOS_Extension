# PackageInstaller.psm1 | WindowsOS@Extension 独立功能包
# Created by Jobs on 2026年10月18日，星期日.
# 只管理传入功能包自己的文件、状态和菜单；导入模块不会修改系统。

# 源包装与已发布 flat 布局共用路径，兼容旧收据且不跟随包装目录链接。
function Resolve-JobsScriptLayoutPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([IO.Path]::GetExtension($Path) -notin @('.ps1','.cmd','.vbs')) { return $Path }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('脚本包装不能是链接：' + $Path) }
        return Join-Path $Path $directory.Name
    }
    return $Path
}
# 仅新源码包装压平到原发布名称；原有 SDK 资源包与 README 布局保持原意。
function Convert-JobsReleaseLayoutRelativePath {
    param([string]$Package, [string]$Relative)
    $parts = @($Relative -split '[\\/]')
    if ($parts.Count -lt 2) { return $Relative }
    $last = $parts[$parts.Count - 1]
    $parent = $parts[$parts.Count - 2]
    if ($last -ceq 'README.md' -and [IO.Path]::GetExtension($parent) -in @('.ps1','.cmd','.vbs')) {
        $sibling = Join-Path (Join-Path $Package (($parts[0..($parts.Count-2)]) -join '/')) $parent
        if ((Test-Path -LiteralPath $sibling -PathType Leaf) -and ([IO.File]::ReadAllText($sibling) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) { return $null }
    }
    if ($last -ceq $parent -and [IO.Path]::GetExtension($last) -in @('.ps1','.cmd','.vbs')) {
        $source = Join-Path $Package $Relative
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and ([IO.File]::ReadAllText($source) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) {
            return (($parts[0..($parts.Count-2)]) -join '/')
        }
    }
    return $Relative
}
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# 安装目录与临时运行目录各自持有状态；运行副本从自身元数据定位。
function Get-JobsPackageBase {
    param([string]$PackagePath, [ValidateSet('installed', 'build')][string]$DeploymentMode = 'installed')
    if (-not [string]::IsNullOrWhiteSpace($PackagePath)) {
        $binding = Join-Path $PackagePath 'deployment.json'
        if (Test-Path -LiteralPath $binding -PathType Leaf) {
            $deployment = Get-Content -LiteralPath $binding -Raw -Encoding UTF8 | ConvertFrom-Json
            return [string]$deployment.BasePath
        }
        if ($DeploymentMode -eq 'build') { return Join-Path ([IO.Path]::GetFullPath($PackagePath)) 'work/WindowsExtension' }
    }
    $local = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    if ([string]::IsNullOrWhiteSpace($local)) { $local = [Environment]::GetFolderPath('LocalApplicationData') }
    if ([string]::IsNullOrWhiteSpace($local)) { throw '无法定位当前用户本地应用数据。' }
    return Join-Path $local 'Jobs/WindowsExtension'
}
# 专用工作区只保存编译中间文件；已部署 release 从不进入此目录。
function Get-JobsPackageBuildRoot {
    param([string]$PackagePath)
    return Join-Path ([IO.Path]::GetFullPath($PackagePath)) 'work/JobsExtensionBuild'
}
# 拒绝路径祖先或子项的链接，避免清理穿出本包工作区。
function Assert-JobsBuildDirectory {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('工作区不能经过链接：' + $current) }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
# 读取真实目录文件 ID，识别检查与搬移之间发生的目录替换。
function Get-JobsBuildDirectoryIdentity {
    param([string]$Path)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '无法核对 Windows 目录身份，保留构建产物。' }
    if (-not ('Jobs.BuildArtifactIdentityV1' -as [type])) {
        Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Jobs {
    public static class BuildArtifactIdentityV1 {
        [StructLayout(LayoutKind.Sequential)]
        struct Information {
            public uint Attributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
            public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Information info);
        public static string Read(string path) {
            using (SafeFileHandle handle = CreateFile(path, 0x80, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero)) {
                if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                Information info;
                if (!GetFileInformationByHandle(handle, out info)) throw new Win32Exception(Marshal.GetLastWin32Error());
                if ((info.Attributes & 0x10) == 0 || (info.Attributes & 0x400) != 0) throw new InvalidOperationException("Not a real directory.");
                return info.Volume.ToString("X8") + ":" + info.IndexHigh.ToString("X8") + info.IndexLow.ToString("X8");
            }
        }
    }
}
'@
    }
    return [Jobs.BuildArtifactIdentityV1]::Read($Path)
}
# 逐层检查后才下钻，不遍历链接，也不把版本元数据作为编译垃圾。
function Assert-JobsBuildArtifactTree {
    param([string]$Path)
    Assert-JobsBuildDirectory $Path
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue($Path)
    while ($pending.Count -gt 0) {
        foreach ($item in @(Get-ChildItem -LiteralPath $pending.Dequeue() -Force -ErrorAction Stop)) {
            if ($item.Name -in @('.git', '.hg', '.svn')) { throw ('工作区包含版本元数据，保留构建产物：' + $item.FullName) }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('工作区含链接，已停止清理：' + $item.FullName) }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
        }
    }
}
# 只读枚举本包注册计划对应键值，兼容命令入口与原生 DLL 登记。
function Get-JobsBuildArtifactRegistryValues {
    param($Manifest, [string]$BuildRoot)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '无法查询 Windows 注册表，保留构建产物。' }
    $plan = @(Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $BuildRoot -PowerShellPath (Join-Path $PSHOME 'powershell.exe'))
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
            try {
                $pending = New-Object 'System.Collections.Generic.Queue[string]'
                foreach ($entry in $plan) { $pending.Enqueue([string]$entry.Key) }
                while ($pending.Count -gt 0) {
                    $path = $pending.Dequeue()
                    $key = $base.OpenSubKey($path, $false)
                    if ($null -eq $key) { continue }
                    try {
                        foreach ($name in $key.GetValueNames()) {
                            $value = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                            if ($value -is [string]) { [Environment]::ExpandEnvironmentVariables($value) }
                            elseif ($value -is [string[]]) { foreach ($part in $value) { [Environment]::ExpandEnvironmentVariables($part) } }
                        }
                        foreach ($child in $key.GetSubKeyNames()) { $pending.Enqueue($path + '\' + $child) }
                    } finally { $key.Dispose() }
                }
            } finally { $base.Dispose() }
        }
    }
}
# 查询失败向上传播，不把不可取得的进程列表当作无人使用。
function Get-JobsBuildArtifactProcessValues {
    $processes = @(Get-CimInstance -ClassName Win32_Process -Property ExecutablePath, CommandLine -ErrorAction Stop)
    if ($processes.Count -eq 0) { throw '进程查询返回空结果，保留构建产物。' }
    foreach ($process in $processes) {
        if ($null -ne $process.ExecutablePath) { [string]$process.ExecutablePath }
        if ($null -ne $process.CommandLine) { [string]$process.CommandLine }
    }
}
# 已卸载残留只在两条路线均禁用且没有登记或进程引用时可清理。
function Assert-JobsOrphanBuildUnused {
    param([string]$PackagePath, $Manifest, [string[]]$SourceRoots)
    foreach ($mode in @('installed', 'build')) {
        $state = Get-JobsPackageState -PackagePath $PackagePath -DeploymentMode $mode
        if ($state.Enabled) { throw '本功能仍有启用的运行路线，保留卸载残留。' }
    }
    $values = @(Get-JobsBuildArtifactRegistryValues -Manifest $Manifest -BuildRoot $SourceRoots[0])
    $values += @(Get-JobsBuildArtifactProcessValues)
    foreach ($root in $SourceRoots) {
        $pattern = [regex]::Escape($root.TrimEnd('\', '/').Replace('/', '\')) + '(?:[\\/]|["''\s]|$)'
        foreach ($value in $values) {
            if ([regex]::IsMatch(([string]$value).Replace('/', '\'), $pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase)) { throw ('构建工作区仍有登记或进程引用，保留产物：' + $root) }
        }
    }
}
# 仅清除身份匹配且不承载当前 release 的专用编译工作区。
function Clear-JobsPackageBuildArtifactsCore {
    param([Parameter(Mandatory = $true)][string]$PackagePath, [string]$BuildPath)
    $manifest = Get-JobsPackageManifest -PackagePath $PackagePath
    $state = Get-JobsPackageState -PackagePath $PackagePath -DeploymentMode installed
    $orphan = -not $state.Enabled
    if ($orphan -and -not [string]::IsNullOrWhiteSpace($BuildPath)) { throw '自动清理仍要求本轮正常安装，保留构建产物。' }
    if (-not $orphan) {
        if ([string]::IsNullOrWhiteSpace($state.ReleasePath) -or
            -not (Test-Path -LiteralPath (Resolve-JobsScriptLayoutPath (Join-Path $state.ReleasePath 'Scripts/Invoke.ps1')) -PathType Leaf)) { throw '本功能在默认程序位置尚无正常安装，保留构建产物。' }
        $runtimeManifest = Get-JobsPackageManifest -PackagePath $state.ReleasePath
        if ($runtimeManifest.Id -cne $manifest.Id) { throw '已安装运行版本身份不一致，保留构建产物。' }
        foreach ($name in @('Common.psm1', 'Action.psm1', 'Invoke.ps1')) {
            if (-not (Test-Path -LiteralPath (Join-Path $state.ReleasePath ('Scripts/' + $name)) -PathType Leaf)) { throw ('已安装运行文件不完整：' + $name) }
        }
        $registryPlan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $state.ReleasePath -PowerShellPath (Join-Path $PSHOME 'powershell.exe'))
        foreach ($entry in $registryPlan) {
            if ($null -ne $entry.PSObject.Properties['InProcServer'] -and -not (Test-Path -LiteralPath $entry.InProcServer -PathType Leaf)) { throw '已安装 DLL 缺失，保留构建产物。' }
        }
        $requiredRuntime = @()
        if ($manifest.Id -in @('flutter-run', 'flutter-tools')) { $requiredRuntime += 'bin/JobsFlutterRunnerHost.exe' }
        if ($manifest.Id -eq 'flutter-tools') { $requiredRuntime += 'Scripts/Actions/run/bin/JobsFlutterRunnerHost.exe' }
        foreach ($relative in $requiredRuntime) {
            if (-not (Test-Path -LiteralPath (Join-Path $state.ReleasePath $relative) -PathType Leaf)) { throw ('已安装运行宿主缺失，保留构建产物：' + $relative) }
        }
    }
    $buildRoot = Get-JobsPackageBuildRoot $PackagePath
    if (-not (Test-Path -LiteralPath $buildRoot)) { Write-Host ('没有可清除的专用构建产物：' + $buildRoot); return }
    Assert-JobsBuildDirectory $buildRoot
    $sourceIdentity = $null
    if ($orphan) { $sourceIdentity = Get-JobsBuildDirectoryIdentity $buildRoot }
    $marker = Get-Content -LiteralPath (Join-Path $buildRoot 'build-owner.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($marker.Id -cne $manifest.Id -or -not [string]::Equals([IO.Path]::GetFullPath([string]$marker.PackagePath), [IO.Path]::GetFullPath($PackagePath), [StringComparison]::OrdinalIgnoreCase)) { throw '构建工作区归属不匹配，已停止清理。' }
    foreach ($mode in @('installed', 'build')) {
        $active = Get-JobsPackageState -PackagePath $PackagePath -DeploymentMode $mode
        if ($active.Enabled -and -not [string]::IsNullOrWhiteSpace($active.ReleasePath)) {
            $activePath = [IO.Path]::GetFullPath([string]$active.ReleasePath).TrimEnd('\', '/')
            if ($activePath -eq $buildRoot.TrimEnd('\', '/') -or $activePath.StartsWith($buildRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw '构建工作区仍被运行版本使用，已停止清理。' }
        }
    }
    $target = $buildRoot
    if (-not [string]::IsNullOrWhiteSpace($BuildPath)) {
        $target = [IO.Path]::GetFullPath($BuildPath)
        if (-not $target.StartsWith($buildRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Parent $target) -ne $buildRoot -or (Split-Path -Leaf $target) -cnotmatch '^[a-f0-9]{32}$') { throw '本轮构建目录不属于专用工作区。' }
    }
    Assert-JobsBuildArtifactTree $target
    if ($orphan) {
        Assert-JobsOrphanBuildUnused -PackagePath $PackagePath -Manifest $manifest -SourceRoots @($buildRoot)
        $quarantine = Join-Path (Split-Path -Parent $target) ('.JobsExtensionCleanup-' + [guid]::NewGuid().ToString('N'))
        $moved = Join-Path $quarantine (Split-Path -Leaf $target)
        [void][IO.Directory]::CreateDirectory($quarantine)
        try {
            Move-Item -LiteralPath $target -Destination $moved -ErrorAction Stop
            Assert-JobsBuildDirectory $moved
            if ((Get-JobsBuildDirectoryIdentity $moved) -cne $sourceIdentity) { throw '构建目录身份变化，保留暂存产物。' }
            $movedMarker = Get-Content -LiteralPath (Join-Path $moved 'build-owner.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($movedMarker.Id -cne $manifest.Id -or -not [string]::Equals([IO.Path]::GetFullPath([string]$movedMarker.PackagePath), [IO.Path]::GetFullPath($PackagePath), [StringComparison]::OrdinalIgnoreCase)) { throw '暂存工作区归属变化，保留构建产物。' }
            Assert-JobsBuildArtifactTree $moved
            Assert-JobsOrphanBuildUnused -PackagePath $PackagePath -Manifest $manifest -SourceRoots @($buildRoot, $moved)
            Assert-JobsBuildArtifactTree $moved
            if ((Get-JobsBuildDirectoryIdentity $moved) -cne $sourceIdentity) { throw '构建目录身份变化，保留暂存产物。' }
            Remove-Item -LiteralPath $moved -Recurse -Force -ErrorAction Stop
            Write-Host ('已清除卸载后的构建残留：' + $target + '；运行文件、配置与注册表保留。')
        } catch {
            if ((Test-Path -LiteralPath $moved) -and -not (Test-Path -LiteralPath $target)) {
                if ((Get-JobsBuildDirectoryIdentity $moved) -ceq $sourceIdentity) { Move-Item -LiteralPath $moved -Destination $target -ErrorAction Stop }
                else { Write-Warning ('未恢复身份变化的目录；原位置：' + $target + '；暂存位置：' + $moved) }
            }
            throw
        } finally {
            if ((Test-Path -LiteralPath $quarantine) -and @(Get-ChildItem -LiteralPath $quarantine -Force).Count -eq 0) { [IO.Directory]::Delete($quarantine) }
        }
        return
    }
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
    Write-Host ('已清除构建产物：' + $target + '；已安装运行文件、配置与注册表保留。')
}
# 与安装共用互斥锁，防止清理另一面板正在编译的工作区。
function Clear-JobsPackageBuildArtifacts {
    param([Parameter(Mandatory = $true)][string]$PackagePath, [string]$BuildPath)
    $lockBase = Get-JobsPackageBase
    if (-not (Test-Path -LiteralPath $lockBase -PathType Container)) { throw '默认程序位置尚未安装，保留构建产物。' }
    $cleanupLock = $null
    try {
        try { $cleanupLock = [IO.File]::Open((Join-Path $lockBase 'manage.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { throw '另一安装或清理事务正在使用工作区，请稍后重试。' }
        Clear-JobsPackageBuildArtifactsCore -PackagePath $PackagePath -BuildPath $BuildPath
    } finally { if ($cleanupLock) { $cleanupLock.Dispose() } }
}
# 编译输出只留在指定目录；DLL 与 EXE 按运行位置部署，OBJ/RSP 不进入 installed release。
function Build-JobsPackageNativeRelease {
    param([string]$PackagePath, [string]$ReleasePath, [string]$DeploymentMode)
    $manifest = Get-JobsPackageManifest -PackagePath $PackagePath
    $output = Join-Path $ReleasePath 'bin'
    if ($DeploymentMode -eq 'installed') {
        $buildRoot = Get-JobsPackageBuildRoot $PackagePath
        Assert-JobsBuildDirectory $buildRoot
        if (Test-Path -LiteralPath $buildRoot) {
            $owner = Get-Content -LiteralPath (Join-Path $buildRoot 'build-owner.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($owner.Id -cne $manifest.Id -or -not [string]::Equals([string]$owner.PackagePath, [IO.Path]::GetFullPath($PackagePath), [StringComparison]::OrdinalIgnoreCase)) { throw '构建工作区归属不匹配。' }
        }
        [void][IO.Directory]::CreateDirectory($buildRoot)
        @{ Id = $manifest.Id; PackagePath = [IO.Path]::GetFullPath($PackagePath) } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $buildRoot 'build-owner.json') -Encoding UTF8
        $output = Join-Path $buildRoot ([guid]::NewGuid().ToString('N'))
    }
    $script:LastBuildPath = $output
    & (Resolve-JobsScriptLayoutPath (Join-Path $ReleasePath 'Scripts/Build.ps1')) -SourceRoot $ReleasePath -OutputRoot $output
    $binaries = @(Get-ChildItem -LiteralPath $output -File | Where-Object { $_.Extension -in @('.dll', '.exe') })
    if (@($binaries | Where-Object { $_.Extension -eq '.dll' }).Count -eq 0) { throw '本轮编译没有产生原生 DLL。' }
    if ($manifest.Id -in @('flutter-run', 'flutter-tools') -and -not (Test-Path -LiteralPath (Join-Path $output 'JobsFlutterRunnerHost.exe') -PathType Leaf)) { throw 'Flutter 后台宿主 EXE 缺失，停止部署。' }
    $runtimeBin = Join-Path $ReleasePath 'bin'
    [void][IO.Directory]::CreateDirectory($runtimeBin)
    foreach ($binary in $binaries) {
        $target = Join-Path $runtimeBin $binary.Name
        if (-not [string]::Equals([IO.Path]::GetFullPath($binary.FullName), [IO.Path]::GetFullPath($target), [StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $binary.FullName -Destination $target -ErrorAction Stop
        }
        if ((Get-FileHash -LiteralPath $binary.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw ('运行产物部署校验失败：' + $binary.Name) }
    }
    if ($manifest.Id -eq 'flutter-tools') {
        # 内嵌 run 动作从自己的包目录查找后台宿主；两种路线都在真实 release 中部署。
        $runnerBin = Join-Path $ReleasePath 'Scripts/Actions/run/bin'
        [void][IO.Directory]::CreateDirectory($runnerBin)
        $hostSource = Join-Path $runtimeBin 'JobsFlutterRunnerHost.exe'
        $hostTarget = Join-Path $runnerBin 'JobsFlutterRunnerHost.exe'
        Copy-Item -LiteralPath $hostSource -Destination $hostTarget -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $hostSource).Hash -ne (Get-FileHash -LiteralPath $hostTarget).Hash) { throw 'Flutter 内嵌后台宿主部署校验失败。' }
    }
}

function Get-JobsPackageManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackagePath)

    $package = [IO.Path]::GetFullPath($PackagePath)
    $path = Join-Path $package 'Extension.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('缺少功能清单：' + $path) }
    $manifest = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    foreach ($name in @('Id', 'Name', 'Label', 'Description', 'DirectoryOnly', 'Console')) {
        if ($null -eq $manifest.PSObject.Properties[$name]) { throw ('功能清单缺少字段：' + $name) }
    }
    if ($manifest.Id -isnot [string] -or $manifest.Id -cnotmatch '^[a-z][a-z0-9-]+$') { throw '功能标识不合法。' }
    if ($manifest.Name -isnot [string] -or $manifest.Name -cnotmatch '^Jobs[A-Za-z0-9]+$') { throw '功能包名称不合法。' }
    foreach ($name in @('Label', 'Description')) {
        if ($manifest.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($manifest.$name) -or $manifest.$name -match '[\x00-\x1f]') {
            throw ('功能清单文本不合法：' + $name)
        }
    }
    if ($manifest.DirectoryOnly -isnot [bool] -or $manifest.Console -isnot [bool]) { throw '功能清单开关必须是布尔值。' }
    return $manifest
}

function Get-JobsPackageState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackagePath, [ValidateSet('installed', 'build')][string]$DeploymentMode = 'installed')

    $manifest = Get-JobsPackageManifest -PackagePath $PackagePath
    $base = Get-JobsPackageBase -PackagePath $PackagePath -DeploymentMode $DeploymentMode
    $root = Join-Path (Join-Path $base 'extensions') $manifest.Id
    $settingsPath = Join-Path $root 'settings.json'
    $enabled = $false
    $release = $null
    $source = 'None'
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $settings.PSObject.Properties['Version'] -or $settings.Version -ne 2 -or
            $null -eq $settings.PSObject.Properties['Id'] -or $settings.Id -cne $manifest.Id -or
            $null -eq $settings.PSObject.Properties['Enabled'] -or $settings.Enabled -isnot [bool] -or
            $null -eq $settings.PSObject.Properties['ReleasePath']) { throw ('本功能安装状态无效：' + $settingsPath) }
        $enabled = $settings.Enabled
        $release = [string]$settings.ReleasePath
        $source = 'Package'
    }
    else {
        $legacyPath = Join-Path $base 'settings.json'
        if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
            $legacy = Get-Content -LiteralPath $legacyPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($null -ne $legacy.PSObject.Properties['Version'] -and $legacy.Version -eq 1 -and
                $null -ne $legacy.PSObject.Properties['Features'] -and $null -ne $legacy.PSObject.Properties['ReleasePath']) {
                $legacyRelease = [string]$legacy.ReleasePath
                # 只有仍有运行文件的旧安装参与迁移，残留选择清单不能复活菜单。
                if (-not [string]::IsNullOrWhiteSpace($legacyRelease) -and
                    (Test-Path -LiteralPath (Join-Path $legacyRelease 'Invoke-Menu.ps1') -PathType Leaf)) {
                    $enabled = $manifest.Id -cin @($legacy.Features)
                    $release = $legacyRelease
                    $source = 'Legacy'
                }
            }
        }
    }
    return [pscustomobject]@{ Id = $manifest.Id; Enabled = $enabled; ReleasePath = $release; Root = $root; Source = $source }
}

function ConvertTo-JobsPackageArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
    if ($Value.IndexOf([char]0) -ge 0) { throw '参数不能包含空字符。' }
    # CommandLineToArgvW 的反斜杠规则；目标仅通过 -File 的字符串参数传入。
    return '"' + ([regex]::Replace($Value, '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Get-JobsPackageRegistryPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)][string]$ReleasePath,
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [bool]$Enabled = $true
    )

    if ($Manifest.Id -cnotmatch '^[a-z][a-z0-9-]+$' -or $Manifest.Name -cnotmatch '^Jobs[A-Za-z0-9]+$') { throw '功能清单标识不合法。' }
    $clsid = '{F92F7AF9-65B6-41CB-A6D8-712F01F79126}'
    $owner = 'Jobs.WindowsExtension.v1'
    foreach ($class in @('DesktopBackground')) {
        [pscustomobject]@{
            Key = 'Software\Classes\' + $class + '\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $Manifest.Id
            Enabled = $Enabled; Owner = $owner
            Values = @{ '' = $clsid; JobsOwner = $owner }
        }
    }
    [pscustomobject]@{
        Key = 'Software\Classes\CLSID\' + $clsid
        Enabled = $Enabled; Owner = $owner
        Values = @{ '' = $Manifest.Label; JobsOwner = $owner }
        InProcServer = Join-Path $ReleasePath 'bin/JobsHiddenFilesTogglerContextMenu.dll'
    }
}

function Assert-JobsPackageSourceFile {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('运行文件不能是目录或链接：' + $Path) }
    if ($item.Extension -in @('.ps1', '.psm1')) {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($item.FullName, [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw ('运行文件语法错误：' + $item.FullName + '；' + $errors[0].Message) }
    }
}

function New-JobsPackageRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $package = [IO.Path]::GetFullPath($PackagePath)
    [void](Get-JobsPackageManifest -PackagePath $package)
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    if (Test-Path -LiteralPath $destinationPath) { throw ('运行目录已存在，拒绝覆盖：' + $destinationPath) }
    $scripts = Join-Path $package 'Scripts'
    $scriptsItem = Get-Item -LiteralPath $scripts -Force -ErrorAction Stop
    if (-not $scriptsItem.PSIsContainer -or ($scriptsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Scripts 必须是本包真实目录。' }
    $files = @('Extension.json')
    foreach ($name in @('Common.psm1', 'Action.psm1', 'Invoke.ps1', 'Manage.ps1', 'PackageInstaller.psm1')) {
        if (-not (Test-Path -LiteralPath (Resolve-JobsScriptLayoutPath (Join-Path $scripts $name)) -PathType Leaf)) { throw ('本包缺少运行文件：Scripts/' + $name) }
    }
    # 只取当前包的直属脚本；开发测试、日志及相邻功能从不进入 release。
    foreach ($item in Get-ChildItem -LiteralPath $scripts -Force -ErrorAction Stop) {
        if ($item.PSIsContainer) {
            if ($item.Extension -eq '.ps1') {
                $wrapped = Resolve-JobsScriptLayoutPath $item.FullName
                if ((Test-Path -LiteralPath $wrapped -PathType Leaf) -and ([IO.File]::ReadAllText($wrapped) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) { $files += 'Scripts/' + $item.Name }
            }
            continue
        }
        if ($item.Extension -in @('.ps1', '.psm1', '.dart', '.cs', '.cpp', '.h', '.def') -and $item.Name -notmatch '(?i)\.Tests?\.') {
            $files += 'Scripts/' + $item.Name
        }
    }
    foreach ($name in @('Manage.cmd', 'Manage.vbs', 'Run.cmd', 'README.md')) {
        if (Test-Path -LiteralPath (Resolve-JobsScriptLayoutPath (Join-Path $package $name)) -PathType Leaf) { $files += $name }
    }
    $files = @($files | ForEach-Object { Convert-JobsReleaseLayoutRelativePath $package $_ } | Where-Object { $null -ne $_ } | Select-Object -Unique)
    foreach ($relative in $files) { Assert-JobsPackageSourceFile -Path (Resolve-JobsScriptLayoutPath (Join-Path $package $relative)) }
    [void][IO.Directory]::CreateDirectory((Join-Path $destinationPath 'Scripts'))
    foreach ($relative in $files) {
        $source = Resolve-JobsScriptLayoutPath (Join-Path $package $relative)
        $target = Join-Path $destinationPath $relative
        Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash) {
            throw ('复制校验失败：' + $relative)
        }
    }
    return $destinationPath
}

function Read-JobsPackageRegistryTree {
    param([Microsoft.Win32.RegistryKey]$Key)
    $values = @()
    foreach ($name in $Key.GetValueNames()) {
        $values += @{ Name = $name; Kind = [int]$Key.GetValueKind($name); Value = $Key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    }
    $children = @{}
    foreach ($name in $Key.GetSubKeyNames()) {
        $child = $Key.OpenSubKey($name)
        try { $children[$name] = Read-JobsPackageRegistryTree -Key $child } finally { $child.Dispose() }
    }
    return @{ Values = $values; Children = $children }
}

function Restore-JobsPackageRegistryTree {
    param([Microsoft.Win32.RegistryKey]$Key, $Tree)
    foreach ($entry in $Tree.Values) { $Key.SetValue($entry.Name, $entry.Value, [Microsoft.Win32.RegistryValueKind]$entry.Kind) }
    foreach ($name in $Tree.Children.Keys) {
        $child = $Key.CreateSubKey($name)
        try { Restore-JobsPackageRegistryTree -Key $child -Tree $Tree.Children[$name] } finally { $child.Dispose() }
    }
}

function Get-JobsPackageRegistrySnapshot {
    param([object[]]$Plan, [Microsoft.Win32.RegistryKey]$RegistryRoot)
    $snapshot = @{}
    foreach ($item in $Plan) {
        $key = $RegistryRoot.OpenSubKey($item.Key)
        if ($null -eq $key) { $snapshot[$item.Key] = $null; continue }
        try {
            if ($key.GetValue('JobsOwner') -ne 'Jobs.WindowsExtension.v1') { throw ('注册表入口归属不明，已停止：HKCU\' + $item.Key) }
            $snapshot[$item.Key] = Read-JobsPackageRegistryTree -Key $key
        }
        finally { $key.Dispose() }
    }
    return $snapshot
}

function Restore-JobsPackageRegistrySnapshot {
    param($Snapshot, [Microsoft.Win32.RegistryKey]$RegistryRoot)
    foreach ($path in $Snapshot.Keys) {
        $RegistryRoot.DeleteSubKeyTree($path, $false)
        if ($null -ne $Snapshot[$path]) {
            $key = $RegistryRoot.CreateSubKey($path)
            try { Restore-JobsPackageRegistryTree -Key $key -Tree $Snapshot[$path] } finally { $key.Dispose() }
        }
    }
}

function Set-JobsPackageRegistry {
    param([object[]]$Plan, [Microsoft.Win32.RegistryKey]$RegistryRoot)
    foreach ($item in $Plan) {
        $RegistryRoot.DeleteSubKeyTree($item.Key, $false)
        if (-not $item.Enabled) { continue }
        $key = $RegistryRoot.CreateSubKey($item.Key)
        try {
            foreach ($name in $item.Values.Keys) { $key.SetValue($name, $item.Values[$name]) }
            if ($null -ne $item.PSObject.Properties['InProcServer']) {
                $server = $key.CreateSubKey('InprocServer32')
                try { $server.SetValue('', $item.InProcServer); $server.SetValue('ThreadingModel', 'Apartment') }
                finally { $server.Dispose() }
            }
        }
        finally { $key.Dispose() }
    }
}

function Set-JobsPackageSettingsFile {
    param([string]$Path, [byte[]]$Bytes)
    $temporary = Join-Path (Split-Path -Parent $Path) ('settings-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { [IO.File]::Delete($temporary) }
    }
}

function Invoke-JobsPackageTransaction {
    param([object[]]$Plan, [Microsoft.Win32.RegistryKey]$RegistryRoot, $Snapshot, [scriptblock]$Commit, [scriptblock]$Rollback)
    try {
        Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $RegistryRoot
        & $Commit
    }
    catch {
        $original = $_
        $rollbackErrors = @()
        try { Restore-JobsPackageRegistrySnapshot -Snapshot $Snapshot -RegistryRoot $RegistryRoot } catch { $rollbackErrors += $_.Exception.Message }
        try { & $Rollback } catch { $rollbackErrors += $_.Exception.Message }
        if ($rollbackErrors.Count -gt 0) {
            throw ('操作失败：' + $original.Exception.Message + '；回滚未完整完成：' + ($rollbackErrors -join '；') + '。请保留备份并手工恢复。')
        }
        throw $original
    }
}

function Set-JobsPackageUninstallShortcut {
    param($Manifest, [string]$ReleasePath, [string]$Mode)

    $programs = [Environment]::GetFolderPath('Programs')
    if ([string]::IsNullOrWhiteSpace($programs)) { throw '无法定位当前用户开始菜单。' }
    $folder = Join-Path (Join-Path $programs 'Jobs Windows Extension') $Manifest.Name
    $path = Join-Path $folder 'Uninstall.lnk'
    if ($Mode -eq 'Uninstall') {
        if (Test-Path -LiteralPath $path -PathType Leaf) { [IO.File]::Delete($path) }
        return
    }
    [void][IO.Directory]::CreateDirectory($folder)
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($path)
        $shortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
        $shortcut.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File ' +
            (ConvertTo-JobsPackageArgument (Resolve-JobsScriptLayoutPath (Join-Path $ReleasePath 'Scripts/Manage.ps1'))) + ' -Mode Uninstall'
        $shortcut.WorkingDirectory = $ReleasePath
        $shortcut.Description = '卸载 ' + $Manifest.Label + ' 右键菜单'
        $shortcut.Save()
    }
    finally { if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) } }
}

function Send-JobsPackageShellChange {
    if (-not ('Jobs.PackageShellNotification' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class PackageShellNotification {
        [DllImport("shell32.dll")]
        public static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);
    }
}
'@
    }
    [Jobs.PackageShellNotification]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Invoke-JobsPackageChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][ValidateSet('Install', 'Uninstall')][string]$Mode,
        [ValidateSet('installed', 'build')][string]$DeploymentMode = 'installed'
    )

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '安装与卸载仅支持 Windows。' }
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1') {
        throw '请使用系统 Windows PowerShell 5.1 或本包 Manage.vbs 入口执行安装与卸载。'
    }
    $script:LastBuildPath = $null
    $manifest = Get-JobsPackageManifest -PackagePath $PackagePath
    $base = Get-JobsPackageBase -PackagePath $PackagePath -DeploymentMode $DeploymentMode
    $root = Join-Path (Join-Path $base 'extensions') $manifest.Id
    [void][IO.Directory]::CreateDirectory($base)
    $lockBase = Get-JobsPackageBase
    [void][IO.Directory]::CreateDirectory($lockBase)
    $managementLock = $null
    try {
        try { $managementLock = [IO.File]::Open((Join-Path $lockBase 'manage.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch { throw '另一个功能包正在安装或卸载，请稍后重试。' }
        $state = Get-JobsPackageState -PackagePath $PackagePath -DeploymentMode $DeploymentMode
        if ($Mode -eq 'Uninstall' -and -not $state.Enabled) {
            Write-Host '当前部署路线未启用；保留其它路线的菜单与运行文件。'
            return [pscustomobject]@{ Id = $manifest.Id; Mode = $Mode; Outcome = 'NotInstalled'; Root = $root; Backup = $null; ReleasePath = $state.ReleasePath; BuildPath = $null }
        }
        $release = $state.ReleasePath
        if ($Mode -eq 'Install') {
            $release = Join-Path (Join-Path $root 'releases') ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
        }
        if ([string]::IsNullOrWhiteSpace($release)) { $release = [IO.Path]::GetFullPath($PackagePath) }
        $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $release -PowerShellPath (Join-Path $PSHOME 'powershell.exe') -Enabled ($Mode -eq 'Install'))
        $registry = [Microsoft.Win32.Registry]::CurrentUser
        # 在复制和写注册表之前核对本包所有键；不同包仍通过共享锁串行更改。
        $snapshot = Get-JobsPackageRegistrySnapshot -Plan $plan -RegistryRoot $registry
        [void][IO.Directory]::CreateDirectory($root)
        $settingsPath = Join-Path $root 'settings.json'
        $hadSettings = Test-Path -LiteralPath $settingsPath -PathType Leaf
        $oldSettings = $null
        if ($hadSettings) { $oldSettings = [IO.File]::ReadAllBytes($settingsPath) }
        $backupDirectory = Join-Path $root 'backups'
        [void][IO.Directory]::CreateDirectory($backupDirectory)
        $backup = Join-Path $backupDirectory ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.clixml')
        @{ Id = $manifest.Id; Registry = $snapshot; Settings = @{ Exists = $hadSettings; Bytes = $oldSettings }; Created = [DateTime]::Now } |
            Export-Clixml -LiteralPath $backup -Depth 40 -ErrorAction Stop
        if ($Mode -eq 'Install') {
            [void](New-JobsPackageRelease -PackagePath $PackagePath -Destination $release)
            @{ Version = 1; Mode = $DeploymentMode; BasePath = $base; Root = $root; Id = $manifest.Id } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'deployment.json') -Encoding UTF8
            # 先完成构建，再进入注册表 / 状态事务；缺编译器时不产生半安装菜单。
            Build-JobsPackageNativeRelease -PackagePath $PackagePath -ReleasePath $release -DeploymentMode $DeploymentMode
        }
        # 卸载保留 v2 禁用墓碑；旧版全局清单随后仍存在也不能重新启用本包。
        $settings = [ordered]@{ Version = 2; Id = $manifest.Id; Enabled = ($Mode -eq 'Install'); DeploymentMode = $DeploymentMode; ReleasePath = $release }
        $encoding = New-Object System.Text.UTF8Encoding($true)
        $newSettings = $encoding.GetPreamble() + $encoding.GetBytes(($settings | ConvertTo-Json -Depth 4))
        $otherSettingsPath = $null
        $otherSettingsBytes = $null
        $otherNewSettings = $null
        if ($Mode -eq 'Install') {
            $otherMode = 'build'
            if ($DeploymentMode -eq 'build') { $otherMode = 'installed' }
            $otherBase = Get-JobsPackageBase -PackagePath $PackagePath -DeploymentMode $otherMode
            $candidate = Join-Path (Join-Path (Join-Path $otherBase 'extensions') $manifest.Id) 'settings.json'
            if ($candidate -ne $settingsPath -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $other = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($other.Id -cne $manifest.Id -or $other.Version -ne 2) { throw '另一部署路线的状态归属无效。' }
                $otherSettingsPath = $candidate
                $otherSettingsBytes = [IO.File]::ReadAllBytes($candidate)
                $other.Enabled = $false
                $otherNewSettings = $encoding.GetPreamble() + $encoding.GetBytes(($other | ConvertTo-Json -Depth 8))
            }
        }
        $installerModule = $ExecutionContext.SessionState.Module
        $commit = {
            if ($otherSettingsPath) { & $installerModule { param($Path, $Bytes) Set-JobsPackageSettingsFile -Path $Path -Bytes $Bytes } $otherSettingsPath $otherNewSettings }
            & $installerModule { param($Path, $Bytes) Set-JobsPackageSettingsFile -Path $Path -Bytes $Bytes } $settingsPath $newSettings
        }.GetNewClosure()
        $rollback = {
            if ($otherSettingsPath) { & $installerModule { param($Path, $Bytes) Set-JobsPackageSettingsFile -Path $Path -Bytes $Bytes } $otherSettingsPath $otherSettingsBytes }
            if ($hadSettings) {
                & $installerModule { param($Path, $Bytes) Set-JobsPackageSettingsFile -Path $Path -Bytes $Bytes } $settingsPath $oldSettings
            }
            elseif (Test-Path -LiteralPath $settingsPath -PathType Leaf) { [IO.File]::Delete($settingsPath) }
        }.GetNewClosure()
        Invoke-JobsPackageTransaction -Plan $plan -RegistryRoot $registry -Snapshot $snapshot -Commit $commit -Rollback $rollback
        $logDirectory = Join-Path $root 'logs'
        try {
            [void][IO.Directory]::CreateDirectory($logDirectory)
            [IO.File]::AppendAllText((Join-Path $logDirectory ((Get-Date -Format 'yyyy-MM-dd') + '.log')), ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Mode + ' ' + $manifest.Id + [Environment]::NewLine), $encoding)
        }
        catch { Write-Warning ('菜单状态已保存，日志写入失败：' + $logDirectory) }
        try { Set-JobsPackageUninstallShortcut -Manifest $manifest -ReleasePath $release -Mode $Mode }
        catch { Write-Warning ('菜单状态已保存，开始菜单快捷方式需手工处理：' + $_.Exception.Message) }
        try { Send-JobsPackageShellChange } catch { Write-Warning '菜单状态已保存，通知资源管理器失败；请重新打开右键菜单。' }
        return [pscustomobject]@{ Id = $manifest.Id; Mode = $Mode; Root = $root; Backup = $backup; ReleasePath = $release; BuildPath = $script:LastBuildPath }
    }
    finally { if ($null -ne $managementLock) { $managementLock.Dispose() } }
}

Export-ModuleMember -Function Get-JobsPackageManifest, Get-JobsPackageState, Get-JobsPackageRegistryPlan, New-JobsPackageRelease, Invoke-JobsPackageChange, Clear-JobsPackageBuildArtifacts
