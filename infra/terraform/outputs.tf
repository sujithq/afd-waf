output "waf_policy_id" {
  value = module.waf.waf_policy_id
}

output "waf_policy_name" {
  value = module.waf.waf_policy_name
}

output "domain_waf_policy_ids" {
  value = module.waf.domain_waf_policy_ids
}

output "domain_waf_policy_names" {
  value = module.waf.domain_waf_policy_names
}

output "apim_name" {
  value = module.apim.apim_name
}

output "log_analytics_workspace_id" {
  value = local.monitoring_workspace_id
}
