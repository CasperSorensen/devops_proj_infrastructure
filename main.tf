terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.1"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "Networking-Hub-RG" {
  name     = "Networking-Hub-RG"
  location = var.location
}

resource "azurerm_resource_group" "Application-Spoke-RG" {
  name     = "Application-Spoke-RG"
  location = var.location
}

# Hub Configuration
resource "azurerm_virtual_network" "hub-vnet" {
  name                = "hub-vnet"
  location            = azurerm_resource_group.Networking-Hub-RG.location
  resource_group_name = azurerm_resource_group.Networking-Hub-RG.name
  address_space       = ["10.0.0.0/16"]
  tags = {
    environment = "hub-spoke"
  }
}

resource "azurerm_subnet" "hub-gateway-subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.Networking-Hub-RG.name
  virtual_network_name = azurerm_resource_group.Networking-Hub-RG.name
  address_prefixes     = ["10.0.1.0/27"]
}

resource "azurerm_subnet" "PrivateLinkSubnet" {
  name                 = "PrivateLinkSubnet"
  resource_group_name  = azurerm_resource_group.Networking-Hub-RG.name
  virtual_network_name = azurerm_resource_group.Networking-Hub-RG.name
  address_prefixes     = ["10.0.2.0/27"]
}

resource "azurerm_subnet" "FirewallSubnet" {
  name                 = "FirewallSubnet"
  resource_group_name  = azurerm_resource_group.Networking-Hub-RG.name
  virtual_network_name = azurerm_resource_group.Networking-Hub-RG.name
  address_prefixes     = ["10.0.3.0/27"]
}

resource "azurerm_subnet" "hub-AksClusterSubnet" {
  name                 = "hub-AksClusterSubnet"
  resource_group_name  = azurerm_resource_group.Networking-Hub-RG.name
  virtual_network_name = azurerm_resource_group.Networking-Hub-RG.name
  address_prefixes     = ["10.0.4.0/27"]
}

# Spoke configuration
resource "azurerm_virtual_network" "spoke-vnet" {
  name                = "spoke-vnet"
  location            = azurerm_resource_group.Application-Spoke-RG.location
  resource_group_name = azurerm_resource_group.Application-Spoke-RG.name
  address_space       = ["10.1.0.0/16"]
  tags = {
    environment = "hub-spoke"
  }
}

resource "azurerm_subnet" "AKSSubnet" {
  name                 = "AKSSubnet"
  resource_group_name  = azurerm_resource_group.Application-Spoke-RG.name
  virtual_network_name = azurerm_resource_group.Application-Spoke-RG.name
  address_prefixes     = ["10.1.1.0/27"]
}

resource "azurerm_subnet" "NodePoolSubnet" {
  name                 = "NodePoolSubnet"
  resource_group_name  = azurerm_resource_group.Application-Spoke-RG.name
  virtual_network_name = azurerm_resource_group.Application-Spoke-RG.name
  address_prefixes     = ["10.1.2.0/27"]
}

resource "azurerm_subnet" "SQLDBPrivateEndpointSubnet" {
  name                 = "SQLDBPrivateEndpointSubnet"
  resource_group_name  = azurerm_resource_group.Application-Spoke-RG.name
  virtual_network_name = azurerm_resource_group.Application-Spoke-RG.name
  address_prefixes     = ["10.1.3.0/27"]
}

resource "azurerm_virtual_network_peering" "hub-to-spoke" {
  name                         = "hub-to-spoke"
  resource_group_name          = azurerm_resource_group.Networking-Hub-RG.name
  virtual_network_name         = azurerm_resource_group.Networking-Hub-RG.name
  remote_virtual_network_id    = azurerm_resource_group.Application-Spoke-RG.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke-to-hub" {
  name                         = "spoke-to-hub"
  resource_group_name          = azurerm_resource_group.Application-Spoke-RG.name
  virtual_network_name         = azurerm_resource_group.Application-Spoke-RG.name
  remote_virtual_network_id    = azurerm_resource_group.Networking-Hub-RG.id
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  allow_virtual_network_access = true
  use_remote_gateways          = false
}

# Modules
resource "azurerm_kubernetes_cluster" "aks-cluster" {
  name                = "aks-cluster"
  location            = azurerm_resource_group.Application-Spoke-RG.location
  resource_group_name = azurerm_resource_group.Application-Spoke-RG.name
  dns_prefix          = "aks-cluster"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = "Development"
  }

  #Enable Azure CNI for custom networking
  network_profile {
    network_plugin = "azure"
    network_policy = "calico"

    # Connect the AKS cluster to the ArgoCD subnet in the Hub VNet
    #subnet = azure
  }
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.aks-cluster.kube_config[0].client_certificate
  sensitive = true
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks-cluster.kube_config_raw
  sensitive = true
}
