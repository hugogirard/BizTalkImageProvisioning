[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$Location,
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]$UserIdentityName,
    [Parameter(Mandatory=$true, HelpMessage="The storage account where the VM provisioning scripts will be stored.")]
    [string]$StorageAccountName,
    [Parameter(HelpMessage="The object ID of the user running the script in the directory (tenant) in which the script is running")]
    [string]$UserObjectId = '',
    [Parameter(HelpMessage = "The location of all the bicep files, leave empty for CWD")]
    [string]$FilesDirectory = ''
)

$InformationPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($FilesDirectory)) {
    $FilesDirectory = (Get-Location).Path
}

if ($null -eq $SubscriptionId) {
    # Get existing context
    $currentAzContext = Get-AzContext

    if ($null -eq $currentAzContext) {
        Write-Error "No Azure context found. Please login to Azure using Connect-AzAccount and try again."
        exit 1
    }

    # Get your current subscription ID.
    $SubscriptionId = $currentAzContext.Subscription.Id
}

# $sigSharingFeature = Get-AzProviderPreviewFeature -Name SIGSharing -ProviderNamespace Microsoft.Compute -ErrorAction SilentlyContinue
# if ($null -ne $sigSharingFeature) {
#     # see https://learn.microsoft.com/en-us/azure/virtual-machines/share-gallery-direct?tabs=portaldirect
#     Write-Warning "SIGSharing preview feature already enabled, skipping"
# }
# else {
#     Register-AzProviderPreviewFeature -Name SIGSharing -ProviderNamespace Microsoft.Compute
#     Write-Information "SIGSharing preview feature enabled"
# }

# Check if resource group exists and create it if not
$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if ($null -eq $resourceGroup) {
    Write-Warning "Resource group not found, creating..."
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location
    Write-Information "Resource group created"
}

# Check if the identity already exists
Write-Information "Check if the User Identity already exists...`n"
$identity = Get-AzUserAssignedIdentity -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -Name $UserIdentityName -ErrorAction SilentlyContinue
$identityNamePrincipalId = $null

if ($null -ne $identity) {
    Write-Warning "User Identity already exists, skipping creation"
    $identityNamePrincipalId = $identity.PrincipalId
}
else {
    # Create an identity
    $identity = New-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $UserIdentityName -SubscriptionId $SubscriptionID -Location $Location
    $identityNamePrincipalId = $(Get-AzUserAssignedIdentity -ResourceGroupName $ResourceGroupName -Name $UserIdentityName).PrincipalId
    Write-Information "User Identity created"
}

