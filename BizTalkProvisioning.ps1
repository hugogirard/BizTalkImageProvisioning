$ProgressPreference = 'SilentlyContinue';
$ErrorActionPreference = "Stop"
Set-StrictMode -version Latest

# taken from https://stackoverflow.com/a/77469034
# adapted
function Install-VSCode-Windows {
    param (
        [Parameter()]
        [ValidateSet('local','global')]
        [string[]]$Scope = 'global'
    )

    # Windows Version x64
    # Define the download URL and the destination
    $Destination = "$installersPath\vscode_installer.exe"
    $Url = "https://code.visualstudio.com/sha/download?build=stable&os=win32-x64"

    # User Installation
    if ($Scope  -eq 'local') {
        $VSCodeUrl = $VSCodeUrl + '-user'
    }

    $UnattendedArgs = '/verysilent /mergetasks=!runcode'

    # Download VSCode installer
    Write-Host "Downloading VSCode"
    Invoke-WebRequest -Uri $Url -OutFile $Destination # Install VS Code silently
    Write-Host "Download finished"

    # Install VSCode
    Write-Host "Installing VSCode"
    Start-Process -FilePath $Destination -ArgumentList $UnattendedArgs -Wait -Passthru
    Write-Host "Installation finished"

    # Remove installer
    Write-Host "Removing installation file"
    Remove-Item $Destination
    Write-Host "Installation file removed"
}

function Install-Dotnet8 {
    $Destination = "$installersPath\dotnet-sdk-8.0.101-win-x64.exe"
    $Url = "https://download.visualstudio.microsoft.com/download/pr/cb56b18a-e2a6-4f24-be1d-fc4f023c9cc8/be3822e20b990cf180bb94ea8fbc42fe/dotnet-sdk-8.0.101-win-x64.exe"
    $UnattendedArgs = '/install /quiet /norestart'

    # Download Dotnet 8 SDK installer
    Write-Host "Downloading Dotnet 8"
    Invoke-WebRequest -Uri $Url -OutFile $Destination
    Write-Host "Download finished"

    # Install Dotnet 8 SDK
    Write-Host "Installing Dotnet 8"
    Start-Process -FilePath $Destination -ArgumentList $UnattendedArgs -Wait -Passthru
    Write-Host "Installation finished"

    # Remove installer
    Write-Host "Removing installation file"
    Remove-Item $Destination
    Write-Host "Installation file removed"
}

function Install-AzureCLI {
    $Destination = "$installersPath\AzureCLI.msi"
    $Url = "https://aka.ms/installazurecliwindows"
    $UnattendedArgs = "/I $installersPath\AzureCLI.msi /quiet"

    # Download Azure CLI installer
    Write-Host "Downloading Azure CLI"
    Invoke-WebRequest -Uri $Url -OutFile $Destination
    Write-Host "Download finished"

    # Install Dotnet 8 SDK
    Write-Host "Installing Azure CLI"
    Start-Process msiexec.exe -ArgumentList $UnattendedArgs -Wait
    Write-Host "Installation finished"

    # Remove installer
    Write-Host "Removing installation file"
    Remove-Item $Destination
    Write-Host "Installation file removed"
}

function Install-VSStudio {
    $Destination = "$installersPath\vs_community.exe"
    $Url = "https://aka.ms/vs/16/release/vs_community.exe"
    # see https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2022
    $UnattendedArgs = "--quiet --norestart --installWhileDownloading --addProductLang Fr-fr"

    # Download Azure CLI installer
    Write-Host "Downloading VS Studio Community Edition"
    Invoke-WebRequest -Uri $Url -OutFile $Destination
    Write-Host "Download finished"

    # Install Dotnet 8 SDK
    Write-Host "Installing VS Studio Community Edition"
    Start-Process -FilePath $Destination -ArgumentList $UnattendedArgs -Wait
    Write-Host "Installation finished"

    # Remove installer
    Write-Host "Removing installation file"
    Remove-Item $Destination
    Write-Host "Installation file removed"
}

