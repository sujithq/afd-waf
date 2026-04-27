resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-${var.environment}-rg"
  location = var.location
}

locals {
  waf_api_policy_config = jsondecode(file("${path.root}/../../config/waf/api-policies.json"))
  base_waf_path_patterns = try(
    local.waf_api_policy_config.base.pathPatterns,
    ["/*"]
  )
  api_waf_policies = {
    for api_name, policy in try(local.waf_api_policy_config.apiPolicies, {}) : api_name => {
      path_patterns = policy.pathPatterns
    }
  }
}

module "waf" {
  source = "./modules/waf-policy-composition"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_prefix         = var.name_prefix
  environment         = var.environment
  waf_mode            = var.waf_mode
  api_waf_policies    = local.api_waf_policies
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
  base_path_patterns  = local.base_waf_path_patterns
  api_waf_policies    = local.api_waf_policies
  api_waf_policy_ids  = module.waf.api_waf_policy_ids
  apim_gateway_host   = module.apim.apim_gateway_host
}