# For VM Image Builder to distribute images, the service must be allowed to inject the images into resource groups.
# To grant the required permissions, create a user-assigned managed identity, and grant it rights on the resource group where the image is built.
Write-Information "Check if role definition for Azure Builder Image exists already exists..."
$imageRoleDefinitionName = "Azure Image Builder Service Image Creation Role"
# check if role definition already exists
$roleDef = Get-AzRoleDefinition -Name $imageRoleDefinitionName -ErrorAction SilentlyContinue
if ($null -ne $roleDef) {
    Write-Warning "Azure Image Builder Role definition already exists, skipping creation"
}
else {
    # Create a role definition file
    $aibRoleImageCreationUrl = "https://raw.githubusercontent.com/azure/azvmimagebuilder/master/solutions/12_Creating_AIB_Security_Roles/aibRoleImageCreation.json"
    $tmpPath = [System.IO.Path]::GetTempPath()
    $aibRoleImageCreationPath = Join-Path -Path $tmpPath -ChildPath "aibRoleImageCreation$(Get-Date -Format "yyyyMMddHHmm").json"

    # Download the configuration
    Invoke-WebRequest -Uri $aibRoleImageCreationUrl -OutFile $aibRoleImageCreationPath -UseBasicParsing
    ((Get-Content -path $aibRoleImageCreationPath -Raw) -replace ', you should delete or split out as appropriate', '') | Set-Content -Path $aibRoleImageCreationPath
    # the template sets the assignable scope to the resource group. Widen it to the subscription as it may be used in other resource groups
    ((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '/resourceGroups/<rgName>', '') | Set-Content -Path $aibRoleImageCreationPath
    ((Get-Content -path $aibRoleImageCreationPath -Raw) -replace '<subscriptionID>', $SubscriptionID) | Set-Content -Path $aibRoleImageCreationPath

    # Create a role definition
    New-AzRoleDefinition -InputFile $aibRoleImageCreationPath
    Write-Information "Role definition created"
}

# Check if role assignment already exists
$roleAssignment = Get-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefinitionName -Scope "/subscriptions/$SubscriptionID/resourceGroups/$ResourceGroupName" -ErrorAction SilentlyContinue
if ($null -ne $roleAssignment) {
    Write-Warning "User Identity Role assignment already exists, skipping creation"
}
else {
    # Grant the role definition to the VM Image Builder service principal
    New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName $imageRoleDefinitionName -Scope "/subscriptions/$SubscriptionID/resourceGroups/$ResourceGroupName" -ErrorAction SilentlyContinue
    Write-Information "Role assignment created"
}

$storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if ($null -ne $storageAccount) {
    Write-Warning "Storage account already exists, skipping creation"
}
else {
    # Create a storage account
    $containerName = "vmbuilderscripts"
    $scope = "/subscriptions/$SubscriptionID/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName/blobServices/default/containers/$containerName"

    Write-Information "Creating storage account..."
    $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $Location -SkuName Standard_LRS -Kind StorageV2 -EnableHttpsTrafficOnly $true
    New-AzStorageContainer -Name $containerName -Context $storageAccount.Context

    Write-Information "Setting role assignements"
    New-AzRoleAssignment -ObjectId $identityNamePrincipalId -RoleDefinitionName "Storage Blob Data Reader" -Scope $scope
    if ($null -ne $UserObjectId) {
        # give the one running the script owner
        New-AzRoleAssignment -ObjectId $UserObjectId -RoleDefinitionName "Storage Blob Data Owner" -Scope $scope
    }

    Write-Information "Storage account created and role assignments set"
}

Read-Host -Prompt "Upload the provisioning scripts AND any other assets (SQL Server ISO image, etc) in the storage account. Press any key to continue..."

$startTime = Get-Date
$endTime = $startTime.AddHours(1)
$containerSASToken = New-AzStorageContainerSASToken -Name $containerName -Context $storageAccount.Context -Permission r -StartTime $startTime -ExpiryTime $endTime
$containerSASTokenSecure = ConvertTo-SecureString -String $containerSASToken -AsPlainText -Force

Write-Information "Provisioning resources..."
$deployment = New-AzResourceGroupDeployment -Name "BizTalkVMImageDeployment" `
                              -ResourceGroupName $ResourceGroupName `
                              -TemplateFile "$FilesDirectory\biztalkvmimage.bicep" `
                              -TemplateParameterFile "$FilesDirectory\biztalkvmimage.bicepparam" `
                              -userIdentityName $identity.Name `
                              -storageAccountName $storageAccount.StorageAccountName `
                              -containerSASToken $containerSASTokenSecure `
                              -Verbose `
                              -ErrorAction Stop

Write-Information "Resources provisioned"

$imageTemplateName = $deployment.Outputs.imageTemplateName.Value

Write-Information "Running image template..."
Invoke-AzResourceAction `
   -ResourceName $imageTemplateName `
   -ResourceGroupName $ResourceGroupName `
   -ResourceType Microsoft.VirtualMachineImages/imageTemplates `
   -ApiVersion "2022-02-14" `
   -Action Run `
   -Force

$choices = '&Yes', '&No'
while ($true) {
    $output = Get-AzImageBuilderTemplate -ImageTemplateName $imageTemplateName -ResourceGroupName $ResourceGroupName | Select-Object -Property Name, LastRunStatusRunState, LastRunStatusMessage, ProvisioningState
    $output | Format-Table -AutoSize
    if ($output.ProvisioningState -eq "Succeeded") {
        break
    }
    Start-Sleep -s 30
    $response = $Host.UI.PromptForChoice("Monitor the image template Build", "Do you want to continue monitoring the image template build ?", $choices, 0)
    if ($response -eq 1) {
        break
    }
}
