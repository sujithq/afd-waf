terraform {
  required_version = ">= 1.14.9, < 2.0.0"

  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.69.0"
    }
  }
}

provider "azurerm" {
  features {}
}
