$ErrorActionPreference = 'Stop'

Start-Transcript -Path "$env:TEMP\DefaultBoot.log" -Force

wpeutil InitializeNetwork
Start-Sleep -Seconds 10

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Install-PackageProvider -Name NuGet -Force -Scope AllUsers
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Install-Module OSD -Force -AllowClobber
Import-Module OSD -Force

Start-OSDCloud `
    -OSName 'Windows 11 25H2 x64' `
    -OSEdition 'Pro' `
    -OSLanguage 'en-us' `
    -OSActivation Retail `
    -Firmware `
    -ZTI

$ScriptsPath = 'C:\Windows\Setup\Scripts'
New-Item -Path $ScriptsPath -ItemType Directory -Force | Out-Null

@'
@echo off
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v AutopilotRegister /t REG_SZ /d "powershell.exe -ExecutionPolicy Bypass -NoExit -File C:\OSDCloud\Scripts\AutopilotRegister.ps1" /f
net user Administrator /active:yes
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d Administrator /f
shutdown /r /t 5
'@ | Out-File "$ScriptsPath\SetupComplete.cmd" -Encoding ascii -Force

New-Item -Path 'C:\OSDCloud\Scripts' -ItemType Directory -Force | Out-Null

@'
$ErrorActionPreference = 'Stop'

Start-Transcript -Path 'C:\Windows\Temp\AutopilotRegister.log' -Force

Set-ExecutionPolicy Bypass -Scope Process -Force

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Install-PackageProvider -Name NuGet -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Script Get-WindowsAutopilotInfo -Force

$AssignedUser = Read-Host "Enter assigned user UPN, or press Enter to skip"
$GroupTag = Read-Host "Enter Autopilot Group Tag, or press Enter to skip"

$Params = @{
    Online = $true
    Assign = $true
}

if ($AssignedUser) {
    $Params.AssignedUser = $AssignedUser
}

if ($GroupTag) {
    $Params.GroupTag = $GroupTag
}

Get-WindowsAutopilotInfo @Params

reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" /v AutopilotRegister /f 2>$null
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /f 2>$null
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /f 2>$null
net user Administrator /active:no

Stop-Transcript

Start-Process -FilePath "$env:WINDIR\System32\Sysprep\Sysprep.exe" -ArgumentList "/oobe /shutdown /quiet" -Wait
'@ | Out-File 'C:\OSDCloud\Scripts\AutopilotRegister.ps1' -Encoding ascii -Force

Stop-Transcript

wpeutil reboot
