Option Explicit
Dim shell, fso, base, windowsDir, processEnv, command, result
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
base = fso.GetParentFolderName(WScript.ScriptFullName)
' Some launch hosts omit these variables. Windows PowerShell needs them even
' before it can execute a script, so repair the child environment here.
windowsDir = fso.GetSpecialFolder(0).Path
Set processEnv = shell.Environment("Process")
processEnv("SystemRoot") = windowsDir
processEnv("windir") = windowsDir
command = """" & windowsDir & "\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "\CodexStatusWidget.ps1"""
On Error Resume Next
result = shell.Run(command, 0, True)
If Err.Number <> 0 Then
    MsgBox "Unable to launch Codex Status: " & Err.Description, vbExclamation, "Codex Status"
    WScript.Quit 1
End If
On Error GoTo 0
If result <> 0 Then
    MsgBox "Codex Status exited with code " & result & ". See CodexStatusWidget-errors.log in " & base, vbExclamation, "Codex Status"
End If
WScript.Quit result
