# Action.psm1
# JobsAndroidStudioOpener
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

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

function Get-JobsAndroidStudio {
    $programs = [Environment]::GetFolderPath('ProgramFiles')
    $candidates = @((Join-Path $programs 'Android\Android Studio\bin\studio64.exe'))
    if ($env:ANDROID_STUDIO_HOME) {
        $candidates += Join-Path $env:ANDROID_STUDIO_HOME 'bin\studio64.exe'
    }
    return Find-JobsExecutable -Name 'studio64.exe' -Candidates $candidates
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Get-JobsDirectory -Target $Target
    $executable = Get-JobsAndroidStudio
    if (-not $executable) {
        Open-JobsMissingTool 'AndroidStudio' 'https://developer.android.com/studio'
        return
    }
    Start-JobsApplication $executable @($directory) $directory
}

Export-ModuleMember -Function Invoke-JobsFeature
