variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "waf_policy_id" { type = string }
variable "domain_waf_policy_ids" {
  type    = map(string)
  default = {}
}
variable "base_path_patterns" { type = list(string) }
variable "domain_waf_policies" {
  type = map(object({
    enabled     = bool
    host_name   = string
    dns_zone_id = optional(string)
    api_names   = list(string)
  }))
  default = {}
}
variable "api_routes" {
  type = map(object({
    domain_policy_name = string
    path_patterns      = list(string)
  }))
  default = {}
}
variable "apim_gateway_host" { type = string }
