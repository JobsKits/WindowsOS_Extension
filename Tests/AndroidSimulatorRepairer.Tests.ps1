# AndroidSimulatorRepairer.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月23日，星期五.
# 只调用隔离文件/假 ADB/CIM；不访问真实设备、注册表、网络或系统菜单。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:assertions = 0
function Assert-Repairer { param([bool]$Condition, [string]$Why) $script:assertions++; if (-not $Condition) { throw ('FAIL: ' + $Why) } }
function Assert-RepairerThrows { param([scriptblock]$Action, [string]$Why) $threw = $false; try { & $Action | Out-Null } catch { $threw = $true }; Assert-Repairer $threw $Why }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ("JobsAndroidRepairer 中文 & 100% ' " + [guid]::NewGuid().ToString('N'))
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -and $temporary.StartsWith('/var/')) { $temporary = '/private' + $temporary }
$module = $null
$oldAvd = $env:ANDROID_AVD_HOME
$oldAndroidUser = $env:ANDROID_USER_HOME
$oldLocal = $env:LOCALAPPDATA
$oldSdkHome = $env:ANDROID_HOME
$oldSdkRoot = $env:ANDROID_SDK_ROOT
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:ANDROID_AVD_HOME = Join-Path $temporary 'avd'
    $env:ANDROID_USER_HOME = Join-Path $temporary 'android-home'
    $env:LOCALAPPDATA = Join-Path $temporary 'user-data'
    $directory = Join-Path $env:ANDROID_AVD_HOME 'Demo.avd'
    [void][IO.Directory]::CreateDirectory($directory)
    $config = Join-Path $directory 'config.ini'
    $original = "AvdId=Demo`r`ndisk.dataPartition.size=2G`r`nhw.ramSize=2048`r`n"
    [IO.File]::WriteAllText($config, $original, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), ('path=' + $directory + "`n"))
    [IO.File]::WriteAllText((Join-Path $directory 'userdata-qemu.img'), 'userdata fixture preserve me')
    $module = Import-Module (Join-Path $root 'JobsAndroidSimulatorRepairer/Scripts/Action.psm1') -PassThru -DisableNameChecking -Force
    & $module {
        $script:Commands = @(); $script:Logs = @(); $script:Qemu = '1'; $script:Avd = 'Demo'; $script:Location = 2
        $script:FreeKB = 1024000; $script:Approve = $true; $script:MutationFailure = $false; $script:UninstallOutput = 'Success'; $script:PackagePresent = $true
        $script:DeviceList = "List of devices attached`nemulator-5554`tdevice`nREALPHONE`tdevice`nemulator-5556`toffline`nemulator-5558`tunauthorized`n"
        function script:Write-JobsLog { param($Message) $script:Logs += $Message }
        function script:Confirm-JobsRepairDanger { param($Description) return $script:Approve }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            $command = $Arguments -join ' '
            $script:Commands += $command
            $output = ''
            switch -Regex ($command) {
                '^devices$' { $output = $script:DeviceList; break }
                ' get-state$' { $output = 'device'; break }
                ' getprop ro.kernel.qemu$' { $output = $script:Qemu; break }
                ' emu avd name$' { $output = $script:Avd + "`nOK`n"; break }
                ' pm get-install-location$' { $output = [string]$script:Location + '[auto]'; break }
                ' pm set-install-location 0$' { if (-not $script:MutationFailure) { $script:Location = 0 }; break }
                ' df -k /data$' { $output = "Filesystem 1K-blocks Used Available Use% Mounted on`n/dev/block/dm-5 2097152 1000 " + $script:FreeKB + " 1% /data`n"; break }
                ' pm path ' { $output = 'package:/data/app/example/base.apk'; break }
                ' uninstall ' { $output = $script:UninstallOutput; if ($output -ceq 'Success') { $script:PackagePresent = $false }; break }
                ' pm list packages ' { if ($script:PackagePresent) { $output = 'package:com.example.app' }; break }
                ' compile --reset -a$' { if ($script:MutationFailure) { $output = 'Error: not supported' } else { $output = 'Success' }; break }
                ' emu kill$' { $output = 'OK'; break }
                '^version$|^-version$' { $output = 'Android tool version fixture'; break }
                default { throw ('Unexpected fixture call: ' + $command) }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
    }
    $env:ANDROID_HOME = Join-Path $temporary 'missing-sdk'
    Assert-RepairerThrows { & $module { Get-JobsRepairTool adb } } '显式SDK缺失时停止，不切换PATH或默认SDK'
    $sdk = Join-Path $temporary 'SDK'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'platform-tools'))
    [IO.File]::WriteAllText((Join-Path $sdk 'platform-tools/adb.exe'), 'fake adb')
    $env:ANDROID_HOME = $sdk
    Assert-Repairer ((& $module { Get-JobsRepairTool adb }) -eq (Join-Path $sdk 'platform-tools/adb.exe')) '显式SDK健康工具复用且路径含特殊字符不经shell'
    $env:ANDROID_HOME = $oldSdkHome
    $env:ANDROID_SDK_ROOT = $oldSdkRoot
    $devices = @(& $module { Get-JobsRepairDevices adb })
    Assert-Repairer ($devices.Count -eq 1 -and $devices[0] -ceq 'emulator-5554') '仅在线模拟器进入选择，真机/offline/unauthorized均排除'
    Assert-Repairer ((& $module { Assert-JobsRepairEmulator adb emulator-5554 }) -ceq 'Demo') 'QEMU身份与唯一AVD名一致'
    Assert-RepairerThrows { & $module { Assert-JobsRepairEmulator adb REALPHONE } } '真机序列号拒绝'
    & $module { $script:Qemu = '0'; $script:Commands = @() }
    Assert-RepairerThrows { & $module { Invoke-JobsRepairDeviceWrite adb emulator-5554 Demo @('shell','pm','set-install-location','0') } } 'emulator前缀伪装真机但QEMU标记不为1时拒绝写入'
    Assert-Repairer (& $module { @($script:Commands | Where-Object { $_ -like '*set-install-location*' }).Count -eq 0 }) '拒绝后无设备写命令'
    & $module { $script:Qemu = '1'; $script:Avd = 'Other' }
    Assert-RepairerThrows { & $module { Assert-JobsRepairEmulator adb emulator-5554 Demo } } '端口被其它AVD复用时拒绝'
    & $module { $script:Avd = "Demo`nOther" }
    Assert-RepairerThrows { & $module { Assert-JobsRepairEmulator adb emulator-5554 } } '多行AVD名称拒绝'
    & $module { $script:Avd = '../escape' }
    Assert-RepairerThrows { & $module { Assert-JobsRepairEmulator adb emulator-5554 } } '不安全AVD名称拒绝'
    & $module { $script:Avd = 'Demo'; $script:Location = 2 }
    & $module { Set-JobsRepairInstallLocation adb emulator-5554 Demo }
    Assert-Repairer (& $module { $script:Location -eq 0 }) '安装位置恢复为自动并回读'
    & $module { $script:Location = 2; $script:MutationFailure = $true }
    Assert-RepairerThrows { & $module { Set-JobsRepairInstallLocation adb emulator-5554 Demo } } '设置退出0但读回未改变则失败'
    & $module { $script:MutationFailure = $false; $script:Location = 0 }
    $space = & $module { Get-JobsRepairSpace adb emulator-5554 }
    Assert-Repairer ($space.FreeMB -eq 1000 -and $space.TotalKB -eq 2097152) 'df按KB解析并转换MB'
    foreach ($text in @('', 'df: permission denied', "Filesystem 1K-blocks Used Available Use% Mounted on`n/dev/x unknown 0 0 0% /data", '/dev/x 1 0 2 0% /data')) {
        Assert-RepairerThrows { & $module { param($Text) ConvertFrom-JobsRepairDf $Text } $text } '未知或异常df不可触发0空间修复'
    }
    foreach ($size in @('1G','8G','1024M','2147483648','1T')) {
        Assert-Repairer ((& $module { param($Size) ConvertTo-JobsRepairSize $Size } $size) -gt 0) ('支持明确容量格式：' + $size)
    }
    foreach ($size in @('0G','-1G','8g','8G;evil','9999999999999999T')) {
        Assert-RepairerThrows { & $module { param($Size) ConvertTo-JobsRepairSize $Size } $size } ('拒绝不合理容量：' + $size)
    }
    foreach ($id in @('com.example.*','com.example.app;id','-x','com.app/evil','com..app')) {
        Assert-RepairerThrows { & $module { param($Id) Remove-JobsRepairPackage adb emulator-5554 Demo $Id } $id } '不接受模糊或含注入的卸载包名'
    }
    & $module { $script:Approve = $false; $script:Commands = @() }
    & $module { Remove-JobsRepairPackage adb emulator-5554 Demo com.example.app }
    Assert-Repairer (& $module { @($script:Commands | Where-Object { $_ -match ' uninstall ' }).Count -eq 0 }) '卸载未精确YES时没有写命令'
    & $module { $script:Approve = $true; $script:UninstallOutput = 'Failure [DELETE_FAILED_INTERNAL_ERROR]' }
    Assert-RepairerThrows { & $module { Remove-JobsRepairPackage adb emulator-5554 Demo com.example.app } } '卸载host退出0但Failure仍报失败'
    & $module { $script:UninstallOutput = 'Success'; $script:PackagePresent = $true }
    & $module { Remove-JobsRepairPackage adb emulator-5554 Demo com.example.app }
    Assert-Repairer (& $module { $script:Commands -contains '-s emulator-5554 uninstall com.example.app' }) '卸载只操作用户精确指定包名'
    Assert-Repairer (& $module { @($script:Commands | Where-Object { $_ -match 'com.android.chrome|youtube|--user 0' }).Count -eq 0 }) '没有内置应用卸载清单'
    & $module { $script:MutationFailure = $true }
    Assert-RepairerThrows { & $module { Reset-JobsRepairCompileCache adb emulator-5554 Demo } } 'compile打印Error而host退出0不报成功'
    & $module { $script:MutationFailure = $false }
    $paths = & $module { Get-JobsRepairAvdConfig Demo }
    Assert-Repairer ($paths.Config -eq $config -and $paths.Directory -eq $directory) '从AVD定位文件读取配置，路径含中文与shell字符可用'
    [IO.File]::WriteAllText($config, $original.Replace('AvdId=Demo','AvdId=Other'))
    Assert-RepairerThrows { & $module { Get-JobsRepairAvdConfig Demo } } '定位到别的AVD配置时拒绝'
    [IO.File]::WriteAllText($config, ($original + "AvdId=Demo`n"))
    Assert-RepairerThrows { & $module { Get-JobsRepairAvdConfig Demo } } '重复AvdId拒绝'
    [IO.File]::WriteAllText($config, $original, (New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), 'path.rel=avd/Demo.avd')
    Assert-Repairer ((& $module { Get-JobsRepairAvdConfig Demo }).Config -eq $config) 'path.rel相对AVD根父目录解析'
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), 'path.rel=../escape')
    Assert-RepairerThrows { & $module { Get-JobsRepairAvdConfig Demo } } '拒绝path.rel越界'
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), ("path=" + $directory + "`npath=" + $directory))
    Assert-RepairerThrows { & $module { Get-JobsRepairAvdConfig Demo } } '拒绝重复AVD定位路径'
    [IO.File]::WriteAllText((Join-Path $env:ANDROID_AVD_HOME 'Demo.ini'), ('path=' + $directory))
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairSameAvdConfig $Paths } $paths } '确认期间定位文件字节变化时拒绝旧快照'
    $paths = & $module { Get-JobsRepairAvdConfig Demo }
    & $module {
        $script:FakeProcesses = @(); $script:DeviceList = 'List of devices attached'
        function script:Get-CimInstance { param($ClassName, $ErrorAction) return $script:FakeProcesses }
    }
    & $module { param($Directory) Assert-JobsRepairAvdStopped adb emulator-5554 $Directory } $directory
    Assert-Repairer $true '设备消失且无进程/锁才接受停机'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='qemu-system-x86_64.exe'; CommandLine='qemu-system-x86_64.exe -avd Demo' }) }
    Assert-RepairerThrows { & $module { param($Directory) Assert-JobsRepairAvdStopped adb emulator-5554 $Directory } $directory } 'ADB消失但QEMU还在运行时拒绝写配置'
    & $module { $script:FakeProcesses = @() }
    $lock = Join-Path $directory 'hardware-qemu.ini.lock'
    [void][IO.Directory]::CreateDirectory($lock)
    Assert-RepairerThrows { & $module { param($Directory) Assert-JobsRepairAvdStopped adb emulator-5554 $Directory } $directory } '锁仍在时拒绝写配置'
    Remove-Item -LiteralPath $lock
    Assert-RepairerThrows { & $module { param($Paths) Set-JobsRepairAvdSize $Paths 1G adb emulator-5554 } $paths } '不允许缩容'
    Assert-RepairerThrows { & $module { param($Paths) Set-JobsRepairAvdSize $Paths 2G adb emulator-5554 } $paths } '同容量不当成扩容'
    Assert-Repairer ([IO.File]::ReadAllText($config) -ceq $original) '取消或拒绝分支保留配置原字节'
    foreach ($text in @('hw.ramSize=2048', "disk.dataPartition.size=2G`ndisk.dataPartition.size=4G", 'disk.dataPartition.size=unknown')) {
        Assert-RepairerThrows { & $module { param($Text) Get-JobsRepairConfiguredSize $Text } $text } '未知/缺失/重复原容量拒绝'
    }
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine='emulator.exe -avd Demo -data C:\outside.img' }) }
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '-data外部userdata拒绝自动扩容'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine='emulator.exe -avd Demo -datadir C:\outside' }) }
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '-datadir外部目录拒绝自动扩容'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine=$null }) }
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '不可读进程参数拒绝自动扩容'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine='emulator.exe -avd Other' }) }
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '未关联目标AVD拒绝自动扩容'
    & $module { $script:FakeProcesses = @([pscustomobject]@{ Name='emulator.exe'; CommandLine='emulator.exe -avd "Demo"' }) }
    & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths
    Assert-Repairer $true '已有明确AVD进程且默认数据路径通过检查'
    [IO.File]::AppendAllText($config, "disk.dataPartition.path=C:\outside.img`n")
    Assert-RepairerThrows { & $module { param($Paths) Assert-JobsRepairDefaultStorage $Paths Demo } $paths } '显式配置数据路径拒绝自动扩容'
    [IO.File]::WriteAllText($config, $original, (New-Object Text.UTF8Encoding($false)))
    & $module { $script:FakeProcesses = @() }
    $backup = & $module { param($Paths) Set-JobsRepairAvdSize $Paths 4G adb emulator-5554 } $paths
    Assert-Repairer (Test-Path -LiteralPath (Join-Path $backup 'avd/userdata-qemu.img')) '完整备份包含userdata，非仅config备份'
    Assert-Repairer ([IO.File]::ReadAllText((Join-Path $backup 'avd/config.ini')) -ceq $original) '备份精确保留原配置字节'
    Assert-Repairer ([IO.File]::ReadAllText((Join-Path $backup 'avd/userdata-qemu.img')) -ceq 'userdata fixture preserve me') '备份userdata内容通过SHA256核验'
    Assert-Repairer (Test-Path -LiteralPath (Join-Path $backup 'locator.ini')) '备份包含AVD定位文件'
    $updated = [IO.File]::ReadAllText($config)
    Assert-Repairer ($updated -ceq $original.Replace('size=2G','size=4G')) '只改容量，保留CRLF和其它配置'
    Assert-Repairer ([IO.File]::ReadAllText((Join-Path $directory 'userdata-qemu.img')) -ceq 'userdata fixture preserve me') '脚本不删除或改写userdata'
    $freshPaths = & $module { Get-JobsRepairAvdConfig Demo }
    & $module { function script:Backup-JobsRepairAvd { param($Paths,$AdditionalBytes) throw 'fixture no backup space' } }
    Assert-RepairerThrows { & $module { param($Paths) Set-JobsRepairAvdSize $Paths 8G adb emulator-5554 } $freshPaths } '完整备份失败立即停止'
    Assert-Repairer ([IO.File]::ReadAllText($config) -ceq $updated) '备份失败不写容量配置'
    & $module {
        $script:Started = $false; $script:Edited = $false
        function script:Stop-JobsRepairAvd { param($Adb,$Serial,$Avd,$Directory) throw 'fixture shutdown timeout' }
        function script:Get-JobsRepairTool { param($Name) return $Name }
        function script:Assert-JobsRepairDefaultStorage { param($Paths,$Avd) }
        function script:Set-JobsRepairAvdSize { param($Paths,$TargetDataSize,$Adb,$Serial) $script:Edited = $true }
        function script:Start-JobsRepairColdAvd { param($Emulator,$Avd,$Serial) $script:Started = $true }
    }
    Assert-RepairerThrows { & $module { Expand-JobsRepairAvd adb emulator-5554 Demo 8G 800 } } '停机超时向上失败'
    Assert-Repairer (& $module { -not $script:Edited -and -not $script:Started }) '停机失败绝不修改配置或重启'
    & $module {
        function script:Stop-JobsRepairAvd { param($Adb,$Serial,$Avd,$Directory) }
        function script:Set-JobsRepairAvdSize { param($Paths,$TargetDataSize,$Adb,$Serial) $script:Edited = $true; return 'fixture-backup' }
        function script:Wait-JobsRepairBoot { param($Adb,$Serial,$Avd) }
        function script:Get-JobsRepairSpace { param($Adb,$Serial) return [pscustomobject]@{TotalKB=2097152; FreeKB=1024000; FreeMB=1000} }
    }
    Assert-RepairerThrows { & $module { Expand-JobsRepairAvd adb emulator-5554 Demo 8G 800 } } '冷启动后空间够但分区总量没增加仍不能报告扩容成功'
    Assert-Repairer (& $module { $script:Edited -and $script:Started }) '实际走过配置与冷启动后执行复测门禁'
    & $module {
        $script:SpaceCalls = 0
        function script:Get-JobsRepairSpace {
            param($Adb,$Serial)
            $script:SpaceCalls++
            if ($script:SpaceCalls -eq 1) { return [pscustomobject]@{TotalKB=2097152;FreeKB=1024;FreeMB=1} }
            return [pscustomobject]@{TotalKB=6291456;FreeKB=1024;FreeMB=1}
        }
    }
    Assert-RepairerThrows { & $module { Expand-JobsRepairAvd adb emulator-5554 Demo 8G 800 } } '容量增加但可用空间不足不报告修复成功'
    & $module {
        $script:SpaceCalls = 0
        function script:Get-JobsRepairSpace {
            param($Adb,$Serial)
            $script:SpaceCalls++
            if ($script:SpaceCalls -eq 1) { return [pscustomobject]@{TotalKB=2097152;FreeKB=1024;FreeMB=1} }
            return [pscustomobject]@{TotalKB=6291456;FreeKB=2097152;FreeMB=2048}
        }
    }
    & $module { Expand-JobsRepairAvd adb emulator-5554 Demo 8G 800 }
    Assert-Repairer (& $module { $script:SpaceCalls -eq 2 }) '前后实际分区与可用空间均满足才通过'
    & $module { function script:Get-JobsRepairSpace { param($Adb,$Serial) return ConvertFrom-JobsRepairDf (Invoke-JobsRepairAdb $Adb @('-s',$Serial,'shell','df','-k','/data')) } }
    & $module {
        $script:ReadonlyWrites = 0; $script:FreeKB = 1024000; $script:Location = 0
        $script:DeviceList = "List of devices attached`nemulator-5554`tdevice`n"
        function script:Get-JobsRepairTool { param($Name) return $Name }
        function script:Read-JobsRepairInput { param($Prompt) throw 'Check must not prompt' }
        function script:Write-JobsLog { param($Message) $script:ReadonlyWrites++; throw 'Check must not log' }
    }
    $hashBefore = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
    & $module { Invoke-JobsAndroidRepair -Check }
    Assert-Repairer (& $module { $script:ReadonlyWrites -eq 0 }) '只读模式无确认、日志和设备写入'
    Assert-Repairer ((Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -ceq $hashBefore) 'Check完整业务保留config字节'
    & $module { $script:FreeKB = 1024; $script:Commands = @() }
    Assert-RepairerThrows { & $module { Invoke-JobsAndroidRepair -Check } } 'Check低空间返回失败而非假成功'
    Assert-Repairer (& $module { @($script:Commands | Where-Object { $_ -match 'set-install-location|uninstall|compile|emu kill' }).Count -eq 0 }) 'Check异常也不执行修复写命令'
    $manifest = Get-Content -LiteralPath (Join-Path $root 'JobsAndroidSimulatorRepairer/Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $installer = Import-Module (Join-Path $root 'JobsAndroidSimulatorRepairer/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking -Force
    $plan = @(& $installer { param($Manifest,$Release) Get-JobsPackageRegistryPlan $Manifest $Release 'powershell.exe' } $manifest (Join-Path $temporary 'release'))
    Assert-Repairer ($plan.Count -eq 2) '安装仅包含一个桌面handler与独立CLSID'
    Assert-Repairer ($plan[0].Key -ceq 'Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.android-simulator-repair') '不注册所有目录背景'
    Assert-Repairer ($plan[1].InProcServer -like '*JobsAndroidSimulatorRepairerContextMenu.dll') '原生DLL属于独立修复包'
    Remove-Module $installer
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $root 'JobsAndroidSimulatorRepairer/Scripts') -File | Where-Object { $_.Extension -in @('.ps1','.psm1') })) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        Assert-Repairer ($bytes.Length -gt 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) ('5.1中文源码UTF8 BOM：' + $file.Name)
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        Assert-Repairer (@($errors).Count -eq 0) ('Parser通过：' + $file.Name)
    }
    Write-Host ('PASS: AndroidSimulatorRepairer.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    if ($module) { Remove-Module $module -ErrorAction SilentlyContinue }
    $env:ANDROID_AVD_HOME = $oldAvd; $env:ANDROID_USER_HOME = $oldAndroidUser; $env:LOCALAPPDATA = $oldLocal
    $env:ANDROID_HOME = $oldSdkHome; $env:ANDROID_SDK_ROOT = $oldSdkRoot
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
