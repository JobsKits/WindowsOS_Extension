# OfficialHarmonyTools.ps1 | JobsFlutterRunner
# Created by Jobs on 2026年11月12日，星期四.
# 官方目录核验先于工具安装；不读取浏览器Cookie、不绕过登录或许可。
function New-JobsRunnerVirtualPrivateDirectory {
    param([string]$Path)
    $ancestor=New-Object IO.DirectoryInfo([IO.Path]::GetFullPath($Path))
    while($null-ne$ancestor){if($ancestor.Exists-and($ancestor.Attributes-band[IO.FileAttributes]::ReparsePoint)){throw '本轮私有目录不能经过链接或联接。'};$ancestor=$ancestor.Parent}
    [void][IO.Directory]::CreateDirectory($Path)
    if([Environment]::OSVersion.Platform-eq[PlatformID]::Win32NT){
        $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl=New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false);$acl.SetOwner($owner)
        foreach($sid in @($owner,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))){
            $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
            $acl.AddAccessRule($rule)
        }
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
    }
    return $Path
}

function ConvertFrom-JobsRunnerHarmonyPublicRelease {
    param($Response)
    if($null-eq$Response.PSObject.Properties['code']-or[string]$Response.code-cne'0'-or$null-eq$Response.PSObject.Properties['value']-or$null-eq$Response.value.PSObject.Properties['status']-or[string]$Response.value.status-cne'4'-or$null-eq$Response.value.PSObject.Properties['content']-or$null-eq$Response.value.content.PSObject.Properties['content']){throw '官方公开Release正文未返回已发布内容。'}
    $html=[string]$Response.value.content.content
    $headings=@([regex]::Matches($html,'(?is)<h[2-6][^>]*>\s*DevEco\s+Studio\s+6\.1\.1\s+Release\s*\((\d+\.\d+\.\d+\.\d+)\)\s*</h[2-6]>'))
    if(-not$headings.Count){throw '官方兼容Release标题无法验证。'}
    $latest=@($headings|Sort-Object @{Expression={[version]$_.Groups[1].Value};Descending=$true})[0]
    $next=@($headings|Where-Object{$_.Index-gt$latest.Index}|Sort-Object Index|Select-Object -First 1)
    $end=if($next.Count){$next[0].Index}else{$html.Length}
    $section=$html.Substring($latest.Index,$end-$latest.Index)
    $versions=@()
    foreach($table in [regex]::Matches($section,'(?is)<table\b[^>]*>.*?</table>')){
        $caption=[regex]::Match($table.Value,'(?is)<caption\b[^>]*>(.*?)</caption>')
        $captionText=[Net.WebUtility]::HtmlDecode(([regex]::Replace($caption.Groups[1].Value,'<[^>]*>',' ')))
        if($captionText-notmatch'(?i)Command\s+line\s+tools\s*$'){continue}
        foreach($row in [regex]::Matches($table.Value,'(?is)<tr\b[^>]*>.*?</tr>')){
            $cells=@([regex]::Matches($row.Value,'(?is)<td\b[^>]*>(.*?)</td>')|ForEach-Object{[Net.WebUtility]::HtmlDecode(([regex]::Replace($_.Groups[1].Value,'<[^>]*>',' '))).Trim()})
            if($cells.Count-ge2-and$cells[0]-ceq'Command Line'){
                if($cells[1]-cnotmatch'^\d+\.\d+\.\d+\.\d+$'){throw '官方Command Line行版本无效。'}
                $versions+=$cells[1]
            }
        }
    }
    if($versions.Count-ne1){throw '当前兼容Release的Command Line行不唯一；未把Emulator组件号当CLT。'}
    if($versions[0]-cne$latest.Groups[1].Value){throw 'Command Line行与当前兼容Release标题版本冲突，未判定健康。'}
    return [pscustomobject]@{Version=$versions[0];Release=$latest.Groups[1].Value;Page='https://developer.huawei.com/consumer/en/doc/harmonyos-releases/deveco-studio-new-features-611/'}
}

