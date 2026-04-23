@description('Deployment environment')
param environment string

@description('Name prefix')
param namePrefix string

@description('WAF mode')
param wafMode string

var policyName = '${namePrefix}-waf-${environment}'

// AVM composition: replace with exact published AVM URI/version approved by your platform team.
resource wafPolicy 'Microsoft.Network/frontdoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: policyName
  location: 'Global'
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
        }
      ]
    }
    customRules: {
      rules: []
    }
  }
}

output wafPolicyId string = wafPolicy.id
