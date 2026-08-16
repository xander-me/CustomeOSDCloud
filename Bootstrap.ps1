[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $CustomerConfigUri,
    [ValidateSet('ZTI','Hybrid','Interactive')] [string] $Mode,
    [string] $ProfileId,
    [switch] $NoGui
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'src/DeploymentEngine.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'src/DeploymentUI.psm1') -Force

function Get-CustomerConfiguration {
    param([Parameter(Mandatory)][string]$Uri)
    if (Test-Path $Uri) { return (Get-Content -Path $Uri -Raw | ConvertFrom-Json) }
    if ($Uri -notmatch '^https://') { throw 'Remote customer configuration must use HTTPS.' }
    Invoke-RestMethod -Method Get -Uri $Uri -TimeoutSec 20
}

$config=$null; $context=$null
try {
    $config=Get-CustomerConfiguration -Uri $CustomerConfigUri
    if (-not $Mode) { $Mode=$config.deployment.defaultMode }
    if ($Mode -notin @($config.deployment.allowedModes)) { throw "Deployment mode '$Mode' is not allowed for this customer." }

    $context=New-DeploymentContext -Config $config -Mode $Mode
    Send-DeploymentEvent -Context $context -Config $config -Stage 'Bootstrap' -Event 'DeploymentStarted' -Message "Deployment started for $($config.customer.displayName)."

    $preflight=Test-DeploymentPreflight -Config $config
    Send-DeploymentEvent -Context $context -Config $config -Stage 'Preflight' -Event 'PreflightCompleted' -Status 'Succeeded' -Message 'Preflight checks completed.' -Data @{Network=$preflight.Network;Internet=$preflight.Internet;TpmReady=$preflight.TpmReady;SecureBoot=$preflight.SecureBoot}
    if (-not $preflight.Internet) { throw 'Internet connectivity check failed.' }

    if ($NoGui) {
        $selection=Resolve-DeploymentSelection -Config $config -Mode $Mode -ProfileId $ProfileId
    } else {
        $selection=Show-DeploymentUI -Config $config -Context $context -InitialMode $Mode
        if (-not $selection) { Send-DeploymentEvent -Context $context -Config $config -Stage 'Bootstrap' -Event 'DeploymentCancelled' -Status 'Waiting' -Message 'Deployment cancelled by technician.'; return }
        $Mode=$selection.Mode
    }

    $context.Mode=$Mode
    $context | Add-Member -NotePropertyName ProfileId -NotePropertyValue $selection.ProfileId -Force
    $context | Add-Member -NotePropertyName GroupTag -NotePropertyValue $selection.GroupTag -Force
    $context | Add-Member -NotePropertyName WindowsVersion -NotePropertyValue $selection.WindowsVersion -Force
    $context | Add-Member -NotePropertyName Edition -NotePropertyValue $selection.Edition -Force
    $context | Add-Member -NotePropertyName Language -NotePropertyValue $selection.Language -Force
    Save-DeploymentState -Context $context

    Send-DeploymentEvent -Context $context -Config $config -Stage 'Bootstrap' -Event 'DeploymentSelectionConfirmed' -Message "Profile $($selection.ProfileName); $($selection.WindowsVersion) $($selection.Edition); $($selection.Language); GroupTag $($selection.GroupTag)."
    Invoke-OSDCloudDeployment -Selection $selection -Config $config -Context $context -WhatIf:$WhatIfPreference
}
catch {
    if ($context -and $config) { Send-DeploymentEvent -Context $context -Config $config -Stage 'Bootstrap' -Event 'DeploymentFailed' -Status 'Failed' -Severity 'Error' -Message $_.Exception.Message -Data @{exceptionType=$_.Exception.GetType().FullName;scriptStackTrace=$_.ScriptStackTrace} }
    Write-Error $_
    exit 1
}
