[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $CustomerConfigUri,
    [Parameter(Mandatory)] [pscustomobject] $Context,
    [string] $WindowsDrive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-OfflineWindowsDrive {
    $candidates = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter -and $_.DriveLetter -ne 'X' }
    foreach ($volume in $candidates) {
        $root = "$($volume.DriveLetter):\"
        if ((Test-Path (Join-Path $root 'Windows\System32\Config\SYSTEM')) -and (Test-Path (Join-Path $root 'Windows\System32\Sysprep\Sysprep.exe'))) {
            return $root.TrimEnd('\')
        }
    }
    throw 'Unable to locate the offline Windows installation.'
}

if (-not $WindowsDrive) { $WindowsDrive = Find-OfflineWindowsDrive }
$targetRoot = Join-Path $WindowsDrive 'ProgramData\OSDDeployment'
$targetSrc = Join-Path $targetRoot 'src'
New-Item -ItemType Directory -Path $targetSrc -Force | Out-Null

$Context | Add-Member -NotePropertyName CustomerConfigUri -NotePropertyValue $CustomerConfigUri -Force
$Context | Add-Member -NotePropertyName HandoffCreatedUtc -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
$Context | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $targetRoot 'state.json') -Encoding UTF8 -Force

Copy-Item (Join-Path $PSScriptRoot 'DeploymentEngine.psm1') (Join-Path $targetSrc 'DeploymentEngine.psm1') -Force
Copy-Item (Join-Path $PSScriptRoot 'PostInstall.ps1') (Join-Path $targetSrc 'PostInstall.ps1') -Force

$escapedUri = $CustomerConfigUri.Replace("'", "''")
$setupScript = @"
`$ErrorActionPreference = 'Stop'
`$logRoot = 'C:\ProgramData\OSDDeployment'
Start-Transcript -Path (Join-Path `$logRoot 'SetupComplete.log') -Append -Force
try {
    `$ps = Join-Path `$logRoot 'src\PostInstall.ps1'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `$ps -CustomerConfigUri '$escapedUri'
    if (`$LASTEXITCODE -ne 0) { throw "PostInstall exited with code `$LASTEXITCODE" }
}
catch {
    Write-Error `$_
    exit 1
}
finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}
"@

$setupDir = Join-Path $WindowsDrive 'Windows\Setup\Scripts'
New-Item -ItemType Directory -Path $setupDir -Force | Out-Null
$setupScript | Set-Content -Path (Join-Path $setupDir 'SetupComplete.cmd.ps1') -Encoding UTF8 -Force

$cmd = @'
@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\Windows\Setup\Scripts\SetupComplete.cmd.ps1"
exit /b %ERRORLEVEL%
'@
$cmd | Set-Content -Path (Join-Path $setupDir 'SetupComplete.cmd') -Encoding ASCII -Force

Write-Host "Post-install handoff installed into $WindowsDrive"
