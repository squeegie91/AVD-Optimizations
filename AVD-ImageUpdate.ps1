# This script will stop relevant services/tasks, uninstall Chocolatey Package Manager, clean up the OS then shutdown the VM to prepare it for snapshotting

#Run As Admin
param([switch]$Elevated)

function Check-Admin {
$currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
$currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if ((Check-Admin) -eq $false) {
if ($elevated)
{

# could not elevate, quit
}
else {
Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -executionpolicy bypass -noexit -file "{0}" -elevated' -f ($myinvocation.MyCommand.Definition))

}
exit
}

# Stop and Disable Services
Write-Host "Stopping and Disabling Services"
Stop-Service -Name bits
Stop-Service -Name wuauserv
Set-Service -Name bits -StartupType Disabled
Set-Service -Name gupdate -DisplayName "Google Update Service (gupdate)" -StartupType Disabled
Set-Service -Name gupdatem -DisplayName "Google Update Service (gupdatem)" -StartupType Disabled
Set-Service -Name edgeupdate -DisplayName "Microsoft Edge Update Service (edgeupdate)" -StartupType Disabled
Set-Service -Name edgeupdatem -DisplayName "Microsoft Edge Update Service (edgeupdatem)" -StartupType Disabled

# Disable Windows Updates
REG ADD HKLM\SYSTEM\CurrentControlSet\Services\WaasMedicSvc /v Start /f /t REG_DWORD /d 4
Set-Service -Name wuauserv -StartupType Disabled

# Disable Scheduled Tasks
Write-Host "Disabling Scheduled Tasks"
Disable-ScheduledTask -TaskName "Adobe Acrobat Update Task"
Disable-ScheduledTask -TaskName "GoogleUpdateTaskMachineCore"
Disable-ScheduledTask -TaskName "GoogleUpdateTaskMachineUA"
Disable-ScheduledTask -TaskName "MicrosoftEdgeUpdateTaskMachineCore"
Disable-ScheduledTask -TaskName "MicrosoftEdgeUpdateTaskMachineUA"



# Uninstall Chocolatey Package Manager
Write-Host "Uninstalling Chocolatey Package Manager"
Remove-Item -Path "C:\ProgramData\chocolatey" -Recurse -Force



# Clean up Image
Write-Host "Cleaning up Image"
#Remove-Item -Path "C:\Users\Public\Desktop\*" -Recurse -Force
Remove-Item -Path $Env:TEMP\* -Recurse -Force
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force
Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force

cd "C:\RSAdmin\CitrixOptimizer"
Get-ChildItem -Path 'C:\RSAdmin\CitrixOptimizer' -Recurse | Unblock-File
.\CtxOptimizerEngine.ps1 -Source Citrix_Windows_10_2009.xml -Mode Execute


# Set Execution Policy
Write-Host "Setting PowerShell Execution Policy to Default"
Set-ExecutionPolicy Default -Force
