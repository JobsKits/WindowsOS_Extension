# FileVolumes.ps1 | JobsFileVolumes
# Created by Jobs on 2026年10月28日，星期三.
# 文件分卷内核；固定内存流式读写，无覆盖发布，始终保留原件。
Set-StrictMode -Version 2.0

function Get-JobsVolumeFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path)) { throw '文件路径必须是绝对路径。' }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem' -or $item.PSIsContainer -or
        ($item.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Device)) -ne 0) { throw '仅支持普通文件，不接受文件夹、链接或设备。' }
    return $item
}

function Get-JobsVolumePart {
    param([string]$Name)
    if ($Name -cnotmatch '^(.+)@([0-9]{1,9})of([0-9]{1,9})$') { throw '分卷命名必须是 完整文件名@序号of总数。' }
    $original = $Matches[1]
    $index = [int]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
    $total = [int]::Parse($Matches[3], [Globalization.CultureInfo]::InvariantCulture)
    if ($original -in @('.', '..') -or $original -match '[<>:"/\\|?*\x00-\x1f]|[. ]$' -or
        $original -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)' -or
        $total -lt 1 -or $index -lt 1 -or $index -gt $total) { throw '非法原文件名或卷号。' }
    return [pscustomobject]@{ Name = $original; Index = $index; Total = $total }
}

function Get-JobsVolumeGroup {
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    if ($Paths.Count -lt 2 -or $Paths.Count -gt 10000) { throw '合并必须完整多选同组分卷（2 至 10000 卷）。' }
    $directory = ''; $name = ''; $parts = @{}; $bytes = [long]0
    foreach ($path in $Paths) {
        $file = Get-JobsVolumeFile $path
        $part = Get-JobsVolumePart $file.Name
        if ($part.Total -ne $Paths.Count -or $file.Length -le 0) { throw '总数与选择数量不符，或存在空分卷。' }
        if ($name.Length -eq 0) { $name = $part.Name; $directory = $file.DirectoryName }
        if ($part.Name -cne $name -or $file.DirectoryName -cne $directory -or $parts.ContainsKey($part.Index)) { throw '请选择同目录、同原文件名、无重复编号的一组完整分卷。' }
        $parts[$part.Index] = $file
        if ($bytes -gt ([long]::MaxValue - $file.Length)) { throw '分卷总长度超出支持范围。' }
        $bytes += $file.Length
    }
    $ordered = @()
    for ($index = 1; $index -le $Paths.Count; $index++) {
        if (-not $parts.ContainsKey($index)) { throw ('缺少第 ' + $index + ' 卷；请全选后重试。') }
        $ordered += $parts[$index]
    }
    return [pscustomobject]@{ Name = $name; Directory = $directory; Files = $ordered; Bytes = $bytes }
}

function Assert-JobsVolumeUnchanged {
    param($Snapshot)
    $current = Get-JobsVolumeFile $Snapshot.FullName
    if ($current.Length -ne $Snapshot.Length -or $current.LastWriteTimeUtc -ne $Snapshot.LastWriteTimeUtc -or
        $current.CreationTimeUtc -ne $Snapshot.CreationTimeUtc) { throw ('输入文件已变化，停止发布：' + $Snapshot.FullName) }
}

function Get-JobsVolumeDigest {
    param([Parameter(Mandatory = $true)][IO.Stream]$Stream)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($hash.ComputeHash($Stream)) } finally { $hash.Dispose() }
}

function Add-JobsVolumeStream {
    param([IO.Stream]$InputStream, [IO.Stream]$OutputStream, $Hash, [byte[]]$Buffer, [long]$Count)
    $remaining = $Count
    while ($remaining -gt 0) {
        $take = [int][Math]::Min($Buffer.Length, $remaining)
        $read = $InputStream.Read($Buffer, 0, $take)
        if ($read -le 0) { throw '输入提前结束，候选结果不发布。' }
        $OutputStream.Write($Buffer, 0, $read)
        [void]$Hash.TransformBlock($Buffer, 0, $read, $Buffer, 0)
        $remaining -= $read
    }
}

function Invoke-JobsFileMerge {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Paths)
    $group = Get-JobsVolumeGroup $Paths
    $destination = Join-Path $group.Directory $group.Name
    if (Test-Path -LiteralPath $destination) { throw ('目标已存在，拒绝覆盖：' + $destination) }
    $candidate = Join-Path $group.Directory ('.JobsMerge-' + [guid]::NewGuid().ToString('N') + '.partial')
    $inputs = New-Object 'Collections.Generic.List[IO.Stream]'
    $hash = [Security.Cryptography.SHA256]::Create()
    $output = $null
    try {
        # FileShare.Read 在 Windows 上阻止写入和删除；所有输入先锁定，再生成输出。
        foreach ($file in $group.Files) {
            $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $inputs.Add($stream)
            Assert-JobsVolumeUnchanged $file
            if ($stream.Length -ne $file.Length) { throw '输入长度已变化。' }
        }
        $output = [IO.File]::Open($candidate, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $buffer = New-Object byte[] 1048576
        for ($index = 0; $index -lt $inputs.Count; $index++) {
            Add-JobsVolumeStream -InputStream $inputs[$index] -OutputStream $output -Hash $hash -Buffer $buffer -Count $group.Files[$index].Length
        }
        [void]$hash.TransformFinalBlock([byte[]]@(), 0, 0)
        $expected = [Convert]::ToBase64String($hash.Hash)
        $output.Flush($true); $output.Dispose(); $output = $null
        $verify = [IO.File]::Open($candidate, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($verify.Length -ne $group.Bytes -or (Get-JobsVolumeDigest $verify) -cne $expected) { throw '候选长度 / SHA-256 校验失败。' }
        } finally { $verify.Dispose() }
        foreach ($file in $group.Files) { Assert-JobsVolumeUnchanged $file }
        [IO.File]::Move($candidate, $destination)
        Write-Host ('✔ 合并完成：' + $destination + '；全部分卷保留。') -ForegroundColor Green
        return $destination
    } catch {
        if ([IO.File]::Exists($candidate)) { Write-Warning ('未发布候选保留：' + $candidate) }
        throw
    } finally {
        if ($null -ne $output) { $output.Dispose() }
        foreach ($stream in $inputs) { $stream.Dispose() }
        $hash.Dispose()
    }
}

