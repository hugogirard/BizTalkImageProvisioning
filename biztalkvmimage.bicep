@description('The location of the resources')
param location string = resourceGroup().location

@description('The name of the user assigned identity')
param userIdentityName string

@description('The name of the image definition gallery')
param galleryName string

@description('The name of the image definition')
param imageGalleryName string

@description('The name of the image template')
param imageTemplateName string

@description('The storage account that holds the scripts to be provisioned on the VM')
param storageAccountName string

@description('The SAS token for the storage account that holds the artifacts to be provisioned on the VM. Necessary as the VM does not inherit the builders identity')
@secure()
param containerSASToken string

@description('The name of the container in the storage account that holds the scripts to be provisioned on the VM')
var scriptContainerName = 'vmbuilderscripts'

param vmSkuSize string = 'Standard_D8_v4'

var imageSource = {
  type: 'PlatformImage'
  publisher: 'MicrosoftBizTalkServer'
  offer: 'BizTalk-Server'
  sku: '2020-Standard'
  version: 'latest'
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

resource userImgBuilderIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: userIdentityName
}

resource gallery 'Microsoft.Compute/galleries@2022-08-03' = {
  name: galleryName
  location: location
  // unavailable for now, need to register
  // see https://learn.microsoft.com/en-us/answers/questions/1276561/unable-to-create-a-gallery-with-rbac-shared-direct
  // properties: {
  //   sharingProfile: {
  //     permissions: 'Groups'
  //   }
  // }
}

resource galleryImage 'Microsoft.Compute/galleries/images@2022-03-03' = {
  name: imageGalleryName
  location: location
  parent: gallery
  properties: {
    architecture: 'x64'
    description: 'Curated image of BizTalk for lab purposes'
    osState: 'Generalized'
    hyperVGeneration: 'V1'
    osType: 'Windows'
    identifier: {
      publisher: 'MicrosoftMCAPSCSU'
      offer: 'BizTalk-Server-DemoLab'
      sku: '2024-POCLab'
    }
  }
}

resource imageTemplate 'Microsoft.VirtualMachineImages/imageTemplates@2022-02-14' = {
  name: imageTemplateName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userImgBuilderIdentity.id}': {}
    }
  }
  properties: {
    // Image build timeout in minutes. Allowed values: 0-960. 0 means the default 240 minutes.
    buildTimeoutInMinutes: 100
    vmProfile: {
      vmSize: vmSkuSize
      osDiskSizeGB: 200
      vnetConfig: null
    }
    source: imageSource
    customize: [
      {
        type: 'File'
        name: 'Download SQL Server 2022 ISO Script'
        destination: 'C:\\installers\\DownloadSQLServer.ps1'
        sourceUri: '${storageAccount.properties.primaryEndpoints.blob}${scriptContainerName}/DownloadSQLServer.ps1'
      }
      {
        type: 'File'
        name: 'Download SQL Server 2022 Configuration File'
        destination: 'C:\\installers\\SQLConfig.ini'
        sourceUri: '${storageAccount.properties.primaryEndpoints.blob}${scriptContainerName}/SQLConfig.ini'
      }      
      {
        type: 'PowerShell'
        name: 'Run SQL Server 2022 ISO Download Script'
        inline: [
          '& "C:\\installers\\DownloadSQLServer.ps1" -SQLServerISOUri "${storageAccount.properties.primaryEndpoints.blob}${scriptContainerName}/SQLServer2022-x64-ENU-Dev.iso${containerSASToken}"'
        ]
      } 
      {
        type: 'PowerShell'
        name: 'Install Tools and Dependencies'
        scriptUri: '${storageAccount.properties.primaryEndpoints.blob}${scriptContainerName}/BizTalkProvisioning.ps1'
        runElevated: true
        runAsSystem: true
      }

    ]
    distribute: [
      {
        type: 'SharedImage'
        galleryImageId: galleryImage.id
        runOutputName: '${last(split(galleryImage.id, '/'))}-SharedImage'
        artifactTags: {
          source: 'azureVmImageBuilder'
          baseosimg: 'windowsServer2019datacenter'
        }
        replicationRegions: []
      }
     ]
  }
}

output imageTemplateName string = imageTemplateName
