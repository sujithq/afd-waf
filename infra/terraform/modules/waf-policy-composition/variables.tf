variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "waf_mode" { type = string }

variable "waf_exclusions" {
  description = "Managed rule exclusions sourced from config/waf/{env}/exclusions.json."
  type = list(object({
    match_variable          = string
    selector_match_operator = string
    selector                = string
  }))
  default = []
}

variable "waf_rule_overrides" {
  description = "Rule group overrides sourced from config/waf/{env}/rule-overrides.json."
  type = list(object({
    rule_group_name = string
    rules = optional(list(object({
      rule_id = string
      enabled = optional(bool, true)
      action  = string
    })), [])
  }))
  default = []
}
