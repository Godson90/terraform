variable "resource_group_name" {
  default = "TFlearning02"
}

variable "ssh_public_key" {
  description = "SSH public key used to access the VM instances."
  type        = string
}

variable "storage_account_name" {
  description = "Globally unique lowercase Azure Storage account name."
  type        = string
  default     = "mytfstorageacct02"
}

variable "key_vault_name" {
  description = "Globally unique alphanumeric Azure Key Vault name."
  type        = string
  default     = "mytfkeyvault02"
}

variable "vpn_root_certificate" {
  description = "Base64-encoded DER data for the VPN root certificate (.cer)."
  type        = string
}

variable "vpn_aad_audience" {
  description = "Microsoft Entra ID application audience for Point-to-Site VPN authentication."
  type        = string
  default     = "54bc1973-9bd2-4aee-8edb-9f99b7f2b9f2"
}

variable "vpn_aad_issuer" {
  description = "Microsoft Entra ID issuer URL for Point-to-Site VPN authentication."
  type        = string
  default     = "https://sts.windows.net/08cc6287-03a2-4a4c-8305-7880408f427a/"
}

variable "vpn_aad_tenant" {
  description = "Microsoft Entra ID tenant URL for Point-to-Site VPN authentication."
  type        = string
  default     = "https://login.microsoftonline.com/08cc6287-03a2-4a4c-8305-7880408f427a/"
}

