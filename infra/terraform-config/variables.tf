variable "environment" {
  type        = string
  description = "Target environment: dev, test, or prod."
}

variable "waf_policy_id" {
  type        = string
  description = "Resource ID of the WAF policy created by the infra stack."
}

variable "waf_policy_name" {
  type        = string
  description = "Name of the WAF policy created by the infra stack."
}

variable "name_prefix" {
  type        = string
  description = "Name prefix used for WAF policy naming."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID used to construct domain-specific WAF policy import IDs."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group containing the WAF policy."
}

variable "waf_mode" {
  type        = string
  default     = "Detection"
  description = "WAF policy mode: Detection or Prevention."
}
