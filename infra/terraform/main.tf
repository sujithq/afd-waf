resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-${var.environment}-rg"
  location = var.location
}

locals {
  waf_policy_config = jsondecode(file("${path.root}/../../config/waf/api-policies.json"))
  domain_policies   = try(local.waf_policy_config.domainPolicies, {})

  base_waf_path_patterns = try(local.waf_policy_config.base.enabled, false) ? ["/*"] : []
  api_routes = merge(
    {},
    [
      for domain_name, domain in local.domain_policies : {
        for api_name, api in try(domain.apis, {}) : api_name => {
          domain_policy_name = domain_name
          path_patterns      = ["/${module.apim.api_paths_by_name[api.apimApiName]}/*"]
        }
      }
    ]...
  )
  domain_waf_policies = {
    for domain_name, domain in local.domain_policies : domain_name => {
      enabled     = try(domain.enabled, false)
      host_name   = domain.hostName
      dns_zone_id = try(domain.dnsZoneId, null)
      api_names   = keys(try(domain.apis, {}))
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
  domain_waf_policies = local.domain_waf_policies
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

  resource_group_name   = azurerm_resource_group.main.name
  location              = var.location
  name_prefix           = var.name_prefix
  environment           = var.environment
  waf_policy_id         = module.waf.waf_policy_id
  domain_waf_policy_ids = module.waf.domain_waf_policy_ids
  base_path_patterns    = local.base_waf_path_patterns
  domain_waf_policies   = local.domain_waf_policies
  api_routes            = local.api_routes
  apim_gateway_host     = module.apim.apim_gateway_host
}
