variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "waf_policy_id" { type = string }
variable "base_path_patterns" { type = list(string) }
variable "api_routes" {
  type = map(object({
    domain_policy_name = string
    path_patterns      = list(string)
  }))
  default = {}
}
variable "apim_gateway_host" { type = string }
