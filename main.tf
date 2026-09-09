# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.0.0"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

# Resource group that contains all Azure infrastructure.
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = "East US "


  tags = {
    Environment = "TerraformDev"
    Team        = "DevOps"
  }
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "myTFVnet"
  address_space       = ["10.0.0.0/16"]
  location            = "East US"
  resource_group_name = azurerm_resource_group.rg.name
}

# Dedicated subnet required by the Azure VPN gateway.
# Do not associate the application NSG with this subnet.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.255.0/27"]
}

# Static public IP used by the Point-to-Site VPN gateway.
resource "azurerm_public_ip" "vpn_gateway" {
  name                = "myTFVpnGatewayIp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}

# Route-based Point-to-Site VPN gateway using OpenVPN and certificate authentication.
resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "myTFVpnGateway"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"

  ip_configuration {
    name                          = "vpn-gateway-ip"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  vpn_client_configuration {
    address_space        = ["172.16.0.0/24"]
    vpn_auth_types       = ["Certificate", "AAD"]
    vpn_client_protocols = ["OpenVPN"]
    aad_audience         = var.vpn_aad_audience
    aad_issuer           = var.vpn_aad_issuer
    aad_tenant           = var.vpn_aad_tenant

    root_certificate {
      name             = "vpn-root-certificate"
      public_cert_data = filebase64(pathexpand(var.vpn_root_certificate_path))
    }
  }
}

# Create a subnet
resource "azurerm_subnet" "subnet" {
  name                              = "myTFSubnet"
  resource_group_name               = azurerm_resource_group.rg.name
  virtual_network_name              = azurerm_virtual_network.vnet.name
  address_prefixes                  = ["10.0.1.0/24"]
  private_endpoint_network_policies = "Disabled"
}

# Dedicated delegated subnet for the Azure DNS Private Resolver.
# Do not associate an NSG with this subnet.
resource "azurerm_subnet" "dns_resolver" {
  name                 = "DnsResolverSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.254.0/28"]

  delegation {
    name = "dns-resolver-delegation"

    service_delegation {
      name = "Microsoft.Network/dnsResolvers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Azure DNS Private Resolver for DNS queries arriving through the VPN.
resource "azurerm_private_dns_resolver" "resolver" {
  name                = "myTFDnsResolver"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  virtual_network_id  = azurerm_virtual_network.vnet.id
}

# Inbound endpoint used as the DNS server in the Azure VPN Client profile.
resource "azurerm_private_dns_resolver_inbound_endpoint" "resolver" {
  name                    = "myTFDnsInbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.resolver.id
  location                = azurerm_resource_group.rg.location

  ip_configurations {
    private_ip_allocation_method = "Static"
    private_ip_address           = "10.0.254.4"
    subnet_id                    = azurerm_subnet.dns_resolver.id
  }
}

# Application Security Group for web application network identities.
resource "azurerm_application_security_group" "app" {
  name                = "myTFApplicationAsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# NSG that permits only HTTP and HTTPS inbound traffic.
resource "azurerm_network_security_group" "nsg" {
  name                = "myTFNsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    # Permit inbound HTTP traffic for web requests.
    name                                       = "AllowHttp"
    priority                                   = 100
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "80"
    source_address_prefix                      = "*"
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }

  security_rule {
    # Permit inbound HTTPS traffic for secure web requests.
    name                                       = "AllowHttps"
    priority                                   = 110
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "443"
    source_address_prefix                      = "*"
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }

  security_rule {
    # Permit SSH from clients connected through the Point-to-Site VPN.
    name                                       = "AllowSshFromVpn"
    priority                                   = 130
    direction                                  = "Inbound"
    access                                     = "Allow"
    protocol                                   = "Tcp"
    source_port_range                          = "*"
    destination_port_range                     = "22"
    source_address_prefix                      = "172.16.0.0/24"
    destination_application_security_group_ids = [azurerm_application_security_group.app.id]
  }

  security_rule {
    # Allow VNet resources to reach private endpoints over HTTPS.
    name                       = "AllowVnetHttps"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  security_rule {
    # Explicitly deny all other inbound traffic.
    name                       = "DenyOtherInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Apply the NSG rules to the application subnet.
resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# Static public IP used by the load balancer.
resource "azurerm_public_ip" "lb" {
  name                = "myTFPublicIp"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Standard load balancer that distributes public web traffic.
resource "azurerm_lb" "lb" {
  name                = "myTFLb"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "public"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

# Backend pool containing the VM Scale Set instances.
resource "azurerm_lb_backend_address_pool" "pool" {
  name            = "myTFBackendPool"
  loadbalancer_id = azurerm_lb.lb.id
}

# Health probe that checks whether each instance serves HTTP.
resource "azurerm_lb_probe" "http" {
  name            = "http-probe"
  loadbalancer_id = azurerm_lb.lb.id
  protocol        = "Http"
  port            = 80
  request_path    = "/"
}

# Forward public HTTP traffic from the load balancer to the instances.
resource "azurerm_lb_rule" "http" {
  name                           = "http"
  loadbalancer_id                = azurerm_lb.lb.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "public"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.pool.id]
  probe_id                       = azurerm_lb_probe.http.id
}

# Cost-conscious Ubuntu VM for the web workload.
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "myTFVm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_D2s_v7"

  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface_ids = [azurerm_network_interface.vm.id]

  custom_data = base64encode(<<-CLOUD_INIT
    #cloud-config
    package_update: true
    packages:
      - nginx
    CLOUD_INIT
  )
}

resource "azurerm_network_interface" "vm" {
  name                = "myTFVmNic"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  ip_configuration {
    name                          = "internal"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.subnet.id
  }
}

resource "azurerm_network_interface_backend_address_pool_association" "vm" {
  network_interface_id    = azurerm_network_interface.vm.id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.pool.id
}

# Associate the application VM NIC with the application security group.
resource "azurerm_network_interface_application_security_group_association" "vm" {
  network_interface_id          = azurerm_network_interface.vm.id
  application_security_group_id = azurerm_application_security_group.app.id
}

# Private storage account for blob data in the existing resource group.
resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  public_network_access_enabled = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }
}

# Private blob container inside the storage account.
resource "azurerm_storage_container" "blob" {
  name                  = "app-data"
  storage_account_id    = azurerm_storage_account.storage.id
  container_access_type = "private"
}

# Private endpoint that exposes Blob storage inside the existing VNet.
resource "azurerm_private_endpoint" "storage" {
  name                = "myTFStoragePrivateEndpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "myTFStorageConnection"
    private_connection_resource_id = azurerm_storage_account.storage.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "blob-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# Private DNS zone so VNet resources resolve the Blob endpoint privately.
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                = "myTFStorageDnsLink"
  private_dns_zone_id = azurerm_private_dns_zone.blob.id
  virtual_network_id  = azurerm_virtual_network.vnet.id
}

# RBAC-enabled Key Vault for application secrets and certificates.
resource "azurerm_key_vault" "key_vault" {
  name                          = var.key_vault_name
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
}

# Private endpoint for Key Vault access from the VNet and VPN.
resource "azurerm_private_endpoint" "key_vault" {
  name                = "myTFKeyVaultPrivateEndpoint"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.subnet.id

  private_service_connection {
    name                           = "myTFKeyVaultConnection"
    private_connection_resource_id = azurerm_key_vault.key_vault.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = "key-vault-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

# Private DNS zone for Key Vault private endpoint name resolution.
resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                = "myTFKeyVaultDnsLink"
  private_dns_zone_id = azurerm_private_dns_zone.key_vault.id
  virtual_network_id  = azurerm_virtual_network.vnet.id
}


