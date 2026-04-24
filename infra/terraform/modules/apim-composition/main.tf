# avm-id: terraform-apim-composition
module "apim" {
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.0.7"

  name                = lower("${var.name_prefix}-apim-${var.environment}")
  location            = var.location
  resource_group_name = var.resource_group_name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = "Developer_1"
  enable_telemetry    = true

  apis = {
    odata1 = {
      name                  = "odata-sap-1"
      type                  = "http"
      display_name          = "OData Mock API 1"
      path                  = "odata1"
      revision              = "1"
      protocols             = ["https"]
      service_url           = "https://example.com/odata1"
      subscription_required = false
      operations = {
        entities = {
          display_name = "List Entities"
          method       = "GET"
          url_template = "/Entities"
          policy = {
            xml_content = <<XML
<policies>
  <inbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>{"value":[{"Id":1,"Name":"Alpha"},{"Id":2,"Name":"Iota"}]}</set-body>
    </return-response>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
          }
        }
      }
    }
    odata2 = {
      name                  = "odata-sap-2"
      type                  = "http"
      display_name          = "OData Mock API 2"
      path                  = "odata2"
      revision              = "1"
      protocols             = ["https"]
      service_url           = "https://example.com/odata2"
      subscription_required = false
      operations = {
        entities = {
          display_name = "List Entities"
          method       = "GET"
          url_template = "/Entities"
          policy = {
            xml_content = <<XML
<policies>
  <inbound>
    <base />
    <return-response>
      <set-status code="200" reason="OK" />
      <set-header name="Content-Type" exists-action="override">
        <value>application/json</value>
      </set-header>
      <set-body>{"value":[{"Id":10,"Name":"Ibis"},{"Id":11,"Name":"Aster"}]}</set-body>
    </return-response>
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
XML
          }
        }
      }
    }
  }
}
