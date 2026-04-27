variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "waf_mode" { type = string }

variable "domain_waf_policies" {
  type = map(object({
    enabled     = bool
    host_name   = string
    dns_zone_id = optional(string)
    api_names   = list(string)
  }))
  default = {}
}
