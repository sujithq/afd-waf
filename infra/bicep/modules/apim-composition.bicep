param environment string
param location string
param namePrefix string
param publisherEmail string
param publisherName string

var apimName = toLower('${namePrefix}-apim-${environment}')

// avm-id: bicep-apim-composition
module apim 'br/public:avm/res/api-management/service:0.14.1' = {
  name: 'apim'
  params: {
    name: apimName
    location: location
    publisherEmail: publisherEmail
    publisherName: publisherName
    sku: 'Developer'
  }
}

output apimName string = apim.outputs.name
output gatewayHostName string = '${apim.outputs.name}.azure-api.net'
