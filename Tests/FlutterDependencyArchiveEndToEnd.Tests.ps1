# FlutterDependencyArchiveEndToEnd.Tests.ps1 | 完整独立发布与真实Dart归档数据链。
# Created by Jobs on 2026年10月29日，星期四.
# 假工具版本/选择、真实文件复制与SHA校验；不联网、不安装SDK、不注册菜单。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$count=0
function Assert($Value,[string]$Message){$script:count++;if(-not$Value){throw $Message}}
function Assert-Throws([scriptblock]$Body,[string]$Message){$failed=$false;try{&$Body|Out-Null}catch{$failed=$true};Assert $failed $Message}
$dart=if($env:JOBS_TEST_DART){$env:JOBS_TEST_DART}else{(Get-Command dart -ErrorAction SilentlyContinue).Source}
if(-not$dart){throw '此数据链回归需要现有Dart，可通过JOBS_TEST_DART指定；不会自动安装。'}
$base=if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){[IO.Path]::GetTempPath()}else{'/private/tmp'}
$temp=Join-Path $base ('jobs-archive-published-chain-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$installer=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$package=Join-Path $temp '发布包 中文 & spaces'
&$installer {param($p,$d)New-JobsPackageRelease -PackagePath $p -Destination $d} (Join-Path $root 'JobsFlutterTools') $package|Out-Null
$module=Import-Module (Join-Path $package 'Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
$project=Join-Path $temp '项目 with spaces'
$target=Join-Path $project 'build/windows'
$output=Join-Path $temp 'exported'
foreach($directory in @($target,$output,(Join-Path $project 'lib'))){[void][IO.Directory]::CreateDirectory($directory)}
[IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
[IO.File]::WriteAllText((Join-Path $project 'pubspec.lock'),"packages: {}`n")
$artifact=Join-Path $target 'native fixture.bin'
[IO.File]::WriteAllBytes($artifact,[byte[]](0..255))
$expected=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash
try{
 &$module {
  param($base,$p,$cache,$output,$runtime)
  $script:fixtureRoot=$base;$script:fixtureProject=$p;$script:fixtureCache=$cache;$script:fixtureOutput=$output;$script:fixtureDart=$runtime
  $script:fixtureOperation='export';$script:fixtureSnapshot='';$script:fixtureAnswer='';$script:engineCalls=0
  $script:RealArchiveProcess=${function:Invoke-JobsSetupProcess}
  function script:Get-JobsInstallRoot{$script:fixtureRoot}
  function script:Test-JobsSetupInteractive{$true}
  function script:Read-Host{param($Prompt)if($Prompt.StartsWith('输入精确')){return $script:fixtureAnswer};return ''}
  function script:Get-JobsSetupFzf{param($p)'fixture-fzf'}
  function script:Get-JobsArchiveDart{param($p)$script:fixtureDart}
  function script:Read-JobsArchiveDirectory{param($Prompt,$Default,$MayBeMissing)if($script:fixtureOperation-ceq'import'){return $script:fixtureSnapshot};return $script:fixtureOutput}
  function script:Get-JobsArchiveCachePlan{param($Project,$Kind,$Fzf,$Manifest,[switch]$Import)[pscustomobject]@{Root=$script:fixtureCache;Platform='windows';ToolVersion='Flutter 3.29.3 arch windows_x64'}}
  function script:Invoke-JobsSetupProcess{
   param($File,[string[]]$Arguments,$Directory,$TimeoutSeconds)
   $script:engineCalls++
   $result=&$script:RealArchiveProcess $File $Arguments $Directory $TimeoutSeconds
   if($Arguments[1]-ceq'export'-and'--check'-cnotin$Arguments){if($result.StdOut-match'(?m)^ARCHIVE_DIRECTORY=([^\r\n]+)'){$script:fixtureSnapshot=$Matches[1]}}
   return $result
  }
 } $temp $project $target $output $dart
 &$module {param($p)Invoke-JobsProjectDependencyArchiveAction $p export-native-dependencies} $project
 $snapshot=&$module{$script:fixtureSnapshot}
 Assert ([IO.File]::Exists((Join-Path $snapshot 'manifest.json'))) '已发布wrapper+真实引擎产生快照'
 Assert ((Get-FileHash -LiteralPath (Join-Path $snapshot 'payload/native fixture.bin') -Algorithm SHA256).Hash-ceq$expected) '导出payload逐字节一致'
 $manifest=Get-Content -LiteralPath (Join-Path $snapshot 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($manifest.kind-ceq'native'-and$manifest.platform-ceq'windows'-and$manifest.toolVersion-ceq'Flutter 3.29.3 arch windows_x64') '跨层元数据来自明确本次计划'
 Assert ((&$module{$script:engineCalls})-eq2) '导出预检+实际执行两次独立引擎调用'
 [IO.File]::Delete($artifact)
 &$module{$script:fixtureOperation='import';$script:fixtureAnswer='';$script:engineCalls=0}
 Assert-Throws{&$module{param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies}$project} '真实导入预检后取消传播'
 Assert (-not[IO.File]::Exists($artifact)) '未YES前没有恢复文件'
 Assert ((&$module{$script:engineCalls})-eq1) '取消仅执行只读引擎预检'
 &$module{$script:fixtureAnswer='YES';$script:engineCalls=0}
 &$module{param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies}$project
 Assert ((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash-ceq$expected) '大写YES后真实恢复原字节'
 Assert ((&$module{$script:engineCalls})-eq2) '导入确认前后均全量校验'
 [IO.File]::WriteAllText($artifact,'local different file')
 &$module{$script:engineCalls=0}
 Assert-Throws{&$module{param($p)Invoke-JobsProjectDependencyArchiveAction $p import-native-dependencies}$project} '真实同名不同内容拒绝'
 Assert ([IO.File]::ReadAllText($artifact)-ceq'local different file') '冲突不会覆盖本地文件'
 Assert ((&$module{$script:engineCalls})-eq1) '冲突预检失败不进入写入'
 $shell=(Get-Process -Id $PID).Path
 foreach($action in @('android-dependencies','export-native-dependencies','import-gradle-dependencies')){
  $text=@(&$shell -NoLogo -NoProfile -File (Join-Path $package 'Scripts/Invoke.ps1') -Target $project -Action $action -Check 2>&1)-join"`n"
  Assert ($LASTEXITCODE-eq0-and$text-match'只读') ('完整发布CLI只读参数能抵达对应业务：'+$action)
 }
 Assert ([IO.File]::ReadAllText($artifact)-ceq'local different file') '所有CLI Check均未修改工程数据'
 Write-Host ('PASS: FlutterDependencyArchiveEndToEnd.Tests.ps1 ('+$count+' assertions; published Windows wrapper and real Dart on '+[Environment]::OSVersion.Platform+'; not Windows native UI)')
}finally{
 Remove-Module $module -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $temp -Recurse -Force
}
