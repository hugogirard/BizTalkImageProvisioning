using 'biztalkvmimage.bicep'

// supplemented from command line
param storageAccountName = ''
param userIdentityName = ''
param containerSASToken = ''

param galleryName = 'galbiztalk'
param imageGalleryName = 'biztalkdemolab'
param imageTemplateName = 'it-biztalkdemo'
param sqlServerISOFileName = 'SQLServer2022-x64-ENU-Dev.iso'