# 仅重入原生HTTP请求；解析、授权、安装和启动都在重试边界之外。
function Get-JobsRunnerHarmonyMetadataRetry {
    param([Exception]$Exception)
    $status=0;$retryAfter=0;$chain=@();$failure=$Exception
    while($null-ne$failure){$chain+=,$failure;$failure=$failure.InnerException}
    foreach($failure in $chain){
        if($null-ne$failure.PSObject.Properties['Response']-and$null-ne$failure.Response){
            $response=$failure.Response
            if($null-ne$response.PSObject.Properties['StatusCode']){$status=[int]$response.StatusCode}
            if($null-ne$response.PSObject.Properties['Headers']-and$null-ne$response.Headers){
                $value=''
                if($null-ne$response.Headers.PSObject.Properties['RetryAfter']-and$response.Headers.RetryAfter){
                    $header=$response.Headers.RetryAfter
                    if($null-ne$header.PSObject.Properties['Delta']-and$header.Delta){$retryAfter=[int][Math]::Ceiling($header.Delta.TotalSeconds)}
                    elseif($null-ne$header.PSObject.Properties['Date']-and$header.Date){$retryAfter=[int][Math]::Ceiling(($header.Date-[DateTimeOffset]::UtcNow).TotalSeconds)}
                }else{try{$value=[string]$response.Headers['Retry-After']}catch{}}
                $seconds=0;$date=[DateTimeOffset]::MinValue
                if($value-and[int]::TryParse($value,[ref]$seconds)){$retryAfter=$seconds}
                elseif($value-and[DateTimeOffset]::TryParse($value,[ref]$date)){$retryAfter=[int][Math]::Ceiling(($date-[DateTimeOffset]::UtcNow).TotalSeconds)}
            }
        }
    }
    if($status){return [pscustomobject]@{Transient=($status-in@(408,429)-or($status-ge500-and$status-le599));Status=$status;RetryAfter=[Math]::Max(0,$retryAfter)}}
    $transient=$false
    foreach($failure in $chain){
        if($failure-is[TimeoutException]){$transient=$true}
        if($failure-is[Net.WebException]-and$failure.Status-in@([Net.WebExceptionStatus]::Timeout,[Net.WebExceptionStatus]::NameResolutionFailure,[Net.WebExceptionStatus]::ProxyNameResolutionFailure,[Net.WebExceptionStatus]::ConnectFailure,[Net.WebExceptionStatus]::ConnectionClosed,[Net.WebExceptionStatus]::ReceiveFailure,[Net.WebExceptionStatus]::SendFailure,[Net.WebExceptionStatus]::KeepAliveFailure)){$transient=$true}
        if($failure-is[Net.Sockets.SocketException]-and$failure.SocketErrorCode-in@([Net.Sockets.SocketError]::HostNotFound,[Net.Sockets.SocketError]::TryAgain,[Net.Sockets.SocketError]::TimedOut,[Net.Sockets.SocketError]::ConnectionReset,[Net.Sockets.SocketError]::ConnectionAborted,[Net.Sockets.SocketError]::ConnectionRefused,[Net.Sockets.SocketError]::NetworkDown,[Net.Sockets.SocketError]::NetworkUnreachable,[Net.Sockets.SocketError]::HostUnreachable)){$transient=$true}
        if($failure.Message-match'(?i)HttpClient\.Timeout|timed out|request timeout|name or service not known|no such host is known|remote name could not be resolved|connection (?:reset|refused)|failed to connect'){$transient=$true}
    }
    return [pscustomobject]@{Transient=$transient;Status=0;RetryAfter=0}
}

