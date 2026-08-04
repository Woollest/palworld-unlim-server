Option Explicit

Dim shell, fso, scriptPath, powershellPath, command, exitCode, index
If WScript.Arguments.Count < 1 Then
    WScript.Quit 2
End If

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptPath = fso.GetAbsolutePathName(WScript.Arguments(0))
shell.CurrentDirectory = fso.GetParentFolderName(fso.GetParentFolderName(scriptPath))
powershellPath = shell.ExpandEnvironmentStrings("%ProgramFiles%\PowerShell\7\pwsh.exe")
If Not fso.FileExists(powershellPath) Then
    powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
End If
command = """" & powershellPath & """ -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & scriptPath & """"
For index = 1 To WScript.Arguments.Count - 1
    command = command & " " & WScript.Arguments(index)
Next

exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
