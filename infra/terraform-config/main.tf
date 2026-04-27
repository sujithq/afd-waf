# Remove the legacy base WAF config module address from state without deleting
# the live policy. Older config-deploy runs managed the base policy at
# module.waf_rules; this stack now manages it at module.base_waf_rules.
removed {
  from = module.waf_rules.azurerm_cdn_frontdoor_firewall_policy.waf

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.api_waf_rules

  lifecycle {
    destroy = false
  }
}

# Import the existing WAF policy (created by infra stack) into this stack's state.
# Terraform skips the import block if the resource is already managed in state.
import {
  to = module.base_waf_rules.azurerm_cdn_frontdoor_firewall_policy.waf
  id = var.waf_policy_id
}

locals {
  waf_policy_config    = jsondecode(file("${path.root}/../../config/waf/api-policies.json"))
  base_waf_config_path = "${path.root}/../../config/waf/base"
  env_waf_config_path  = "${path.root}/../../config/waf/${var.environment}"
  domain_waf_policy_names = {
    for domain_name, policy in try(local.waf_policy_config.domainPolicies, {}) : domain_name => lower(replace("${var.name_prefix}waf${var.environment}${domain_name}", "-", ""))
  }
  domain_waf_policy_ids = {
    for domain_name, policy_name in local.domain_waf_policy_names : domain_name => "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/${policy_name}"
  }
}

import {
  for_each = local.domain_waf_policy_ids
  to       = module.domain_waf_rules[each.key].azurerm_cdn_frontdoor_firewall_policy.waf
  id       = each.value
}

module "base_waf_rules" {
  source = "./modules/waf-rules"

  waf_policy_name     = var.waf_policy_name
  resource_group_name = var.resource_group_name
  waf_mode            = var.waf_mode
  waf_config_paths    = [local.base_waf_config_path, local.env_waf_config_path]
}

module "domain_waf_rules" {
  for_each = local.domain_waf_policy_names

  source = "./modules/waf-rules"

  waf_policy_name     = each.value
  resource_group_name = var.resource_group_name
  waf_mode            = var.waf_mode
  waf_config_paths    = [local.base_waf_config_path, local.env_waf_config_path, "${path.root}/../../config/waf/${var.environment}/domains/${each.key}"]
}
