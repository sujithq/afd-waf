# avm-id: terraform-waf-composition

# Load WAF configuration from JSON files
locals {
  exclusions_json = jsondecode(file("${var.waf_config_path}/exclusions.json"))
  overrides_json  = jsondecode(file("${var.waf_config_path}/rule-overrides.json"))

  # Transform exclusions from JSON format to Terraform format
  # JSON structure: array of {matchVariable, selectorMatchOperator, selector, ruleSet, ruleGroup, ruleId}
  # Need to transform to managed_rules.overrides[].rules[].exclusions format
  # Group exclusions by rule
  exclusions_by_rule = {
    for excl in local.exclusions_json.exclusions :
    "${excl.ruleGroup}.${excl.ruleId}" => excl...
  }

  # Build rule overrides with exclusions
  rule_overrides = flatten([
    for rule_key, exclusions in local.exclusions_by_rule : [
      {
        rule_id = split(".", rule_key)[1]
        enabled = true
        action  = "AnomalyScoring" # DRS 2.1 uses AnomalyScoring
        exclusions = [
          for excl in exclusions : {
            match_variable = excl.matchVariable
            selector       = excl.selector
            operator       = excl.selectorMatchOperator
          }
        ]
      }
    ]
  ])

  # Group rules by rule group
  rules_by_group = {
    for rule in local.rule_overrides :
    split(".", keys({ for k, v in local.exclusions_by_rule : k => v if contains(split(".", k), rule.rule_id) })[0])[0] => rule...
  }

  # Simpler approach: Extract unique rule groups and build overrides
  unique_rule_groups = distinct([
    for excl in local.exclusions_json.exclusions : excl.ruleGroup
  ])

  # Build overrides structure grouped by rule group
  overrides = [
    for rule_group in local.unique_rule_groups : {
      rule_group_name = rule_group
      rules = [
        for rule_id in distinct([
          for excl in local.exclusions_json.exclusions :
          excl.ruleId if excl.ruleGroup == rule_group
          ]) : {
          rule_id = rule_id
          enabled = true
          action  = "AnomalyScoring" # DRS 2.1 uses AnomalyScoring for rule-level actions
          exclusions = [
            for excl in local.exclusions_json.exclusions :
            {
              match_variable = excl.matchVariable
              selector       = excl.selector
              operator       = excl.selectorMatchOperator
            } if excl.ruleGroup == rule_group && excl.ruleId == rule_id
          ]
        }
      ]
    }
  ]

  # Managed rules configuration
  managed_rules = [
    {
      type    = "Microsoft_DefaultRuleSet"
      action  = "Block"
      version = "2.1"
      # Apply overrides with exclusions from JSON
      overrides = local.overrides
    },
    {
      type    = "Microsoft_BotManagerRuleSet"
      action  = "Block"
      version = "1.1"
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
