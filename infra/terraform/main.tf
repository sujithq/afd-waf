resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-${var.environment}-rg"
  location = var.location
}

resource "azurerm_log_analytics_workspace" "monitoring" {
  count = var.enable_monitoring && var.log_analytics_workspace_id == null ? 1 : 0

  name                = "${var.name_prefix}-law-${var.environment}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

locals {
  waf_policy_config       = jsondecode(file("${path.root}/../../config/waf/api-policies.json"))
  domain_policies         = try(local.waf_policy_config.domainPolicies, {})
  monitoring_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : try(azurerm_log_analytics_workspace.monitoring[0].id, null)

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

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_prefix         = var.name_prefix
  environment         = var.environment
  waf_policy_id       = module.waf.waf_policy_id
  base_path_patterns  = local.base_waf_path_patterns
  api_routes          = local.api_routes
  apim_gateway_host   = module.apim.apim_gateway_host
  diagnostic_settings = var.enable_monitoring ? {
    afd_logs = {
      name                           = "${var.name_prefix}-afd-${var.environment}-logs"
      log_categories                 = ["FrontDoorAccessLog", "FrontDoorHealthProbeLog", "FrontDoorWebApplicationFirewallLog"]
      log_groups                     = []
      metric_categories              = ["AllMetrics"]
      log_analytics_destination_type = "AzureDiagnostics"
      workspace_resource_id          = local.monitoring_workspace_id
    }
  } : {}
}

resource "azurerm_monitor_diagnostic_setting" "apim" {
  count = var.enable_monitoring ? 1 : 0

  name                           = "${var.name_prefix}-apim-${var.environment}-logs"
  target_resource_id             = module.apim.apim_resource_id
  log_analytics_workspace_id     = local.monitoring_workspace_id
  log_analytics_destination_type = "AzureDiagnostics"

  enabled_log {
    category = "GatewayLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
