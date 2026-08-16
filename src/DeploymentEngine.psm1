Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DeploymentContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$Config,[Parameter(Mandatory)][ValidateSet('ZTI','Hybrid','Interactive')][string]$Mode)
    $bios=Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue; $computer=Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    [pscustomobject]@{DeploymentId=[guid]::NewGuid().ToString();CustomerId=$Config.customer.id;CustomerName=$Config.customer.displayName;Mode=$Mode;StartedUtc=[datetime]::UtcNow.ToString('o');SerialNumber=$bios.SerialNumber;Manufacturer=$computer.Manufacturer;Model=$computer.Model;Stage='Bootstrap';Status='Running'}
}

function Send-DeploymentEvent {
    [CmdletBinding()] param([Parameter(Mandatory)][pscustomobject]$Context,[Parameter(Mandatory)][pscustomobject]$Config,[Parameter(Mandatory)][string]$Stage,[Parameter(Mandatory)][string]$Event,[ValidateSet('Running','Succeeded','Failed','Waiting')][string]$Status='Running',[ValidateSet('Information','Warning','Error')][string]$Severity='Information',[string]$Message,[hashtable]$Data)
    $payload=[ordered]@{schemaVersion='1.0';deploymentId=$Context.DeploymentId;customerId=$Context.CustomerId;timestampUtc=[datetime]::UtcNow.ToString('o');device=@{serialNumber=$Context.SerialNumber;manufacturer=$Context.Manufacturer;model=$Context.Model};stage=$Stage;event=$Event;status=$Status;severity=$Severity;message=$Message;data=$Data}
    $json=$payload|ConvertTo-Json -Depth 8 -Compress; Write-Host "[$Stage][$Status] $Message"
    if($Config.telemetry.enabled -and $Config.telemetry.endpoint){try{Invoke-RestMethod -Method Post -Uri $Config.telemetry.endpoint -ContentType 'application/json' -Body $json -TimeoutSec 10|Out-Null}catch{Write-Warning "Telemetry delivery failed: $($_.Exception.Message)"}}
}

function Save-DeploymentState { [CmdletBinding()] param([Parameter(Mandatory)][pscustomobject]$Context,[string]$Path='C:\ProgramData\OSDDeployment\state.json'); $directory=Split-Path -Parent $Path;if(-not(Test-Path $directory)){New-Item -ItemType Directory -Path $directory -Force|Out-Null};$Context|ConvertTo-Json -Depth 6|Set-Content -Path $Path -Encoding UTF8 -Force }

function Test-DeploymentPreflight { [CmdletBinding()] param([Parameter(Mandatory)][pscustomobject]$Config);$checks=[ordered]@{};$checks.Network=[bool](Get-NetIPConfiguration -ErrorAction SilentlyContinue|Where-Object{$_.IPv4DefaultGateway}|Select-Object -First 1);try{$checks.Internet=Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue}catch{$checks.Internet=$false};try{$tpm=Get-Tpm -ErrorAction Stop;$checks.TpmReady=[bool]$tpm.TpmReady}catch{$checks.TpmReady=$false};try{$checks.SecureBoot=[bool](Confirm-SecureBootUEFI -ErrorAction Stop)}catch{$checks.SecureBoot=$false};[pscustomobject]$checks }

function Resolve-DeploymentSelection { [CmdletBinding()] param([Parameter(Mandatory)][pscustomobject]$Config,[Parameter(Mandatory)][ValidateSet('ZTI','Hybrid','Interactive')][string]$Mode,[string]$ProfileId);$profiles=@($Config.deployment.profiles);$profile=if($ProfileId){$profiles|Where-Object id -EQ $ProfileId|Select-Object -First 1}else{$profiles|Where-Object default -EQ $true|Select-Object -First 1};if(-not$profile){throw 'No deployment profile could be resolved.'};[pscustomobject]@{ProfileId=$profile.id;ProfileName=$profile.displayName;WindowsVersion=$profile.windowsVersion;Edition=$profile.edition;Language=$profile.language;Drivers=$profile.drivers;GroupTag=$profile.groupTag;Mode=$Mode} }

