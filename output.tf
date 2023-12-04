output "client_certificate" {
  value     = azurerm_kubernetes_cluster.rg_main.kube_config.0.client_certificate
  sensitive = true
}

output "kube_config" {
  value = azurerm_kubernetes_cluster.rg_main.kube_config_raw

  sensitive = true
}

output "kube_resource_group_name" {
  value = azurerm_kubernetes_cluster.rg_main.node_resource_group
}


# Output the public IP address
output "public_ip_address" {
  value = azurerm_public_ip.aks_public_ip.ip_address
}
