# Action.psm1
# JobsVSCodeOpener
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'ProjectEligibility.ps1')

function Show-JobsMessage {
    param([string]$Message)
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($Message, 'Jobs Windows 右键扩展')
}

function Start-JobsApplication {
    param([string]$Executable, [string[]]$Arguments, [string]$Directory, [switch]$VisibleConsole)
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = (($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' ')
    $start.WorkingDirectory = $Directory
    # 可交互命令通过 ShellExecute 新开可见窗口，避免继承菜单宿主的隐藏控制台。
    $start.UseShellExecute = [bool]$VisibleConsole
    if ($VisibleConsole) { $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal }
    [void][System.Diagnostics.Process]::Start($start)
}

function Open-JobsMissingTool {
    param([string]$Name, [string]$Url)
    Show-JobsMessage "未找到 $Name。即将打开官方下载页，安装后重新右键即可。"
    Start-Process -FilePath $Url
}

function Get-JobsVSCode {
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    $programs = [Environment]::GetFolderPath('ProgramFiles')
    $programs32 = [Environment]::GetFolderPath('ProgramFilesX86')
    if (-not $programs32) { $programs32 = $programs }
    return Find-JobsExecutable -Name 'Code.exe' -Candidates @(
        (Join-Path $local 'Programs\Microsoft VS Code\Code.exe'),
        (Join-Path $programs 'Microsoft VS Code\Code.exe'),
        (Join-Path $programs32 'Microsoft VS Code\Code.exe')
    )
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Resolve-JobsTarget -Target $Target
    if (-not (Test-JobsIDEProject -Directory $directory -IDE 'vscode')) {
        throw '当前目标不符合此 IDE 的项目打开条件；请重新右键有效的非空目录。'
    }
    $executable = Get-JobsVSCode
    if (-not $executable) {
        Open-JobsMissingTool 'VSCode' 'https://code.visualstudio.com/download'
        return
    }
    Start-JobsApplication $executable @($directory) $directory
}

Export-ModuleMember -Function Invoke-JobsFeature
