targetScope = 'resourceGroup'

@description('Deployment environment')
param environment string

@description('Resource location')
param location string = resourceGroup().location

@description('Name prefix')
param namePrefix string

@description('AFD endpoint host name')
param afdHostName string

@description('APIM publisher email')
param apimPublisherEmail string

@description('APIM publisher name')
param apimPublisherName string

@description('WAF mode')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Detection'

module wafPolicy './modules/waf-policy-composition.bicep' = {
  name: 'wafPolicy'
  params: {
    namePrefix: namePrefix
    environment: environment
    wafMode: wafMode
  }
}

module apim './modules/apim-composition.bicep' = {
  name: 'apim'
  params: {
    location: location
    namePrefix: namePrefix
    environment: environment
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
  }
}

module apis './modules/apim-odata-mock-apis.bicep' = {
  name: 'apimApis'
  params: {
    apimName: apim.outputs.apimName
  }
}

module afd './modules/afd-composition.bicep' = {
  name: 'afd'
  params: {
    namePrefix: namePrefix
    environment: environment
    afdHostName: afdHostName
    wafPolicyId: wafPolicy.outputs.wafPolicyId
    apimGatewayHostName: apim.outputs.gatewayHostName
  }
}

output wafPolicyId string = wafPolicy.outputs.wafPolicyId
output apimName string = apim.outputs.apimName
output frontDoorProfileName string = afd.outputs.frontDoorProfileName