function Invoke-JobsRunnerHarmonyMetadataRequest {
    param([string]$Label,[scriptblock]$Operation)
    $attempt=0
    while($true){
        $attempt++
        try{return &$Operation}
        catch [Management.Automation.PipelineStoppedException]{throw}
        catch{
            $retry=Get-JobsRunnerHarmonyMetadataRetry $_.Exception
            if(-not$retry.Transient){throw}
            $delay=[int][Math]::Max($retry.RetryAfter,[Math]::Min(30,2*[Math]::Pow(2,[Math]::Min(4,$attempt-1))))
            Write-Host ($Label+' 瞬时网络失败'+$(if($retry.Status){'（HTTP '+$retry.Status+'）'}else{''})+'，'+$delay+' 秒后重新查询；Ctrl+C 可取消。') -ForegroundColor Yellow
            # 单次HTTP有20秒超时；等待分片使取消及时生效，不重放后续安装或启动。
            for($remaining=$delay;$remaining-gt0;$remaining--){Start-Sleep -Seconds 1}
        }
    }
}

function Get-JobsRunnerHarmonyPublicRelease {
    $request=@{centerPrefix='doccenter';language='en';level2NodeAlias='release-notes';isApi=0;fileName='deveco-studio-new-features-611'}|ConvertTo-Json -Compress
    $response=Invoke-JobsRunnerHarmonyMetadataRequest '官方公开兼容Release' {Invoke-RestMethod -Uri 'https://svc-drcn.developer.huawei.com/community/servlet/consumer/cn/documentPortal/getCenterDocument' -Method Post -ContentType 'application/json' -Body $request -TimeoutSec 20}
    return ConvertFrom-JobsRunnerHarmonyPublicRelease $response
}

