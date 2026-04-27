output "waf_policy_id" {
  value = module.base_waf_rules.waf_policy_id
}

output "api_waf_policy_ids" {
  value = { for api_name, module_instance in module.api_waf_rules : api_name => module_instance.waf_policy_id }
}
