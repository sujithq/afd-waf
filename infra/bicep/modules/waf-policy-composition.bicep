@description('Deployment environment')
param environment string

@description('Name prefix')
param namePrefix string

@description('WAF mode')
param wafMode string

var policyName = '${namePrefix}-waf-${environment}'

// avm-id: bicep-waf-composition
module wafPolicy 'br/public:avm/res/network/front-door-web-application-firewall-policy:0.3.3' = {
  name: 'wafPolicy'
  params: {
    name: policyName
    sku: 'Premium_AzureFrontDoor'
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

output wafPolicyId string = wafPolicy.outputs.resourceId
