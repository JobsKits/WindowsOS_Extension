# ProjectSetupProgress.psm1 | 真实阶段事件，与原始终端日志分开。
# Created by Jobs on 2026年10月28日，星期三.
Set-StrictMode -Version 2.0
# 无会话时保持 CLI 可独立运行，不产生旁路文件。
function Set-JobsSetupProgress {
 param([string]$Node,[ValidateSet('pending','running','waiting','done','failed','skipped')][string]$State,[string]$Detail='',[string]$Version='')
 if($Node-ne'overall'-and$State-in@('running','waiting')){$script:activeNode=$Node}
 if (-not $env:JOBS_SETUP_SESSION) { return }
 $file=Join-Path $env:JOBS_SETUP_SESSION 'events.jsonl'
 $event=[ordered]@{time=(Get-Date).ToString('o');node=$Node;state=$State;detail=$Detail}
 if(-not[string]::IsNullOrWhiteSpace($Version)){$event['version']=$Version}
 [IO.File]::AppendAllText($file,($event|ConvertTo-Json -Compress)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
}
# 统一绑定输入等待状态，输入只在原始控制台进行。
function Read-JobsSetupInput {
 param([string]$Prompt,[string]$Node='run.arguments')
 Set-JobsSetupProgress $Node waiting $Prompt
 $value=Read-Host $Prompt
 Set-JobsSetupProgress $Node running '已收到输入'
 return $value
}
# 唯一工具版本源；损坏或缺失时明确标未检测，不伪造版本。
function Get-JobsSetupVersion {
 param([string]$Path=(Join-Path $PSScriptRoot 'SetupVersion.json'))
 try {
  $value=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
  if($value.version-cnotmatch'^\d+\.\d+\.\d+$'-or$value.build-cnotmatch'^\d{4}\.\d{2}\.\d{2}\.\d+$'){throw '工具版本格式无效'}
  return [pscustomobject]@{Version=$value.version;Build=$value.build;Label=('v'+$value.version+' build '+$value.build)}
 }catch{return [pscustomobject]@{Version=$null;Build=$null;Label='工具版本未检测'}}
}
# 兼容旧事件和未检测组件，版本展示与状态提示分开。
function Get-JobsSetupDetectedVersion {
 param($Value)
 if($null-ne$Value-and$null-ne$Value.PSObject.Properties['VersionText']-and-not[string]::IsNullOrWhiteSpace([string]$Value.VersionText)){return [string]$Value.VersionText}
 return '尚未检测'
}
# 返回当前真实子步骤，供等待/失败显示关联。
function Get-JobsSetupActiveNode { if(Get-Variable activeNode -Scope Script -ErrorAction SilentlyContinue){return $script:activeNode};return $null }
Export-ModuleMember -Function Set-JobsSetupProgress,Read-JobsSetupInput,Get-JobsSetupActiveNode,Get-JobsSetupVersion,Get-JobsSetupDetectedVersion
