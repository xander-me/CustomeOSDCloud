[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $CustomerConfigUri,
    [ValidateSet('ZTI','Hybrid','Interactive')] [string] $Mode,
    [string] $ProfileId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'src/DeploymentEngine.psm1'
Import-Module $modulePath -Force

function Get-CustomerConfiguration {
    param([Parameter(Mandatory)][string]$Uri)

    if (Test-Path $Uri) {
        return (Get-Content -Path $Uri -Raw | ConvertFrom-Json)
    }

    if ($Uri -notmatch '^https://') { throw 'Remote customer configuration must use HTTPS.' }
    Invoke-RestMethod -Method Get -Uri $Uri -TimeoutSec 20
}

try {
    $config = Get-CustomerConfiguration -Uri $CustomerConfigUri
    if (-not $Mode) { $Mode = $config.deployment.defaultMode }
    if ($Mode -notin @($config.deployment.allowedModes)) { throw "Deployment mode '$Mode' is not allowed for this customer." }

    $context = New-DeploymentContext -Config $config -Mode $Mode
    Send-DeploymentEvent -Context $context -Config $config -Stage 'Bootstrap' -Event 'DeploymentStarted' -Message "Deployment started for $($config.customer.displayName)."

    $preflight = Test-DeploymentPreflight -Config $config
    Send-DeploymentEvent -Context $context -Config $config -Stage 'Preflight' -Event 'PreflightCompleted' -Status 'Succeeded' -Message 'Preflight checks completed.' -Data @{ Network=$preflight.Network; Internet=$preflight.Internet; TpmReady=$preflight.TpmReady; SecureBoot=$preflight.SecureBoot }

    if (-not $preflight.Internet) { throw 'Internet connectivity check failed.' }
    if (-not $preflight.TpmReady) { Write-Warning 'TPM is not ready. Autopilot readiness may be affected.' }
    if (-not $preflight.SecureBoot) { Write-Warning 'Secure Boot is not confirmed.' }

    $selection = Resolve-DeploymentSelection -Config $config -Mode $Mode -ProfileId $ProfileId
    $context | Add-Member -NotePropertyName ProfileId -NotePropertyValue $selection.ProfileId -Force
    $context | Add-Member -NotePropertyName GroupTag -NotePropertyValue $selection.GroupTag -Force

    Write-Host ''
    Write-Host $config.customer.branding.heading
    Write-Host ('=' * $config.customer.branding.heading.Length)
    Write-Host "Customer : $($config.customer.displayName)"
    Write-Host "Mode     : $Mode"
    Write-Host "Profile  : $($selection.ProfileName)"
    Write-Host "Windows  : $($selection.WindowsVersion) $($selection.Edition)"
    Write-Host "Language : $($selection.Language)"
    Write-Host "Drivers  : $($selection.Drivers)"
    Write-Host "GroupTag : $($selection.GroupTag)"
    Write-Host "Deploy ID: $($context.DeploymentId)"
    Write-Host ''

    Save-DeploymentState -Context $context
    Invoke-OSDCloudDeployment -Selection $selection -Config $config -Context $context -WhatIf:$WhatIfPreference
}
catch {
    if ($context -and $config) {
        Send-DeploymentEvent -Context $context -Config $config -Stage 'Bootstrap' -Event 'DeploymentFailed' -Status 'Failed' -Severity 'Error' -Message $_.Exception.Message -Data @{ exceptionType=$_.Exception.GetType().FullName; scriptStackTrace=$_.ScriptStackTrace }
    }
    Write-Error $_
    exit 1
}
