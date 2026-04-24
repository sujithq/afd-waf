# Import the existing WAF policy (created by infra stack) into this stack's state.
# Terraform skips the import block if the resource is already managed in state.
import {
  to = module.waf_rules.azurerm_cdn_frontdoor_firewall_policy.waf
  id = var.waf_policy_id
}

module "waf_rules" {
  source = "./modules/waf-rules"

  waf_policy_name     = var.waf_policy_name
  resource_group_name = var.resource_group_name
  waf_mode            = var.waf_mode
  waf_config_path     = "${path.root}/../../config/waf/${var.environment}"
}
