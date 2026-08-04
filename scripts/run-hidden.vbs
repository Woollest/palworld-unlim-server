Option Explicit

Dim shell, fso, scriptPath, powershellPath, command, exitCode
If WScript.Arguments.Count < 1 Then
    WScript.Quit 2
End If

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptPath = fso.GetAbsolutePathName(WScript.Arguments(0))
shell.CurrentDirectory = fso.GetParentFolderName(fso.GetParentFolderName(scriptPath))
powershellPath = shell.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
command = """" & powershellPath & """ -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & scriptPath & """"

' Window style 0 runs without creating a visible console window.
' Wait for completion so Task Scheduler receives the real exit code and can retry failures.
exitCode = shell.Run(command, 0, True)
WScript.Quit exitCode
