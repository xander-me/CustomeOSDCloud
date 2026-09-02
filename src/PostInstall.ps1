[CmdletBinding()]
param(
    [string] $StatePath = 'C:\ProgramData\OSDDeployment\state.json',
    [Parameter(Mandatory)] [string] $CustomerConfigUri,
    [switch] $SkipAutopilot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'DeploymentEngine.psm1') -Force

function Get-CustomerConfiguration {
    param([Parameter(Mandatory)][string]$Uri)
    if (Test-Path $Uri) { return (Get-Content -Path $Uri -Raw | ConvertFrom-Json) }
    if ($Uri -notmatch '^https://') { throw 'Remote customer configuration must use HTTPS.' }
    Invoke-RestMethod -Method Get -Uri $Uri -TimeoutSec 20
}

if (-not (Test-Path $StatePath)) { throw "Deployment state not found: $StatePath" }
$config = Get-CustomerConfiguration -Uri $CustomerConfigUri
$context = Get-Content -Path $StatePath -Raw | ConvertFrom-Json

try {
    Send-DeploymentEvent -Context $context -Config $config -Stage 'WindowsBoot' -Event 'PostInstallStarted' -Message 'Post-install runner started in installed Windows.'

    if ($config.regional.timeZone) {
        Set-TimeZone -Id $config.regional.timeZone -ErrorAction Stop
        Send-DeploymentEvent -Context $context -Config $config -Stage 'PostInstall' -Event 'TimeZoneConfigured' -Status 'Succeeded' -Message "Timezone set to $($config.regional.timeZone)."
    }

    try { w32tm.exe /resync /force | Out-Null } catch { Write-Warning $_.Exception.Message }

    if (-not $SkipAutopilot -and $config.autopilot.enabled) {
        $selection = [pscustomobject]@{
            ProfileId=$context.ProfileId; ProfileName=$context.ProfileId; WindowsVersion=$context.WindowsVersion
            Edition=$context.Edition; Language=$context.Language; Drivers='Auto'; GroupTag=$context.GroupTag; Mode=$context.Mode
        }
        Invoke-AutopilotRegistration -Selection $selection -Config $config -Context $context
    }

    $context.Stage='ReadyForOOBE'; $context.Status='Succeeded'
    Save-DeploymentState -Context $context -Path $StatePath
    Send-DeploymentEvent -Context $context -Config $config -Stage 'ReadyForOOBE' -Event 'PostInstallCompleted' -Status 'Succeeded' -Message 'Post-install workflow completed. Device is ready to return to OOBE.'
}
catch {
    $context.Status='Failed'; Save-DeploymentState -Context $context -Path $StatePath
    Send-DeploymentEvent -Context $context -Config $config -Stage 'PostInstall' -Event 'PostInstallFailed' -Status 'Failed' -Severity 'Error' -Message $_.Exception.Message -Data @{exceptionType=$_.Exception.GetType().FullName;scriptStackTrace=$_.ScriptStackTrace}
    throw
}
