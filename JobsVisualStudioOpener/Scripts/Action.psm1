# Action.psm1
# JobsVisualStudioOpener
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

function Get-JobsVisualStudio {
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    $programs32 = [Environment]::GetFolderPath('ProgramFilesX86')
    if (-not $programs32) { $programs32 = [Environment]::GetFolderPath('ProgramFiles') }
    $vswhere = Join-Path $programs32 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
        $result = Invoke-JobsProcess -FilePath $vswhere -Arguments @('-latest', '-products', '*', '-find', 'Common7\IDE\devenv.exe') -WorkingDirectory $local
        if ($result.ExitCode -eq 0) {
            $candidate = ($result.StdOut.Trim() -split '\r?\n')[0]
            if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                return $candidate
            }
        }
    }
    return Find-JobsExecutable -Name 'devenv.exe' -Candidates @()
}

function Select-JobsSolution {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if ([IO.Path]::GetExtension($Path) -in @('.sln', '.slnx', '.csproj', '.vcxproj', '.fsproj', '.vbproj')) {
            return $Path
        }
    }
    $directory = Get-JobsDirectory $Path
    $entries = @(Get-ChildItem -LiteralPath $directory -File)
    $candidates = @($entries | Where-Object { $_.Extension -in @('.sln', '.slnx') })
    if ($candidates.Count -eq 0) {
        $candidates = @($entries | Where-Object { $_.Extension -in @('.csproj', '.vcxproj', '.fsproj', '.vbproj') })
    }
    if ($candidates.Count -eq 1) { return $candidates[0].FullName }
    if ($candidates.Count -eq 0) { throw '当前目录没有 Visual Studio 解决方案或项目文件；不会递归猜测子项目。' }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = '存在多个项目，请明确选择'
        $dialog.InitialDirectory = $directory
        $dialog.Filter = 'Visual Studio 项目|*.sln;*.slnx;*.csproj;*.vcxproj;*.fsproj;*.vbproj'
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
        return $dialog.FileName
    } finally { $dialog.Dispose() }
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $path = Resolve-JobsTarget -Target $Target
    $directory = Get-JobsDirectory -Target $path
    $executable = Get-JobsVisualStudio
    if (-not $executable) {
        Open-JobsMissingTool 'Visual Studio' 'https://visualstudio.microsoft.com/downloads/'
        return
    }
    $project = Select-JobsSolution $path
    if ($project) {
        Start-JobsApplication $executable @($project) $directory
    }
}

Export-ModuleMember -Function Invoke-JobsFeature
