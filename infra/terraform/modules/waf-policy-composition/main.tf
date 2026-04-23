# avm-id: terraform-waf-composition
module "waf_policy" {
  source  = "Azure/avm-res-network-frontdoorwebapplicationfirewallpolicy/azurerm"
  version = "0.1.0"

  name                = "${var.name_prefix}-waf-${var.environment}"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  mode                = var.waf_mode
  enable_telemetry    = true
}
