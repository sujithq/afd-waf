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

variable "waf_config_path" {
  type        = string
  description = "Path to the directory containing exclusions.json and rule-overrides.json."
}