function Invoke-OSDCloudDeployment {
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='High')] param([Parameter(Mandatory)][pscustomobject]$Selection,[Parameter(Mandatory)][pscustomobject]$Config,[Parameter(Mandatory)][pscustomobject]$Context)
    if($env:SystemDrive -ne 'X:'){throw 'Disk wipe is only permitted when running from WinPE (SystemDrive X:).'};if(-not(Get-Command Start-OSDCloud -ErrorAction SilentlyContinue)){throw 'Start-OSDCloud is not available. Import/install the OSD module in WinPE first.'}
    $fixedDisks=@(Get-Disk -ErrorAction Stop|Where-Object{$_.BusType -ne 'USB' -and -not $_.IsBoot});if($fixedDisks.Count -eq 0){throw 'No non-USB target disk was found.'}
    Send-DeploymentEvent -Context $Context -Config $Config -Stage 'DiskPreparation' -Event 'DiskWipePending' -Status 'Waiting' -Severity 'Warning' -Message "OSDCloud is ready to clear the target disk and deploy $($Selection.WindowsVersion)." -Data @{disks=@($fixedDisks|ForEach-Object{@{number=$_.Number;friendlyName=$_.FriendlyName;size=$_.Size}})}
    $target=if($Context.SerialNumber){"$($Context.Manufacturer) $($Context.Model) [$($Context.SerialNumber)]"}else{"$($Context.Manufacturer) $($Context.Model)"};if(-not$PSCmdlet.ShouldProcess($target,'CLEAR TARGET DISK and start OSDCloud deployment')){Send-DeploymentEvent -Context $Context -Config $Config -Stage 'DiskPreparation' -Event 'DiskWipeCancelled' -Status 'Waiting' -Message 'Disk wipe was cancelled or simulated with WhatIf.';return}
    $osName=$Selection.WindowsVersion;if($osName -notmatch 'x64$'){$osName="$osName x64"};$params=@{OSName=$osName;OSEdition=$Selection.Edition;OSLanguage=$Selection.Language};if($Selection.Mode -eq 'ZTI'){$params.ZTI=$true}
    Send-DeploymentEvent -Context $Context -Config $Config -Stage 'DiskPreparation' -Event 'DiskWipeStarted' -Message 'Handing control to OSDCloud. Target disk clear is enabled.';Send-DeploymentEvent -Context $Context -Config $Config -Stage 'WindowsInstallation' -Event 'OSDCloudStarted' -Message "Starting OSDCloud with OSName '$osName', edition '$($Selection.Edition)', language '$($Selection.Language)'."
    try{Start-OSDCloud @params;Send-DeploymentEvent -Context $Context -Config $Config -Stage 'WindowsInstallation' -Event 'OSDCloudReturned' -Status 'Succeeded' -Message 'OSDCloud deployment engine returned successfully.'}catch{Send-DeploymentEvent -Context $Context -Config $Config -Stage 'WindowsInstallation' -Event 'OSDCloudFailed' -Status 'Failed' -Severity 'Error' -Message $_.Exception.Message -Data @{exceptionType=$_.Exception.GetType().FullName;scriptStackTrace=$_.ScriptStackTrace};throw}
}

function Invoke-AutopilotRegistration {
    [CmdletBinding(SupportsShouldProcess)] param([Parameter(Mandatory)][pscustomobject]$Selection,[Parameter(Mandatory)][pscustomobject]$Config,[Parameter(Mandatory)][pscustomobject]$Context)
    if(-not $Config.autopilot.enabled){return};if($Config.autopilot.authentication -ne 'Interactive'){throw "Unsupported Autopilot authentication mode: $($Config.autopilot.authentication)"}
    if($env:SystemDrive -eq 'X:'){throw 'Autopilot registration must run from installed Windows, not WinPE.'}
    Send-DeploymentEvent -Context $Context -Config $Config -Stage 'AutopilotAuthentication' -Event 'AuthenticationRequired' -Status 'Waiting' -Message 'Microsoft Entra interactive authentication is required. MFA and Conditional Access are handled by Microsoft.'
    if(-not$PSCmdlet.ShouldProcess($Context.SerialNumber,"Register with Windows Autopilot using GroupTag '$($Selection.GroupTag)'")){return}

    $scriptPath=Join-Path $env:TEMP 'Get-WindowsAutopilotInfo.ps1'
    try{
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        Save-Script -Name Get-WindowsAutopilotInfo -Path $env:TEMP -Force -ErrorAction Stop
        if(-not(Test-Path $scriptPath)){throw 'Get-WindowsAutopilotInfo.ps1 was not downloaded from PowerShell Gallery.'}
        Send-DeploymentEvent -Context $Context -Config $Config -Stage 'AutopilotAuthentication' -Event 'AuthenticationStarted' -Message 'Starting Microsoft interactive authentication for Autopilot registration.'
        $apParams=@{Online=$true;Assign=$true};if($Selection.GroupTag){$apParams.GroupTag=$Selection.GroupTag}
        & $scriptPath @apParams
        if($LASTEXITCODE -and $LASTEXITCODE -ne 0){throw "Get-WindowsAutopilotInfo exited with code $LASTEXITCODE"}
        Send-DeploymentEvent -Context $Context -Config $Config -Stage 'AutopilotRegistration' -Event 'AutopilotImportCompleted' -Status 'Succeeded' -Message "Autopilot import completed for GroupTag '$($Selection.GroupTag)'. The script was instructed to wait for profile assignment."
    }catch{
        Send-DeploymentEvent -Context $Context -Config $Config -Stage 'AutopilotRegistration' -Event 'AutopilotImportFailed' -Status 'Failed' -Severity 'Error' -Message $_.Exception.Message -Data @{exceptionType=$_.Exception.GetType().FullName;scriptStackTrace=$_.ScriptStackTrace};throw
    }finally{if(Test-Path $scriptPath){Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue}}
}

Export-ModuleMember -Function New-DeploymentContext,Send-DeploymentEvent,Save-DeploymentState,Test-DeploymentPreflight,Resolve-DeploymentSelection,Invoke-OSDCloudDeployment,Invoke-AutopilotRegistration