function Invoke-JobsRunnerHarmonyOfficialService {
    param([string]$Service,[hashtable]$Request)
    $body=@{svc=('PartnerCommunityService/v1/developer/downloadCenter/'+$Service);reqType=1;reqJson=($Request|ConvertTo-Json -Compress)}|ConvertTo-Json -Compress
    $result=Invoke-JobsRunnerHarmonyMetadataRequest ('官方CLT '+$Service) {
        $headers=@{Origin='https://developer.huawei.com';'X-HD-DATE'=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ',[Globalization.CultureInfo]::InvariantCulture);'X-HD-SERIALNO'=[DateTime]::UtcNow.Ticks.ToString()}
        Invoke-RestMethod -Uri 'https://svc-drcn.developer.huawei.com/svc/community/common/v1/delegate' -Method Post -ContentType 'application/json;charset=UTF-8' -Headers $headers -Body $body -TimeoutSec 20
    }
    return ConvertFrom-JobsRunnerHarmonyOfficialEnvelope $result
}

function ConvertFrom-JobsRunnerHarmonyOfficialEnvelope {
    param($Response)
    if($null-ne$Response.PSObject.Properties['returnCode']-and[string]$Response.returnCode-cne'0') {return [pscustomobject]@{code=[string]$Response.returnCode}}
    if($null-ne$Response.PSObject.Properties['resJson']) {
        if($null-eq$Response.PSObject.Properties['returnCode']){throw '官方目录外封装缺少returnCode。'}
        if($Response.resJson-isnot[string]){throw '官方目录外封装不是JSON字符串。'}
        $Response=$Response.resJson|ConvertFrom-Json -ErrorAction Stop
    }
    return $Response
}

function New-JobsRunnerHarmonyUpdateState {
    param([string]$State,[string]$Reason,$Package=$null)
    return [pscustomobject]@{State=$State;Reason=$Reason;Package=$Package;Page='https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos'}
}

function Get-JobsRunnerHarmonyOfficialUpdate {
    param($Evidence=$null)
    try {
        $response=if($null-ne$Evidence){ConvertFrom-JobsRunnerHarmonyOfficialEnvelope $Evidence.versionResponse}else{Invoke-JobsRunnerHarmonyOfficialService 'getToolVersionList' @{toolAlias='command-line-tools-for-hmos';language='cn'}}
        if($null-eq$response.PSObject.Properties['code']-or[string]$response.code-cne'00000') {
            $code=if($null-ne$response.PSObject.Properties['code']){[string]$response.code}else{'schema'}
            return New-JobsRunnerHarmonyUpdateState 'Blocked' ('官方CLT更新目录未能验证（'+$code+'）。登录/协议授权可能阻止获取；未启动设备，不能把固定旧版本当作最新版。')
        }
        if($null-eq$response.PSObject.Properties['value']-or$null-eq$response.value.PSObject.Properties['versionTypeList']){throw '官方目录缺少versionTypeList。'}
        $candidates=@()
        foreach($platform in @($response.value.versionTypeList)) {
            if($null-eq$platform.PSObject.Properties['osType']-or[string]$platform.osType-cne'1'){continue}
            if($null-eq$platform.PSObject.Properties['versionList']){throw 'Windows目录缺少versionList。'}
            foreach($release in @($platform.versionList)) {
                foreach($field in @('versionId','versionName','buildVersion','packageList')){if($null-eq$release.PSObject.Properties[$field]){throw ('正式版本缺少'+$field)}}
                if([string]$release.versionName-notmatch'(?i)Release'-or[string]$release.versionName-match'(?i)beta|preview|canary|alpha|\brc\d*\b'){continue}
                if([string]$release.buildVersion-cnotmatch'^\d+\.\d+\.\d+\.\d+$'){throw '正式CLT版本格式无效。'}
                if([string]$release.buildVersion-cnotmatch'^6\.1\.1\.\d+$'){continue}
                foreach($package in @($release.packageList)) {
                    foreach($field in @('sdkId','packageId','packageName','packageSize','sha256')){if($null-eq$package.PSObject.Properties[$field]){throw ('正式包缺少'+$field)}}
                    $version=[string]$release.buildVersion
                    if([string]$package.packageName-cnotin@(('commandline-tools-windows-x64-'+$version+'.zip'),('command-line-tools-windows-x64-'+$version+'.zip'))){continue}
                    if([string]$package.sha256-cnotmatch'^[a-fA-F0-9]{64}$'){throw '官方Windows包没有可核验SHA-256。'}
                    $size=0L
                    if(-not[long]::TryParse([string]$package.packageSize,[ref]$size)-or$size-le0-or$size-gt16GB){throw '官方Windows包大小无法验证。'}
                    foreach($id in @($release.versionId,$package.sdkId,$package.packageId)){if([string]$id-cnotmatch'^[A-Za-z0-9_.-]+$'){throw '官方版本或包标识无效。'}}
                    $candidates+=[pscustomobject]@{Version=$version;VersionId=$release.versionId;SdkId=$package.sdkId;PackageId=$package.packageId;Name=$package.packageName;Size=$size;Sha256=[string]$package.sha256}
                }
            }
        }
        $ordered=@($candidates|Sort-Object @{Expression={[version]$_.Version};Descending=$true})
        if(-not$ordered.Count){throw '官方目录未返回明确Release的Windows x64 CLT，未使用旧固定包代替。'}
        $latest=$ordered[0]
        if(@($ordered|Where-Object{$_.Version-ceq$latest.Version}).Count-ne1){throw '同一最新正式版本的Windows包不唯一。'}
        if($null-ne$Evidence-and$null-ne$Evidence.PSObject.Properties['archivePath']-and$Evidence.archivePath) {
            $archive=[string]$Evidence.archivePath
            if(-not[IO.Path]::IsPathRooted($archive)-or-not[IO.File]::Exists($archive)){throw '本人提供的官方归档路径不存在或不是绝对路径。'}
            Assert-JobsRunnerPlainFile $archive
            $latest|Add-Member NoteProperty ArchivePath $archive
            $latest|Add-Member NoteProperty Url ''
            return New-JobsRunnerHarmonyUpdateState 'Verified' '按本人提供的官方元数据与本地归档核验；在线目录授权状态未改变。' $latest
        }
        $download=if($null-ne$Evidence){ConvertFrom-JobsRunnerHarmonyOfficialEnvelope $Evidence.downloadResponse}else{Invoke-JobsRunnerHarmonyOfficialService 'getToolVersionDownloadUrl' @{versionId=$latest.VersionId;sdkId=$latest.SdkId;packageId=$latest.PackageId}}
        if($null-eq$download.PSObject.Properties['code']-or[string]$download.code-cne'00000'-or$null-eq$download.PSObject.Properties['value']-or$null-eq$download.value.PSObject.Properties['downloadUrl']){return New-JobsRunnerHarmonyUpdateState 'Blocked' ('官方最新正式CLT '+$latest.Version+' 的下载授权未完成；未回退旧版本、未启动设备。')}
        $uri=$null
        if(-not[Uri]::TryCreate([string]$download.value.downloadUrl,[UriKind]::Absolute,[ref]$uri)-or$uri.Scheme-cne'https'-or$uri.UserInfo-or$uri.Fragment-or$uri.Host-notmatch'(?i)(^|\.)(?:huawei\.com|huaweicloud\.com|dbankcdn\.(?:com|cn)|harmonyos\.com)$'){throw '官方包下载URL不是受信HTTPS来源。'}
        if([IO.Path]::GetFileName([Uri]::UnescapeDataString($uri.AbsolutePath))-cne$latest.Name){throw '官方下载URL的末文件名与已核验包名不符。'}
        $latest|Add-Member NoteProperty Url $uri.AbsoluteUri
        return New-JobsRunnerHarmonyUpdateState 'Verified' ('已核验官方Windows x64正式CLT '+$latest.Version) $latest
    } catch [Management.Automation.PipelineStoppedException] {throw}
    catch [OperationCanceledException] {throw}
    catch {return New-JobsRunnerHarmonyUpdateState 'Unverified' ('官方CLT更新检查未完成：'+$_.Exception.Message+'；未安装或启动。')}
}

function Read-JobsRunnerHarmonyOfficialEvidence {
    $path=Read-JobsRunnerInput '本人从官方取得的完整元数据JSON绝对路径（b返回，q取消）'
    if($null-eq$path-or$path-in@('q','Q')){return $null}
    if($path-in@('b','B','←')){return [pscustomobject]@{Kind='Back'}}
    $path=$path.Trim('"')
    if(-not[IO.Path]::IsPathRooted($path)-or-not[IO.File]::Exists($path)){throw '官方元数据文件不存在或不是绝对路径。'}
    Assert-JobsRunnerPlainFile $path
    if((Get-Item $path).Length-gt10MB){throw '官方元数据文件过大，未读取。'}
    $data=[IO.File]::ReadAllText($path)|ConvertFrom-Json -ErrorAction Stop
    foreach($field in @('source','checkedAtUtc','versionResponse')){if($null-eq$data.PSObject.Properties[$field]){throw ('官方元数据证据缺少'+$field)}}
    if($data.source-cne'https://svc-drcn.developer.huawei.com/svc/community/common/v1/delegate'){throw '元数据来源声明不是官方目录接口。'}
    $checked=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$data.checkedAtUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$checked)-or$checked-lt[DateTimeOffset]::UtcNow.AddHours(-24)-or$checked-gt[DateTimeOffset]::UtcNow.AddMinutes(5)){throw '官方元数据核验时间无效或已超过24小时，未以旧目录判定最新。'}
    Write-Host '本轮使用本人显式提供的官方元数据；仍逐项校验正式Windows包与归档，不代表匿名在线目录已获授权。'
    return $data
}

