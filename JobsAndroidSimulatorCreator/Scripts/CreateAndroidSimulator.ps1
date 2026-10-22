# CreateAndroidSimulator.ps1 | JobsAndroidSimulatorCreator
# Created by Jobs on 2026年10月22日，星期四.
[CmdletBinding()]
param([switch]$Check)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '本入口只支持 Windows。' }
    $module = Import-Module (Join-Path $PSScriptRoot 'Action.psm1') -PassThru -DisableNameChecking
    if ($Check) {
        & $module {
            [void](Get-JobsAndroidArchitecture)
            $sdk = Get-JobsAndroidSdk
            if (-not (Test-Path -LiteralPath $sdk -PathType Container)) { throw ('SDK 目录不存在；只读体检不会创建：' + $sdk) }
            $java = Get-JobsAndroidJava -ReadOnly
            $tools = Get-JobsAndroidHealthyTools -Sdk $sdk -Java $java -ReadOnly
            Repair-JobsAndroidComponents -Sdk $sdk -Java $java -Tools $tools -ReadOnly
            $emulator = Join-Path $sdk 'emulator/emulator.exe'
            $result = Invoke-JobsProcess -FilePath $emulator -Arguments @('-accel-check') -TimeoutSeconds 20
            if ($result.ExitCode -ne 0) { throw ('加速体检失败：' + $result.StdOut + $result.StdErr) }
            Write-Host ('SDK：' + $sdk + [Environment]::NewLine + 'Java：' + $java + [Environment]::NewLine + '工具：' + $tools + [Environment]::NewLine + '只读体检通过；没有安装组件或创建 AVD。')
        }
        exit 0
    }
    & $module { Invoke-JobsAndroidSimulatorAction -Target ([Environment]::GetFolderPath('DesktopDirectory')) }
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
