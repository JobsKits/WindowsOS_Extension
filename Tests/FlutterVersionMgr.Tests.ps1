# FlutterVersionMgr.Tests.ps1
# Windows@Extension
# Created by Jobs on 2026年10月19日，星期一.
# 全部业务操作为隔离夹具，不运行真实 FVM、WinGet 或网络下载。

[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:assertions = 0
function Assert-Fvm {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Assert-FvmThrows {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action | Out-Null } catch { $threw = $true }
    Assert-Fvm $threw $Message
}

$root = Split-Path -Parent $PSScriptRoot
$testParent = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $testParent = '/private/tmp' }
$temporary = Join-Path $testParent ("JobsFvm [中文] & 100% ' " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$savedLocal = $env:LOCALAPPDATA
$module = $null
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'UserData'
    $standalone = Join-Path $temporary 'JobsFlutterVersionMgr'
    Copy-Item -LiteralPath (Join-Path $root 'JobsFlutterVersionMgr') -Destination $standalone -Recurse
    $module = Import-Module (Join-Path $standalone 'Scripts/Action.psm1') -PassThru -DisableNameChecking
    $cases = @(
        @{ Text = "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n"; Good = $true; Name = '常见 block 项目' },
        @{ Text = "dependencies:`n  flutter: {sdk: flutter}`n  cupertino_icons: ^1.0.0"; Good = $true; Name = 'flutter inline' },
        @{ Text = 'dependencies: {flutter: {sdk: flutter}, collection: ^1.0.0}'; Good = $true; Name = 'dependencies inline' },
        @{ Text = 'DEPENDENCIES: {FLUTTER: {SDK: flutter}}'; Good = $false; Name = 'YAML 根键区分大小写' },
        @{ Text = 'dependencies: {FLUTTER: {sdk: flutter}}'; Good = $false; Name = 'YAML flow flutter 键区分大小写' },
        @{ Text = 'dependencies: {flutter: {SDK: flutter}}'; Good = $false; Name = 'YAML flow sdk 键区分大小写' },
        @{ Text = 'dependencies: {flutter: {sdk:flutter}}'; Good = $false; Name = '无空格纯量并非 sdk 映射' },
        @{ Text = "'dependencies':`n  'flutter':`n    'sdk': 'flutter' # 正常注释"; Good = $true; Name = '引用键和值及尾注释' },
        @{ Text = "description: 'sdk: flutter # merely text'`ndependencies:`n  flutter:`n    sdk: flutter"; Good = $true; Name = '描述中含井号不影响真实依赖' },
        @{ Text = "name: dart_app`nenvironment:`n  sdk: ^3.0.0"; Good = $false; Name = '纯 Dart' },
        @{ Text = "# dependencies:`n#   flutter:`n#     sdk: flutter"; Good = $false; Name = '注释伪装' },
        @{ Text = "description: |`n  dependencies:`n    flutter:`n      sdk: flutter"; Good = $false; Name = 'description 标量伪装' },
        @{ Text = "dev_dependencies:`n  flutter_test:`n    sdk: flutter"; Good = $false; Name = '仅 flutter_test' },
        @{ Text = "dependencies:`n  flutter_test:`n    sdk: flutter"; Good = $false; Name = 'dependencies 仅 flutter_test' },
        @{ Text = "dependencies:`n  flutter:`n    path: ../flutter`n  other:`n    sdk: flutter"; Good = $false; Name = '其它依赖 sdk 不得串入' },
        @{ Text = "dependencies:`n  flutter:`n    description: |`n      sdk: flutter"; Good = $false; Name = 'flutter 描述标量伪装' },
        @{ Text = "dependencies:`n  flutter:`n    nested:`n      sdk: flutter"; Good = $false; Name = '嵌套 sdk 伪装' },
        @{ Text = "dependencies:`n  flutter:`n    sdk: flutter`n    sdk: other"; Good = $false; Name = '重复 sdk' },
        @{ Text = "dependencies:`n  flutter:`n    sdk: flutter`ndependencies: {}"; Good = $false; Name = '重复根 dependencies' },
        @{ Text = 'dependencies: {flutter: {sdk: flutter}, flutter: {sdk: other}}'; Good = $false; Name = '重复 flow flutter' },
        @{ Text = "dependencies:`n  flutter: *flutter_dependency"; Good = $false; Name = '未解释 YAML 别名安全拒绝' },
        @{ Text = "dependencies:`n`tflutter:`n`t  sdk: flutter"; Good = $false; Name = 'Tab 缩进拒绝' }
    )
    foreach ($case in $cases) {
        $actual = & $module { param($Text) Test-JobsFlutterPubspec $Text } $case.Text
        Assert-Fvm ($actual -eq $case.Good) ('pubspec：' + $case.Name)
    }
    $project = Join-Path $temporary 'parent/app'
    [void][IO.Directory]::CreateDirectory($project)
    $pubspec = Join-Path $project 'pubspec.yaml'
    [IO.File]::WriteAllText($pubspec, "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n")
    $parentConfig = Join-Path (Split-Path -Parent $project) '.fvmrc'
    [IO.File]::WriteAllText($parentConfig, '{"flutter":"3.16.0","keep":"parent"}')
    $melos = Join-Path (Split-Path -Parent $project) 'melos.yaml'
    [IO.File]::WriteAllText($melos, 'sdkPath: old-parent-path')
    $inspection = & $module { param($Project) New-JobsFvmInspection $Project } $project
    $shadowConfig = Get-Content -LiteralPath (Join-Path $inspection '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($null -eq $shadowConfig.PSObject.Properties['flutter']) '未绑定子项目使用独立空影子配置，不能继承父版本'
    Assert-Fvm ([IO.File]::ReadAllText((Join-Path $inspection 'pubspec.yaml')) -ceq [IO.File]::ReadAllText($pubspec)) '影子体检使用目标pubspec原文'
    Remove-Item -LiteralPath $inspection -Recurse -Force
    & $module { param($Project) Assert-JobsFlutterProject $Project } $project
    Assert-Fvm $true 'Flutter 项目不要求已有 SDK 或 lib 目录'
    Assert-FvmThrows { & $module { param($Project) Assert-JobsFlutterProject $Project } (Split-Path -Parent $project) } '不递归发现子工程'
    & $module {
        function script:Get-JobsFvmToolchain { param($Directory) throw '不应触发工具链' }
    }
    Assert-FvmThrows { & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } (Split-Path -Parent $project) } '非法项目在任何工具体检前阻断'
    $beforeParent = [IO.File]::ReadAllBytes($parentConfig)
    $beforeMelos = [IO.File]::ReadAllBytes($melos)
    & $module { param($Project) Set-JobsProjectFvmVersion $Project '3.19.0' } $project
    $config = Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($config.flutter -ceq '3.19.0' -and $config.updateMelosSettings -eq $false) '精确根配置且关闭向父 Melos 传播'
    $config | Add-Member -NotePropertyName 'flavors' -NotePropertyValue @{ staging = '3.16.0' }
    $config | Add-Member -NotePropertyName 'custom' -NotePropertyValue @{ nested = @{ keep = 'retained' } }
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), ($config | ConvertTo-Json -Depth 8))
    & $module { param($Project) Set-JobsProjectFvmVersion $Project '3.22.0' } $project
    $afterConfig = Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($afterConfig.flavors.staging -ceq '3.16.0' -and $afterConfig.custom.nested.keep -ceq 'retained') '切换保留既有配置字段'
    Assert-Fvm ([Convert]::ToBase64String([IO.File]::ReadAllBytes($parentConfig)) -ceq [Convert]::ToBase64String($beforeParent)) '父 .fvmrc 字节保持'
    Assert-Fvm ([Convert]::ToBase64String([IO.File]::ReadAllBytes($melos)) -ceq [Convert]::ToBase64String($beforeMelos)) '父 melos.yaml 字节保持'
    Assert-FvmThrows { & $module { param($Project) Set-JobsProjectFvmVersion $Project 'stable' } $project } '禁止把浮动渠道当指定版本'
    Assert-FvmThrows { & $module { param($Project) Set-JobsProjectFvmVersion $Project '3.19.0 & whoami' } $project } '版本参数注入拒绝'
    Assert-Fvm (& $module { Test-JobsFlutterVersion '1.12.13+hotfix.9' }) '官方旧 hotfix 具体版本保留'
    $legacyProject = Join-Path $temporary 'legacy'
    [void][IO.Directory]::CreateDirectory((Join-Path $legacyProject '.fvm'))
    [IO.File]::WriteAllText((Join-Path $legacyProject '.fvm/fvm_config.json'), '{"flutterSdkVersion":"3.16.0","flavors":{"dev":"3.10.0"},"cachePath":"custom-cache","flutterUrl":"custom-url","updateVscodeSettings":false}')
    & $module { param($Project) Set-JobsProjectFvmVersion $Project '3.22.0' } $legacyProject
    $legacyMigrated = Get-Content -LiteralPath (Join-Path $legacyProject '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($legacyMigrated.flutter -ceq '3.22.0' -and $null -eq $legacyMigrated.PSObject.Properties['flutterSdkVersion']) '旧flutterSdkVersion迁移且不覆盖新选择'
    Assert-Fvm ($legacyMigrated.flavors.dev -ceq '3.10.0' -and $legacyMigrated.cachePath -ceq 'custom-cache' -and $legacyMigrated.flutterUrl -ceq 'custom-url' -and $legacyMigrated.updateVscodeSettings -eq $false) '旧版flavors/源/缓存/IDE策略迁移保留'
    Assert-FvmThrows { & $module { param($Project) New-JobsFvmInspection $Project } $legacyProject } '相对cachePath明确阻断而非改变缓存语义'
    [IO.File]::WriteAllText((Join-Path $project '.gitignore'), "existing/`n")
    [IO.File]::WriteAllText((Join-Path $project 'app.code-workspace'), '{"folders":[],"settings":{"keep":true}}')
    $backup = & $module { param($Project) Backup-JobsFvmProject $Project } $project
    Assert-Fvm ([IO.File]::ReadAllText((Join-Path $backup 'files/.gitignore')) -ceq "existing/`n") '备份保留配置字节'
    $snapshot = Get-Content -LiteralPath (Join-Path $backup 'snapshot.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm (@($snapshot.Entries | Where-Object { $_.Path -ceq '.fvm' -and $_.Type -ceq 'Absent' }).Count -eq 1) '备份记录原本不存在的目标'
    Assert-Fvm ([IO.File]::Exists((Join-Path $backup 'files/app.code-workspace'))) 'FVM可能修改的根workspace已精确备份'
    $guardProject = Join-Path $temporary 'guard-project'
    [void][IO.Directory]::CreateDirectory((Join-Path $guardProject '.fvm'))
    $outsideFile = Join-Path $temporary 'outside-settings.json'
    [IO.File]::WriteAllText($outsideFile, 'outside-retained')
    foreach ($relative in @('.fvm/fvm_config.json', '.fvm/version', '.fvm/release', '.fvm/.gitignore', 'unsafe.code-workspace')) {
        $link = Join-Path $guardProject $relative
        [void](New-Item -ItemType SymbolicLink -Path $link -Target $outsideFile)
        Assert-FvmThrows { & $module { param($Project) Assert-JobsFvmWritePaths $Project } $guardProject } ('FVM已知写路径拒绝链接：' + $relative)
        [IO.File]::Delete($link)
    }
    $dangling = Join-Path $guardProject '.fvm/version'
    [void](New-Item -ItemType SymbolicLink -Path $dangling -Target (Join-Path $temporary 'missing-outside'))
    Assert-FvmThrows { & $module { param($Project) Assert-JobsFvmWritePaths $Project } $guardProject } '悬空配置链接不得伪装不存在'
    [IO.File]::Delete($dangling)
    Assert-Fvm ([IO.File]::ReadAllText($outsideFile) -ceq 'outside-retained') '门禁没有写出项目边界'
    & $module {
        function script:Read-JobsFvmWebJson {
            param($Uri)
            return [pscustomobject]@{
                current_release = [pscustomobject]@{ stable = 'newhash'; beta = 'betahash' }
                releases = @(
                    [pscustomobject]@{ version = '3.22.0'; channel = 'stable'; hash = 'newhash'; release_date = '2024-05-14T00:00:00Z' },
                    [pscustomobject]@{ version = '3.19.0'; channel = 'stable'; hash = 'oldhash'; release_date = '2024-02-14T00:00:00Z' },
                    [pscustomobject]@{ version = '3.23.0-0.1.pre'; channel = 'beta'; hash = 'betahash'; release_date = '2024-05-15T00:00:00Z' }
                )
            }
        }
    }
    $cached = @([pscustomobject]@{ Version = '3.19.0'; Ready = $true; Directory = 'unused' }, [pscustomobject]@{ Version = '3.16.0'; Ready = $false; Directory = 'unused' })
    $choices = @(& $module { param($Cached) Get-JobsFlutterReleaseChoices $Cached '3.19.0' } $cached)
    Assert-Fvm ($choices.Count -eq 3) '联网列出历史与最新并去除未就绪的无发布缓存'
    Assert-Fvm (@($choices | Where-Object { $_.Label -match '最新stable' -and $_.Version -ceq '3.22.0' }).Count -eq 1) '最新 stable 使用官方 current_release'
    Assert-Fvm (@($choices | Where-Object { $_.Label -match '当前项目' -and $_.Ready }).Count -eq 1) '当前项目和就绪缓存标注'
    Assert-Fvm (@($choices | Where-Object { $_.Version -ceq '3.23.0-0.1.pre' -and $_.Label -match '最新beta' }).Count -eq 1) '历史 beta 精确版本可选'
    & $module { function script:Read-JobsFvmWebJson { param($Uri) throw 'offline fixture' } }
    $offline = @(& $module { param($Cached) Get-JobsFlutterReleaseChoices $Cached '3.19.0' } $cached)
    Assert-Fvm ($offline.Count -eq 1 -and $offline[0].Ready -and $offline[0].Offline -and $offline[0].Label -match '最新未知') '离线仅允许已初始化缓存且最新未知'
    Assert-FvmThrows { & $module { Get-JobsFlutterReleaseChoices @() '' } } '无网络无就绪缓存时停止'
    & $module {
        function script:Get-JobsFvmToolchain { param($Directory) return [pscustomobject]@{ Fvm = 'fixture.exe'; Fzf = 'fzf-fixture.exe'; Context = [pscustomobject]@{ versionsCachePath = 'fixture-cache'; flutterUrl = 'fixture-source' } } }
        function script:Get-JobsFvmCachedVersions { param($Fvm, $Directory) $script:LastInspection = $Directory; return [pscustomobject]@{ Version = '3.22.0'; Ready = $true; Directory = 'unused' } }
        function script:Get-JobsFlutterReleaseChoices { param($Cached, $Current) return [pscustomobject]@{ Version = '3.22.0'; Ready = $true; Offline = $true; Label = 'fixture' } }
        function script:Select-JobsFlutterVersion { param($Fzf, $Choices, $Directory) return $null }
    }
    $hashBefore = (Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash
    $pathBefore = $env:PATH
    & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project
    Assert-Fvm ((Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash -ceq $hashBefore) 'fzf Esc 取消不写项目'
    Assert-Fvm ($env:PATH -ceq $pathBefore) '退出恢复进程 PATH'
    $usedInspection = & $module { $script:LastInspection }
    Assert-Fvm ($usedInspection -cne $project -and -not [IO.Directory]::Exists($usedInspection)) 'API缓存体检使用项目外影子目录且退出精确清理'
    & $module {
        function script:Select-JobsFlutterVersion { param($Fzf, $Choices, $Directory) return $Choices[0] }
        function script:Read-Host { param($Prompt) return '' }
    }
    & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project
    Assert-Fvm ((Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash -ceq $hashBefore) '最终回车跳过不写项目'
    & $module {
        $script:Commands = @()
        function script:Read-Host { param($Prompt) return 'go' }
        function script:Assert-JobsFvmSymlinkSupport { param($Directory) }
        function script:Invoke-JobsFvmTool {
            param($File, $Arguments, $Directory, [switch]$Visible, $TimeoutSeconds)
            $script:Commands += ($Arguments -join ' ')
            if ($Arguments[0] -ceq 'api') {
                return [pscustomobject]@{ ExitCode = 0; StdOut = '{"context":{"versionsCachePath":"fixture-cache","flutterUrl":"fixture-source"}}'; StdErr = '' }
            }
            if ($Arguments[0] -ceq 'use') {
                # 模拟FVM已知字段序列化会丢未知custom字段，业务收尾须补回。
                [IO.File]::WriteAllText((Join-Path $Directory '.fvmrc'), '{"flutter":"3.22.0","updateMelosSettings":false}')
                $sdk = Join-Path (Split-Path -Parent $Directory) 'sdk-cache'
                [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
                [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'), '@echo fixture')
                [void][IO.Directory]::CreateDirectory((Join-Path $Directory '.fvm'))
                if (-not (Test-Path -LiteralPath (Join-Path $Directory '.fvm/flutter_sdk'))) {
                    [void](New-Item -ItemType SymbolicLink -Path (Join-Path $Directory '.fvm/flutter_sdk') -Target $sdk)
                }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = '{"frameworkVersion":"3.22.0"}'; StdErr = '' }
        }
    }
    & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project
    $commands = @(& $module { $script:Commands })
    Assert-Fvm ($commands.Count -eq 3 -and $commands[0] -ceq 'api context --compress' -and $commands[1] -ceq 'use 3.22.0 --skip-pub-get --skip-setup' -and $commands[2] -ceq 'flutter --version --machine') '离线缓存上下文复检后仅切换并复核，不安装/联网pub'
    $finalConfig = Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Fvm ($finalConfig.custom.nested.keep -ceq 'retained' -and $finalConfig.flavors.staging -ceq '3.16.0') 'FVM序列化丢弃的原有字段已补回'
    Assert-Fvm (@($commands | Where-Object { $_ -match '^global|pub get' }).Count -eq 0) '不设置全局版本或获取项目依赖'
    Assert-Fvm ([Convert]::ToBase64String([IO.File]::ReadAllBytes($parentConfig)) -ceq [Convert]::ToBase64String($beforeParent)) '完整模拟操作后父配置保持'
    & $module {
        $script:Commands = @()
        function script:Get-JobsFlutterReleaseChoices { param($Cached, $Current) return [pscustomobject]@{ Version = '3.22.0'; Ready = $false; Offline = $false; Label = 'uncached fixture' } }
    }
    & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project
    $installCommands = @(& $module { $script:Commands })
    Assert-Fvm ($installCommands.Count -eq 4 -and $installCommands[1] -ceq 'install 3.22.0 --skip-pub-get' -and $installCommands[2] -ceq 'use 3.22.0 --skip-pub-get --skip-setup') '未缓存路径先安装再绑定精确版本'
    $beforeConcurrent = (Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash
    & $module {
        $script:Commands = @()
        function script:Select-JobsFlutterVersion {
            param($Fzf, $Choices, $Directory)
            [IO.File]::AppendAllText((Join-Path $Directory 'pubspec.yaml'), "`n# external edit during selection")
            return $Choices[0]
        }
    }
    Assert-FvmThrows { & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project } '选版期间项目变动在写入前停止'
    Assert-Fvm ((Get-FileHash -LiteralPath (Join-Path $project '.fvmrc')).Hash -ceq $beforeConcurrent) '并发变动阻断保留原配置'
    Assert-Fvm (@(& $module { $script:Commands }).Count -eq 0) '并发阻断没有执行安装/切换'
    & $module {
        $script:Commands = @()
        function script:Select-JobsFlutterVersion { param($Fzf, $Choices, $Directory) return $Choices[0] }
        function script:Invoke-JobsFvmTool {
            param($File, $Arguments, $Directory, [switch]$Visible, $TimeoutSeconds)
            $script:Commands += ($Arguments -join ' ')
            return [pscustomobject]@{ ExitCode = 0; StdOut = '{"context":{"versionsCachePath":"different-cache","flutterUrl":"fixture-source"}}'; StdErr = '' }
        }
    }
    Assert-FvmThrows { & $module { param($Project) Invoke-JobsFlutterVersionAction $Project } $project } '新根配置改变继承缓存时阻断旧Ready状态'
    $driftCommands = @(& $module { $script:Commands })
    Assert-Fvm ($driftCommands.Count -eq 1 -and $driftCommands[0] -ceq 'api context --compress') '上下文变化后没有下载或切换'
    Write-Host ('PASS: FlutterVersionMgr.Tests.ps1 (' + $script:assertions + ' assertions; fixtures only)')
}
finally {
    if ($null -ne $module) { Remove-Module $module }
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
