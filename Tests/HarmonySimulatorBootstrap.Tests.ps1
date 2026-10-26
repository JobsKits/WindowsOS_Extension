# SDL 工具依赖隔离回归；不联网、不注册、不运行真实 Emulator。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot '../JobsHarmonySimulatorCreator/Scripts/Action.psm1') -PassThru -DisableNameChecking -Force
$script:assertions = 0
function Assert-Tools { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Assert-ToolsThrows { param([scriptblock]$Body, [string]$Pattern); $caught = ''; try { & $Body | Out-Null } catch { $caught = $_.Exception.Message }; Assert-Tools ($caught -match $Pattern) ('Expected ' + $Pattern + '; got ' + $caught) }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('JobsHarmonyBootstrap-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('LOCALAPPDATA','HARMONY_EMULATOR_BIN','DEVECO_STUDIO_HOME','TOOL_HOME','HARMONY_CLT_ARCHIVE','PROCESSOR_ARCHITECTURE','PROCESSOR_ARCHITEW6432','ProgramFiles','ProgramFiles(x86)')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    [void][IO.Directory]::CreateDirectory($temp)
    $env:LOCALAPPDATA = Join-Path $temp 'Local 中文 & space'
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'; $env:PROCESSOR_ARCHITEW6432 = $null
    $env:HARMONY_EMULATOR_BIN = $null; $env:DEVECO_STUDIO_HOME = $null; $env:TOOL_HOME = $null
    $env:HARMONY_CLT_ARCHIVE = $null; $env:ProgramFiles = $null; ${env:ProgramFiles(x86)} = $null
    $realPackage = & $module { Get-JobsHarmonyToolPackage }
    Assert-Tools ($realPackage.Url -ceq 'https://libsdl.org/harmonyos-devtools/commandline-tools-windows-x64-6.1.1.280.zip') 'Windows x64 SDL source'
    Assert-Tools ($realPackage.Size -eq 2601671927) 'Package size uses Int64'
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    function New-FixtureZip {
        param([string[]]$Names = @('command-line-tools/version.txt','command-line-tools/emulator/Emulator.exe'), [switch]$Symlink)
        $file = Join-Path $temp ([guid]::NewGuid().ToString('N') + '.zip')
        $zip = [IO.Compression.ZipFile]::Open($file, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Names) {
                $entry = $zip.CreateEntry($name)
                if ($Symlink) { $entry.ExternalAttributes = -1577058304 }
                $writer = New-Object IO.StreamWriter($entry.Open())
                try { $writer.Write('fixture') } finally { $writer.Dispose() }
            }
        } finally { $zip.Dispose() }
        return $file
    }
    $archive = New-FixtureZip
    $package = [pscustomobject]@{Version='fixture';Url=$realPackage.Url;Size=(Get-Item -LiteralPath $archive).Length;Sha256=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash}
    & $module {
        param($Package, $Archive)
        $script:FixturePackage = $Package; $script:FixtureArchive = $Archive; $script:Downloads = 0; $script:Probes = 0; $script:FailDownload = $false; $script:FailProbe = $false
        function script:Get-JobsHarmonyToolPackage { return $script:FixturePackage }
        function script:Get-Command { return @() }
        function script:Receive-JobsHarmonyToolArchive {
            param($Package, $Destination)
            $script:Downloads++
            if ($script:FailDownload) { throw 'fixture download failure' }
            Copy-Item -LiteralPath $script:FixtureArchive -Destination $Destination
        }
        function script:Assert-JobsHarmonyCapabilities {
            param($Emulator)
            $script:Probes++
            if ($script:FailProbe) { throw 'fixture incompatible tool' }
            if (-not [IO.File]::Exists($Emulator)) { throw 'fixture missing executable' }
        }
    } $package $archive
    Assert-ToolsThrows { & $module { Get-JobsHarmonyEmulator } } '只读 Check 不安装'
    Assert-Tools (-not [IO.Directory]::Exists($env:LOCALAPPDATA)) 'Readonly discovery does not write'
    $installed = & $module { Get-JobsHarmonyEmulator -InstallMissing }
    Assert-Tools ([IO.File]::Exists($installed)) 'SDL install publishes complete tool'
    Assert-Tools ((& $module { $script:Downloads }) -eq 1) 'Missing tool downloads once'
    Assert-Tools ((& $module { Get-JobsHarmonyEmulator -InstallMissing }) -ceq $installed) 'Next run reuses managed tool'
    Assert-Tools ((& $module { $script:Downloads }) -eq 1) 'Healthy tool does not redownload'
    $toolsDirectory = & $module { Get-JobsHarmonyToolsHome }
    Assert-Tools (@(Get-ChildItem -LiteralPath $toolsDirectory -Force -Filter '.install-*').Count -eq 0) 'Successful install cleans staging'
    $env:HARMONY_EMULATOR_BIN = Join-Path $temp 'missing.exe'
    Assert-ToolsThrows { & $module { Get-JobsHarmonyEmulator -InstallMissing } } '指定 Emulator 不存在'
    Assert-Tools ((& $module { $script:Downloads }) -eq 1) 'Explicit invalid tool does not download'
    $env:HARMONY_EMULATOR_BIN = $null
    $env:HARMONY_CLT_ARCHIVE = $archive
    $other = & $module { Install-JobsHarmonyTools }
    Assert-Tools ($other -cne $installed -and [IO.File]::Exists($installed)) 'Second install preserves original directory'
    Assert-Tools ((& $module { $script:Downloads }) -eq 1) 'Local ZIP avoids network'
    Assert-Tools ([IO.File]::Exists($archive)) 'Local ZIP is retained'
    Assert-ToolsThrows { & $module { Get-JobsHarmonyEmulator -InstallMissing } } '多份兼容'
    $badPackage = [pscustomobject]@{Size=$package.Size+1;Sha256=$package.Sha256}
    Assert-ToolsThrows { & $module { param($File,$Dest,$Package) Expand-JobsHarmonyToolArchive $File $Dest $Package } $archive (Join-Path $temp 'bad-size') $badPackage } '大小不符'
    $badPackage.Size = $package.Size; $badPackage.Sha256 = ('0' * 64)
    Assert-ToolsThrows { & $module { param($File,$Dest,$Package) Expand-JobsHarmonyToolArchive $File $Dest $Package } $archive (Join-Path $temp 'bad-hash') $badPackage } 'SHA-256 不符'
    foreach ($names in @(
        @('command-line-tools/../../escape'), @('/absolute'), @('command-line-tools/file:stream'),
        @('command-line-tools/CON'), @('command-line-tools/dir./file'), @('command-line-tools/one','command-line-tools/ONE')
    )) {
        $malicious = New-FixtureZip -Names $names
        $metadata = [pscustomobject]@{Size=(Get-Item -LiteralPath $malicious).Length;Sha256=(Get-FileHash -LiteralPath $malicious -Algorithm SHA256).Hash}
        $destination = Join-Path $temp ([guid]::NewGuid().ToString('N'))
        Assert-ToolsThrows { & $module { param($File,$Dest,$Package) Expand-JobsHarmonyToolArchive $File $Dest $Package } $malicious $destination $metadata } '不安全|保留路径'
        Assert-Tools (-not [IO.Directory]::Exists($destination)) 'Invalid ZIP is rejected before extraction'
    }
    $link = New-FixtureZip -Symlink
    $metadata = [pscustomobject]@{Size=(Get-Item -LiteralPath $link).Length;Sha256=(Get-FileHash -LiteralPath $link -Algorithm SHA256).Hash}
    Assert-ToolsThrows { & $module { param($File,$Dest,$Package) Expand-JobsHarmonyToolArchive $File $Dest $Package } $link (Join-Path $temp 'symlink') $metadata } '符号链接'
    & $module { $script:FailProbe = $true }
    Assert-ToolsThrows { & $module { Install-JobsHarmonyTools } } 'incompatible'
    Assert-Tools (@(Get-ChildItem -LiteralPath $toolsDirectory -Force -Filter '.install-*').Count -eq 0) 'Failed probe cleans staging'
    Assert-Tools (@(Get-ChildItem -LiteralPath $toolsDirectory -Directory -Filter 'clt-*').Count -eq 2) 'Failed probe never publishes'
    $env:HARMONY_CLT_ARCHIVE = $null
    & $module { $script:FailProbe = $false; $script:FailDownload = $true }
    Assert-ToolsThrows { & $module { Install-JobsHarmonyTools } } 'download failure'
    Assert-Tools (@(Get-ChildItem -LiteralPath $toolsDirectory -Force -Filter '.install-*').Count -eq 0) 'Download failure cleans staging'
    Assert-Tools ([IO.File]::Exists($installed)) 'Failures preserve existing tools'
    Write-Host ('PASS: HarmonySimulatorBootstrap.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
