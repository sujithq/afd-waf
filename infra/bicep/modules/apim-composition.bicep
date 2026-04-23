param environment string
param location string
param namePrefix string
param publisherEmail string
param publisherName string

var apimName = toLower('${namePrefix}-apim-${environment}')

// avm-id: bicep-apim-composition
// AVM composition: replace with AVM module reference once pinned in module registry policy.
resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

output apimName string = apim.name
output gatewayHostName string = '${apim.name}.azure-api.net'
