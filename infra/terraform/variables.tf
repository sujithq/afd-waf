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

variable "enable_api_waf_associations" {
  type        = bool
  default     = true
  description = "Set false for a bootstrap apply that removes/skips API WAF associations while AFD route patterns are created. Run a normal apply afterwards to add the associations back."
}