function Wait-JobsRunnerHarmonyOfficialUpdate {
    param([string]$MinimumVersion='')
    $check=$true;$state=$null
    while($true) {
        if($check){$state=Get-JobsRunnerHarmonyOfficialUpdate;$check=$false}
        if($state.State-ceq'Verified'){
            if(-not$MinimumVersion-or[version]$state.Package.Version-ge[version]$MinimumVersion){return $state.Package}
            $state=New-JobsRunnerHarmonyUpdateState 'Unverified' '下载元数据比官方兼容Release旧，未使用旧包代替更新。'
        }
        Write-Host $state.Reason -ForegroundColor Yellow
        $choice=Select-JobsRunnerChoice '鸿蒙启动环境未就绪：官方更新授权/核验' @('打开官方下载页','重新检查官方下载元数据','使用本人取得的官方元数据/归档','返回上一层') -Back
        if($null-eq$choice){return $null}
        if($choice.Kind-ceq'Back'-or$choice.Index-eq3){return [pscustomobject]@{Kind='Back'}}
        if($choice.Index-eq0){[void](Start-Process -FilePath $state.Page -PassThru);Write-Host '浏览器登录不会自动授权本脚本的匿名请求。可在官方页面本人完成授权、保存官方目录元数据和归档后使用本层显式入口；本脚本不读取Cookie。'}
        elseif($choice.Index-eq1){$check=$true}
        elseif($choice.Index-eq2){
            try{
                $evidence=Read-JobsRunnerHarmonyOfficialEvidence
                if($null-eq$evidence){return $null}
                if($null-ne$evidence.PSObject.Properties['Kind']-and$evidence.Kind-ceq'Back'){continue}
                $state=Get-JobsRunnerHarmonyOfficialUpdate $evidence
            }catch [Management.Automation.PipelineStoppedException]{throw}
            catch [OperationCanceledException]{throw}
            catch{Write-Host ('官方元数据未通过：'+$_.Exception.Message) -ForegroundColor Yellow}
        }
    }
}

