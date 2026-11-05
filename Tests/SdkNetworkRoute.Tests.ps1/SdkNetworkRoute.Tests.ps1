# 网络选路隔离回归；新探测传输入口全部由假响应替代，禁止真实网络。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'JobsFlutterTools/Scripts/SdkDownloadRoute.ps1/SdkDownloadRoute.ps1')
$script:checks=0;$script:batches=0;$script:mode='normal';$script:requests=@();$script:configured=@();$script:logs=New-Object 'Collections.Generic.List[string]'
function Assert-Route([bool]$Condition,[string]$Message){$script:checks++;if(-not$Condition){throw $Message}}
function script:Get-JobsSdkConfiguredProxies {return $script:configured}
function script:Get-JobsSdkNativeWindowsProxy {param($Uri)return [pscustomobject]@{Mode='native-wininet';Url='http://existing.corp:8080'}}
function script:Write-JobsSdkRouteMessage {param($Text)$script:logs.Add((Protect-JobsSdkRouteText $Text))}
function script:Invoke-JobsSdkRouteProbeBatch {
    param($Requests,$Environment,$Directory)
    $script:batches++;$script:requests=@($Requests)
    $responses=@()
    foreach($request in $Requests){
        $bytes=New-Object byte[] 16384;for($i=0;$i-lt$bytes.Length;$i++){$bytes[$i]=90};$bytes[0]=80;$bytes[1]=75;$bytes[2]=3;$bytes[3]=4
        $size=203538812;$etag='0'*32;$status='206';$exitCode=0;$speed=if(([Uri]$request.Uri).Host-ceq'storage.flutter-io.cn'){1048576}else{32768}
        $headers="Content-Range: bytes 0-16383/$size`r`nETag: `"$etag`"`r`nContent-Type: application/zip`r`n"
        if($script:mode-ceq'a-large-fails'){$speed=if(([Uri]$request.Uri).Host-ceq'storage.googleapis.com'){2097152}else{32768}}
        if($request.Proxy.Mode-ceq'configured-proxy'){$speed=2097152}
        if($request.Kind-ceq'object-metadata'){
            $bytes=[Text.Encoding]::UTF8.GetBytes('{"size":"203538812","md5Hash":"AAAAAAAAAAAAAAAAAAAAAA=="}')
            $status='200';$headers='Content-Type: application/json'
        }
        if($script:mode-ceq'bad200'-and$request.Kind-ne'object-metadata'){$status='200'}
        if($script:mode-ceq'html'-and$request.Kind-ne'object-metadata'){$bytes[0]=60;$bytes[1]=104}
        if($script:mode-ceq'mismatch'-and([Uri]$request.Uri).Host-ceq'storage.flutter-io.cn'){$bytes[5]=65}
        if($script:mode-in@('metadata-only','unverified-mirror')-and$request.Kind-ne'object-metadata'-and([Uri]$request.Uri).Host-ceq'storage.googleapis.com'){$bytes=[byte[]]@();$exitCode=28;$speed=0}
        if($script:mode-ceq'unverified-mirror'-and$request.Kind-ceq'object-metadata'){$bytes=[byte[]]@();$exitCode=28;$speed=0}
        $metrics=$status+'|127.0.0.1|0.01|0.02|0.04|0.05|0.2|'+$bytes.Length+'|'+$speed+'|'+$request.Uri+'|0'
        $responses+=[pscustomobject]@{Request=$request;ExitCode=$exitCode;Metrics=$metrics;Error='';Headers=$headers;Body=$bytes}
    }
    return $responses
}
$uri='https://storage.googleapis.com/flutter_infra_release/flutter/'+('a'*40)+'/dart-sdk-windows-x64.zip'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsSdkNetworkUnit-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
try{
    $global:JobsFlutterSdkRouteCache=@{}
    $route=Get-JobsFlutterSdkRoute $uri 'Flutter3.38.4 / engine-a / windows-x64' @{} -PublicObject $true
    Assert-Route ($route.Ready-and$route.Verified-and([Uri]$route.Uri).Host-ceq'storage.flutter-io.cn') '相同真实制品证据下选择更快CFUG'
    Assert-Route ($script:requests.Count-eq3-and$route.Environment['FLUTTER_STORAGE_BASE_URL']-ceq'https://storage.flutter-io.cn') '官方/CFUG及官方对象元数据并行参与'
    Assert-Route (-not$route.Environment.Contains('PUB_HOSTED_URL')) '不依据SDK测速擅自改Pub源'
    [void](Get-JobsFlutterSdkRoute $uri 'Flutter3.38.4 / engine-a / windows-x64' @{} -PublicObject $true)
    Assert-Route ($script:batches-eq1) '同任务短期缓存避免每个小下载重测'
    $explicit=@{FLUTTER_STORAGE_BASE_URL='';PUB_HOSTED_URL='';HTTPS_PROXY=''}
    $route=Get-JobsFlutterSdkRoute $uri 'explicit-empty' $explicit -PublicObject $true
    Assert-Route ($route.Ready-and$route.Uri-ceq$uri-and$route.Environment.Count-eq0-and$script:requests.Count-eq1) '显式源及代理空值不被AUTO覆盖'
    Assert-Route ($explicit.Count-eq3-and$explicit['FLUTTER_STORAGE_BASE_URL']-ceq''-and$explicit['HTTPS_PROXY']-ceq'') '调用者原始环境不被写入'
    $route=Get-JobsFlutterSdkRoute $uri 'private-source' @{FLUTTER_STORAGE_BASE_URL='https://user:password@private.invalid/prefix?token=secret';HTTPS_PROXY='http://proxy:password@proxy.invalid:8080'} -PublicObject $true
    Assert-Route ($route.Environment.Count-eq0-and$script:requests.Count-eq1) '显式自定义源及代理只验证原配置组合'
    Assert-Route (-not(($script:logs-join"`n")-match'password|token=secret')) '所有预检来源及代理诊断脱敏'
    $script:mode='bad200';$global:JobsFlutterSdkRouteCache=@{}
    $route=Get-JobsFlutterSdkRoute $uri 'bad200' @{} -PublicObject $true
    Assert-Route (-not$route.Ready) 'HTTP200忽略Range不能当高速成功'
    $count=$script:batches;[void](Get-JobsFlutterSdkRoute $uri 'bad200' @{} -PublicObject $true)
    Assert-Route ($script:batches-eq$count) '失败缓存短期去抖，不忙循环'
    Clear-JobsSdkRouteCache $route.Key;[void](Get-JobsFlutterSdkRoute $uri 'bad200' @{} -PublicObject $true)
    Assert-Route ($script:batches-eq($count+1)) '获取失败可失效坏路线并重测'
    $script:mode='html';$global:JobsFlutterSdkRouteCache=@{}
    Assert-Route (-not(Get-JobsFlutterSdkRoute $uri 'html' @{} -PublicObject $true).Ready) '即使206也拒绝小错误页/非ZIP内容'
    $script:mode='mismatch';$global:JobsFlutterSdkRouteCache=@{}
    $route=Get-JobsFlutterSdkRoute $uri 'mismatch' @{} -PublicObject $true
    Assert-Route ($route.Ready-and([Uri]$route.Uri).Host-ceq'storage.googleapis.com') '镜像样本与官方冲突时不得靠相同ETag绕过'
    $script:mode='metadata-only';$global:JobsFlutterSdkRouteCache=@{}
    $route=Get-JobsFlutterSdkRoute $uri 'metadata-only' @{} -PublicObject $true
    Assert-Route ($route.Ready-and([Uri]$route.Uri).Host-ceq'storage.flutter-io.cn') '官方制品慢不可达时以官方对象size/MD5对镜像ETag核验'
    $script:mode='unverified-mirror';$global:JobsFlutterSdkRouteCache=@{}
    $offline=Get-JobsFlutterSdkRoute $uri 'unverified' @{} -PublicObject $true
    Assert-Route ($offline.Ready-and([Uri]$offline.Uri).Host-ceq'storage.flutter-io.cn'-and($script:logs-join"`n").Contains('不冒称已通过官方hash核验')) 'Google完全断网仍允许已授权镜像精确目标证据，明确官方摘要未取得'
    $route=Get-JobsFlutterSdkRoute $uri 'trusted-release-sha' @{} -ExpectedSha256 ('f'*64) -PublicObject $true
    Assert-Route ($route.Ready-and([Uri]$route.Uri).Host-ceq'storage.flutter-io.cn') '有可信发布SHA的同版本归档可选镜像，下载后仍验完整SHA'
    $script:mode='normal';$script:configured=@('http://existing.corp:8080');$global:JobsFlutterSdkRouteCache=@{}
    $route=Get-JobsFlutterSdkRoute $uri 'existing-enterprise-proxy' @{} -PublicObject $true
    Assert-Route ($route.Ready-and$route.Proxy-ceq'http://existing.corp:8080'-and$route.Environment['HTTPS_PROXY']-ceq$route.Proxy) '复用当前配置的企业代理，非固定端口'
    $route=Get-JobsFlutterSdkRoute $uri 'native-bits' @{HTTPS_PROXY='http://explicit.invalid:9999'} -Transport windows-native -PublicObject $true
    Assert-Route ($route.Ready-and$route.ProxyMode-ceq'native-wininet'-and-not$route.Environment.Contains('HTTPS_PROXY')) '原生BITS只按实际WinINET路线评分，不冒称新环境代理已生效'
    $script:configured=@()
    $sdk=Join-Path $temporary 'sdk';$project=Join-Path $temporary 'project';[void][IO.Directory]::CreateDirectory($project)
    foreach($relative in @('bin/internal/engine.version','bin/cache/dart-sdk/bin/dart.exe','bin/cache/engine-dart-sdk.stamp','version')){$path=Join-Path $sdk $relative;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $path));[IO.File]::WriteAllText($path,$(if($relative-match'engine'){('a'*40)}elseif($relative-ceq'version'){'3.38.4'}else{'fake'}))}
    $start=New-JobsSdkToolStart (Join-Path $sdk 'bin/flutter.exe') @('--version','--machine') $project @{}
    Assert-Route ($null-eq(Get-JobsSdkProcessRouteTarget $start @{})) '健康SDK普通版本检查不做不必要网络探测'
    Remove-Item -LiteralPath (Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp')
    $target=Get-JobsSdkProcessRouteTarget $start @{PROCESSOR_ARCHITECTURE='ARM64'}
    Assert-Route ($target.Uri.EndsWith('/dart-sdk-windows-arm64.zip')-and$target.Transport-ceq'windows-native') '冷启动按SDK真实目标架构构造制品，不拿其它架构冒充'
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/engine.realm'),'staging/private')
    $privateEnv=@{FLUTTER_STORAGE_BASE_URL='https://private.invalid/objects';FLUTTER_PREBUILT_ENGINE_VERSION='custom_engine_123';FLUTTER_REALM='private-realm'}
    $private=Get-JobsSdkProcessRouteTarget $start $privateEnv
    Assert-Route ($private.Uri-ceq'https://private.invalid/objects/private-realm/flutter_infra_release/flutter/custom_engine_123/dart-sdk-windows-x64.zip') '自定义storage/engine/realm按真实命名空间构造目标'
    $global:JobsFlutterSdkRouteCache=@{};$script:mode='normal'
    $privateRoute=Get-JobsFlutterSdkRoute $private.Uri 'private-engine' $privateEnv -Transport windows-native
    Assert-Route ($privateRoute.Ready-and$script:requests.Count-eq1-and-not@($script:requests|Where-Object{([Uri]$_.Uri).Host-ceq'storage.googleapis.com'}).Count) 'private engine仅探测用户源，不向Google泄露目标或被Google404阻断'
    $realm=Get-JobsSdkProcessRouteTarget $start @{}
    Assert-Route ($realm.Uri.Contains('/staging/private/flutter_infra_release/')) '读取SDK实际engine.realm'
    $noRealm=Get-JobsSdkProcessRouteTarget $start @{FLUTTER_REALM=''}
    Assert-Route (-not$noRealm.Uri.Contains('/staging/private/')) '显式空realm优先于旧缓存realm'
    $unknown=Get-JobsFlutterSdkRoute $uri 'unknown-engine' @{}
    Assert-Route (-not@($script:requests|Where-Object{([Uri]$_.Uri).Host-ceq'storage.flutter-io.cn'}).Count) '未知engine没有公开来源证据时不向公共镜像泄漏'
    [void](Get-JobsFlutterSdkRoute $realm.Uri 'private-realm' @{} -PublicObject $false)
    Assert-Route (-not@($script:requests|Where-Object{([Uri]$_.Uri).Host-ceq'storage.flutter-io.cn'}).Count) '非空realm不因包含flutter_infra_release就扇出CFUG'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk '.git'))
    [IO.File]::WriteAllText((Join-Path $sdk '.git/config'),"[remote `"origin`"]`n    url = https://github.com/flutter/flutter.git`n")
    [IO.File]::WriteAllText((Join-Path $sdk '.git/HEAD'),'ref: refs/heads/stable')
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/flutter.version.json'),'{"frameworkVersion":"3.20.0","engineRevision":"old"}')
    function script:Read-JobsSdkReleaseManifest {
        param($Environment)
        return ('{"base_url":"https://storage.googleapis.com/flutter_infra_release/releases","current_release":{"stable":"new-release"},"releases":[{"hash":"new-release","channel":"stable","version":"3.99.0","dart_sdk_arch":"x64","archive":"stable/windows/flutter_windows_3.99.0-stable.zip","sha256":"'+('b'*64)+'"}]}')|ConvertFrom-Json
    }
    $upgrade=New-JobsSdkToolStart (Join-Path $sdk 'bin/flutter.exe') @('upgrade') $project @{}
    $upTarget=Get-JobsSdkProcessRouteTarget $upgrade @{FLUTTER_REALM=''}
    Assert-Route ($upTarget.Artifact.Uri.EndsWith('/flutter_windows_3.99.0-stable.zip')-and$upTarget.Artifact.Identity.Contains('3.99.0')-and-not$upTarget.Artifact.Identity.Contains('3.20.0')) '热旧SDK升级stable使用current_release目标而不是旧metadata'
    Assert-Route ($upTarget.Uri-ceq'https://github.com/flutter/flutter.git/info/refs?service=git-upload-pack') '升级仍核验实际Git源不改origin'
    function script:Get-JobsSdkFvmContext {param($Tool,$Directory,$Environment)return [pscustomobject]@{flutterUrl='https://github.com/flutter/flutter.git';versionsCachePath=$sdk}}
    $install=New-JobsSdkToolStart 'fvm.exe' @('install','stable','--no-setup') $project @{}
    $fvmTarget=Get-JobsSdkProcessRouteTarget $install @{}
    Assert-Route ($fvmTarget.Artifact.Uri.EndsWith('/flutter_windows_3.99.0-stable.zip')-and$fvmTarget.Uri.Contains('github.com/flutter/flutter')) 'FVM channel获取包含精确新archive和原Git两个预检阶段'
    [IO.File]::WriteAllText((Join-Path $sdk '.git/HEAD'),'ref: refs/heads/master')
    $legacy=Get-JobsSdkProcessRouteTarget $upgrade @{FLUTTER_REALM=''}
    Assert-Route ($legacy.Artifact.Uri.EndsWith('/'+('a'*40)+'/dart-sdk-windows-x64.zip')-and$legacy.Artifact.Identity.Contains('已落地源码')-and$legacy.Artifact.PublicObject) '无发布归档的legacy重试按已落地真实engine补Dart选路，不假称解析了新版本'
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'),'{"flutterUrl":"https://github.com/flutter/flutter.git","flutter":"3.38.4"}')
    [IO.File]::WriteAllText((Join-Path $sdk '.git/config'),"[remote `"origin`"]`n    url = https://private.invalid/custom.git`n")
    $actualFork=Get-JobsSdkProcessRouteTarget $start @{FLUTTER_REALM=''}
    Assert-Route ($actualFork.Uri-ceq'https://private.invalid/custom.git/info/refs?service=git-upload-pack') '声明官方版本不覆盖实际SDK私库origin，不向CFUG泄漏实际engine'
    $privateRelease=Get-JobsSdkRequestedRelease stable @{FLUTTER_STORAGE_BASE_URL='https://private.invalid/objects'}
    Assert-Route ($null-eq$privateRelease) '私有source请求不会为了公共manifest泄漏目标'
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'),'{"flutterUrl":"https://gitcode.example/Jobs/custom.git","flutter":"custom_sdk"}')
    $target=Get-JobsSdkProcessRouteTarget $start @{}
    Assert-Route ($target.Uri-ceq'https://private.invalid/custom.git/info/refs?service=git-upload-pack') 'Harmony/用户fork只测原Git网络通道，不重写仓库地址'
    Assert-Route ((ConvertTo-JobsSdkRouteArgument 'C:\SDK path\')-ceq'"C:\SDK path\\"') 'Win32参数引用保留路径反斜杠与空格'
    # A小样本始终最快，但真正大下载失败；必须转B，不能invalidate后永远选回A。
    . (Join-Path $root 'JobsFlutterTools/Scripts/SdkDownloadOutput.ps1')
    $script:JobsSdkRetryLog=Join-Path $temporary 'acquisition.log'
    $script:actual=New-Object 'Collections.Generic.List[string]'
    $script:payload=[Text.Encoding]::UTF8.GetBytes(('Z'*32768))
    $expected=Join-Path $temporary 'expected';[IO.File]::WriteAllBytes($expected,$script:payload)
    $sha=(Get-FileHash -LiteralPath $expected -Algorithm SHA256).Hash
    function script:Get-JobsSdkRouteEnvironment {param($Start)return @{}}
    function script:Start-Sleep {param($Seconds,$Milliseconds)}
    function script:Receive-JobsSdkRoutedFile {
        param($Route,$Destination,$TimeoutSeconds,$Environment)
        if(([Uri]$Route.Uri).Host-ceq'storage.googleapis.com'){$script:actual.Add('A');throw 'fixture large transfer connection reset'}
        $script:actual.Add('B');[IO.File]::WriteAllBytes($Destination,$script:payload)
    }
    $script:mode='a-large-fails';$global:JobsFlutterSdkRouteCache=@{};$global:JobsFlutterSdkRouteFailures=@{}
    $script:auto404=0
    [void](Invoke-JobsSdkAcquire -InitialDelaySeconds 0 -Operation {
        $script:auto404++
        [pscustomobject]@{ExitCode=$(if($script:auto404-eq1){1}else{0});StdOut='';StdErr=$(if($script:auto404-eq1){'HTTP request failed: (404) Not Found'}else{''});SdkRouteAutoSource=$true}
    })
    Assert-Route ($script:auto404-eq2) 'AUTO镜像未同步404不得被旧错误分类抢先硬停'
    $download=Join-Path $temporary 'download.zip'
    Receive-JobsSdkWebFile 'https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.38.4-stable.zip' $download 30 -ExpectedSha256 $sha
    Assert-Route (($script:actual-join'|')-ceq'A|B'-and(Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash-ceq$sha) '真实下载失败的最快A降权后切B成功，不困在同一坏路线'
    . (Join-Path $root 'JobsFlutterRunner/Scripts/SdkDownloadRoute.ps1/SdkDownloadRoute.ps1')
    [IO.File]::WriteAllText((Join-Path $sdk '.git/config'),"[remote `"origin`"]`n    url = https://github.com/flutter/flutter.git`n")
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'),'{"flutter":"3.38.4"}')
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/engine-dart-sdk.stamp'),('a'*40))
    $cacheSource=Join-Path $sdk 'packages/flutter_tools/lib/src/flutter_cache.dart'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $cacheSource))
    [IO.File]::WriteAllText($cacheSource,"'sky_engine' 'flutter_gpu' class FontSubsetArtifacts class FlutterEngineStamp")
    $universalStart=New-JobsSdkToolStart (Join-Path $sdk 'bin/flutter.exe') @('precache','--universal') $project @{}
    $target=Get-JobsSdkProcessRouteTarget $universalStart @{FLUTTER_REALM=''}
    Assert-Route ($target.Uri.EndsWith('/'+('a'*40)+'/sky_engine.zip')-and-not$target.Uri.Contains('android')) '冷通用SDK按实际engine选择sky_engine，不误测Android制品'
    foreach($relative in @('bin/cache/pkg/sky_engine','bin/cache/pkg/flutter_gpu','bin/cache/artifacts/engine/common/flutter_patched_sdk','bin/cache/artifacts/engine/common/flutter_patched_sdk_product','bin/cache/artifacts/engine/windows-x64','bin/cache/artifacts/material_fonts','bin/cache/artifacts/gradle_wrapper')){[void][IO.Directory]::CreateDirectory((Join-Path $sdk $relative))}
    foreach($relative in @('bin/cache/flutter_sdk.stamp','bin/cache/font-subset.stamp','bin/cache/engine_stamp.stamp')){[IO.File]::WriteAllText((Join-Path $sdk $relative),('a'*40))}
    foreach($relative in @('bin/cache/artifacts/gradle_wrapper/gradlew','bin/cache/artifacts/gradle_wrapper/gradlew.bat','bin/cache/artifacts/gradle_wrapper/gradle/wrapper/gradle-wrapper.jar','bin/cache/artifacts/engine/windows-x64/font-subset.exe','bin/cache/engine_stamp.json')){$file=Join-Path $sdk $relative;[void][IO.Directory]::CreateDirectory((Split-Path -Parent $file));[IO.File]::WriteAllText($file,'fixture')}
    foreach($name in @('material_fonts','gradle_wrapper')){[IO.File]::WriteAllText((Join-Path $sdk ('bin/internal/'+$name+'.version')),'fixture-version');[IO.File]::WriteAllText((Join-Path $sdk ('bin/cache/'+$name+'.stamp')),'fixture-version')}
    foreach($relative in @('bin/cache/pkg/sky_engine/pubspec.yaml','bin/cache/pkg/flutter_gpu/pubspec.yaml','bin/cache/artifacts/engine/windows-x64/flutter_tester.exe')){[IO.File]::WriteAllText((Join-Path $sdk $relative),'fixture')}
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/engine_stamp.json'),('{"git_revision":"'+('a'*40)+'"}'))
    $packageConfig=Join-Path $sdk 'packages/flutter_tools/.dart_tool/package_config.json'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $packageConfig))
    [IO.File]::WriteAllText((Join-Path $sdk 'packages/flutter_tools/pubspec.yaml'),'name: flutter_tools')
    [IO.File]::WriteAllText($packageConfig,'{"configVersion":2,"packages":[{"name":"flutter_tools","rootUri":"../"}]}')
    Assert-Route ($null-eq(Get-JobsSdkProcessRouteTarget $universalStart @{FLUTTER_REALM=''})) '通用stamps与payload均健康时不要求联网测速'
    [IO.File]::WriteAllText($packageConfig,'{"configVersion":2,"packages":[{"name":"missing","rootUri":"../missing/"}]}')
    Assert-Route ($null-ne(Get-JobsSdkProcessRouteTarget $universalStart @{FLUTTER_REALM=''})) 'Pub根缺失不能误判公共缓存就绪'
    [IO.File]::WriteAllText($packageConfig,'{"configVersion":2,"packages":[{"name":"flutter_tools","rootUri":"../"}]}')
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/engine_stamp.json'),('{"git_revision":"'+('b'*40)+'"}'))
    Assert-Route ($null-ne(Get-JobsSdkProcessRouteTarget $universalStart @{FLUTTER_REALM=''})) 'engine元数据内容失配不能只凭stamp通过'
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/engine_stamp.json'),('{"git_revision":"'+('a'*40)+'"}'))
    [IO.File]::Move($cacheSource,$cacheSource+'.saved')
    $unknownTarget=Get-JobsSdkProcessRouteTarget $universalStart @{FLUTTER_REALM=''}
    Assert-Route ($unknownTarget.Uri.EndsWith('/dart-sdk-windows-x64.zip')) '未知通用布局保守检测实际engine代表制品'
    [IO.File]::Move($cacheSource+'.saved',$cacheSource)
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/flutter_sdk.stamp'),('b'*40))
    $target=Get-JobsSdkProcessRouteTarget $universalStart @{FLUTTER_REALM=''}
    Assert-Route ($target.Uri.EndsWith('/sky_engine.zip')) '旧engine stamp不能误判通用缓存就绪'
    [IO.File]::WriteAllText((Join-Path $sdk 'bin/cache/flutter_sdk.stamp'),('a'*40))
    Remove-Item -LiteralPath (Join-Path $sdk 'bin/cache/artifacts/engine/windows-x64/font-subset.exe')
    Assert-Route ($null-ne(Get-JobsSdkProcessRouteTarget $universalStart @{FLUTTER_REALM=''})) '缺失通用payload不能只凭stamp跳过网络准备'
    $target=Get-JobsSdkProcessRouteTarget $universalStart @{FLUTTER_STORAGE_BASE_URL='https://private.invalid/objects';FLUTTER_REALM='scoped'}
    Assert-Route ($target.Uri-ceq('https://private.invalid/objects/scoped/flutter_infra_release/flutter/'+('a'*40)+'/sky_engine.zip')-and-not$target.PublicObject) '通用资源仍尊重显式source/realm，不扩公共镜像'
    Write-Host ('PASS: SdkNetworkRoute.Tests.ps1 ('+$script:checks+' assertions; all transport mocked, no SDK/network)')
}finally{Remove-Item -LiteralPath $temporary -Recurse -Force}
