[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$SQLServerISOUri
)

$ProgressPreference = 'SilentlyContinue';

Write-Host "Creating installers folder..."
$installersPath = "C:\installers"
New-Item -Path $installersPath -ItemType Directory -Force

Write-Host "Downloading SQL Server 2022 ISO..."
Invoke-WebRequest -Uri $SQLServerISOUri `
                  -OutFile "$installersPath\SQLServer2022-x64-ENU-Dev.iso"

Write-Host "Done"