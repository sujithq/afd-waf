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

  front_door_firewall_policies = {
    waf = {
      name                = "${var.name_prefix}-waf-${var.environment}"
      resource_group_name = var.resource_group_name
      sku_name            = "Premium_AzureFrontDoor"
      mode                = "Detection"
      managed_rules = {
        drs = {
          type    = "Microsoft_DefaultRuleSet"
          version = "2.1"
          action  = "Log"
        }
      }
    }
  }

  front_door_security_policies = {
    waf_association = {
      name = "waf-association"
      firewall = {
        front_door_firewall_policy_key = "waf"
        association = {
          endpoint_keys     = ["endpoint"]
          patterns_to_match = ["/*"]
        }
      }
    }
  }
}
