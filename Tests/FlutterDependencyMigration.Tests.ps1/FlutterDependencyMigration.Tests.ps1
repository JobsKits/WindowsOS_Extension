# FlutterDependencyMigration.Tests.ps1 | 隔离验证终端选择、ZIP 证据与融合确认。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$count = 0
function Assert($Value,[string]$Message) { $script:count++; if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Body,[string]$Message) { $failed=$false;try { &$Body | Out-Null } catch { $failed=$true }; Assert $failed $Message }
$tempBase = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [IO.Path]::GetTempPath() } else { '/private/tmp' }
$temp = Join-Path $tempBase ('JobsMigrationTests-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$module = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/FlutterDependencyMigration.psm1/FlutterDependencyMigration.psm1') -PassThru -DisableNameChecking
try {
    $bundle = Join-Path $temp 'bundle with 空格'
    [void][IO.Directory]::CreateDirectory((Join-Path $bundle '.hidden'))
    [IO.File]::WriteAllText((Join-Path $bundle '.hidden/value.txt'),'private-source-bytes')
    [IO.File]::WriteAllText((Join-Path $bundle 'manifest.json'),'{}')
    $zip = &$module { param($p) Compress-JobsMigrationBundle $p } $bundle
    Assert ([IO.File]::Exists($zip)) '生成真实 ZIP'
    &$module { param($p,$z) Assert-JobsMigrationZip $p $z } $bundle $zip
    Assert $true '逐文件校验包含隐藏目录'
    Assert-Throws { &$module { param($p) Compress-JobsMigrationBundle $p } $bundle } '已有 ZIP 不覆盖'
    [IO.File]::WriteAllText((Join-Path $bundle '.hidden/value.txt'),'changed')
    Assert-Throws { &$module { param($p,$z) Assert-JobsMigrationZip $p $z } $bundle $zip } '产物变动拒绝删除'
    Assert ([IO.File]::Exists((Join-Path $bundle '.hidden/value.txt'))) '失败仍保留原目录'
    $drag = '"' + $bundle + '"'
    Assert ((&$module {param($p)ConvertFrom-JobsMigrationPath $p} $drag) -ceq $bundle) '引号路径按数据解析'
    Assert-Throws { &$module { ConvertFrom-JobsMigrationPath '$(touch bad)' } } '不执行命令表达式'
    $project = Join-Path $temp 'project'
    $destination = Join-Path $temp 'output'
    $raw = Join-Path $temp 'renamed-cache'
    foreach($path in @($project,$destination,$raw)) { [void][IO.Directory]::CreateDirectory($path) }
    &$module {
        param($t)
        $script:realMigrationDart=${function:Get-JobsMigrationDart}
        $script:fixture=$t
        $script:answers=New-Object 'Collections.Generic.Queue[string]'
        $script:calls=New-Object 'Collections.Generic.List[string]'
        $script:failPreview=$false
        $script:omitPlan=$false
        $script:created=''
        function script:Read-JobsMigrationLine {
            param($Prompt)
            if ($script:answers.Count-eq0) { throw ('fixture exhausted: '+$Prompt) }
            return $script:answers.Dequeue()
        }
        function script:Get-JobsMigrationDart {param($p)'fixture-dart'}
        function script:Invoke-JobsMigrationEngine {
            param($Dart,[string[]]$Arguments,$Project)
            $script:calls.Add(($Arguments-join '|'))
            if ($Arguments[0]-eq'import') {
                if ($script:failPreview) { throw 'fixture conflict' }
                if ($script:omitPlan) { return 'missing marker' }
                return 'JOBS_MIGRATION_PLAN=' + ('0' * 64)
            }
            $script:created=Join-Path (Join-Path $script:fixture 'output') ('created-'+[guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($script:created)
            [IO.File]::WriteAllText((Join-Path $script:created 'manifest.json'),'{}')
            [IO.File]::WriteAllText((Join-Path $script:created '.private'),'payload')
            return 'JOBS_MIGRATION_OUTPUT='+$script:created
        }
    } $temp
    &$module {param($p,$d)$script:answers.Clear();foreach($a in @('','',$d,'skip')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p export-all-dependencies} $project $destination
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq1 -and $calls[0]-notlike '*--all*') '空回车默认私库'
    $created=&$module {$script:created}
    Assert ([IO.Directory]::Exists($created)-and-not[IO.File]::Exists($created+'.zip')) '非空不打包，保留目录'
    &$module {param($p,$d)$script:calls.Clear();foreach($a in @('',' ',$d,'','')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p export-all-dependencies} $project $destination
    $calls=@(&$module {$script:calls.ToArray()});$created=&$module {$script:created}
    Assert ($calls.Count-eq1 -and $calls[0].EndsWith('|--all')) '空格也明确全提取'
    Assert ([IO.Directory]::Exists($created)-and[IO.File]::Exists($created+'.zip')) '空回车 ZIP 且空回车不删除'
    &$module {param($p,$d)$script:calls.Clear();foreach($a in @('','',$d,'','delete')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p export-all-dependencies} $project $destination
    $created=&$module {$script:created}
    Assert (-not[IO.Directory]::Exists($created)-and[IO.File]::Exists($created+'.zip')) '明确非空只删除本次已验证产物'
    Assert ([IO.Directory]::Exists($bundle)) '其它目录不受删除影响'
    &$module {param($p,$s)$script:calls.Clear();foreach($a in @('','',$s,'')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $project $raw
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq1 -and $calls[0]-notlike '*--apply*') '原始重命名缓存传给预检，空输入重问，非YES零apply'
    &$module {param($p,$s)$script:calls.Clear();foreach($a in @('',$s,'YES')){$script:answers.Enqueue($a)};Invoke-JobsFlutterMigration $p import-all-dependencies} $project $raw
    $calls=@(&$module {$script:calls.ToArray()})
    Assert ($calls.Count-eq2 -and $calls[1].EndsWith('|--apply|--expected-plan|'+('0'*64))) 'YES才执行融合'
    &$module {param($s)$script:calls.Clear();$script:failPreview=$true;foreach($a in @('',$s)){$script:answers.Enqueue($a)}} $raw
    Assert-Throws { &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project } '预检冲突停止'
    Assert ((&$module {$script:calls.Count})-eq1) '预检冲突无apply'
    &$module {param($s)$script:calls.Clear();$script:failPreview=$false;$script:omitPlan=$true;foreach($a in @('',$s)){$script:answers.Enqueue($a)}} $raw
    Assert-Throws { &$module {param($p)Invoke-JobsFlutterMigration $p import-all-dependencies} $project } '缺少计划指纹拒绝进入YES'
    Assert ((&$module {$script:calls.Count})-eq1) '计划指纹缺失无apply'
    &$module {$script:answers.Clear();$script:answers.Enqueue('cancel');$script:calls.Clear()}
    &$module {param($p)Invoke-JobsFlutterMigration $p export-all-dependencies} $project
    Assert ((&$module {$script:calls.Count})-eq0) '首屏取消无引擎调用'
    $extract = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Actions/extract/Scripts/Action.psm1') -PassThru -DisableNameChecking
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.dart_tool'))
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.lock'),'fixture-lock')
    [IO.File]::WriteAllText((Join-Path $project '.dart_tool/package_config.json'),'{}')
    &$extract {
        param($t)
        $script:scopeFixture=$t
        $script:scope=''
        $script:scopeArguments=@()
        function script:Show-JobsExtractorIntro {$true}
        function script:Get-JobsInstallRoot {$script:scopeFixture}
        function script:Get-JobsExtractorDesktop {$script:scopeFixture}
        function script:Find-JobsExtractorDart {param($p)'fixture.exe'}
        function script:Read-Host {param($Prompt) if($Prompt -like '*只提取私库*') {return $script:scope}; return ''}
        function script:Invoke-JobsProcess {
            param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds)
            $script:scopeArguments=@($Arguments)
            [pscustomobject]@{StdOut='fixture complete';StdErr='';ExitCode=0}
        }
    } $temp
    &$extract {param($p)Invoke-JobsFlutterDependencyAction $p} $project
    Assert ((&$extract {'--private-only' -in $script:scopeArguments})) '普通 Pub 提取空回车默认私库'
    &$extract {$script:scope=' '}
    &$extract {param($p)Invoke-JobsFlutterDependencyAction $p} $project
    Assert ((&$extract {'--private-only' -notin $script:scopeArguments})) '普通 Pub 提取空格显式全提取'
    Remove-Module $extract -ErrorAction SilentlyContinue
    $native=Join-Path $temp 'native-dart.exe'
    $header=New-Object byte[] 128
    $header[0]=0x4D;$header[1]=0x5A;$header[0x3C]=0x40;$header[0x40]=0x50;$header[0x41]=0x45;$header[0x44]=0x64;$header[0x45]=0x86
    [IO.File]::WriteAllBytes($native,$header)
    &$module {
        param($exe,$t)
        $script:fixtureNative=$exe
        $script:probeCalls=New-Object 'Collections.Generic.List[string]'
        function script:Get-Command {
            param($Name,$CommandType,[switch]$All,$ErrorAction)
            @([pscustomobject]@{Source=(Join-Path $script:fixture 'flutter/bin/dart.bat')},[pscustomobject]@{Source=$script:fixtureNative},[pscustomobject]@{Source='ignored.sh'})
        }
    } $native $temp
    $candidates=@(&$module {Get-JobsMigrationSystemDartCandidates})
    Assert ($candidates.Count-eq2 -and $candidates[0].EndsWith('cache/dart-sdk/bin/dart.exe')-and$candidates[1]-ceq$native) '系统Dart候选只取原生exe或Flutter shim旁原生文件，不执行bat'
    &$module {
        function script:Get-JobsMigrationSystemDartCandidates {$script:fixtureNative}
        function script:Invoke-JobsProcess {
            param($FilePath,$Arguments,$WorkingDirectory,$TimeoutSeconds)
            $script:probeCalls.Add($FilePath+'|'+($Arguments-join '|'))
            [pscustomobject]@{StdOut='Dart SDK version: 3.9.0';StdErr='';ExitCode=0}
        }
    }
    $selected=&$module {param($p)&$script:realMigrationDart $p} $project
    Assert ($selected-ceq$native) '缺少FVM时通过真实PE头校验后复用已有系统Dart'
    Assert ((&$module {$script:probeCalls.Count-eq1-and$script:probeCalls[0].EndsWith('|--version')})) '只体检原生Dart，不运行shim或安装命令'
    Write-Host ('PASS: FlutterDependencyMigration.Tests.ps1 ('+$count+' assertions; no user cache writes)')
} finally { Remove-Module $module -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $temp -Recurse -Force }
