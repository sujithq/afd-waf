# avm-id: terraform-afd-composition
module "afd" {
  source  = "Azure/avm-res-cdn-profile/azurerm"
  version = "0.1.9"

  name                = "${var.name_prefix}-afd-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Premium_AzureFrontDoor"
  enable_telemetry    = true

  front_door_endpoints = {
    endpoint = {
      name = "${var.name_prefix}-ep-${var.environment}"
    }
  }

  front_door_custom_domains = {
    for domain_name, domain in var.domain_waf_policies : domain_name => {
      name        = lower(replace("${var.name_prefix}-${var.environment}-${domain_name}", "-", ""))
      dns_zone_id = domain.dns_zone_id
      host_name   = domain.host_name
      tls = {
        certificate_type = "ManagedCertificate"
      }
    } if domain.enabled
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
      host_name                      = replace(var.apim_gateway_host, "https://", "")
      origin_host_header             = replace(var.apim_gateway_host, "https://", "")
      http_port                      = 80
      https_port                     = 443
      enabled                        = true
      certificate_name_check_enabled = true
      priority                       = 1
      weight                         = 1000
    }
  }

  front_door_routes = merge({
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
    },
    {
      for api_name, route in var.api_routes : api_name => {
        name                   = "${api_name}-route"
        endpoint_key           = "endpoint"
        origin_group_key       = "apim_group"
        origin_keys            = ["apim_origin"]
        patterns_to_match      = route.path_patterns
        supported_protocols    = ["Http", "Https"]
        forwarding_protocol    = "HttpsOnly"
        https_redirect_enabled = true
        custom_domain_keys     = try(var.domain_waf_policies[route.domain_policy_name].enabled, false) ? [route.domain_policy_name] : []
      }
    }
  )
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

resource "azurerm_cdn_frontdoor_security_policy" "domain_waf_association" {
  for_each = {
    for domain_name, domain in var.domain_waf_policies : domain_name => domain
    if domain.enabled
  }

  name                     = lower(replace("${each.key}-waf-association", "-", ""))
  cdn_frontdoor_profile_id = module.afd.resource_id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = var.domain_waf_policy_ids[each.key]

      association {
        patterns_to_match = ["/*"]

        domain {
          cdn_frontdoor_domain_id = module.afd.frontdoor_custom_domains[each.key].id
        }
      }
    }
  }
}
