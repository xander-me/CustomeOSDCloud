Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-DeploymentContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Config,
        [Parameter(Mandatory)] [ValidateSet('ZTI','Hybrid','Interactive')] [string] $Mode
    )

    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue

    [pscustomobject]@{
        DeploymentId = [guid]::NewGuid().ToString()
        CustomerId   = $Config.customer.id
        CustomerName = $Config.customer.displayName
        Mode          = $Mode
        StartedUtc    = [datetime]::UtcNow.ToString('o')
        SerialNumber  = $bios.SerialNumber
        Manufacturer  = $computer.Manufacturer
        Model         = $computer.Model
        Stage         = 'Bootstrap'
        Status        = 'Running'
    }
}

function Send-DeploymentEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [Parameter(Mandatory)] [pscustomobject] $Config,
        [Parameter(Mandatory)] [string] $Stage,
        [Parameter(Mandatory)] [string] $Event,
        [ValidateSet('Running','Succeeded','Failed','Waiting')] [string] $Status = 'Running',
        [ValidateSet('Information','Warning','Error')] [string] $Severity = 'Information',
        [string] $Message,
        [hashtable] $Data
    )

    $payload = [ordered]@{
        schemaVersion = '1.0'
        deploymentId  = $Context.DeploymentId
        customerId    = $Context.CustomerId
        timestampUtc  = [datetime]::UtcNow.ToString('o')
        device        = @{
            serialNumber = $Context.SerialNumber
            manufacturer = $Context.Manufacturer
            model        = $Context.Model
        }
        stage    = $Stage
        event    = $Event
        status   = $Status
        severity = $Severity
        message  = $Message
        data     = $Data
    }

    $json = $payload | ConvertTo-Json -Depth 8 -Compress
    Write-Host "[$Stage][$Status] $Message"

    if ($Config.telemetry.enabled -and $Config.telemetry.endpoint) {
        try {
            Invoke-RestMethod -Method Post -Uri $Config.telemetry.endpoint -ContentType 'application/json' -Body $json -TimeoutSec 10 | Out-Null
        }
        catch {
            Write-Warning "Telemetry delivery failed: $($_.Exception.Message)"
        }
    }
}

function Save-DeploymentState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [string] $Path = 'C:\ProgramData\OSDDeployment\state.json'
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $Context | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8 -Force
}

function Test-DeploymentPreflight {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [pscustomobject] $Config)

    $checks = [ordered]@{}
    $checks.Network = [bool](Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1)
    try { $checks.Internet = Test-NetConnection -ComputerName 'www.microsoft.com' -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue } catch { $checks.Internet = $false }

    try {
        $tpm = Get-Tpm -ErrorAction Stop
        $checks.TpmReady = [bool]$tpm.TpmReady
    } catch { $checks.TpmReady = $false }

    try { $checks.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $checks.SecureBoot = $false }

    [pscustomobject]$checks
}

function Resolve-DeploymentSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Config,
        [Parameter(Mandatory)] [ValidateSet('ZTI','Hybrid','Interactive')] [string] $Mode,
        [string] $ProfileId
    )

    $profiles = @($Config.deployment.profiles)
    $profile = if ($ProfileId) { $profiles | Where-Object id -EQ $ProfileId | Select-Object -First 1 } else { $profiles | Where-Object default -EQ $true | Select-Object -First 1 }
    if (-not $profile) { throw 'No deployment profile could be resolved.' }

    [pscustomobject]@{
        ProfileId      = $profile.id
        ProfileName    = $profile.displayName
        WindowsVersion = $profile.windowsVersion
        Edition        = $profile.edition
        Language       = $profile.language
        Drivers        = $profile.drivers
        GroupTag       = $profile.groupTag
        Mode           = $Mode
    }
}

function Invoke-OSDCloudDeployment {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Selection,
        [Parameter(Mandatory)] [pscustomobject] $Config,
        [Parameter(Mandatory)] [pscustomobject] $Context
    )

    Send-DeploymentEvent -Context $Context -Config $Config -Stage 'OSDCloud' -Event 'DeploymentPrepared' -Message "Prepared $($Selection.WindowsVersion) $($Selection.Edition), $($Selection.Language), drivers $($Selection.Drivers)."

    if (-not $PSCmdlet.ShouldProcess($Context.SerialNumber, 'Wipe disk and start OSDCloud deployment')) { return }

    # Deliberately guarded in V0.1. The production Start-OSDCloud invocation will be
    # implemented after parameter mapping is validated against the target OSDCloud release.
    throw 'Destructive OSDCloud execution is not enabled in V0.1.'
}

function Invoke-AutopilotRegistration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Selection,
        [Parameter(Mandatory)] [pscustomobject] $Config,
        [Parameter(Mandatory)] [pscustomobject] $Context
    )

    if (-not $Config.autopilot.enabled) { return }
    Send-DeploymentEvent -Context $Context -Config $Config -Stage 'Autopilot' -Event 'AuthenticationRequired' -Status 'Waiting' -Message 'Interactive Microsoft authentication is required for Autopilot registration.'

    if ($PSCmdlet.ShouldProcess($Context.SerialNumber, "Register with Autopilot using GroupTag '$($Selection.GroupTag)'")) {
        # No tenant credentials are persisted. Production implementation will invoke
        # Get-WindowsAutopilotInfo/Graph through interactive authentication.
        Write-Host "Autopilot registration prepared. GroupTag: $($Selection.GroupTag)"
    }
}

Export-ModuleMember -Function New-DeploymentContext,Send-DeploymentEvent,Save-DeploymentState,Test-DeploymentPreflight,Resolve-DeploymentSelection,Invoke-OSDCloudDeployment,Invoke-AutopilotRegistration
