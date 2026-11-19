# Action.psm1 | JobsFileVisibility
# Created by Jobs on 2026年11月18日，星期三.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
# Explicit Hide/Show actions are idempotent, including mixed selections.
function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$Target,
          [Parameter(Mandatory=$true)][ValidateSet('Hide','Show')][string]$State)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '隐藏属性仅支持 Windows；没有修改任何项目。' }
    if ($Target.Count -eq 0) { throw '请选择至少一个文件或文件夹。' }
    $library = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/JobsFileVisibilityContextMenu.dll'
    if (-not (Test-Path -LiteralPath $library -PathType Leaf)) { throw '本包 DLL 缺失，请先安装 / 更新。' }
    if (-not ('Jobs.Visibility.Native' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Jobs.Visibility {
    public static class Native {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
        [DllImport("kernel32.dll", CharSet=CharSet.Ansi, ExactSpelling=true, SetLastError=true)]
        static extern IntPtr GetProcAddress(IntPtr module, string name);
        [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
        [UnmanagedFunctionPointer(CallingConvention.StdCall, CharSet=CharSet.Unicode)]
        delegate uint SetVisibility([MarshalAs(UnmanagedType.LPWStr)] string path, [MarshalAs(UnmanagedType.Bool)] bool hidden);
        public static uint Apply(string library, string path, bool hidden) {
            IntPtr module = LoadLibraryExW(library, IntPtr.Zero, 0x1100);
            if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                IntPtr address = GetProcAddress(module, "JobsSetFileVisibility");
                if (address == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                SetVisibility action = (SetVisibility)Marshal.GetDelegateForFunctionPointer(address, typeof(SetVisibility));
                return action(path, hidden);
            } finally { FreeLibrary(module); }
        }
    }
}
'@
    }
    $failures = New-Object 'Collections.Generic.List[string]'
    foreach ($path in $Target) {
        try {
            $resolved = Resolve-JobsTarget -Target $path
            $errorCode = [Jobs.Visibility.Native]::Apply($library, $resolved, ($State -eq 'Hide'))
            if ($errorCode -ne 0) { throw (New-Object ComponentModel.Win32Exception([int]$errorCode)) }
            [pscustomobject]@{ Path=$resolved; State=$State; Success=$true }
        } catch { $failures.Add($path + ': ' + $_.Exception.Message) }
    }
    if ($failures.Count -gt 0) { throw ('部分项目未完成；成功项保留：' + ($failures -join '; ')) }
}
Export-ModuleMember -Function Invoke-JobsFeature
