# FlutterDependencyMigrationEndToEnd.Tests.ps1 | 真实发布副本、Dart 读写和 ZIP 往返。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$count=0
function Assert($Value,[string]$Message){$script:count++;if(-not$Value){throw $Message}}
function Assert-Throws([scriptblock]$Body,[string]$Message){$failed=$false;try{&$Body|Out-Null}catch{$failed=$true};Assert $failed $Message}
function ConvertTo-FixtureUri([string]$Path){$builder=New-Object UriBuilder;$builder.Scheme='file';$builder.Host='';$builder.Port=-1;$builder.Path=$Path.TrimEnd('\','/')+'/';return $builder.Uri.AbsoluteUri}
function Write-Fixture([string]$Path,[string]$Value){[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path));[IO.File]::WriteAllText($Path,$Value)}
$dart=if($env:JOBS_TEST_DART){$env:JOBS_TEST_DART}else{(Get-Command dart -ErrorAction Stop).Source}
$tempBase=if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){[IO.Path]::GetTempPath()}else{'/private/tmp'}
$temp=Join-Path $tempBase ('JobsMigrationPublished-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$saved=@{}
foreach($name in @('PUB_CACHE','GRADLE_USER_HOME','MAVEN_REPO_LOCAL')){$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
$module=$null
try{
    $package=Join-Path $temp 'copied-release'
    $installer=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    &$installer {param($p,$d)New-JobsPackageRelease -PackagePath $p -Destination $d} (Join-Path $root 'JobsFlutterTools') $package | Out-Null
    foreach($path in @('Scripts/FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1','Scripts/FlutterDependencyMigration.dart','Scripts/ExtractFlutterDependencies.dart','Scripts/ImportFlutterDependencies.dart')){
        Assert ((Get-FileHash -LiteralPath (Join-Path $package $path)).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root ('JobsFlutterTools/'+$path))).Hash) ('独立发布完整性：'+$path)
    }
    $module=Import-Module (Join-Path $package 'Scripts/FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1') -PassThru -DisableNameChecking
    $project=Join-Path $temp 'source 工程'
    $target=Join-Path $temp 'target 工程'
    $output=Join-Path $temp 'output'
    $donor=Join-Path $temp 'donor'
    $sourcePub=Join-Path $donor 'renamed dart'
    $sourceGradle=Join-Path $donor 'renamed android'
    $targetPub=Join-Path $temp 'environment/pub'
    $targetGradle=Join-Path $temp 'environment/gradle'
    $spec="name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n  alpha:`n    git: https://private.invalid/alpha.git`n  beta: ^1.0.0`n"
    Write-Fixture (Join-Path $project 'pubspec.yaml') $spec
    Write-Fixture (Join-Path $target 'pubspec.yaml') $spec
    Write-Fixture (Join-Path $project 'pubspec.lock') "packages:`n  alpha:`n    source: git`n    version: '1.0.0'`n  beta:`n    description:`n      name: beta`n      url: https://pub.dev`n    source: hosted`n    version: '1.0.0'`n  flutter:`n    source: sdk`n    version: '0.0.0'`n"
    $alpha=Join-Path $sourcePub 'git/alpha-ref'
    $beta=Join-Path $sourcePub 'hosted/pub.dev/beta-1.0.0'
    $flutter=Join-Path $temp 'fake-flutter'
    Write-Fixture (Join-Path $alpha 'pubspec.yaml') "name: alpha`nversion: 1.0.0`n"
    Write-Fixture (Join-Path $alpha 'lib/alpha.dart') '// private alpha'
    Write-Fixture (Join-Path $beta 'pubspec.yaml') "name: beta`nversion: 1.0.0`n"
    Write-Fixture (Join-Path $beta 'lib/beta.dart') '// public beta'
    Write-Fixture (Join-Path $flutter 'pubspec.yaml') "name: flutter`nversion: 0.0.0`n"
    $config=@{configVersion=2;packages=@(@{name='fixture';rootUri=(ConvertTo-FixtureUri $project)},@{name='alpha';rootUri=(ConvertTo-FixtureUri $alpha)},@{name='beta';rootUri=(ConvertTo-FixtureUri $beta)},@{name='flutter';rootUri=(ConvertTo-FixtureUri $flutter)})}|ConvertTo-Json -Depth 6
    Write-Fixture (Join-Path $project '.dart_tool/package_config.json') $config
    Write-Fixture (Join-Path $project 'android/build.gradle.kts') "repositories { maven { url = uri(`"https://private.invalid/maven`"); content { includeGroup(`"private.group`") } } }"
    foreach($relative in @('pubspec.lock','android/build.gradle.kts')) { Write-Fixture (Join-Path $target $relative) ([IO.File]::ReadAllText((Join-Path $project $relative))) }
    $privateJar='caches/modules-2/files-2.1/private.group/sdk/1/hash/sdk.jar'
    $publicJar='caches/modules-2/files-2.1/public.group/sdk/1/hash/sdk.jar'
    Write-Fixture (Join-Path $sourceGradle $privateJar) 'private-jar'
    Write-Fixture (Join-Path $sourceGradle $publicJar) 'public-jar'
    Write-Fixture (Join-Path $sourceGradle 'gradle.properties') 'do not copy credential'
    Write-Fixture (Join-Path $sourcePub 'credentials.json') 'do not copy credential'
    [void][IO.Directory]::CreateDirectory($output)
    $env:PUB_CACHE=$sourcePub;$env:GRADLE_USER_HOME=$sourceGradle;$env:MAVEN_REPO_LOCAL=Join-Path $temp 'source-maven'
    &$module {
        param($runtime)
        $script:testDart=$runtime
        $script:answers=New-Object 'Collections.Generic.Queue[string]'
        $script:mutateSource=''
        function script:Get-JobsMigrationDart {param($p)$script:testDart}
        function script:Read-JobsMigrationLine {param($Prompt)if($script:answers.Count-eq0){throw ('fixture exhausted: '+$Prompt)};if($script:mutateSource -and $Prompt -like '*大写 YES*'){[IO.File]::WriteAllText($script:mutateSource,'changed during confirmation')};$script:answers.Dequeue()}
    } $dart
    &$module {param($p,$d)foreach($a in @('','',$d,'','')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p export-all-dependencies} $project $output
    $bundles=@(Get-ChildItem -LiteralPath $output -Directory)
    Assert ($bundles.Count-eq1) '真实引擎默认私库产生唯一完整产物'
    $bundle=$bundles[0].FullName
    Assert ([IO.File]::Exists((Join-Path $bundle 'migration.json'))-and[IO.File]::Exists($bundle+'.zip')) '完整清单及真实ZIP存在'
    $manifest=Get-Content -LiteralPath (Join-Path $bundle 'migration.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($manifest.scope-ceq'private-candidates') '私库默认值抵达真实引擎'
    Assert ([IO.File]::Exists((Join-Path $bundle ('payload/gradle/'+$privateJar)))-and-not[IO.File]::Exists((Join-Path $bundle ('payload/gradle/'+$publicJar)))) '私有Maven组有证据提取，公共组不提取'
    $env:PUB_CACHE=$targetPub;$env:GRADLE_USER_HOME=$targetGradle;$env:MAVEN_REPO_LOCAL=Join-Path $temp 'environment/maven'
    &$module {param($p,$s)foreach($a in @('',$s,'')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $bundle
    Assert (-not[IO.Directory]::Exists($targetGradle)-and-not[IO.Directory]::Exists((Join-Path $target 'vendor'))) '真实预检取消零写入'
    &$module {param($p,$s)foreach($a in @('',$s,'YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $bundle
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $privateJar))-ceq'private-jar') '真实原生缓存融合保留原字节'
    Assert ([IO.File]::ReadAllText((Join-Path $target 'pubspec_overrides.yaml'))-match'alpha') '真实Pub私库恢复本地相对覆盖'
    &$module {param($p,$s)foreach($a in @('',$s,'YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $target $donor
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'public-jar') '改名原始Gradle目录按内容识别融合'
    Assert ([IO.File]::ReadAllText((Join-Path $targetPub 'hosted/pub.dev/beta-1.0.0/lib/beta.dart'))-ceq'// public beta') '改名原始Pub目录按内容识别融合'
    Assert (-not[IO.File]::Exists((Join-Path $targetGradle 'gradle.properties'))-and-not[IO.File]::Exists((Join-Path $targetPub 'credentials.json'))) '原始缓存认证文件未迁移'
    $changing='caches/modules-2/files-2.1/private.group/new/1/hash/new.jar'
    Write-Fixture (Join-Path $sourceGradle $changing) 'before confirmation'
    &$module {param($s,$f)$script:mutateSource=$f;foreach($a in @('',$s,'YES')){$script:answers.Enqueue($a)}} $donor (Join-Path $sourceGradle $changing)
    Assert-Throws {&$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $target} '确认期间源文件变化，真实计划指纹阻断写入'
    Assert (-not[IO.File]::Exists((Join-Path $targetGradle $changing))) '变化后的新文件未写入目标'
    &$module {$script:mutateSource=''}
    Write-Fixture (Join-Path $targetGradle $publicJar) 'local conflict'
    &$module {param($s)$script:answers.Enqueue('');$script:answers.Enqueue($s)} $donor
    Assert-Throws {&$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $target} '真实同名异内容预检拒绝'
    Assert ([IO.File]::ReadAllText((Join-Path $targetGradle $publicJar))-ceq'local conflict') '真实冲突原文件保留'
    Write-Host ('PASS: FlutterDependencyMigrationEndToEnd.Tests.ps1 ('+$count+' assertions; real Dart/copied Windows release on '+[Environment]::OSVersion.Platform+'; not Windows native UI)')
} finally {
    foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
    if($module){Remove-Module $module -ErrorAction SilentlyContinue}
    Remove-Item -LiteralPath $temp -Recurse -Force
}
