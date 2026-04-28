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

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(set(string), [])
    log_groups                               = optional(set(string), ["allLogs"])
    metric_categories                        = optional(set(string), ["AllMetrics"])
    log_analytics_destination_type           = optional(string, "AzureDiagnostics")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default = {}
}
