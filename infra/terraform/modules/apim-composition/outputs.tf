output "apim_name" {
  value = azurerm_api_management.this.name
}

output "apim_gateway_host" {
  value = azurerm_api_management.this.gateway_url
}
