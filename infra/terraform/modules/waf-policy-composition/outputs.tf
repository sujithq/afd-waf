output "waf_policy_id" {
  value = azurerm_cdn_frontdoor_firewall_policy.waf.id
}

output "waf_policy_name" {
  value = azurerm_cdn_frontdoor_firewall_policy.waf.name
}

output "domain_waf_policy_ids" {
  value = { for domain_name, policy in azurerm_cdn_frontdoor_firewall_policy.domain : domain_name => policy.id }
}

output "domain_waf_policy_names" {
  value = { for domain_name, policy in azurerm_cdn_frontdoor_firewall_policy.domain : domain_name => policy.name }
}
