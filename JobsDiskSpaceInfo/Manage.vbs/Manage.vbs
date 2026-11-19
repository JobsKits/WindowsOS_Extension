Option Explicit
' Created by Jobs on 2026-10-28. WScript launches the management GUI without a console.
Dim shell, files, folder, script, host, command, argument, index
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
' JOBS_SOURCE_LAYOUT_ROOT_V1: source package and flat release use the same feature directory.
If LCase(files.GetFileName(folder)) = LCase(files.GetFileName(WScript.ScriptFullName)) Then folder = files.GetParentFolderName(folder)
script = files.BuildPath(folder, "Scripts\Manage.ps1")
If files.FolderExists(script) Then script = files.BuildPath(script, files.GetFileName(script))
host = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
If Not files.FileExists(script) Then
    MsgBox "Missing Scripts\Manage.ps1. Please copy the complete package.", vbCritical, "Jobs Management"
    WScript.Quit 1
End If
command = Quote(host) & " -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File " & Quote(script)
For index = 0 To WScript.Arguments.Count - 1
    argument = WScript.Arguments(index)
    If InStr(argument, Chr(34)) > 0 Or InStr(argument, vbCr) > 0 Or InStr(argument, vbLf) > 0 Then
        MsgBox "Invalid argument.", vbCritical, "Jobs Management"
        WScript.Quit 1
    End If
    command = command & " " & Quote(argument)
Next
On Error Resume Next
shell.Run command, 0, False
If Err.Number <> 0 Then
    MsgBox Err.Description, vbCritical, "Jobs Management"
    WScript.Quit 1
End If
' Quote literal WScript arguments without changing their contents.
Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
