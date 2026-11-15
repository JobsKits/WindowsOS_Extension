Option Explicit
' Created by Jobs on 2026-10-28. WScript launches the management GUI without a console.
Dim shell, files, folder, script, host, command, argument, index
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = files.GetParentFolderName(WScript.ScriptFullName)
script = files.BuildPath(folder, "Scripts\Manage.ps1")
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
Function Quote(value)
    Quote = Chr(34) & value & Chr(34)
End Function
