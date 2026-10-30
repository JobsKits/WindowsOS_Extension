# PackageInstaller.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月18日，星期日.
# 文件和状态使用隔离临时目录；Windows 注册验证只在 GUID 隔离子键下运行。
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
$project = Split-Path -Parent $PSScriptRoot
$template = Join-Path $project 'Infrastructure/PackageInstaller.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsPackageTests-' + [guid]::NewGuid().ToString('N'))
$oldLocalAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
$encoding = New-Object Text.UTF8Encoding($true)

function Assert-JobsTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:Assertions++
}

function Assert-JobsThrows {
    param([scriptblock]$Body, [string]$Message)
    $threw = $false
    try { & $Body } catch { $threw = $true }
    Assert-JobsTest $threw $Message
}

function Write-JobsTestText {
    param([string]$Path, [string]$Text)
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Write-JobsTestJson {
    param([string]$Path, $Value)
    Write-JobsTestText -Path $Path -Text ($Value | ConvertTo-Json -Depth 8)
}

function New-JobsTestPackage {
    param([string]$Path, [string]$Id, [string]$Name, [bool]$DirectoryOnly, [bool]$Console)
    Write-JobsTestJson -Path (Join-Path $Path 'Extension.json') -Value @{
        Id = $Id; Name = $Name; Label = '测试功能'; Description = '隔离测试。'; DirectoryOnly = $DirectoryOnly; Console = $Console
    }
    $scripts = Join-Path $Path 'Scripts'
    Write-JobsTestText -Path (Join-Path $scripts 'Common.psm1') -Text 'function Get-JobsTestValue { return 42 }; Export-ModuleMember -Function Get-JobsTestValue'
    Write-JobsTestText -Path (Join-Path $scripts 'Action.psm1') -Text 'function Invoke-JobsFeature { param([string]$Target) return $Target }; Export-ModuleMember -Function Invoke-JobsFeature'
    Write-JobsTestText -Path (Join-Path $scripts 'Invoke.ps1') -Text 'param([string]$Target); Import-Module (Join-Path $PSScriptRoot "Action.psm1"); Invoke-JobsFeature -Target $Target'
    Copy-Item -LiteralPath $template -Destination (Join-Path $scripts 'PackageInstaller.psm1')
    Copy-Item -LiteralPath (Join-Path $project 'Infrastructure/Manage.ps1') -Destination (Join-Path $scripts 'Manage.ps1')
    Write-JobsTestText -Path (Join-Path $Path 'Manage.cmd') -Text '@echo off'
    Write-JobsTestText -Path (Join-Path $Path 'README.md') -Text '测试功能包。'
}

try {
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', (Join-Path $temporary 'Local'))
    $installer = Import-Module $template -PassThru -DisableNameChecking
    Assert-JobsTest (-not (Test-Path -LiteralPath $temporary)) '导入安装器不创建文件或执行安装'
    $first = Join-Path $temporary 'Sources/JobsFirst'
    $second = Join-Path $temporary 'Sources/JobsSecond'
    New-JobsTestPackage -Path $first -Id 'test-first' -Name 'JobsFirst' -DirectoryOnly $false -Console $false
    New-JobsTestPackage -Path $second -Id 'test-second' -Name 'JobsSecond' -DirectoryOnly $true -Console $true
    $manifest = Get-JobsPackageManifest -PackagePath $first
    Assert-JobsTest ($manifest.Id -eq 'test-first' -and $manifest.Label -ceq '测试功能') '按本包读取 UTF8 manifest'
    $manifestPath = Join-Path $first 'Extension.json'
    $originalManifest = [IO.File]::ReadAllBytes($manifestPath)
    foreach ($badId in @('../test', 'Test-first', 'first\other', '')) {
        $manifest.Id = $badId
        Write-JobsTestJson $manifestPath $manifest
        Assert-JobsThrows { Get-JobsPackageManifest -PackagePath $first } ('拒绝非法 Id：' + $badId)
    }
    [IO.File]::WriteAllBytes($manifestPath, $originalManifest)
    $manifest = Get-JobsPackageManifest -PackagePath $first
    $manifest.Name = 'OtherFeature'
    Write-JobsTestJson $manifestPath $manifest
    Assert-JobsThrows { Get-JobsPackageManifest -PackagePath $first } '拒绝非法功能包名称'
    [IO.File]::WriteAllBytes($manifestPath, $originalManifest)
    $manifest = Get-JobsPackageManifest -PackagePath $first
    $manifest.Console = 'false'
    Write-JobsTestJson $manifestPath $manifest
    Assert-JobsThrows { Get-JobsPackageManifest -PackagePath $first } '布尔开关拒绝字符串'
    [IO.File]::WriteAllBytes($manifestPath, $originalManifest)
    $manifest = Get-JobsPackageManifest -PackagePath $first

    $state = Get-JobsPackageState -PackagePath $first
    $base = Join-Path ([Environment]::GetEnvironmentVariable('LOCALAPPDATA')) 'Jobs/WindowsExtension'
    Assert-JobsTest (-not $state.Enabled -and $state.Source -eq 'None') '新包初始为未安装'
    Assert-JobsTest ($state.Root -eq (Join-Path $base 'extensions/test-first')) '每个功能有自己的安装根目录'
    Assert-JobsTest (-not (Test-Path -LiteralPath $base)) '查询安装状态不创建目录'
    $legacyRelease = Join-Path $base 'releases/legacy'
    Write-JobsTestJson -Path (Join-Path $base 'settings.json') -Value @{ Version = 1; Features = @('test-first'); ReleasePath = $legacyRelease }
    Assert-JobsTest (-not (Get-JobsPackageState -PackagePath $first).Enabled) '仅旧选择清单而无旧运行文件时不能判定已安装'
    Write-JobsTestText -Path (Join-Path $legacyRelease 'Invoke-Menu.ps1') -Text '# legacy entry'
    $legacy = Get-JobsPackageState -PackagePath $first
    Assert-JobsTest ($legacy.Enabled -and $legacy.Source -eq 'Legacy') '已有旧安装可逐包迁移状态'
    Assert-JobsTest (-not (Get-JobsPackageState -PackagePath $second).Enabled) '旧全局设置未启用的另包保持禁用'
    $settingsPath = Join-Path $state.Root 'settings.json'
    Write-JobsTestJson -Path $settingsPath -Value @{ Version = 2; Id = 'test-first'; Enabled = $false; ReleasePath = $legacyRelease }
    $disabled = Get-JobsPackageState -PackagePath $first
    Assert-JobsTest (-not $disabled.Enabled -and $disabled.Source -eq 'Package') '卸载禁用墓碑覆盖旧全局安装状态'
    Write-JobsTestJson -Path $settingsPath -Value @{ Version = 2; Id = 'test-first'; Enabled = $true; ReleasePath = 'own-release' }
    Assert-JobsTest ((Get-JobsPackageState -PackagePath $first).ReleasePath -eq 'own-release') '独立状态优先于旧全局设置'
    Write-JobsTestJson -Path $settingsPath -Value @{ Version = 2; Id = 'test-second'; Enabled = $true; ReleasePath = 'own-release' }
    Assert-JobsThrows { Get-JobsPackageState -PackagePath $first } '状态 Id 不匹配时拒绝操作'
    [IO.File]::Delete($settingsPath)

    $release = Join-Path $temporary 'Release 中文 & 100%'
    $powerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $release -PowerShellPath $powerShell)
    Assert-JobsTest ($plan.Count -eq 4) '文件功能仅生成本包四个上下文'
    Assert-JobsTest (@($plan.Key | Select-Object -Unique).Count -eq 4) '菜单路径唯一'
    foreach ($item in $plan) {
        Assert-JobsTest ($item.Key.EndsWith('\Jobs.WindowsExtension.test-first')) '菜单只指向当前包 Id'
        Assert-JobsTest ($item.Enabled -and $item.Owner -eq 'Jobs.WindowsExtension.v1') '维持旧 owner 兼容并启用本包'
        Assert-JobsTest ($item.Command.Contains('-WindowStyle Hidden -File "' + (Join-Path $release 'Scripts/Invoke.ps1') + '"')) '非控制台功能隐藏窗口且直接使用本包入口'
        Assert-JobsTest (-not $item.Command.Contains(' -Action ') -and -not $item.Command.Contains(' -Command ')) '注册命令无需全局分派器'
        $placeholder = '%1'
        if ($item.Key.Contains('\Directory\Background\')) { $placeholder = '%V' }
        Assert-JobsTest ($item.Command.EndsWith('-Target "' + $placeholder + '|JobsPathEnd"')) '保留盘符反斜杠保护和正确目标占位符'
    }
    $quoteCases = @(
        @{ Value = ''; Expected = '""' },
        @{ Value = 'C:\'; Expected = '"C:\\"' },
        @{ Value = 'C:\研发 & 团队\100% done'; Expected = '"C:\研发 & 团队\100% done"' },
        @{ Value = 'C:\a"b\'; Expected = '"C:\a\"b\\"' }
    )
    foreach ($case in $quoteCases) {
        $quoted = & $installer { param($Value) ConvertTo-JobsPackageArgument -Value $Value } $case.Value
        Assert-JobsTest ($quoted -ceq $case.Expected) '参数引用遵守 Windows 反斜杠及引号规则'
    }
    $secondManifest = Get-JobsPackageManifest -PackagePath $second
    $otherPlan = @(Get-JobsPackageRegistryPlan -Manifest $secondManifest -ReleasePath $release -PowerShellPath $powerShell -Enabled $false)
    Assert-JobsTest ($otherPlan.Count -eq 3) '仅目录功能只生成三个上下文'
    Assert-JobsTest (@($otherPlan | Where-Object { $_.Enabled }).Count -eq 0) '禁用计划仍保留完整删除范围'
    Assert-JobsTest (@($otherPlan | Where-Object { $_.Command -notmatch '-WindowStyle Normal -File' }).Count -eq 0) '控制台业务使用可见窗口'
    Assert-JobsTest (@($plan.Key | Where-Object { $_ -in $otherPlan.Key }).Count -eq 0) '两个包没有共享菜单键'

    Write-JobsTestText -Path (Join-Path $first 'Scripts/LocalHelper.psm1') -Text 'function Test-LocalHelper { return 1 }'
    Write-JobsTestText -Path (Join-Path $first 'Scripts/Action.Tests.ps1') -Text 'throw "tests must not ship"'
    Write-JobsTestText -Path (Join-Path $first 'Scripts/Tests/Nested.ps1') -Text 'throw "nested tests must not ship"'
    Write-JobsTestText -Path (Join-Path $first 'logs/private.log') -Text 'not shipped'
    Write-JobsTestText -Path (Join-Path $first 'Tests/private.ps1') -Text 'throw "not shipped"'
    [void](New-JobsPackageRelease -PackagePath $first -Destination $release)
    Assert-JobsTest ((Get-JobsPackageManifest -PackagePath $release).Id -eq 'test-first') 'release 保留完整本包清单'
    foreach ($name in @('Common.psm1', 'Action.psm1', 'Invoke.ps1', 'Manage.ps1', 'PackageInstaller.psm1', 'LocalHelper.psm1')) {
        $relative = 'Scripts/' + $name
        Assert-JobsTest ((Get-FileHash -LiteralPath (Join-Path $first $relative)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $release $relative)).Hash) ('复制 SHA256 一致：' + $relative)
    }
    foreach ($name in @('Manage.cmd', 'README.md')) {
        Assert-JobsTest (Test-Path -LiteralPath (Join-Path $release $name) -PathType Leaf) ('release 附带独立管理入口：' + $name)
    }
    foreach ($relative in @('Tests', 'logs', 'Scripts/Tests', 'Scripts/Action.Tests.ps1', 'JobsSecond', 'Extensions.json')) {
        Assert-JobsTest (-not (Test-Path -LiteralPath (Join-Path $release $relative))) ('release 排除测试/日志/总入口/其它包：' + $relative)
    }
    Assert-JobsThrows { New-JobsPackageRelease -PackagePath $first -Destination $release } '拒绝覆盖已有 release'
    Write-JobsTestText -Path (Join-Path $first 'Scripts/Broken.psm1') -Text 'function Broken {'
    Assert-JobsThrows { New-JobsPackageRelease -PackagePath $first -Destination (Join-Path $temporary 'BadRelease') } '复制前拒绝语法错误的运行文件'
    Assert-JobsTest (-not (Test-Path -LiteralPath (Join-Path $temporary 'BadRelease'))) '语法校验失败不产生半成品目录'
    [IO.File]::Delete((Join-Path $first 'Scripts/Broken.psm1'))
    # 从两个不同目录导入同名模块仍按参数定位本包；随后移走源目录验证独立性。
    $moduleA = Import-Module (Join-Path $first 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $moduleB = Import-Module (Join-Path $second 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $fromA = & $moduleA { param($Path) Get-JobsPackageManifest -PackagePath $Path } $first
    $fromB = & $moduleB { param($Path) Get-JobsPackageManifest -PackagePath $Path } $second
    Assert-JobsTest ($fromA.Id -eq 'test-first' -and $fromB.Id -eq 'test-second') '同名模块对象保持调用隔离'
    Move-Item -LiteralPath (Join-Path $temporary 'Sources') -Destination (Join-Path $temporary 'HiddenSources')
    $releaseModule = Import-Module (Join-Path $release 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $releaseManifest = & $releaseModule { param($Path) Get-JobsPackageManifest -PackagePath $Path } $release
    Assert-JobsTest ($releaseManifest.Id -eq 'test-first') '移走源码和其它功能后已部署包仍可独立管理'
    $action = Import-Module (Join-Path $release 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    Assert-JobsTest ((& $action { Invoke-JobsFeature -Target '独立目标' }) -ceq '独立目标') '移走其它包后仍可运行本包业务'
    $atomicPath = Join-Path $temporary 'atomic-settings.json'
    & $releaseModule { param($Path) Set-JobsPackageSettingsFile -Path $Path -Bytes ([Text.Encoding]::UTF8.GetBytes('first')) } $atomicPath
    & $releaseModule { param($Path) Set-JobsPackageSettingsFile -Path $Path -Bytes ([Text.Encoding]::UTF8.GetBytes('second')) } $atomicPath
    Assert-JobsTest ((Get-Content -LiteralPath $atomicPath -Raw -Encoding UTF8) -eq 'second') 'settings 原子写入支持首次创建和重复替换'
    $closureResult = & $releaseModule {
        param($Path)
        $module = $ExecutionContext.SessionState.Module
        $bytes = [Text.Encoding]::UTF8.GetBytes('closure')
        $commit = { & $module { param($Path, $Bytes) Set-JobsPackageSettingsFile -Path $Path -Bytes $Bytes } $Path $bytes }.GetNewClosure()
        & $commit
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    } $atomicPath
    Assert-JobsTest ($closureResult -eq 'closure') '事务闭包通过所持模块对象访问私有写入函数'

    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        if (-not ('Jobs.PackageTestNative' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class PackageTestNative {
        [DllImport("shell32.dll", SetLastError = true)]
        private static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string commandLine, out int count);
        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr memory);
        public static string[] Arguments(string commandLine) {
            int count;
            IntPtr values = CommandLineToArgvW(commandLine, out count);
            if (values == IntPtr.Zero) throw new InvalidOperationException("CommandLineToArgvW failed");
            try {
                string[] result = new string[count];
                for (int i = 0; i < count; i++) result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(values, i * IntPtr.Size));
                return result;
            } finally { LocalFree(values); }
        }
    }
}
'@
        }
        foreach ($target in @('C:\', 'C:\研发 & 团队\100% done', 'C:\引号''与`字符\file.txt')) {
            foreach ($item in $plan) {
                $placeholder = '%1'
                if ($item.Key.Contains('\Directory\Background\')) { $placeholder = '%V' }
                $argv = [Jobs.PackageTestNative]::Arguments($item.Command.Replace($placeholder, $target))
                $fileIndex = [Array]::IndexOf($argv, '-File')
                $targetIndex = [Array]::IndexOf($argv, '-Target')
                Assert-JobsTest ($argv[0] -eq $powerShell) '原生 argv 保留 PowerShell 路径'
                Assert-JobsTest ($argv[$fileIndex + 1] -eq (Join-Path $release 'Scripts/Invoke.ps1')) '原生 argv 保留本包运行路径'
                Assert-JobsTest ($argv[$targetIndex + 1] -eq ($target + '|JobsPathEnd') -and $argv.Count -eq $targetIndex + 2) '根盘符/中文/&/%目标只占一个参数'
            }
        }
        $registryPath = 'Software\JobsPackageInstallerTests\' + [guid]::NewGuid().ToString('N')
        Assert-JobsTest ($registryPath -match '^Software\\JobsPackageInstallerTests\\[0-9a-f]{32}$') '注册测试仅使用 GUID 隔离子键'
        $registryRoot = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($registryPath)
        try {
            & $releaseModule { param($Plan, $Root) Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $Root } $otherPlan $registryRoot
            foreach ($item in $otherPlan) { $item.Enabled = $true }
            & $releaseModule { param($Plan, $Root) Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $Root } $otherPlan $registryRoot
            & $releaseModule { param($Plan, $Root) Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $Root } $plan $registryRoot
            foreach ($item in $plan) {
                $key = $registryRoot.OpenSubKey($item.Key)
                try { Assert-JobsTest ($key.GetValue('JobsOwner') -eq 'Jobs.WindowsExtension.v1') '独立安装维持旧归属标记' } finally { $key.Dispose() }
            }
            foreach ($item in $plan) { $item.Enabled = $false }
            & $releaseModule { param($Plan, $Root) Set-JobsPackageRegistry -Plan $Plan -RegistryRoot $Root } $plan $registryRoot
            foreach ($item in $otherPlan) {
                $key = $registryRoot.OpenSubKey($item.Key)
                try { Assert-JobsTest ($null -ne $key) '卸载一个功能保留另一个包的全部菜单' } finally { if ($key) { $key.Dispose() } }
            }
            $foreign = $registryRoot.CreateSubKey($plan[1].Key)
            try { $foreign.SetValue('JobsOwner', 'other-owner'); $foreign.SetValue('Keep', 'foreign') } finally { $foreign.Dispose() }
            Assert-JobsThrows { & $releaseModule { param($Plan, $Root) Get-JobsPackageRegistrySnapshot -Plan $Plan -RegistryRoot $Root } $plan $registryRoot } '归属不明时预检拒绝整包操作'
            $foreign = $registryRoot.OpenSubKey($plan[1].Key)
            try { Assert-JobsTest ($foreign.GetValue('Keep') -eq 'foreign') '归属冲突保留外部键内容' } finally { $foreign.Dispose() }
            $registryRoot.DeleteSubKeyTree($plan[1].Key, $false)
            $original = $registryRoot.CreateSubKey($plan[0].Key)
            try {
                $original.SetValue('JobsOwner', 'Jobs.WindowsExtension.v1')
                $original.SetValue('MUIVerb', 'original')
                $original.SetValue('Multi', [string[]]@('甲', '乙'), [Microsoft.Win32.RegistryValueKind]::MultiString)
                $child = $original.CreateSubKey('child')
                try { $child.SetValue('Binary', [byte[]]@(0, 42, 255), [Microsoft.Win32.RegistryValueKind]::Binary) } finally { $child.Dispose() }
            }
            finally { $original.Dispose() }
            foreach ($item in $plan) { $item.Enabled = $true }
            $snapshot = & $releaseModule { param($Plan, $Root) Get-JobsPackageRegistrySnapshot -Plan $Plan -RegistryRoot $Root } $plan $registryRoot
            Assert-JobsThrows {
                & $releaseModule {
                    param($Plan, $Root, $Snapshot, $Path)
                    $module = $ExecutionContext.SessionState.Module
                    $before = [IO.File]::ReadAllBytes($Path)
                    $commit = {
                        & $module { param($Path) Set-JobsPackageSettingsFile -Path $Path -Bytes ([Text.Encoding]::UTF8.GetBytes('new')) } $Path
                        throw '模拟状态提交失败'
                    }.GetNewClosure()
                    $rollback = { & $module { param($Path, $Bytes) Set-JobsPackageSettingsFile -Path $Path -Bytes $Bytes } $Path $before }.GetNewClosure()
                    Invoke-JobsPackageTransaction -Plan $Plan -RegistryRoot $Root -Snapshot $Snapshot -Commit $commit -Rollback $rollback
                } $plan $registryRoot $snapshot $atomicPath
            } '状态提交失败触发注册表和文件联合回滚'
            Assert-JobsTest ((Get-Content -LiteralPath $atomicPath -Raw -Encoding UTF8) -eq 'closure') '事务失败恢复设置原始字节'
            $restored = $registryRoot.OpenSubKey($plan[0].Key)
            try {
                Assert-JobsTest ($restored.GetValue('MUIVerb') -eq 'original') '事务失败恢复旧菜单标签'
                Assert-JobsTest ($restored.GetValueKind('Multi') -eq [Microsoft.Win32.RegistryValueKind]::MultiString -and ($restored.GetValue('Multi') -join ',') -ceq '甲,乙') '事务失败恢复多字符串及值类型'
                $child = $restored.OpenSubKey('child')
                try { Assert-JobsTest (($child.GetValue('Binary') -join ',') -eq '0,42,255') '事务失败恢复子键与二进制值' } finally { $child.Dispose() }
            }
            finally { $restored.Dispose() }
            $newKey = $registryRoot.OpenSubKey($plan[1].Key)
            try { Assert-JobsTest ($null -eq $newKey) '事务失败移除本次新建菜单' } finally { if ($newKey) { $newKey.Dispose() } }
        }
        finally {
            $registryRoot.Dispose()
            [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($registryPath, $false)
        }
    }
    else { Write-Host 'SKIP: Windows 原生 argv 与隔离注册事务验证需在 Windows 执行。' }
}
finally {
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $oldLocalAppData)
    foreach ($name in @('installer', 'moduleA', 'moduleB', 'releaseModule', 'action')) {
        $variable = Get-Variable -Name $name -ErrorAction SilentlyContinue
        if ($null -ne $variable -and $null -ne $variable.Value) { Remove-Module $variable.Value -ErrorAction SilentlyContinue }
    }
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
Write-Host ('PASS: PackageInstaller.Tests.ps1 (' + $script:Assertions + ' assertions)')
