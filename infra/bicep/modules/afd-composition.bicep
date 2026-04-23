param environment string
param namePrefix string
param afdHostName string
param wafPolicyId string
param apimGatewayHostName string

var profileName = '${namePrefix}-afd-${environment}'
var endpointName = '${namePrefix}-ep-${environment}'
var originGroupName = '${namePrefix}-og-${environment}'

// avm-id: bicep-afd-composition
module profile 'br/public:avm/res/cdn/profile:0.19.2' = {
  name: 'afdProfile'
  params: {
    name: profileName
    location: 'global'
    sku: 'Premium_AzureFrontDoor'
    originResponseTimeoutSeconds: 120
    originGroups: [
      {
        name: originGroupName
        loadBalancingSettings: {
          sampleSize: 4
          successfulSamplesRequired: 3
          additionalLatencyInMilliseconds: 50
        }
        healthProbeSettings: {
          probePath: '/status-0123456789abcdef'
          probeRequestType: 'HEAD'
          probeProtocol: 'Https'
          probeIntervalInSeconds: 120
        }
        origins: [
          {
            name: 'apim-origin'
            hostName: apimGatewayHostName
            originHostHeader: apimGatewayHostName
            httpPort: 80
            httpsPort: 443
            enabledState: 'Enabled'
            enforceCertificateNameCheck: true
            priority: 1
            weight: 1000
          }
        ]
      }
    ]
    afdEndpoints: [
      {
        name: endpointName
        enabledState: 'Enabled'
        routes: [
          {
            name: 'default'
            originGroupName: originGroupName
            supportedProtocols: [
              'Http'
              'Https'
            ]
            patternsToMatch: [
              '/*'
            ]
            forwardingProtocol: 'HttpsOnly'
            httpsRedirect: 'Enabled'
            enabledState: 'Enabled'
            linkToDefaultDomain: 'Enabled'
          }
        ]
      }
    ]
    securityPolicies: [
      {
        name: 'waf-association'
        wafPolicyResourceId: wafPolicyId
        associations: [
          {
            domains: [
              {
                id: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Cdn/profiles/${profileName}/afdEndpoints/${endpointName}'
              }
            ]
            patternsToMatch: [
              '/*'
            ]
          }
        ]
      }
    ]
  }
}

output frontDoorProfileName string = profile.outputs.name
output frontDoorEndpointHostName string = afdHostName
