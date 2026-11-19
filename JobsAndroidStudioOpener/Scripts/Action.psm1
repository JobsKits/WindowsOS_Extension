# Action.psm1
# JobsAndroidStudioOpener
# Created by Jobs on 2026年10月18日，星期日.


# 源包装与已发布 flat 布局共用路径，兼容旧收据且不跟随包装目录链接。
function Resolve-JobsScriptLayoutPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([IO.Path]::GetExtension($Path) -notin @('.ps1','.cmd','.vbs')) { return $Path }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('脚本包装不能是链接：' + $Path) }
        return Join-Path $Path $directory.Name
    }
    return $Path
}
# 仅新源码包装压平到原发布名称；原有 SDK 资源包与 README 布局保持原意。
function Convert-JobsReleaseLayoutRelativePath {
    param([string]$Package, [string]$Relative)
    $parts = @($Relative -split '[\\/]')
    if ($parts.Count -lt 2) { return $Relative }
    $last = $parts[$parts.Count - 1]
    $parent = $parts[$parts.Count - 2]
    if ($last -ceq 'README.md' -and [IO.Path]::GetExtension($parent) -in @('.ps1','.cmd','.vbs')) {
        $sibling = Join-Path (Join-Path $Package (($parts[0..($parts.Count-2)]) -join '/')) $parent
        if ((Test-Path -LiteralPath $sibling -PathType Leaf) -and ([IO.File]::ReadAllText($sibling) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) { return $null }
    }
    if ($last -ceq $parent -and [IO.Path]::GetExtension($last) -in @('.ps1','.cmd','.vbs')) {
        $source = Join-Path $Package $Relative
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and ([IO.File]::ReadAllText($source) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) {
            return (($parts[0..($parts.Count-2)]) -join '/')
        }
    }
    return $Relative
}
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
. (Resolve-JobsScriptLayoutPath (Join-Path $PSScriptRoot 'ProjectEligibility.ps1'))

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

    $directory = Resolve-JobsTarget -Target $Target
    if (-not (Test-JobsIDEProject -Directory $directory -IDE 'android-studio')) {
        throw '当前目标不符合此 IDE 的项目打开条件；请重新右键有效的非空目录。'
    }
    $executable = Get-JobsAndroidStudio
    if (-not $executable) {
        Open-JobsMissingTool 'AndroidStudio' 'https://developer.android.com/studio'
        return
    }
    Start-JobsApplication $executable @($directory) $directory
}

Export-ModuleMember -Function Invoke-JobsFeature
