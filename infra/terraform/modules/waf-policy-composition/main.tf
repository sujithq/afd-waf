# avm-id: terraform-waf-composition
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                = "${var.name_prefix}-waf-${var.environment}"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  enabled             = true
  mode                = var.waf_mode
}

# AVM note: replace direct resource with pinned AVM module source when approved.
