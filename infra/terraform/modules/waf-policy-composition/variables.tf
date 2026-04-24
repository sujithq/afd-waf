variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "waf_mode" { type = string }

variable "waf_config_path" {
  type        = string
  description = "Path to the WAF configuration directory containing exclusions.json and rule-overrides.json"
}
