locals {
  exclusions_json = jsondecode(file("${var.waf_config_path}/exclusions.json"))
  overrides_json  = jsondecode(file("${var.waf_config_path}/rule-overrides.json"))

  # Build a map of rule action overrides keyed by "ruleGroup.ruleId" from rule-overrides.json
  # so they can be merged with exclusion-derived rules below.
  override_map = {
    for entry in flatten([
      for grp in local.overrides_json.overrides : [
        for r in grp.rules : {
          key    = "${grp.ruleGroup}.${r.ruleId}"
          action = r.action
        }
      ]
    ]) : entry.key => entry.action
  }

  # Collect unique rule groups from BOTH exclusions and overrides so that
  # entries in rule-overrides.json without a corresponding exclusion are
  # still applied.
  unique_rule_groups = distinct(concat(
    [for excl in local.exclusions_json.exclusions : excl.ruleGroup],
    [for grp in local.overrides_json.overrides : grp.ruleGroup]
  ))

  # For each group, collect unique rule IDs from BOTH sources.
  unique_rules_per_group = {
    for rule_group in local.unique_rule_groups : rule_group => distinct(concat(
      [for excl in local.exclusions_json.exclusions : excl.ruleId if excl.ruleGroup == rule_group],
      flatten([
        for grp in local.overrides_json.overrides : [for r in grp.rules : r.ruleId]
        if grp.ruleGroup == rule_group
      ])
    ))
  }

  # Build override entries with per-rule exclusions.
  # action defaults to "AnomalyScoring" (correct for DRS 2.1 anomaly-scoring mode)
  # unless explicitly overridden in rule-overrides.json.
  rule_overrides = [
    for rule_group in local.unique_rule_groups : {
      rule_group_name = rule_group
      rules = [
        for rule_id in local.unique_rules_per_group[rule_group] : {
          rule_id = rule_id
          action  = lookup(local.override_map, "${rule_group}.${rule_id}", "AnomalyScoring")
          exclusions = [
            for excl in local.exclusions_json.exclusions : {
              match_variable = excl.matchVariable
              operator       = excl.selectorMatchOperator
              selector       = excl.selector
            } if excl.ruleGroup == rule_group && excl.ruleId == rule_id
          ]
        }
      ]
    }
  ]
}

resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  name                = var.waf_policy_name
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  mode                = var.waf_mode
  enabled             = true

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"

    dynamic "override" {
      for_each = local.rule_overrides
      content {
        rule_group_name = override.value.rule_group_name

        dynamic "rule" {
          for_each = override.value.rules
          content {
            rule_id = rule.value.rule_id
            action  = rule.value.action

            dynamic "exclusion" {
              for_each = rule.value.exclusions
              content {
                match_variable = exclusion.value.match_variable
                operator       = exclusion.value.operator
                selector       = exclusion.value.selector
              }
            }
          }
        }
      }
    }
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.1"
    action  = "Block"
  }
}
