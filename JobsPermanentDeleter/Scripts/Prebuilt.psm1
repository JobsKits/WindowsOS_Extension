# Prebuilt.psm1 | JobsPermanentDeleter
# Created by Jobs on 2026年11月18日，星期三.
Set-StrictMode -Version 2.0
# Match the fixed native source set and PE machine before reusing a distributed DLL.
function Get-JobsVerifiedPrebuiltBinary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourceRoot,
          [Parameter(Mandatory=$true)][ValidateSet('x64','arm64','x86')][string]$Target)
    if ($Target -eq 'x86') { return $null }
    $root = [IO.Path]::GetFullPath($SourceRoot)
    $receiptPath = Join-Path $root 'Dist/BuildVerification.json'
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { return $null }
    try {
        $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($receipt.schemaVersion -ne 1 -or $receipt.featureId -cne 'permanent-delete') { return $null }
        $sources = @('Scripts/ContextMenu.cpp','Scripts/ContextMenu.def','Scripts/PermanentDelete.h','Scripts/DeleteDialog.h','Scripts/DeleteText.h')
        if (@($receipt.nativeSources.PSObject.Properties).Count -ne $sources.Count) { return $null }
        $binary = $receipt.binaries.$Target
        $relative = 'Dist/' + $Target + '/JobsPermanentDeleter.dll'
        if ($binary.path -cne $relative) { return $null }
        foreach ($name in @($sources + @('Dist/BuildVerification.json',$relative))) {
            $path = Join-Path $root $name
            $current = $path
            while ($true) {
                $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
                if ([string]::Equals($current,$root,[StringComparison]::OrdinalIgnoreCase)) { break }
                $current = Split-Path -Parent $current
                if ([string]::IsNullOrWhiteSpace($current)) { return $null }
            }
            if ($name -in $sources) {
                $expected = $receipt.nativeSources.$name
                if ($expected -cnotmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $expected) { return $null }
            }
        }
        $dll = Join-Path $root $relative
        if ($binary.sha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ine $binary.sha256) { return $null }
        $bytes = [IO.File]::ReadAllBytes($dll)
        if ($bytes.Length -lt 128 -or $bytes[0] -ne 77 -or $bytes[1] -ne 90) { return $null }
        $offset = [BitConverter]::ToInt32($bytes,60)
        if ($offset -lt 64 -or $offset -gt $bytes.Length - 24 -or [BitConverter]::ToUInt32($bytes,$offset) -ne 17744) { return $null }
        $machine = [BitConverter]::ToUInt16($bytes,$offset+4)
        $required = if ($Target -eq 'x64') { 34404 } else { 43620 }
        if ($machine -ne $required) { return $null }
        return [pscustomobject]@{ Path = $dll; ExpectedSha256 = [string]$binary.sha256 }
    } catch {
        Write-Warning ('预编译产物未通过核验，改用本机 MSVC：' + $_.Exception.Message)
        return $null
    }
}
Export-ModuleMember -Function Get-JobsVerifiedPrebuiltBinary
