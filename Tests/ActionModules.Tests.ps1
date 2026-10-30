# ActionModules.Tests.ps1
# WindowsOS@Extension
# Created by Jobs on 2026年10月18日，星期日.

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Because)
    $script:assertions++
    if (-not $Condition) { throw "断言失败：$Because" }
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$temporary = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporary = '/private/tmp' }
$testRoot = Join-Path $temporary ("JobsFeatureModules [中文] '& " + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$savedLocalData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
try {
    $env:LOCALAPPDATA = $testRoot
    [IO.File]::WriteAllText((Join-Path $testRoot 'settings.gradle'), 'rootProject.name = "fixture"')
    [IO.File]::WriteAllText((Join-Path $testRoot 'build.gradle'), 'plugins { id "com.android.application" }')
    $parsedCatalog = Get-Content -LiteralPath (Join-Path $sourceRoot 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $catalog = @($parsedCatalog)
    $packages = @($catalog | ForEach-Object { Get-Item -LiteralPath (Join-Path $sourceRoot $_.Name) })
    Assert-True ($packages.Count -eq $catalog.Count) '清单登记功能包均有自己的源码'
    foreach ($package in $packages) {
        # 只复制当前功能的清单、模块和本包私有依赖；父目录没有安装器或其它功能可供回调。
        $standalone = Join-Path $testRoot $package.Name
        $scripts = Join-Path $standalone 'Scripts'
        [void][IO.Directory]::CreateDirectory($scripts)
        Copy-Item -LiteralPath (Join-Path $package.FullName 'Extension.json') -Destination $standalone
        foreach ($name in @('Common.psm1', 'Action.psm1')) {
            Copy-Item -LiteralPath (Join-Path $package.FullName ('Scripts/' + $name)) -Destination $scripts
        }
        if ($package.Name -eq 'JobsFileVolumes') {
            Copy-Item -LiteralPath (Join-Path $package.FullName 'Scripts/FileVolumes.ps1') -Destination $scripts
        }
        if ($package.Name -eq 'JobsFileContentViewer') {
            Copy-Item -LiteralPath (Join-Path $package.FullName 'Scripts/FileViewer.ps1') -Destination $scripts
        }
        if ($package.Name -eq 'JobsHarmonySimulatorCreator') {
            Copy-Item -LiteralPath (Join-Path $package.FullName 'Scripts/HarmonyTools.ps1') -Destination $scripts
        }
        if ($package.Name -in @('JobsRunAuthorizer', 'JobsRunAuthorizationRevoker')) {
            Copy-Item -LiteralPath (Join-Path $package.FullName 'Scripts/RunPermissions.ps1') -Destination $scripts
        }
        if ($package.Name -in @('JobsAndroidStudioOpener', 'JobsVSCodeOpener')) {
            foreach ($name in @('IDEProject.cs', 'ProjectEligibility.ps1')) {
                Copy-Item -LiteralPath (Join-Path $package.FullName ('Scripts/' + $name)) -Destination $scripts
            }
        }
        $manifest = Get-Content -LiteralPath (Join-Path $standalone 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $actionPath = Join-Path $scripts 'Action.psm1'
        $bytes = [IO.File]::ReadAllBytes($actionPath)
        Assert-True ($bytes.Length -gt 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) ($package.Name + ' 使用 UTF-8 BOM')
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($actionPath, [ref]$tokens, [ref]$errors)
        Assert-True ($errors.Count -eq 0) ($package.Name + ' 独立模块语法正确')
        $imports = @($ast.FindAll({ param($node)
            $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Import-Module'
        }, $false))
        Assert-True ($imports.Count -eq 1 -and $imports[0].Extent.Text -eq "Import-Module (Join-Path `$PSScriptRoot 'Common.psm1') -DisableNameChecking") ($package.Name + ' 只导入本包 Common')
        $readCommands = @($ast.FindAll({ param($node)
            $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Get-Content'
        }, $true))
        foreach ($readCommand in $readCommands) {
            Assert-True ($readCommand.Extent.Text -match '-Encoding UTF8') ($package.Name + ' 显式按 UTF-8 读取业务文件')
        }
        # 模拟实际 Invoke：先导 Common，再导 Action；嵌套导入不能撤销入口的基础命令。
        $entryCommon = Import-Module (Join-Path $scripts 'Common.psm1') -PassThru -DisableNameChecking
        $module = Import-Module $actionPath -PassThru -DisableNameChecking
        try {
            Assert-True ($null -ne (Get-Command Get-JobsInstallRoot -ErrorAction SilentlyContinue)) ($package.Name + ' Action 导入保留入口 Common 命令')
            Assert-True ($module.ExportedCommands.Count -eq 1 -and $module.ExportedCommands.ContainsKey('Invoke-JobsFeature')) ($package.Name + ' 只暴露统一功能入口')
            $installRoot = & $module { Get-JobsInstallRoot }
            $expectedRoot = Join-Path (Join-Path $testRoot 'Jobs/WindowsExtension/extensions') $manifest.Id
            Assert-True ($installRoot -eq $expectedRoot) ($package.Name + ' 安装数据归当前功能')
            if ($manifest.Id -eq 'flutter-tools') {
                $rejected = $false
                try { & $module { param($Target) Invoke-JobsFeature -Target $Target -Action 'unknown-action' } $testRoot } catch { $rejected = $true }
                Assert-True $rejected '统一 Flutter 入口只接受固定动作；有效绑定及打包另由 FlutterTools.Tests.ps1 覆盖'
                continue
            }
            if ($manifest.Id -eq 'open-sourcetree') {
                $rejected = $false
                try { & $module { param($Target) Invoke-JobsFeature -Target $Target } $testRoot } catch { $rejected = $true }
                Assert-True $rejected 'Sourcetree 拒绝非 Git 目录；安装检测与传输由 SourcetreeOpener.Tests.ps1 覆盖'
                continue
            }
            if ($manifest.Id -eq 'file-volumes') {
                $rejected = $false
                try { & $module { param($Target) Invoke-JobsFeature -Mode Split -Paths @($Target) } $testRoot } catch { $rejected = $true }
                Assert-True $rejected '分卷入口拒绝目录，流式业务另由FileVolumes.Tests.ps1覆盖'
                continue
            }
            if ($manifest.Id -eq 'git-rollback') {
                $rejected = $false
                try { & $module { param($Target) Invoke-JobsFeature -Target $Target } $testRoot } catch { $rejected = $true }
                Assert-True $rejected 'Git 回退拒绝非交互入口，不放宽确认；业务由 GitRollback.Tests.ps1 隔离覆盖'
                Assert-True (-not (Test-Path -LiteralPath (Join-Path $installRoot 'logs'))) 'Git 回退在自述确认前不写日志或执行业务'
                continue
            }
            if ($manifest.Id -eq 'android-simulator-repair') {
                $rejected = $false
                try { & $module { param($Target) Invoke-JobsFeature -Target $Target } $testRoot } catch { $rejected = $true }
                Assert-True $rejected 'Android 修复入口复检并拒绝普通目录；实际业务由 AndroidSimulatorRepairer.Tests.ps1 隔离覆盖'
                continue
            }
            if ($manifest.Id -eq 'hidden-files-toggle') {
                $rejected = $false
                try { & $module { param($Target) Invoke-JobsFeature -Target $Target } $testRoot } catch { $rejected = $true }
                Assert-True $rejected '隐藏文件切换拒绝普通目录；真实偏好由专用隔离夹具替代，不改变用户状态'
                continue
            }
            $result = & $module {
                param($Id, $Target)
                function script:Set-Clipboard { param($Value) $script:Captured = $Value }
                function script:Start-Process { param($FilePath) $script:Captured = $FilePath }
                function script:Start-JobsApplication {
                    param($Executable, $Arguments, $Directory, [switch]$VisibleConsole)
                    $script:Captured = @{ Executable = $Executable; Arguments = @($Arguments); Directory = $Directory }
                }
                function script:Get-JobsGitRemote { param($Directory) return 'git@example.com:Jobs/Repo.git' }
                function script:Find-JobsExecutable { param($Name, $Candidates) return 'terminal.exe' }
                function script:Get-JobsVSCode { return 'code.exe' }
                function script:Get-JobsAndroidStudio { return 'studio.exe' }
                function script:Get-JobsVisualStudio { return 'devenv.exe' }
                function script:Select-JobsSolution { param($Path) return 'solution.sln' }
                function script:Invoke-JobsSdkInspect { param($Directory) $script:Captured = $Directory }
                function script:Invoke-JobsFlutterDependencyAction { param($Directory) $script:Captured = $Directory }
                function script:Invoke-JobsFlutterVersionAction { param($Directory) $script:Captured = $Directory }
                function script:Invoke-JobsAndroidSimulatorAction { param($Target) $script:Captured = $Target }
                function script:Invoke-JobsHarmonyRepairAction { param($Target) $script:Captured = $Target }
                function script:Invoke-JobsFileContentViewer { param($Target) $script:Captured = $Target }
                function script:Invoke-JobsRunPermissionAction { param($Target, $Mode) $script:Captured = $Target }
                function script:Invoke-JobsHarmonySimulatorAction { param($Target) $script:Captured = $Target }
                function script:Invoke-JobsFlutterRunAction { param($Target) $script:Captured = $Target }
                function script:Invoke-JobsFlutterPackageAction { param($Target) $script:Captured = $Target }
                function script:Invoke-JobsFlutterDoctorAction { param($Target) $script:Captured = $Target }
                function script:Invoke-JobsFlutterCodegenAction { param($Target) $script:Captured = $Target }
                function script:Invoke-JobsBuildCleanAction { param($Directory) $script:Captured = $Directory }
                function script:Invoke-JobsFlutterAction { param($Directory) $script:Captured = $Directory }
                function script:Invoke-JobsCodeGraphAction { param($Directory) $script:Captured = $Directory }
                function script:Invoke-JobsGitAction { param($Directory) $script:Captured = $Directory }
                function script:Invoke-JobsProxyConfiguratorAction { param($Directory) $script:Captured = $Directory }
                Invoke-JobsFeature -Target ($Target + '|JobsPathEnd')
                return $script:Captured
            } $manifest.Id $testRoot
            switch ($manifest.Id) {
                'copy-path' { Assert-True ($result -eq $testRoot) '路径复制保留目标并剥离菜单哨兵' }
                'copy-git-remote' { Assert-True ($result -eq 'git@example.com:Jobs/Repo.git') 'Git 复制保留原始远端' }
                'open-git-remote' { Assert-True ($result -eq 'https://example.com/Jobs/Repo') 'Git 打开经本包 URL 转换' }
                'open-vscode' { Assert-True ($result.Executable -eq 'code.exe' -and $result.Arguments[0] -eq $testRoot -and $result.Directory -eq $testRoot) 'VSCode 只调用本包业务' }
                'open-android-studio' { Assert-True ($result.Executable -eq 'studio.exe' -and $result.Arguments[0] -eq $testRoot -and $result.Directory -eq $testRoot) 'Android Studio 只调用本包业务' }
                'open-visual-studio' { Assert-True ($result.Executable -eq 'devenv.exe' -and $result.Arguments[0] -eq 'solution.sln' -and $result.Directory -eq $testRoot) 'Visual Studio 使用本包项目选择' }
                'open-terminal' { Assert-True ($result.Executable -eq 'terminal.exe' -and $result.Arguments[0] -eq '-d' -and $result.Arguments[1] -eq $testRoot) '终端保留目标目录参数' }
                default { Assert-True ($result -eq $testRoot) ($package.Name + ' 同步调用本包业务且保留绝对目标') }
            }
        }
        finally {
            Remove-Module $module
            Remove-Module $entryCommon
        }
    }
    Write-Host ("ActionModules tests passed: {0} assertions." -f $script:assertions)
}
finally {
    [Environment]::SetEnvironmentVariable('LOCALAPPDATA', $savedLocalData, 'Process')
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