function Invoke-JobsFileSplit {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][long]$LimitBytes)
    $file = Get-JobsVolumeFile $Path
    if ($LimitBytes -lt 1 -or $file.Length -le $LimitBytes) { throw '文件必须大于所选分卷上限；请调小上限后重试。' }
    $total = [long][Math]::Ceiling([decimal]$file.Length / [decimal]$LimitBytes)
    if ($total -gt 10000) { throw '超过 10000 卷，请调大分卷上限。' }
    $chunk = [long][Math]::Ceiling([decimal]$file.Length / [decimal]$total)
    $destination = Join-Path $file.DirectoryName ($file.Name + '.chunks')
    if (Test-Path -LiteralPath $destination) { throw ('分卷目录已存在，拒绝覆盖：' + $destination) }
    $candidate = Join-Path $file.DirectoryName ('.JobsSplit-' + [guid]::NewGuid().ToString('N') + '.partial')
    $inputStream = $null; $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $inputStream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        Assert-JobsVolumeUnchanged $file
        if ($inputStream.Length -ne $file.Length) { throw '源文件长度已变化。' }
        [void][IO.Directory]::CreateDirectory($candidate)
        $buffer = New-Object byte[] 1048576
        $remaining = $file.Length
        $volumes = @()
        for ($index = 1; $index -le $total; $index++) {
            $path = Join-Path $candidate ($file.Name + '@' + $index + 'of' + $total)
            $output = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $size = [long][Math]::Min($chunk, $remaining)
            try {
                Add-JobsVolumeStream -InputStream $inputStream -OutputStream $output -Hash $hash -Buffer $buffer -Count $size
                $output.Flush($true)
            } finally { $output.Dispose() }
            $volumes += $path; $remaining -= $size
        }
        if ($remaining -ne 0 -or $inputStream.Position -ne $inputStream.Length) { throw '拆分总长度校验失败。' }
        [void]$hash.TransformFinalBlock([byte[]]@(), 0, 0)
        $expected = [Convert]::ToBase64String($hash.Hash)
        $composed = [Security.Cryptography.SHA256]::Create()
        try {
            foreach ($path in $volumes) {
                $part = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    if ($part.Length -lt 1 -or $part.Length -gt $LimitBytes) { throw '分卷长度超出范围。' }
                    while (($read = $part.Read($buffer, 0, $buffer.Length)) -gt 0) { [void]$composed.TransformBlock($buffer, 0, $read, $buffer, 0) }
                } finally { $part.Dispose() }
            }
            [void]$composed.TransformFinalBlock([byte[]]@(), 0, 0)
            if ([Convert]::ToBase64String($composed.Hash) -cne $expected) { throw '分卷重组 SHA-256 不一致。' }
        } finally { $composed.Dispose() }
        $inputStream.Position = 0
        if ((Get-JobsVolumeDigest $inputStream) -cne $expected) { throw '源文件内容在拆分期间发生变化。' }
        Assert-JobsVolumeUnchanged $file
        [IO.Directory]::Move($candidate, $destination)
        Write-Host ('✔ 拆分完成：' + $destination + '；源文件保留。') -ForegroundColor Green
        return $destination
    } catch {
        if ([IO.Directory]::Exists($candidate)) { Write-Warning ('未发布分卷保留：' + $candidate) }
        throw
    } finally {
        if ($null -ne $inputStream) { $inputStream.Dispose() }
        $hash.Dispose()
    }
}

function Show-JobsVolumeLimit {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'Jobs · 选择分卷上限'; $form.ClientSize = New-Object Drawing.Size(430, 180)
    $form.StartPosition = 'CenterScreen'; $form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
    $options = New-Object Windows.Forms.ComboBox
    $options.SetBounds(20, 20, 390, 30); $options.DropDownStyle = 'DropDownList'
    [void]$options.Items.AddRange([object[]]@('50 MiB', '100 MiB', '1900 MiB', '自定义 MiB'))
    $options.SelectedIndex = 0; $form.Controls.Add($options)
    $custom = New-Object Windows.Forms.NumericUpDown
    $custom.SetBounds(20, 65, 390, 30); $custom.Minimum = [decimal]0.001; $custom.Maximum = [decimal]1048576
    $custom.DecimalPlaces = 3; $custom.Value = [decimal]50; $custom.Enabled = $false
    $options.Add_SelectedIndexChanged({ $custom.Enabled = $options.SelectedIndex -eq 3 })
    $form.Controls.Add($custom)
    $confirm = New-Object Windows.Forms.Button
    $confirm.Text = '开始拆分'; $confirm.SetBounds(220, 120, 90, 35); $confirm.DialogResult = 'OK'
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '取消'; $cancel.SetBounds(320, 120, 90, 35); $cancel.DialogResult = 'Cancel'
    $form.Controls.AddRange([Windows.Forms.Control[]]@($confirm, $cancel)); $form.CancelButton = $cancel
    try {
        if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return [long]0 }
        $mib = $custom.Value
        if ($options.SelectedIndex -lt 3) { $mib = @([decimal]50, [decimal]100, [decimal]1900)[$options.SelectedIndex] }
        return [long][Math]::Floor($mib * 1048576)
    } finally { $form.Dispose() }
}
