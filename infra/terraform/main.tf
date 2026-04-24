resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-${var.environment}-rg"
  location = var.location
}

module "waf" {
  source = "./modules/waf-policy-composition"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_prefix         = var.name_prefix
  environment         = var.environment
  waf_mode            = var.waf_mode
  waf_config_path     = "${path.root}/../../config/waf/${var.environment}"
}

module "apim" {
  source = "./modules/apim-composition"

  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  name_prefix          = var.name_prefix
  environment          = var.environment
  apim_publisher_email = var.apim_publisher_email
  apim_publisher_name  = var.apim_publisher_name
}

module "afd" {
  source = "./modules/afd-composition"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_prefix         = var.name_prefix
  environment         = var.environment
  waf_policy_id       = module.waf.waf_policy_id
  apim_gateway_host   = module.apim.apim_gateway_host
}
