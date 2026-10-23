# 官方镜像下载流程的隔离回归，不联网、不接受真实许可、不操作真实模拟器。
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot '../JobsHarmonySimulatorCreator/Scripts/Action.psm1') -PassThru -Force -DisableNameChecking
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsHarmonyImages-' + [guid]::NewGuid().ToString('N'))
$script:count = 0
function Assert-Image { param($Value, $Message); if (-not $Value) { throw $Message }; $script:count++ }
try {
    $agreements = Join-Path $temporary 'agreement'
    [void][IO.Directory]::CreateDirectory($agreements)
    foreach ($file in @('HarmonyOS_SDK_Agreement.txt','HarmonyOS_Software_Service_Agreement.txt')) { [IO.File]::WriteAllText((Join-Path $agreements $file), 'Official agreement fixture') }
    $emulator = Join-Path $temporary 'Emulator.exe'
    & $module {
        $script:Online = @(
            [pscustomobject]@{ deviceType='2in1 Foldable'; osVersion='HarmonyOS 6.1.1(24)'; SoftWareVersion='6.1.0.125'; downloaded='false'; upgradable='false'; releaseType='Release' },
            [pscustomobject]@{ deviceType='phone'; osVersion='HarmonyOS 6.9.0(29)'; SoftWareVersion='6.9.0'; downloaded='false'; upgradable='false'; releaseType='Release' },
            [pscustomobject]@{ deviceType='phone'; osVersion='HarmonyOS 6.10.0(30)'; SoftWareVersion='6.10.0'; downloaded='false'; upgradable='false'; releaseType='Release' },
            [pscustomobject]@{ deviceType='phone'; osVersion='HarmonyOS 7.0.0(31)'; SoftWareVersion='7.0.0'; downloaded='false'; upgradable='false'; releaseType='Beta' }
        )
        function script:Invoke-JobsHarmonyQuery {
            param($Emulator, $Arguments)
            if ($Arguments[-1] -ceq 'false') { return ConvertTo-Json -InputObject @($script:Online) -Compress }
            return ConvertTo-Json -InputObject @($script:Installed) -Compress
        }
        function script:Select-JobsHarmonyChoice { param($Title,$Choices); return $Choices[0] }
        function script:Read-JobsHarmonyInput {
            param($Prompt)
            if ($script:Answers.Count -eq 0) { throw 'fixture EOF' }
            return $script:Answers.Dequeue()
        }
        function script:Invoke-JobsHarmonyInteractive {
            param($Emulator,$Arguments)
            $script:Calls.Add(($Arguments -join '|'))
            if ($script:Fail -ceq $Arguments[0]) { throw 'fixture official failure' }
            if ($Arguments[0] -ceq '-install' -and -not $script:NoInstall) {
                $script:Installed = @($script:Online | Where-Object { $_.deviceType -ceq $Arguments[2] -and $_.osVersion -ceq $Arguments[4] } | ForEach-Object {
                    $copy = $_ | ConvertTo-Json | ConvertFrom-Json
                    $copy.downloaded = 'true'
                    $copy
                })
            }
        }
        function script:Reset-ImageFixture {
            $script:HarmonyLicensesConfirmed = $false
            $script:Installed = @()
            $script:Calls = New-Object 'Collections.Generic.List[string]'
            $script:Answers = New-Object 'Collections.Generic.Queue[string]'
            $script:Answers.Enqueue(''); $script:Answers.Enqueue('')
            $script:NoInstall = $false; $script:Fail = ''
        }
        Reset-ImageFixture
    }
    $available = @(& $module { param($Bin) Get-JobsHarmonyImages $Bin -Available } $emulator)
    Assert-Image ($available.Count -eq 3 -and $available[0].OsVersion -ceq 'HarmonyOS 6.10.0(30)') '手机优先、数字版本排序、过滤 Beta'
    Assert-Image ($available[2].DeviceType -ceq '2in1 Foldable') '支持官方含空格与数字的设备类型'
    $installed = @(& $module { param($Bin) Install-JobsHarmonyImage $Bin } $emulator)
    Assert-Image ($installed.Count -eq 1 -and $installed[0].DeviceType -ceq 'phone') '连续回车下载且复检后只返回选中镜像'
    $calls = @(& $module { $script:Calls.ToArray() })
    Assert-Image (($calls -join '~') -ceq '-license|accept~-install|-deviceType|phone|-osVersion|HarmonyOS 6.10.0(30)|-force') '确认后接受许可，安装使用独立参数'
    foreach ($failure in @('cancel-download','cancel-license','license','install','no-image')) {
        & $module { param($Mode)
            Reset-ImageFixture
            if ($Mode -eq 'cancel-download') { $script:Answers.Clear(); $script:Answers.Enqueue('q') }
            if ($Mode -eq 'cancel-license') { $script:Answers.Clear(); $script:Answers.Enqueue(''); $script:Answers.Enqueue('q') }
            if ($Mode -eq 'license') { $script:Fail = '-license' }
            if ($Mode -eq 'install') { $script:Fail = '-install' }
            if ($Mode -eq 'no-image') { $script:NoInstall = $true }
        } $failure
        $errorText = ''
        try { & $module { param($Bin) Install-JobsHarmonyImage $Bin } $emulator | Out-Null } catch { $errorText = $_.Exception.Message }
        Assert-Image ($errorText.Length -gt 0) ('失败或取消必须停止：' + $failure)
        $calls = @(& $module { $script:Calls.ToArray() })
        Assert-Image (@($calls | Where-Object { $_ -like '-install|*' }).Count -le 1) '失败不循环安装'
        if ($failure -like 'cancel-*') { Assert-Image ($calls.Count -eq 0) '取消不接受许可或下载' }
        if ($failure -eq 'no-image') { Assert-Image ($errorText -match '仍未下载就绪') '退出 0 但镜像未就绪不得报告成功' }
    }
    Write-Host ('Harmony image workflow passed: ' + $script:count + ' assertions')
} finally {
    Remove-Module $module -Force
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
