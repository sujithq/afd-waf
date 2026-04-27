variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "waf_policy_id" { type = string }
variable "base_path_patterns" { type = list(string) }
variable "api_waf_policy_ids" { type = map(string) }
variable "api_waf_policies" {
  type = map(object({
    path_patterns = list(string)
  }))
  default = {}
}
variable "enable_api_waf_associations" { type = bool }
variable "apim_gateway_host" { type = string }
