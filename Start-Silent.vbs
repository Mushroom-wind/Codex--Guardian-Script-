' Start LocalAI Guardian in a hidden PowerShell window.
Option Explicit

Dim fso, shell, scriptDir, guardName, guardPath, command
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
guardName = ChrW(&H770B) & ChrW(&H95E8) & ChrW(&H72D7)
guardPath = scriptDir & "\" & guardName & ".ps1"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & guardPath & """"

shell.Run command, 0, False
