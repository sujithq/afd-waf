param apimName string

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' existing = {
  name: apimName
}

resource api1 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'odata-sap-1'
  parent: apim
  properties: {
    path: 'odata1'
    displayName: 'OData Mock API 1'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

resource api2 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'odata-sap-2'
  parent: apim
  properties: {
    path: 'odata2'
    displayName: 'OData Mock API 2'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
  }
}

resource op1 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  name: 'entities'
  parent: api1
  properties: {
    displayName: 'List Entities'
    method: 'GET'
    urlTemplate: '/Entities'
    templateParameters: []
    responses: [
      {
        statusCode: 200
      }
    ]
  }
}

resource op2 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  name: 'entities'
  parent: api2
  properties: {
    displayName: 'List Entities'
    method: 'GET'
    urlTemplate: '/Entities'
    templateParameters: []
    responses: [
      {
        statusCode: 200
      }
    ]
  }
}
