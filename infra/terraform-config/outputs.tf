output "waf_policy_id" {
  value = module.base_waf_rules.waf_policy_id
}

output "domain_waf_policy_ids" {
  value = { for domain_name, module_instance in module.domain_waf_rules : domain_name => module_instance.waf_policy_id }
}
