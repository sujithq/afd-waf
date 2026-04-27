variable "waf_policy_name" {
  type        = string
  description = "Name of the existing WAF policy to manage."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group containing the WAF policy."
}

variable "waf_mode" {
  type        = string
  description = "WAF policy mode: Detection or Prevention."
}

variable "waf_config_paths" {
  type        = list(string)
  description = "Ordered directories containing exclusions.json and rule-overrides.json. Later entries append to earlier base entries."
}

variable "disabled_exclusions" {
  type = list(object({
    matchVariable         = string
    selectorMatchOperator = string
    selector              = string
    ruleSet               = string
    ruleGroup             = string
    ruleId                = string
  }))
  default     = []
  description = "Exclusions to remove from the merged config for this WAF policy. Used for API-specific opt-outs from base exclusions."
}
