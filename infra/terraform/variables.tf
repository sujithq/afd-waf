variable "location" {
  type = string
}

variable "environment" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "waf_mode" {
  type    = string
  default = "Detection"
}

variable "apim_publisher_email" {
  type = string
}

variable "apim_publisher_name" {
  type = string
}

variable "enable_monitoring" {
  type    = bool
  default = true
}

variable "log_analytics_workspace_id" {
  type     = string
  default  = null
  nullable = true
}
