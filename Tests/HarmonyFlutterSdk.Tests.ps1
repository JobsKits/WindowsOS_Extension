# HarmonyFlutterSdk.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月23日，星期五.
# 使用临时项目与假 FVM；不联网、不安装工具、不注册菜单。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:count = 0
function Assert-HarmonySdk($Value, [string]$Message) { $script:count++; if (-not $Value) { throw ('FAIL: ' + $Message) } }
function Assert-HarmonyThrows([scriptblock]$Action, [string]$Message) {
    $blocked = $false
    try { & $Action | Out-Null } catch { $blocked = $true }
    Assert-HarmonySdk $blocked $Message
}
$root = Split-Path -Parent $PSScriptRoot
$temporaryRoot = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryRoot = '/private/tmp' }
$temporary = Join-Path $temporaryRoot ('JobsHarmonySdk [中文] & 100% ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$saved = @{}
foreach ($key in @('LOCALAPPDATA','FVM_CACHE_PATH','FVM_FLUTTER_URL','FVM_USE_GIT_CACHE','PATH')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    $env:LOCALAPPDATA = Join-Path $temporary 'local'
    $path = Join-Path $root 'JobsFlutterTools/Scripts/HarmonySdk.psm1'
    $module = Import-Module $path -PassThru -Force -DisableNameChecking
    $sha = '0123456789abcdef0123456789abcdef01234567'
    $tagSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $ref = '3.35.7+ohos-1.0.5'
    $remote = $tagSha + "`trefs/tags/" + $ref + "`n" + $sha + "`trefs/tags/" + $ref + '^{}'
    $choices = @(& $module { param($Text) ConvertFrom-JobsHarmonyTags $Text } $remote)
    Assert-HarmonySdk ($choices.Count -eq 1 -and $choices[0].Commit -ceq $sha) 'annotated tag resolves peeled commit'
    Assert-HarmonySdk ($choices[0].Version -ceq ('custom_jobs_ohos_' + $sha)) 'custom cache key uses immutable commit'
    Assert-HarmonySdk ((& $module { param($Text,$Ref) Resolve-JobsHarmonyCommit $Text $Ref } $remote $ref) -ceq $sha) 'selection commit resolves exact tag'
    Assert-HarmonyThrows { & $module { param($Text,$Ref) Resolve-JobsHarmonyCommit $Text $Ref } ($remote + "`n" + $sha + "`trefs/heads/" + $ref) $ref } 'same-name tag and branch rejected'
    Assert-HarmonyThrows { & $module { ConvertFrom-JobsHarmonyTags "not-a-sha`trefs/tags/3.35.7+ohos-1.0.5" } } 'invalid remote record rejected'
    Assert-HarmonySdk (@(& $module { ConvertFrom-JobsHarmonyTags "0123456789abcdef0123456789abcdef01234567`trefs/tags/3.35.7" }).Count -eq 0) 'upstream native tags excluded'
    $variant = @(& $module { ConvertFrom-JobsHarmonyTags "0123456789abcdef0123456789abcdef01234567`trefs/tags/v3.47.7+ohos-0.0.1-pre" })
    Assert-HarmonySdk ($variant.Count -eq 1 -and $variant[0].Prerelease -eq $true -and $variant[0].BaseVersion -eq [version]'3.47.7') 'v-prefix and prerelease tag parsed explicitly'
    $sorting = @(& $module {
        Get-JobsHarmonyTagChoices "0123456789abcdef0123456789abcdef01234567`trefs/tags/3.41.9+ohos-1.0.9`n0123456789abcdef0123456789abcdef01234567`trefs/tags/3.41.9+ohos-1.0.10`n0123456789abcdef0123456789abcdef01234567`trefs/tags/v3.47.7+ohos-0.0.1-pre"
    })
    Assert-HarmonySdk ($sorting[0].Ref -ceq '3.41.9+ohos-1.0.10' -and $sorting[1].Ref -ceq '3.41.9+ohos-1.0.9' -and $sorting[2].Prerelease -eq $true) 'stable tags first and OH numeric suffix sorts 1.0.10 before 1.0.9'
    $project = Join-Path $temporary 'parent/app'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: app`ndependencies:`n  flutter:`n    sdk: flutter`n")
    [IO.File]::WriteAllText((Join-Path (Split-Path -Parent $project) '.fvmrc'), '{"flutter":"3.16.0","parent":true}')
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"3.38.5","custom":{"keep":true},"flavors":{"dev":"3.38.4"}}')
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.vscode'))
    [IO.File]::WriteAllText((Join-Path $project '.vscode/settings.json'), '{"dart.flutterSdkPath":"keep/ide","keep":true}')
    [IO.File]::WriteAllText((Join-Path $project '.gitignore'), "keep/`n")
    $oldSdk = Join-Path $temporary 'native-sdk'
    [void][IO.Directory]::CreateDirectory($oldSdk)
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.fvm'))
    $linkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
    [void](New-Item -ItemType $linkType -Path (Join-Path $project '.fvm/flutter_sdk') -Target $oldSdk)
    $before = [IO.File]::ReadAllText((Join-Path $project '.fvmrc'))
    $beforeIde = [IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json'))
    $beforeIgnore = [IO.File]::ReadAllText((Join-Path $project '.gitignore'))
    & $module { function script:Invoke-JobsHarmonyGit { throw 'network must not run during check' } }
    & $module { param($Project) Invoke-JobsHarmonySdkAction -Target $Project -Check } $project
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.fvmrc')) -ceq $before) 'check leaves project config unchanged'
    Assert-HarmonySdk (-not [IO.Directory]::Exists((Join-Path $env:LOCALAPPDATA 'JobsFlutter'))) 'check creates no cache'
    $cache = & $module { Get-JobsHarmonyCache }
    $sdk = Join-Path $cache ('versions/custom_jobs_ohos_' + $sha)
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk '.git'))
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'), 'fake sdk only')
    $stamp = & $module { param($Project) Get-JobsHarmonyBindingStamp $Project } $project
    $shadow = Join-Path $temporary 'shadow'
    [void][IO.Directory]::CreateDirectory($shadow)
    Copy-Item -LiteralPath (Join-Path $project '.fvmrc') -Destination (Join-Path $shadow '.fvmrc')
    $config = & $module { param($Project,$Version,$Cache) Set-JobsHarmonyConfig $Project $Version $Cache } $shadow ('custom_jobs_ohos_' + $sha) $cache
    Assert-HarmonySdk ($config.custom.keep -eq $true -and $config.flavors.dev -ceq '3.38.4') 'existing fields and flavors preserved'
    Assert-HarmonySdk ($config.updateMelosSettings -eq $false -and $config.useGitCache -eq $false) 'parent Melos updates and shared git cache disabled'
    $body = ($config | ConvertTo-Json -Depth 100) + [Environment]::NewLine
    & $module { function script:Complete-JobsHarmonyConfigPublication { throw 'injected publication failure after link move' } }
    Assert-HarmonyThrows { & $module { param($Project,$Sdk,$Config,$Stamp) Publish-JobsHarmonyBinding $Project $Sdk $Config $Stamp } $project $sdk $body $stamp } 'publishing failure reported'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.fvmrc')) -ceq $before) 'failed native-to-OH switch restores original config bytes'
    Assert-HarmonySdk ([string]@(Get-Item -LiteralPath (Join-Path $project '.fvm/flutter_sdk')).Target -ceq $oldSdk) 'failed native-to-OH switch restores original SDK link'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json')) -ceq $beforeIde -and [IO.File]::ReadAllText((Join-Path $project '.gitignore')) -ceq $beforeIgnore) 'failure preserves IDE and ignore'
    $module = Import-Module $path -PassThru -Force -DisableNameChecking
    & $module { param($Project,$Sdk,$Config,$Stamp) Publish-JobsHarmonyBinding $Project $Sdk $Config $Stamp } $project $sdk $body $stamp
    Assert-HarmonySdk ((Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw | ConvertFrom-Json).flutter -ceq ('custom_jobs_ohos_' + $sha)) 'successful project config published'
    Assert-HarmonySdk ([string]@(Get-Item -LiteralPath (Join-Path $project '.fvm/flutter_sdk')).Target -ceq $sdk) 'published SDK link is absolute selected cache'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json')) -ceq $beforeIde -and [IO.File]::ReadAllText((Join-Path $project '.gitignore')) -ceq $beforeIgnore) 'success preserves IDE and ignore'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path (Split-Path -Parent $project) '.fvmrc')) -ceq '{"flutter":"3.16.0","parent":true}') 'parent project untouched'
    Assert-HarmonyThrows { & $module { param($Project,$Sdk,$Config,$Stamp) Publish-JobsHarmonyBinding $Project $Sdk $Config $Stamp } $project $sdk $body $stamp } 'stale project fingerprint prevents publication'
    $guard = Join-Path $temporary 'unsafe'
    [void][IO.Directory]::CreateDirectory((Join-Path $guard '.fvm/flutter_sdk'))
    Copy-Item -LiteralPath (Join-Path $project 'pubspec.yaml') -Destination (Join-Path $guard 'pubspec.yaml')
    Assert-HarmonyThrows { & $module { param($Project) Assert-JobsHarmonyBindingPaths $Project } $guard } 'real SDK source directory never overwritten'
    & $module {
        $script:TestCommit = '0123456789abcdef0123456789abcdef01234567'
        function script:Read-Host { param($Prompt) return '' }
        function script:Invoke-JobsHarmonyGit {
            param($Git,$Arguments,$Directory,$TimeoutSeconds)
            if ($Arguments[0] -ceq 'ls-remote') { return $script:TestCommit + "`trefs/tags/3.35.7+ohos-1.0.5" }
            if ($Arguments[2] -ceq 'rev-parse') { return $script:TestCommit }
            if ($Arguments[2] -ceq 'remote') { return 'https://gitcode.com/CPF-Flutter/flutter_flutter.git' }
            if ($Arguments[2] -ceq 'status') { return '' }
            throw 'unexpected Git operation in fixture'
        }
        & $script:HarmonyManager {
            $script:TestCommit = '0123456789abcdef0123456789abcdef01234567'
            $script:FailHap = $true
            function script:Get-JobsFvmToolchain { param($Directory,$InspectionDirectory) return [pscustomobject]@{Git='fake-git';Fvm='fake-fvm';Fzf='fake-fzf'} }
            function script:Select-JobsFlutterVersion { param($Fzf,$Choices,$Directory) return @($Choices)[0] }
            function script:Invoke-JobsFvmTool {
                param($File,$Arguments,$Directory,[switch]$Visible,$TimeoutSeconds)
                if ($Arguments[0] -ceq 'use') {
                    [void][IO.Directory]::CreateDirectory((Join-Path $Directory '.fvm'))
                    $target = Join-Path $env:FVM_CACHE_PATH ('versions/' + $Arguments[1])
                    $kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
                    [void](New-Item -ItemType $kind -Path (Join-Path $Directory '.fvm/flutter_sdk') -Target $target)
                    return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
                }
                if ($Arguments[1] -ceq '--version') { return [pscustomobject]@{ExitCode=0;StdOut=('{"frameworkRevision":"' + $script:TestCommit + '"}');StdErr=''} }
                if ($script:FailHap) { return [pscustomobject]@{ExitCode=1;StdOut='';StdErr='unsupported hap'} }
                return [pscustomobject]@{ExitCode=0;StdOut='Build hap';StdErr=''}
            }
        }
    }
    $existingCache = Join-Path $temporary 'keep-existing-cache'
    $env:FVM_CACHE_PATH = $existingCache; $env:FVM_FLUTTER_URL = 'keep-existing-url'; $env:FVM_USE_GIT_CACHE = 'true'
    $pathBefore = $env:PATH
    $currentBeforeFailure = [IO.File]::ReadAllText((Join-Path $project '.fvmrc'))
    Assert-HarmonyThrows { & $module { param($Project) Invoke-JobsHarmonySdkAction -Target $Project } $project } 'SDK without hap capability fails before real project publication'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.fvmrc')) -ceq $currentBeforeFailure) 'failed shadow capability check leaves live binding bytes'
    Assert-HarmonySdk ($env:FVM_CACHE_PATH -ceq $existingCache -and $env:FVM_FLUTTER_URL -ceq 'keep-existing-url' -and $env:FVM_USE_GIT_CACHE -ceq 'true' -and $env:PATH -ceq $pathBefore) 'failure restores all process environment'
    & $module { & $script:HarmonyManager { $script:FailHap = $false } }
    & $module { param($Project) Invoke-JobsHarmonySdkAction -Target $Project } $project
    Assert-HarmonySdk ($env:FVM_CACHE_PATH -ceq $existingCache -and $env:FVM_FLUTTER_URL -ceq 'keep-existing-url' -and $env:FVM_USE_GIT_CACHE -ceq 'true' -and $env:PATH -ceq $pathBefore) 'success restores all process environment'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json')) -ceq $beforeIde -and [IO.File]::ReadAllText((Join-Path $project '.gitignore')) -ceq $beforeIgnore) 'shadow workflow never rewrites live IDE or ignore'
    Assert-HarmonySdk (@(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Jobs/WindowsExtension/extensions/flutter-tools') -Directory -Filter 'inspection-*').Count -eq 0) 'private shadow cleaned after success and failure'
    Assert-HarmonySdk (& $module { param($Project) Test-JobsManagedHarmonyBinding $Project } $project) 'known CPF convention recognized for native return path'
    & $module {
        function script:Invoke-JobsHarmonyGit {
            param($Git,$Arguments,$Directory,$TimeoutSeconds)
            if ($Arguments[2] -ceq 'remote') { return 'https://github.com/flutter/flutter.git' }
            throw 'unexpected native fixture Git operation'
        }
        & $script:HarmonyManager {
            $script:NativeFails = $true
            function script:Get-JobsFvmToolchain {
                param($Directory,$InspectionDirectory)
                return [pscustomobject]@{Git='fake-git';Fvm='fake-fvm';Fzf='fake-fzf';Context=[pscustomobject]@{flutterUrl=$env:FVM_FLUTTER_URL;versionsCachePath=(Join-Path $env:FVM_CACHE_PATH 'versions')}}
            }
            function script:Get-JobsFvmCachedVersions { return @() }
            function script:Get-JobsFlutterReleaseChoices { return [pscustomobject]@{Version='3.38.5';Ready=$false;Offline=$false;Label='3.38.5 | official stable'} }
            function script:Invoke-JobsFvmTool {
                param($File,$Arguments,$Directory,[switch]$Visible,$TimeoutSeconds)
                if ($Arguments[0] -ceq 'install') {
                    $sdk = Join-Path $env:FVM_CACHE_PATH ('versions/' + $Arguments[1])
                    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin'))
                    [void][IO.Directory]::CreateDirectory((Join-Path $sdk '.git'))
                    [IO.File]::WriteAllText((Join-Path $sdk 'bin/flutter.bat'), 'fixture sdk only')
                    return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
                }
                if ($Arguments[0] -ceq 'use') {
                    [void][IO.Directory]::CreateDirectory((Join-Path $Directory '.fvm'))
                    $target = Join-Path $env:FVM_CACHE_PATH ('versions/' + $Arguments[1])
                    $kind = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { 'Junction' } else { 'SymbolicLink' }
                    [void](New-Item -ItemType $kind -Path (Join-Path $Directory '.fvm/flutter_sdk') -Target $target)
                    return [pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}
                }
                if ($script:NativeFails) { return [pscustomobject]@{ExitCode=1;StdOut='';StdErr='fake initialization failure'} }
                return [pscustomobject]@{ExitCode=0;StdOut='{"frameworkVersion":"3.38.5"}';StdErr=''}
            }
        }
    }
    $beforeNativeFailure = [IO.File]::ReadAllText((Join-Path $project '.fvmrc'))
    Assert-HarmonyThrows { & $module { param($Project) Invoke-JobsNativeSdkFromHarmony -Target $Project } $project } 'native return initialization failure reported'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.fvmrc')) -ceq $beforeNativeFailure -and [string]@(Get-Item -LiteralPath (Join-Path $project '.fvm/flutter_sdk')).Target -ceq $sdk) 'failed OH-to-native initialization preserves complete OH binding'
    & $module { & $script:HarmonyManager { $script:NativeFails = $false } }
    & $module { param($Project) Invoke-JobsNativeSdkFromHarmony -Target $Project } $project
    $nativeConfig = Get-Content -LiteralPath (Join-Path $project '.fvmrc') -Raw | ConvertFrom-Json
    Assert-HarmonySdk ($nativeConfig.flutter -ceq '3.38.5' -and $nativeConfig.flutterUrl -ceq 'https://github.com/flutter/flutter.git' -and $nativeConfig.cachePath -ceq (Join-Path (Split-Path -Parent $cache) 'official')) 'OH-to-native return selects explicit official source and separate cache'
    Assert-HarmonySdk ($nativeConfig.custom.keep -eq $true -and $nativeConfig.flavors.dev -ceq '3.38.4') 'native return preserves user config fields'
    Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $project '.vscode/settings.json')) -ceq $beforeIde -and [IO.File]::ReadAllText((Join-Path $project '.gitignore')) -ceq $beforeIgnore) 'round-trip preserves live IDE and ignore'
    Assert-HarmonySdk ($env:FVM_CACHE_PATH -ceq $existingCache -and $env:FVM_FLUTTER_URL -ceq 'keep-existing-url' -and $env:FVM_USE_GIT_CACHE -ceq 'true' -and $env:PATH -ceq $pathBefore) 'native return restores inherited environment'
    Assert-HarmonyThrows { & $module { param($Project) Invoke-JobsNativeSdkFromHarmony -Target $Project } $project } 'native return route rejects unrelated native binding'
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"custom_unknown","flutterUrl":"https://example.invalid/fork.git"}')
    Assert-HarmonyThrows { & $module { param($Project) & $script:HarmonyManager { param($Path) Invoke-JobsFlutterVersionAction $Path } $Project } $project } 'native selector rejects unknown fork before toolchain operations'
    $menu = [IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/FlutterToolsMenu.h'))
    $actions = @([regex]::Matches($menu, '\{L"([^"]+)",') | ForEach-Object { $_.Groups[1].Value })
    Assert-HarmonySdk ($actions.Count -eq 14 -and $actions[4] -ceq 'sdk-manage' -and $actions[5] -ceq 'ohos-sdk-manage' -and $actions[6] -ceq 'package') 'menu order keeps native SDK and inserts OH immediately after it'
    foreach ($name in @('Action.psm1','Invoke.ps1','OpenCmd.ps1')) {
        Assert-HarmonySdk ([IO.File]::ReadAllText((Join-Path $root ('JobsFlutterTools/Scripts/' + $name))).Contains("'ohos-sdk-manage'")) ('dispatch whitelist includes OH: ' + $name)
    }
    $native = [IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ContextMenu.cpp'))
    Assert-HarmonySdk ($native.Contains('i < 8 || i == 10') -and $native.Contains('(i < 10 ? doctors : repairs)') -and $native.Contains('if (i == 10 &&')) 'all native submenu indices shifted together'
    foreach ($file in @('JobsFlutterTools/Scripts/HarmonySdk.psm1','JobsFlutterTools/Scripts/CheckHarmonySdk.ps1')) {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
        Assert-HarmonySdk (@($errors).Count -eq 0) ('PowerShell syntax: ' + $file)
        $bytes = [IO.File]::ReadAllBytes((Join-Path $root $file))
        Assert-HarmonySdk ($bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) ('PowerShell 5.1 UTF-8 BOM: ' + $file)
    }
    Write-Host ('PASS: ' + $script:count + ' OpenHarmony SDK assertions; no network or registry changes')
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
