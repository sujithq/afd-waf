output "frontdoor_profile_id" {
  value = module.afd.resource_id
}

output "custom_domain_ids" {
  value = { for domain_name, domain in module.afd.frontdoor_custom_domains : domain_name => domain.id }
}

output "custom_domain_host_names" {
  value = { for domain_name, domain in module.afd.frontdoor_custom_domains : domain_name => domain.host_name }
}
