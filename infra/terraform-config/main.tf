# Import the existing WAF policy (created by infra stack) into this stack's state.
# Terraform skips the import block if the resource is already managed in state.
import {
  to = module.base_waf_rules.azurerm_cdn_frontdoor_firewall_policy.waf
  id = var.waf_policy_id
}

locals {
  waf_api_policy_config = jsondecode(file("${path.root}/../../config/waf/api-policies.json"))
  base_waf_config_path  = "${path.root}/../../config/waf/base"
  env_waf_config_path   = "${path.root}/../../config/waf/${var.environment}"
  api_waf_policy_names = {
    for api_name, policy in try(local.waf_api_policy_config.apiPolicies, {}) : api_name => lower(replace("${var.name_prefix}waf${var.environment}${api_name}", "-", ""))
  }
  api_waf_policy_ids = {
    for api_name, policy_name in local.api_waf_policy_names : api_name => "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Network/frontDoorWebApplicationFirewallPolicies/${policy_name}"
  }
}

import {
  for_each = local.api_waf_policy_ids
  to       = module.api_waf_rules[each.key].azurerm_cdn_frontdoor_firewall_policy.waf
  id       = each.value
}

module "base_waf_rules" {
  source = "./modules/waf-rules"

  waf_policy_name     = var.waf_policy_name
  resource_group_name = var.resource_group_name
  waf_mode            = var.waf_mode
  waf_config_paths    = [local.base_waf_config_path, local.env_waf_config_path]
}

module "api_waf_rules" {
  for_each = local.api_waf_policy_names

  source = "./modules/waf-rules"

  waf_policy_name     = each.value
  resource_group_name = var.resource_group_name
  waf_mode            = var.waf_mode
  waf_config_paths    = [local.base_waf_config_path, local.env_waf_config_path, "${path.root}/../../config/waf/${var.environment}/apis/${each.key}"]
}
