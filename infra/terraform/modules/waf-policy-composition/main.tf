# avm-id: terraform-waf-composition
locals {
  # Build managed_rules combining both rule sets.
  # Exclusions are applied to the DefaultRuleSet; the BotManagerRuleSet is included unchanged.
  managed_rules = [
    {
      type    = "Microsoft_DefaultRuleSet"
      version = "2.1"
      action  = "Block"
      # Map selector_match_operator to the AVM module's required 'operator' field name.
      exclusions = [for e in var.waf_exclusions : {
        match_variable = e.match_variable
        operator       = e.selector_match_operator
        selector       = e.selector
      }]
      overrides = [for o in var.waf_rule_overrides : {
        rule_group_name = o.rule_group_name
        exclusions      = []
        rules = [for r in o.rules : {
          rule_id    = r.rule_id
          enabled    = r.enabled
          action     = r.action
          exclusions = []
        }]
      }]
    },
    {
      type       = "Microsoft_BotManagerRuleSet"
      version    = "1.1"
      action     = "Block"
      exclusions = []
      overrides  = []
    }
  ]
}

module "waf_policy" {
  source  = "Azure/avm-res-network-frontdoorwebapplicationfirewallpolicy/azurerm"
  version = "0.1.0"

  name                = lower(replace("${var.name_prefix}waf${var.environment}", "-", ""))
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  mode                = var.waf_mode
  enable_telemetry    = true
  managed_rules       = local.managed_rules
}
