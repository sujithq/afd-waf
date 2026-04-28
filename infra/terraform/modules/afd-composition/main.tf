# avm-id: terraform-afd-composition
locals {
  apim_origin_host = trimsuffix(replace(var.apim_gateway_host, "https://", ""), "/")
}

module "afd" {
  source  = "Azure/avm-res-cdn-profile/azurerm"
  version = "0.1.9"

  name                = "${var.name_prefix}-afd-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Premium_AzureFrontDoor"
  enable_telemetry    = true
  diagnostic_settings = var.diagnostic_settings

  front_door_endpoints = {
    endpoint = {
      name = "${var.name_prefix}-ep-${var.environment}"
    }
  }

  front_door_origin_groups = {
    apim_group = {
      name = "${var.name_prefix}-og-${var.environment}"
      load_balancing = {
        default = {
          sample_size                        = 4
          successful_samples_required        = 3
          additional_latency_in_milliseconds = 50
        }
      }
      health_probe = {
        default = {
          interval_in_seconds = 120
          path                = "/status-0123456789abcdef"
          protocol            = "Https"
          request_type        = "HEAD"
        }
      }
    }
  }

  front_door_origins = {
    apim_origin = {
      name                           = "apim-origin"
      origin_group_key               = "apim_group"
      host_name                      = local.apim_origin_host
      host_header                    = local.apim_origin_host
      http_port                      = 80
      https_port                     = 443
      enabled                        = true
      certificate_name_check_enabled = true
      priority                       = 1
      weight                         = 1000
    }
  }

  front_door_routes = {
    default = {
      name                   = "default"
      endpoint_key           = "endpoint"
      origin_group_key       = "apim_group"
      origin_keys            = ["apim_origin"]
      patterns_to_match      = ["/*"]
      supported_protocols    = ["Http", "Https"]
      forwarding_protocol    = "HttpsOnly"
      https_redirect_enabled = true
    }
  }
}

moved {
  from = module.afd.azurerm_cdn_frontdoor_route.routes["api1"]
  to   = azurerm_cdn_frontdoor_route.api_routes["api1"]
}

moved {
  from = module.afd.azurerm_cdn_frontdoor_route.routes["api2"]
  to   = azurerm_cdn_frontdoor_route.api_routes["api2"]
}

moved {
  from = module.afd.azurerm_cdn_frontdoor_route.routes["api3"]
  to   = azurerm_cdn_frontdoor_route.api_routes["api3"]
}

moved {
  from = module.afd.azurerm_cdn_frontdoor_route.routes["api4"]
  to   = azurerm_cdn_frontdoor_route.api_routes["api4"]
}

resource "azurerm_cdn_frontdoor_route" "api_routes" {
  for_each = var.api_routes

  name                            = "${each.key}-route"
  cdn_frontdoor_endpoint_id       = module.afd.frontdoor_endpoints["endpoint"].id
  cdn_frontdoor_origin_group_id   = module.afd.frontdoor_origin_groups["apim_group"].id
  cdn_frontdoor_origin_ids        = [module.afd.frontdoor_origins["apim_origin"].id]
  patterns_to_match               = each.value.path_patterns
  supported_protocols             = ["Http", "Https"]
  forwarding_protocol             = "HttpsOnly"
  https_redirect_enabled          = true
  link_to_default_domain          = true
  cdn_frontdoor_custom_domain_ids = []

  lifecycle {
    ignore_changes = [cdn_frontdoor_custom_domain_ids]
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "base_waf_association" {
  for_each = length(var.base_path_patterns) > 0 ? { base = true } : {}

  name                     = "base-waf-association"
  cdn_frontdoor_profile_id = module.afd.resource_id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = var.waf_policy_id

      association {
        patterns_to_match = var.base_path_patterns

        domain {
          cdn_frontdoor_domain_id = module.afd.frontdoor_endpoints["endpoint"].id
        }
      }
    }
  }
}
