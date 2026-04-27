variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "waf_mode" { type = string }

variable "api_waf_policies" {
  type = map(object({
    path_patterns = list(string)
  }))
  default = {}
}
