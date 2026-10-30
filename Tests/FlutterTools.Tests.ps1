Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent $PSScriptRoot
$root = Join-Path $source 'JobsFlutterTools'
$count = 0
function Assert($value, $message) { $script:count++; if (-not $value) { throw $message } }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('JobsFlutterToolsTest-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try {
 $installer = Import-Module (Join-Path $root 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
 $manifest = & $installer { param($p) Get-JobsPackageManifest $p } $root
 Assert ($manifest.Id -ceq 'flutter-tools') 'single menu owner'
 $plan = @(& $installer { param($m,$t) Get-JobsPackageRegistryPlan -Manifest $m -ReleasePath $t -PowerShellPath 'powershell.exe' } $manifest $temp)
 Assert (@($plan | Where-Object Enabled).Count -eq 4) '3 registrations plus CLSID'
 Assert (@($plan | Where-Object { -not $_.Enabled }).Count -eq 64) 'retire exactly 8 legacy owners across 4 scopes and 2 handler types'
 Assert (@($plan | Group-Object Key | Where-Object Count -gt 1).Count -eq 0) 'no duplicate registry mutations'
 foreach ($row in $plan) { Assert ($row.Owner -ceq 'Jobs.WindowsExtension.v1') 'ownership protected'; Assert ($row.Key -notmatch 'open-terminal|android-simulator|harmony-simulator|clean-build-artifacts') 'unrelated registrations untouched' }
 $off = @(& $installer { param($m,$t) Get-JobsPackageRegistryPlan -Manifest $m -ReleasePath $t -PowerShellPath 'powershell.exe' -Enabled $false } $manifest $temp)
 Assert ($off.Count -eq 4 -and @($off | Where-Object Enabled).Count -eq 0) 'uninstall only unified group, does not resurrect old menus'
 $release = Join-Path $temp 'release'
 & $installer { param($p,$d) New-JobsPackageRelease -PackagePath $p -Destination $d } $root $release | Out-Null
 foreach ($path in @('Scripts/SetupVersion.json','Scripts/ProjectSetupLogTail.psm1','Scripts/ProjectSetup.psm1','Scripts/ProjectSetupRun.ps1','Scripts/ProjectSetupProcess.cs','Scripts/ProjectSetupProgress.psm1','Scripts/ProjectSetupWorker.ps1','Scripts/ProjectSetupDashboard.ps1','Scripts/FlutterProjectTools.dart','Scripts/Actions/run/Scripts/RunnerHost.cs','Scripts/Actions/extract/Scripts/ExtractFlutterDependencies.dart','Scripts/Actions/import-dependencies/Scripts/Action.psm1','Scripts/Actions/import-dependencies/Scripts/ImportFlutterDependencies.dart','Scripts/Actions/import-dependencies/Scripts/ExtractFlutterDependencies.dart','Scripts/Actions/import-dependencies/Scripts/Common.psm1','Scripts/Actions/import-dependencies/Extension.json','Scripts/Actions/android-support/Scripts/Action.psm1','Scripts/FlutterToolsMenu.h','Scripts/HarmonySdk.psm1','Scripts/CheckHarmonySdk.ps1')) {
  Assert ([IO.File]::Exists((Join-Path $release $path))) ('complete self-contained release: '+$path)
  Assert ((Get-FileHash (Join-Path $root $path)).Hash -eq (Get-FileHash (Join-Path $release $path)).Hash) ('copy integrity: '+$path)
 }
 $action = Import-Module (Join-Path $release 'Scripts/Action.psm1') -PassThru -DisableNameChecking
 $project = Join-Path $temp 'fixture project'
 [void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
 [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
 $blocked=$false;try { & $action { param($p) Get-JobsToolsFvm $p } $project } catch { $blocked=$true }
 Assert $blocked 'missing FVM blocks before global fallback'
 [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"harmony/3.22.0-ohos"}')
 [void][IO.Directory]::CreateDirectory((Join-Path $project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin'))
 foreach ($file in @('.fvm/flutter_sdk/bin/flutter.bat','.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe')) { [IO.File]::WriteAllText((Join-Path $project $file),'fixture only') }
 $binding = & $action { param($p) Get-JobsToolsFvm $p } $project
 Assert ($binding.Flutter -eq (Join-Path $project '.fvm/flutter_sdk/bin/flutter.bat')) 'same project Flutter'
 Assert ($binding.Dart -eq (Join-Path $project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe')) 'same project Dart'
 [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":[]}')
 $blocked=$false;try { & $action { param($p) Get-JobsToolsFvm $p } $project } catch { $blocked=$true }
 Assert $blocked 'invalid FVM config cannot be healthy'
 $entries = @(Get-Content (Join-Path $source 'Extensions.json') -Raw | ConvertFrom-Json)
 Assert (@($entries | Where-Object { $_.Id -like 'flutter-*' }).Count -eq 1) 'catalog has one Flutter owner'
 Write-Host "PASS: $count Windows packaging/dispatch assertions (no registry changes)"
} finally { Remove-Item -LiteralPath $temp -Recurse -Force }
