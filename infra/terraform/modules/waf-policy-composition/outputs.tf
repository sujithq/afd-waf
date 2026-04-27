output "waf_policy_id" {
  value = azurerm_cdn_frontdoor_firewall_policy.waf.id
}

output "waf_policy_name" {
  value = azurerm_cdn_frontdoor_firewall_policy.waf.name
}

output "api_waf_policy_ids" {
  value = { for api_name, policy in azurerm_cdn_frontdoor_firewall_policy.api : api_name => policy.id }
}

output "api_waf_policy_names" {
  value = { for api_name, policy in azurerm_cdn_frontdoor_firewall_policy.api : api_name => policy.name }
}