function Get-JobsRunnerHarmonyToolVersion {
    param([string]$Root)
    $file=Join-Path $Root 'version.txt'
    if(-not[IO.File]::Exists($file)){return ''}
    Assert-JobsRunnerPlainFile $file
    $versions=@([regex]::Matches([IO.File]::ReadAllText($file),'(?<![0-9])\d+\.\d+\.\d+\.\d+(?![0-9])')|ForEach-Object{$_.Value}|Select-Object -Unique)
    if($versions.Count-ne1){return ''}
    return $versions[0]
}

function Install-JobsRunnerOfficialHarmonyTools {
    param($Package)
    $root=&$script:JobsPrepareCore.Tools {Get-JobsHarmonyToolsHome}
    &$script:JobsPrepareCore.Tools {param($Path)Assert-JobsSetupDirectory $Path} $root
    [void][IO.Directory]::CreateDirectory($root)
    $token=[guid]::NewGuid().ToString('N');$stage=Join-Path $root ('.official-'+$token)
    [void](New-JobsRunnerVirtualPrivateDirectory $stage)
    $archive=Join-Path $stage $Package.Name
    if($null-ne$Package.PSObject.Properties['ArchivePath']-and$Package.ArchivePath){
        Write-Host ('核验本人提供的官方CLT归档：'+$Package.ArchivePath+'；独立用户缓存，不覆盖旧安装。')
        [IO.File]::Copy($Package.ArchivePath,$archive,$false)
    }else{
        Write-Host ('获取官方正式CLT '+$Package.Version+'；来源：'+([Uri]$Package.Url).Host+'；独立用户缓存，不覆盖旧安装。')
        [void](Invoke-JobsSdkAcquire -Label ('官方CLT '+$Package.Version+' '+([Uri]$Package.Url).GetLeftPart([UriPartial]::Path)) -Operation { Receive-JobsSdkWebFile $Package.Url $archive 1200 -SingleAttempt -ExpectedSha256 $Package.Sha256 })
    }
    if((Get-Item $archive).Length-ne$Package.Size-or(Get-FileHash $archive -Algorithm SHA256).Hash-ine$Package.Sha256){throw '官方归档大小或SHA-256不符，保留现场且未发布。'}
    &$script:JobsPrepareCore.Tools {param($Zip,$Destination,$Package)Expand-JobsHarmonyToolArchive $Zip $Destination $Package} $archive (Join-Path $stage 'extract') $Package
    $content=Join-Path $stage 'extract/command-line-tools'
    if((Get-JobsRunnerHarmonyToolVersion $content)-cne$Package.Version-or-not(Test-JobsPrepareToolFiles $content)-or-not[IO.File]::Exists((Join-Path $content 'emulator/Emulator.exe'))){throw '解压后的官方CLT版本或必要组件未通过，未发布。'}
    $destination=Join-Path $root ('clt-'+$Package.Version+'-official-'+$token)
    [IO.Directory]::Move($content,$destination)
    [void](New-JobsRunnerVirtualPrivateDirectory $destination)
    return $destination
}
