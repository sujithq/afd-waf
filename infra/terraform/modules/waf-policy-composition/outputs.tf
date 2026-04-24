output "waf_policy_id" {
  value = azurerm_cdn_frontdoor_firewall_policy.waf.id
}

output "waf_policy_name" {
  value = azurerm_cdn_frontdoor_firewall_policy.waf.name
}
