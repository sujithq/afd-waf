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