function Install-SQLServer {
    $ISOFile = "$installersPath\SQLServer2022-x64-ENU-Dev.iso"

    $mountResult = Mount-DiskImage -ImagePath $ISOFile
    $driveLetter = ($mountResult | Get-Volume).DriveLetter

    # see https://learn.microsoft.com/en-us/sql/database-engine/install-windows/install-sql-server-from-the-command-prompt?view=sql-server-ver16
    # PIDs:
    # Evaluation: 00000-00000-00000-00000-00000
    # Express: 11111-00000-00000-00000-00000
    # Developer: 22222-00000-00000-00000-00000
    $UnattendedArgs = '/ConfigurationFile=C:\installers\SQLConfig.ini /IAcceptSQLServerLicenseTerms=true'

    # Install SQL Server
    Write-Host "Installing SQL Server"
    Start-Process -FilePath "$($driveLetter):\setup.exe" -ArgumentList $UnattendedArgs -Wait
    Write-Host "Installation finished"

    Dismount-DiskImage -ImagePath $ISOFile

    # Azure's SetupComplete.cmd looks for a %SystemRoot%\OEM\SetupComplete2.cmd file and runs it
    # see https://matt.kotsenas.com/posts/azure-setupcomplete2
    Write-Host "Create SetupComplete2.cmd"
    $path = "$($Env:SystemRoot)\OEM"
@'
$adminAccount = Get-WmiObject Win32_UserAccount -filter "LocalAccount=True" | ?{$_.SID -Like "S-1-5-21-*-500"}
$UnattendedArgs = "/Q /ACTION=CompleteImage /INSTANCEID=MSSQLSERVER /INSTANCENAME=MSSQLSERVER /IACCEPTSQLSERVERLICENSETERMS=1 /SQLSYSADMINACCOUNTS=$($adminAccount.Domain)\$($adminAccount.Name) /BROWSERSVCSTARTUPTYPE=AUTOMATIC /INDICATEPROGRESS /TCPENABLED=1 /PID=`"22222-00000-00000-00000-00000`""
Start-Process -FilePath  "C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\SQL2022\setup.exe" -ArgumentList $UnattendedArgs -Wait
# Since we are using SetupComplete2.cmd, add a hook for future us to use SetupComplete3.cmd
if (Test-Path $Env:SystemRoot\OEM\SetupComplete3.cmd)
{
& $Env:SystemRoot\OEM\SetupComplete3.cmd
}
'@ | Out-File -Encoding ASCII -FilePath "$path\SetupComplete2.ps1"

    "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File %~dp0SetupComplete2.ps1" | Out-File -Encoding ASCII -FilePath "$path\SetupComplete2.cmd"    
}

function Install-Git {
    $Destination = "$installersPath\Git-2.43.0-64-bit.exe"
    $Url = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
    $UnattendedArgs = "/SILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /NORESTARTAPPLICATIONS /COMPONENTS='icons,ext\reg\shellhere,assoc,assoc_sh'"
    
    # Download Azure CLI installer
    Write-Host "Downloading Git 2.43.0"
    Invoke-WebRequest -Uri $Url -OutFile $Destination
    Write-Host "Download finished"

    # Install Dotnet 8 SDK
    Write-Host "Installing Git 2.43.0"
    Start-Process -FilePath $Destination -ArgumentList $UnattendedArgs -Wait
    Write-Host "Installation finished"

    # Remove installer
    Write-Host "Removing installation file"
    Remove-Item $Destination
    Write-Host "Installation file removed"
}

function Install-BizTalk {
    # see https://learn.microsoft.com/en-us/biztalk/install-and-config-guides/appendix-a-silent-installation
    $UnattendedArgs ='/QUIET /NORESTART /L C:\installers\BizTalkInstall.log /ADDLOCAL ALL /INSTALLDIR "C:\Program Files (x86)\Microsoft BizTalk Server 2020"'

    # Install Dotnet 8 SDK
    Write-Host "Installing BizTalk Server 2020"
    Start-Process -FilePath "C:\BizTalk Server 2020 Standard\BizTalk Server\Setup.exe" -ArgumentList $UnattendedArgs -Wait
    Write-Host "Installation finished"    
}

Write-Host "Creating installers folder..."
$installersPath = "C:\installers"
New-Item -Path $installersPath -ItemType Directory -Force

# Remove Microsoft OLE DB Driver for SQL Server as it conflicts with SQL Server 2022
Start-Process -FilePath msiexec.exe -ArgumentList '/quiet /x "{74A97B61-DE37-40DF-9E00-B302E5D3C4CE}"' -Wait

Install-SQLServer
Install-BizTalk
Install-Git
Install-VSCode-Windows
Install-Dotnet8
Install-AzureCLI
Install-VSStudio