locals {
  _exclusions_raw = jsondecode(file("${path.root}/../../config/waf/${var.environment}/exclusions.json"))
  _overrides_raw  = jsondecode(file("${path.root}/../../config/waf/${var.environment}/rule-overrides.json"))

  # Map JSON camelCase fields to the Terraform variable shape.
  waf_exclusions = [for e in local._exclusions_raw.exclusions : {
    match_variable          = e.matchVariable
    selector_match_operator = e.selectorMatchOperator
    selector                = e.selector
  }]

  waf_rule_overrides = [for o in local._overrides_raw.overrides : {
    rule_group_name = o.ruleGroupName
    rules = [for r in try(o.rules, []) : {
      rule_id = r.ruleId
      enabled = try(r.enabled, true)
      action  = try(r.action, "Log")
    }]
  }]
}

resource "azurerm_resource_group" "main" {
  name     = "${var.name_prefix}-${var.environment}-rg"
  location = var.location
}

module "waf" {
  source = "./modules/waf-policy-composition"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_prefix         = var.name_prefix
  environment         = var.environment
  waf_mode            = var.waf_mode
  waf_exclusions      = local.waf_exclusions
  waf_rule_overrides  = local.waf_rule_overrides
}

module "apim" {
  source = "./modules/apim-composition"

  resource_group_name  = azurerm_resource_group.main.name
  location             = var.location
  name_prefix          = var.name_prefix
  environment          = var.environment
  apim_publisher_email = var.apim_publisher_email
  apim_publisher_name  = var.apim_publisher_name
}

module "afd" {
  source = "./modules/afd-composition"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  name_prefix         = var.name_prefix
  environment         = var.environment
  waf_policy_id       = module.waf.waf_policy_id
  apim_gateway_host   = module.apim.apim_gateway_host
}
