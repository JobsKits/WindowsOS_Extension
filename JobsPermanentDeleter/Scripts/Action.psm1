# Action.psm1 | JobsPermanentDeleter
# Created by Jobs on 2026年11月18日，星期三.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# CLI always uses the native confirmation dialog; no unattended deletion route exists.
function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$Target)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '永久删除仅支持 Windows；没有删除任何项目。' }
    if ($Target.Count -eq 0 -or $Target.Count -gt 128) { throw '请选择 1 至 128 个文件或文件夹。' }
    $library = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin/JobsPermanentDeleterContextMenu.dll'
    if (-not (Test-Path -LiteralPath $library -PathType Leaf)) { throw '本包 DLL 缺失，请先安装 / 更新。' }
    if (-not ('Jobs.PermanentDelete.Native' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Jobs.PermanentDelete {
    public static class Native {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
        [DllImport("kernel32.dll", CharSet=CharSet.Ansi, ExactSpelling=true, SetLastError=true)]
        static extern IntPtr GetProcAddress(IntPtr module, string name);
        [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
        [UnmanagedFunctionPointer(CallingConvention.StdCall, CharSet=CharSet.Unicode)]
        delegate uint Confirm([MarshalAs(UnmanagedType.LPArray, ArraySubType=UnmanagedType.LPWStr, SizeParamIndex=1)] string[] paths, uint count);
        public static uint Run(string library, string[] paths) {
            IntPtr module = LoadLibraryExW(library, IntPtr.Zero, 0x1100);
            if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                IntPtr address = GetProcAddress(module, "JobsConfirmPermanentDelete");
                if (address == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                Confirm action = (Confirm)Marshal.GetDelegateForFunctionPointer(address, typeof(Confirm));
                return action(paths, (uint)paths.Length);
            } finally { FreeLibrary(module); }
        }
    }
}
'@
    }
    $errorCode = [Jobs.PermanentDelete.Native]::Run($library, $Target)
    if ($errorCode -eq 1223) { Write-Host '已取消；没有删除任何项目。'; return }
    if ($errorCode -ne 0) { throw (New-Object ComponentModel.Win32Exception([int]$errorCode)) }
}
Export-ModuleMember -Function Invoke-JobsFeature
