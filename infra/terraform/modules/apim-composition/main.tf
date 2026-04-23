# avm-id: terraform-apim-composition
resource "azurerm_api_management" "this" {
  name                = lower("${var.name_prefix}-apim-${var.environment}")
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = "Developer_1"
}

resource "azurerm_api_management_api" "odata1" {
  name                = "odata-sap-1"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  revision            = "1"
  display_name        = "OData Mock API 1"
  path                = "odata1"
  protocols           = ["https"]
  service_url         = "https://example.com/odata1"
}

resource "azurerm_api_management_api" "odata2" {
  name                = "odata-sap-2"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  revision            = "1"
  display_name        = "OData Mock API 2"
  path                = "odata2"
  protocols           = ["https"]
  service_url         = "https://example.com/odata2"
}

# AVM note: replace direct resources with pinned AVM modules as part of platform module governance.
