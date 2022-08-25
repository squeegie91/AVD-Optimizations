# This scrpt will install Chocolatey Package Manager, update installed applications including Windows and Office then restart the computer on completion

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
 


# Install Chocolatey Package Manager
Write-Host "Installing Chocolatey Package Manager"
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))


# Update Adobe Actobat Reader DC
Write-Host "Updating Adobe Acrobat Reader DC"
choco upgrade adobereader -y -yes -confirm


# Update Microsoft Edge
Write-Host "Updating Microsoft Edge"
choco upgrade microsoft-edge -y -yes -confirm


# Update Google Chrome
Write-Host "Updating Google Chrome"
choco upgrade googlechrome -y -yes -confirm
