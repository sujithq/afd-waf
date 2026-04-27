output "apim_name" {
  value = module.apim.name
}

output "apim_gateway_host" {
  value = module.apim.apim_gateway_url
}

output "api_paths_by_name" {
  value = {
    for _, api in local.apis : api.name => api.path
  }
}
