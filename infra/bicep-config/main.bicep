targetScope = 'resourceGroup'

@description('Name of the existing WAF policy to configure')
param wafPolicyName string

@description('WAF policy mode')
@allowed([
  'Detection'
  'Prevention'
])
param wafMode string = 'Detection'

@description('Managed rule group overrides derived from config/waf/{environment}/. Each entry must contain ruleGroupName and rules[].')
param ruleGroupOverrides array = []

// avm-id: bicep-waf-config
resource wafPolicy 'Microsoft.Network/frontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: wafPolicyName
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
    customRules: {
      rules: []
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleGroupOverrides: ruleGroupOverrides
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

output wafPolicyId string = wafPolicy.id
