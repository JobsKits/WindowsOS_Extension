# CommandShortcutTests.ps1 | JobsCommandShortcutCreator
# Created by Jobs on 2026年11月13日，星期五.
# 仅使用临时目录；不注册菜单、不显示GUI、不运行批处理目标。

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
. (Resolve-JobsScriptLayoutPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Scripts/CommandShortcut.ps1'))
. (Resolve-JobsScriptLayoutPath (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) 'Tests/NativeFixtures.ps1'))
$script:Assertions = 0
function Assert-Shortcut {
    param([bool]$Value, [string]$Reason)
    $script:Assertions++
    if (-not $Value) { throw $Reason }
}
function Assert-ShortcutThrows {
    param([scriptblock]$Body, [string]$Reason)
    $thrown = $false
    try { & $Body | Out-Null } catch { $thrown = $true }
    Assert-Shortcut $thrown $Reason
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('JobsShortcutTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    foreach ($extension in @('.cmd', '.bat', '.ps1')) {
        $name = '原生 '' %!&() $(Get-Date)' + $extension
        $directory = Join-Path $root $name
        [void][IO.Directory]::CreateDirectory($directory)
        $scriptPath = Join-Path $directory $name
        $original = if ($extension -eq '.ps1') { '[IO.File]::WriteAllText((Join-Path $PSScriptRoot ''executed.json''), (ConvertTo-Json -InputObject @($args))); exit 23' } else { '@echo off' + "`r`n" + 'exit /b 23' }
        [IO.File]::WriteAllText($scriptPath, $original, (New-Object Text.UTF8Encoding($true)))
        $hash = (Get-FileHash -LiteralPath $scriptPath).Hash
        $context = Get-JobsCommandShortcutTarget $directory
        Assert-Shortcut ($context.Extension -eq $extension) 'Native script extension is retained.'
        $destination = New-JobsCommandShortcut $directory ('外层快捷入口' + $extension)
        Assert-Shortcut ([IO.File]::Exists($destination)) 'A sibling launcher is created.'
        Assert-Shortcut ((Get-FileHash -LiteralPath $scriptPath).Hash -ceq $hash) 'Creating a launcher leaves source bytes unchanged.'
        Assert-Shortcut (-not [IO.File]::Exists((Join-Path $directory 'executed.json'))) 'Creation never executes the source script.'
        $bytes = [IO.File]::ReadAllBytes($destination)
        if ($extension -eq '.ps1') {
            Assert-Shortcut ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) 'PowerShell launcher uses UTF-8 BOM for Windows PowerShell 5.1.'
            $content = [IO.File]::ReadAllText($destination)
            Assert-Shortcut ($content.Contains('$PSScriptRoot') -and $content.Contains('@jobsLauncherForward')) 'PowerShell resolves its own location and forwards arguments.'
        } else {
            $content = [IO.File]::ReadAllText($destination)
            Assert-Shortcut ($content.Contains('%%!&()') -and $content.Contains('%~dp0') -and $content.Contains('%*')) 'Batch quoting preserves percent, special path characters and argument forwarding.'
            Assert-Shortcut (-not $content.Contains('call ') -and -not $content.Contains('/s /c')) 'Batch execution avoids CALL and a second cmd expansion.'
            Assert-Shortcut ($content.Contains('chcp %jobsLauncherCodePage%')) 'Original batch console code page is restored.'
        }
        Assert-ShortcutThrows { New-JobsCommandShortcut $directory ('外层快捷入口' + $extension) } 'Existing launcher cannot be overwritten.'
        $occupiedDirectory = Join-Path $root ('同名目录' + $extension)
        [void][IO.Directory]::CreateDirectory($occupiedDirectory)
        Assert-ShortcutThrows { New-JobsCommandShortcut $directory ('同名目录' + $extension) } 'Existing directory cannot be overwritten.'
        foreach ($invalid in @('', ' ', '..', 'x.txt', ('x/y' + $extension), ('x:y' + $extension), ('x?y' + $extension), ('CON' + $extension), ('x' + "`n" + $extension))) {
            Assert-Shortcut (-not (Test-JobsCommandShortcutName $invalid $extension)) ('Reject invalid name ' + $invalid)
        }
    }
    $ordinary = Join-Path $root 'ordinary'
    [void][IO.Directory]::CreateDirectory($ordinary)
    Assert-ShortcutThrows { Get-JobsCommandShortcutTarget $ordinary } 'Ordinary folder cannot become a script package.'
    $missing = Join-Path $root 'missing.cmd'
    [void][IO.Directory]::CreateDirectory($missing)
    Assert-ShortcutThrows { Get-JobsCommandShortcutTarget $missing } 'A package must contain its same-named script.'
    foreach ($language in @('zh-Hans', 'zh-Hant', 'bo', 'en', 'ja', 'fr', 'es', 'de', 'ru', 'ko')) {
        foreach ($key in @('title','create','cancel','prompt','invalidName','invalidTarget','suffix','language','theme','system','dark','light')) {
            $text = Get-JobsCommandShortcutText $key $language '.bat'
            Assert-Shortcut (-not [string]::IsNullOrWhiteSpace($text) -and $text -cne $key) ('Complete translation ' + $language + '/' + $key)
        }
    }
    # 回调通过所属Action模块解析私有函数，不依赖GetNewClosure动态模块的查找路径。
    $packageRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $actionModule = Import-Module (Join-Path $packageRoot 'Scripts/Action.psm1') -DisableNameChecking -PassThru
    $moduleCall = & $actionModule { New-JobsCommandShortcutModuleInvoker }
    $fakeControls = @{ Title = ''; Theme = ''; Created = ''; PreferencePath = (Join-Path $root 'callback-preferences.json') }
    $callbackTarget = Join-Path $root '原生 '' %!&() $(Get-Date).ps1'
    $callback = {
        $fakeControls.Title = & $moduleCall -Name 'Get-JobsCommandShortcutText' -Arguments @('title', 'en', '.ps1')
        $fakeControls.Theme = & $moduleCall -Name 'Resolve-JobsPanelTheme' -Arguments @('dark')
        & $moduleCall -Name 'Save-JobsPanelPreferences' -Arguments @('dark', 'en', $fakeControls.PreferencePath)
        $fakeControls.Created = & $moduleCall -Name 'New-JobsCommandShortcut' -Arguments @($callbackTarget, 'callback.ps1')
    }.GetNewClosure()
    & $callback
    Assert-Shortcut ($fakeControls.Title -ceq 'Create Script Launcher') 'Dynamic GUI callback reaches private localized text in its owning module.'
    Assert-Shortcut ($fakeControls.Theme -ceq 'dark') 'Dynamic GUI callback reaches imported presentation helpers.'
    Assert-Shortcut ([IO.File]::Exists($fakeControls.PreferencePath)) 'Dynamic GUI callback can save preferences to an isolated test location.'
    Assert-Shortcut ([IO.File]::Exists($fakeControls.Created)) 'Dynamic GUI callback can invoke the private creation service.'
    Remove-Module $actionModule
    # Renaming the complete package proves that no creation-time machine path is embedded.
    $moved = $root + '-moved'
    [IO.Directory]::Move($root, $moved)
    $root = $moved
    $launcher = Join-Path $root '外层快捷入口.ps1'
    $pwsh = (Get-Process -Id $PID).Path
    $arguments = @('空格 参数', '单''引号', '$();&!%')
    & $pwsh -NoLogo -NoProfile -File $launcher @arguments
    $code = $LASTEXITCODE
    Assert-Shortcut ($code -eq 23) 'PowerShell launcher preserves the script exit code after relocation.'
    $executed = Join-Path (Join-Path $root '原生 '' %!&() $(Get-Date).ps1') 'executed.json'
    $receipt = Get-Content -LiteralPath $executed -Raw -Encoding UTF8
    # 5.1 的 JSON 数组从管道作为单对象输出，先取解析值再归一化，避免多包一层。
    $received = $receipt | ConvertFrom-Json
    $received = @($received)
    Assert-Shortcut ($received.Count -eq $arguments.Count) ('PowerShell retains the argument count; expected=' + $arguments.Count + '; actual=' + $received.Count + '; receipt=' + $receipt)
    for ($index = 0; $index -lt $arguments.Count; $index++) {
        Assert-Shortcut ($received[$index] -ceq $arguments[$index]) ('PowerShell argument remains literal at index ' + $index + '.')
    }
    $link = Join-Path $root '悬空.ps1'
    if (New-JobsTestSymbolicLink -Path $link -Target (Join-Path $root 'not-present')) {
        Assert-ShortcutThrows { New-JobsCommandShortcut (Join-Path $root '原生 '' %!&() $(Get-Date).ps1') '悬空.ps1' } 'Dangling links cannot be overwritten.'
        Assert-Shortcut (([IO.File]::GetAttributes($link) -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'Dangling link survives.'
    }
    $packageLink = Join-Path $root 'linked.ps1'
    if (New-JobsTestSymbolicLink -Path $packageLink -Target (Join-Path $root '原生 '' %!&() $(Get-Date).ps1') -Directory) {
        Assert-ShortcutThrows { Get-JobsCommandShortcutTarget $packageLink } 'Reparse-point directories are rejected.'
    }
    Assert-Shortcut (@(Get-ChildItem -LiteralPath $root -Filter '.jobs-command-shortcut-*' -Force).Count -eq 0) 'Temporary files are cleaned after success and refusal.'
    Write-Output ('PASS: ' + $script:Assertions + ' command shortcut assertions')
} finally {
    if ([IO.Directory]::Exists($root)) { [IO.Directory]::Delete($root, $true) }
}
