# AndroidSimulatorRepair.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月22日，星期四.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:assertions = 0
function Assert-Repair { param([bool]$Condition, [string]$Why) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Why) } }
function Assert-RepairThrows { param([scriptblock]$Action, [string]$Why) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; Assert-Repair $threw $Why }
$path = Join-Path $root 'JobsAndroidSimulatorCreator/Scripts/Action.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("JobsAndroidRepair 中文 & 100% ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$module = $null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $payload = Join-Path $temporary 'payload'
    [void][IO.Directory]::CreateDirectory((Join-Path $payload 'cmdline-tools/lib'))
    foreach ($name in @('sdkmanager', 'avdmanager')) { [IO.File]::WriteAllText((Join-Path $payload ('cmdline-tools/lib/' + $name + '-classpath.jar')), ('fixture ' + $name)) }
    $zip = Join-Path $temporary 'fixture.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($payload, $zip)
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    $xml = '<repository><remotePackage path="cmdline-tools;latest"><archives><archive><host-os>windows</host-os><complete><url>commandlinetools-win-123_latest.zip</url><checksum type="sha256">' + $hash + '</checksum></complete></archive></archives></remotePackage></repository>'
    $sdk = Join-Path $temporary 'SDK-on-independent-volume'
    $oldTools = Join-Path $sdk 'cmdline-tools/latest'
    [void][IO.Directory]::CreateDirectory($oldTools)
    [IO.File]::WriteAllText((Join-Path $oldTools 'existing.txt'), 'existing remains')
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        param($Archive, $Repository)
        $script:FixtureArchive = $Archive; $script:FixtureRepository = $Repository; $script:Downloads = @(); $script:FailDownload = $false
        function script:Confirm-JobsAndroidDownload { param($Description) return $true }
        function script:Invoke-WebRequest {
            param([switch]$UseBasicParsing, $Uri, $OutFile, $TimeoutSec)
            $script:Downloads += $OutFile
            if ($script:FailDownload) { throw 'fixture network unavailable' }
            if ($Uri.EndsWith('.xml')) { [IO.File]::WriteAllText($OutFile, $script:FixtureRepository) }
            else { Copy-Item -LiteralPath $script:FixtureArchive -Destination $OutFile }
        }
    } $zip $xml
    $installed = & $module { param($Sdk) Install-JobsAndroidCommandTools $Sdk } $sdk
    Assert-Repair (Test-Path -LiteralPath (Join-Path $installed 'lib/sdkmanager-classpath.jar')) '官方下载夹具安装 sdkmanager'
    Assert-Repair (Test-Path -LiteralPath (Join-Path $installed 'lib/avdmanager-classpath.jar')) '安装前检查两个必要 jar'
    Assert-Repair ((Split-Path -Parent $installed) -eq (Join-Path $sdk 'cmdline-tools')) '最终目录属于 SDK 卷'
    $downloads = @(& $module { $script:Downloads })
    Assert-Repair ($downloads.Count -eq 2) '仅读官方元数据与选中归档'
    foreach ($download in $downloads) {
        Assert-Repair ((Split-Path -Parent (Split-Path -Parent $download)) -eq (Join-Path $sdk 'cmdline-tools')) '下载和解压 stage 在 SDK 下，未从系统临时卷 Move'
        Assert-Repair ((Split-Path -Leaf (Split-Path -Parent $download)) -match '^\.jobs-stage-[0-9a-f]{32}$') '本次 stage 独立且范围精确'
    }
    Assert-Repair (@(Get-ChildItem -LiteralPath (Join-Path $sdk 'cmdline-tools') -Force | Where-Object { $_.Name -like '.jobs-stage-*' }).Count -eq 0) '成功仅清理本次 stage'
    Assert-Repair ([IO.File]::ReadAllText((Join-Path $oldTools 'existing.txt')) -eq 'existing remains') '旧 latest 完整保留'
    $second = & $module { param($Sdk) Install-JobsAndroidCommandTools $Sdk } $sdk
    Assert-Repair ($second -ne $installed -and (Test-Path -LiteralPath $installed)) '重复修复创建独立新目录，不覆盖上一版本'
    & $module { $script:FailDownload = $true }
    Assert-RepairThrows { & $module { param($Sdk) Install-JobsAndroidCommandTools $Sdk } $sdk } '下载失败传播'
    Assert-Repair (@(Get-ChildItem -LiteralPath (Join-Path $sdk 'cmdline-tools') -Force | Where-Object { $_.Name -like '.jobs-stage-*' }).Count -eq 0) '失败精确清除私有 stage'
    Assert-Repair ((Test-Path -LiteralPath $second) -and (Test-Path -LiteralPath (Join-Path $oldTools 'existing.txt'))) '失败保留两个已安装版本及旧目录'
    Remove-Module $module
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        $script:RepairCount = 0; $script:HealthCalls = @(); $script:FailOld = $false; $script:FailNew = $false; $script:ToolsMissing = $false
        function script:Get-JobsAndroidTools { param($Sdk) if ($script:ToolsMissing) { return $null }; return 'old-tools' }
        function script:Install-JobsAndroidCommandTools { param($Sdk, $Reason) $script:RepairCount++; return 'new-tools' }
        function script:Invoke-JobsAndroidTool {
            param($Java, $Tools, $Tool, $Arguments)
            $script:HealthCalls += ($Tools + ':' + $Tool)
            if (($Tools -eq 'old-tools' -and $script:FailOld) -or ($Tools -eq 'new-tools' -and $script:FailNew)) { throw 'fixture broken tool' }
            return 'healthy'
        }
    }
    Assert-Repair ((& $module { Get-JobsAndroidHealthyTools sdk java }) -eq 'old-tools') '健康工具直接复用'
    Assert-Repair (& $module { $script:RepairCount -eq 0 -and $script:HealthCalls.Count -eq 2 }) '健康检测实际运行 sdkmanager 与 avdmanager'
    & $module { $script:FailOld = $true; $script:HealthCalls = @() }
    Assert-Repair ((& $module { Get-JobsAndroidHealthyTools sdk java }) -eq 'new-tools') '坏工具经一次安装后返回健康新版本'
    Assert-Repair (& $module { $script:RepairCount -eq 1 -and @($script:HealthCalls | Where-Object { $_ -like 'new-tools:*' }).Count -eq 2 }) '修复后两项工具重新体检'
    & $module { $script:RepairCount = 0; $script:FailNew = $true }
    Assert-RepairThrows { & $module { Get-JobsAndroidHealthyTools sdk java } } '修复后仍坏立即停止'
    Assert-Repair (& $module { $script:RepairCount -eq 1 }) '不会无限安装新版本'
    & $module { $script:RepairCount = 0 }
    Assert-RepairThrows { & $module { Get-JobsAndroidHealthyTools sdk java -ReadOnly } } '只读模式发现损坏就报告'
    Assert-Repair (& $module { $script:RepairCount -eq 0 }) '只读体检不调用安装'
    & $module { $script:ToolsMissing = $true; $script:FailNew = $false; $script:RepairCount = 0 }
    Assert-Repair ((& $module { Get-JobsAndroidHealthyTools sdk java }) -eq 'new-tools') '工具不存在也遵守同一安装复检流程'
    Assert-Repair (& $module { $script:RepairCount -eq 1 }) '不存在只安装一次'
    Remove-Module $module
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    & $module {
        $script:Missing = @('emulator'); $script:RepairDone = $false; $script:FailRecheck = $false; $script:Commands = @(); $script:ConfirmCount = 0
        $script:Approved = $true; $script:HealthChecks = @()
        function script:Get-JobsAndroidUnhealthyComponents {
            param($Sdk)
            if (-not $script:RepairDone -or $script:FailRecheck) {
                foreach ($id in $script:Missing) { [pscustomobject]@{ Id = $id; Error = 'fixture bad version'; HasDirectory = $true } }
            }
        }
        function script:Confirm-JobsAndroidDownload { param($Description) $script:ConfirmCount++; return $script:Approved }
        function script:Invoke-JobsAndroidTool {
            param($Java, $Tools, $Tool, $Arguments, [switch]$Interactive)
            $script:Commands += ($Arguments -join ' ')
            if ($Arguments -contains '--install') { $script:RepairDone = $true }
        }
    }
    & $module { Repair-JobsAndroidComponents sdk java tools }
    Assert-Repair (& $module { $script:Commands.Count -eq 3 -and $script:ConfirmCount -eq 1 }) '坏工具一次确认后执行许可、卸载、安装'
    Assert-Repair (& $module { $script:Commands[1] -eq '--sdk_root=sdk --uninstall emulator' -and $script:Commands[2] -eq '--sdk_root=sdk --install emulator' }) '仅重装损坏 emulator，健康 platform-tools 保留'
    & $module { $script:RepairDone = $false; $script:FailRecheck = $true; $script:Commands = @(); $script:Missing = @('emulator', 'platform-tools') }
    Assert-RepairThrows { & $module { Repair-JobsAndroidComponents sdk java tools } } '组件修复后仍坏停止'
    Assert-Repair (& $module { @($script:Commands | Where-Object { $_ -match '--install ' }).Count -eq 1 }) '组件不循环重装'
    Assert-Repair (& $module { $script:Commands[-1] -eq '--sdk_root=sdk --install emulator platform-tools' }) 'ADB 损坏和 Emulator 一同精确修复'
    & $module { $script:RepairDone = $false; $script:Commands = @(); $script:ConfirmCount = 0 }
    Assert-RepairThrows { & $module { Repair-JobsAndroidComponents sdk java tools -ReadOnly } } '只读组件检查直接报告'
    Assert-Repair (& $module { $script:Commands.Count -eq 0 -and $script:ConfirmCount -eq 0 }) '只读组件不确认不联网不卸载'
    & $module { $script:Approved = $false }
    Assert-RepairThrows { & $module { Repair-JobsAndroidComponents sdk java tools } } '拒绝安装则停止'
    Assert-Repair (& $module { $script:Commands.Count -eq 0 }) '未批准不动 SDK'
    Remove-Module $module
    $module = Import-Module $path -PassThru -DisableNameChecking -Force
    $componentSdk = Join-Path $temporary 'components'
    foreach ($name in @('emulator/emulator.exe', 'platform-tools/adb.exe')) {
        $file = Join-Path $componentSdk $name
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
        [IO.File]::WriteAllText($file, 'fixture executable')
    }
    & $module {
        $script:HealthChecks = @()
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            $script:HealthChecks += ($FilePath + '|' + ($Arguments -join ' '))
            return [pscustomobject]@{ ExitCode = 1; StdOut = ''; StdErr = 'fixture broken executable' }
        }
    }
    $broken = @(& $module { param($Sdk) Get-JobsAndroidUnhealthyComponents $Sdk } $componentSdk)
    Assert-Repair ($broken.Count -eq 2) '二进制存在但不能运行仍判定损坏'
    Assert-Repair (& $module { @($script:HealthChecks | Where-Object { $_ -like '*adb.exe|version' }).Count -eq 1 }) '实际执行 ADB version'
    Assert-Repair (& $module { @($script:HealthChecks | Where-Object { $_ -like '*emulator.exe|-version' }).Count -eq 1 }) '实际执行 emulator -version'
    Write-Host ('PASS: AndroidSimulatorRepair.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ($module) { Remove-Module $module -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
