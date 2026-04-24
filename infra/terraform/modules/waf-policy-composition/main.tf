# Raw azurerm resource (not AVM module) so that lifecycle.ignore_changes can be
# used to prevent infra-deploy from reverting managed_rule_set changes that are
# owned by the config-deploy stack.
resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  name                = lower(replace("${var.name_prefix}waf${var.environment}", "-", ""))
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  mode                = var.waf_mode
  enabled             = true

  lifecycle {
    ignore_changes = [managed_rule, custom_rule]
  }
}
