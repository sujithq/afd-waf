# avm-id: terraform-afd-composition
resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.name_prefix}-afd-${var.environment}"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.name_prefix}-ep-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "${var.name_prefix}-og-${var.environment}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }
}

resource "azurerm_cdn_frontdoor_origin" "apim" {
  name                          = "apim-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  host_name                     = replace(var.apim_gateway_host, "https://", "")
  http_port                     = 80
  https_port                    = 443
  origin_host_header            = replace(var.apim_gateway_host, "https://", "")
  priority                      = 1
  weight                        = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_route" "default" {
  name                          = "default"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.apim.id]
  patterns_to_match             = ["/*"]
  supported_protocols           = ["Http", "Https"]
  forwarding_protocol           = "HttpsOnly"
  https_redirect_enabled        = true
  link_to_default_domain        = true
}

resource "azurerm_cdn_frontdoor_security_policy" "waf" {
  name                     = "waf-association"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = var.waf_policy_id

      association {
        patterns_to_match = ["/*"]
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
      }
    }
  }
}

# AVM note: replace direct resources with pinned AVM modules as part of module governance.
