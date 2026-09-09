# Azure Terraform Lab

Terraform configuration for an Azure application environment in **East US**. The project provisions a private virtual network, a single Ubuntu web VM, private Blob storage, and a Point-to-Site VPN path for administrative and storage access.

## Architecture

```text
												 Internet
														|
									 Standard Public IP
														|
										Azure Load Balancer
														|
										myTFApplicationAsg
														|
								 myTFVm (Ubuntu + nginx)
														|
												 myTFVnet
												 10.0.0.0/16
														|
						 +--------------+--------------+
						 |                             |
			 myTFSubnet                    Private Endpoint
			 10.0.1.0/24                   Blob Storage
						 |                             |
			 Application NSG              mytfstorageacct02
			 TCP 22, 80, 443                    |
																 app-data container

			 Point-to-Site VPN  --->  GatewaySubnet
			 172.16.0.0/24             10.0.255.0/27
																			|
															DNS Private Resolver
															inbound: 10.0.254.4
```

## Resources

| Area | Resource | Configuration |
| --- | --- | --- |
| Resource group | `TFlearning02` | East US |
| VNet | `myTFVnet` | `10.0.0.0/16` |
| Application subnet | `myTFSubnet` | `10.0.1.0/24` |
| VM | `myTFVm` | Ubuntu 24.04, `Standard_D2s_v7`, nginx bootstrap |
| Load balancer | `myTFLb` | Standard SKU, HTTP frontend on port 80 |
| NSG | `myTFNsg` | HTTP/HTTPS, VPN-scoped SSH, deny other inbound traffic |
| ASG | `myTFApplicationAsg` | Attached to the application VM NIC |
| Storage | `mytfstorageacct02` | Standard LRS, public access disabled |
| Blob container | `app-data` | Private access, 7-day soft delete |
| Private endpoint | `myTFStoragePrivateEndpoint` | Blob subresource in the application subnet |
| VPN gateway | `myTFVpnGateway` | `VpnGw1AZ`, OpenVPN, certificate + Entra ID |
| DNS resolver | `myTFDnsResolver` | Inbound endpoint `10.0.254.4` |

## Prerequisites

- macOS or another supported Terraform host
- Terraform `>= 1.1.0`
- Azure CLI authenticated with a subscription:

	```bash
	az login
	az account set --subscription "c3c90939-5b92-**********************"
	```

- An SSH public key value for the VM, supplied through `ssh_public_key`
- A base64-encoded DER-encoded VPN root certificate value, supplied through `vpn_root_certificate`
- Permission to create Azure networking, compute, storage, and VPN resources

The AzureRM provider is pinned to version `5.0.0` in `main.tf`. Terraform downloads this provider locally into `.terraform`, which is intentionally ignored by Git.

## Certificate Setup

The gateway trusts the public root certificate. The private root key must never be placed in Terraform, Git, or `terraform.tfvars`.

Create a root certificate on macOS:

```bash
openssl genrsa -out ~/.vpn-root.key 4096

openssl req -x509 -new -nodes \
	-key ~/.vpn-root.key \
	-sha256 -days 3650 \
	-out ~/.vpn-root.pem \
	-subj "/CN=Terraform VPN Root"

openssl x509 -in ~/.vpn-root.pem -outform DER -out ~/.vpn-root.cer
```

Create a client certificate signed by the root certificate:

```bash
openssl genrsa -out ~/.vpn-client.key 2048

openssl req -new \
	-key ~/.vpn-client.key \
	-out ~/.vpn-client.csr \
	-subj "/CN=Azure VPN Client"

openssl x509 -req \
	-in ~/.vpn-client.csr \
	-CA ~/.vpn-root.pem \
	-CAkey ~/.vpn-root.key \
	-CAcreateserial \
	-out ~/.vpn-client.crt \
	-days 365 \
	-sha256

openssl pkcs12 -export \
	-out ~/.vpn-client.p12 \
	-inkey ~/.vpn-client.key \
	-in ~/.vpn-client.crt \
	-passout pass:
```

The final command creates a `.p12` file with a blank password. Import it into the macOS login keychain:

```bash
open ~/.vpn-client.p12
open -a "Keychain Access"
```

## Configuration Variables

Defaults are defined in `variable.tf`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `resource_group_name` | `TFlearning02` | Existing or new resource group |
| `ssh_public_key` | No default | Public key value installed on the VM |
| `storage_account_name` | `mytfstorageacct02` | Globally unique lowercase storage name |
| `vpn_root_certificate` | No default | Base64-encoded DER public VPN root certificate |
| `vpn_aad_audience` | Confirmed Entra application ID | VPN Entra audience |
| `vpn_aad_issuer` | Tenant issuer URL | VPN Entra issuer |
| `vpn_aad_tenant` | Tenant login URL | VPN Entra tenant |

Override values in a local `terraform.tfvars` file. Do not commit that file if it contains environment-specific values.

For HCP Terraform, add these as **Terraform variables** in the workspace settings. Do not add them as environment variables and do not commit their values to Git:

| Name | Value | Sensitive |
| --- | --- | --- |
| `ssh_public_key` | Contents of `~/.ssh/id_ed25519.pub` | No |
| `vpn_root_certificate` | Base64 output of `~/.vpn-root.cer` | No |

You can copy the values on macOS with:

```bash
cat ~/.ssh/id_ed25519.pub
base64 < ~/.vpn-root.cer | tr -d '\n'
```

Set both variables in the HCP Terraform workspace before running a plan. The remote runner cannot access files stored on your Mac.

Example:

```hcl
resource_group_name   = "TFlearning02"
ssh_public_key        = "ssh-ed25519 AAAA... user@example.com"
storage_account_name  = "myuniquestorageacct01"
vpn_root_certificate  = "<base64-encoded DER certificate>"
```

Generate the base64 certificate value for HCP Terraform with:

```bash
base64 < ~/.vpn-root.cer | tr -d '\n'
```

## Deploy

Initialize, format, validate, and review the plan:

```bash
terraform init
terraform fmt
terraform validate
terraform plan
```

Apply after reviewing the plan:

```bash
terraform apply
```

The `VpnGw1AZ` gateway can take a significant amount of time to create or update and incurs ongoing Azure charges. The gateway public IP is zone-redundant across zones 1, 2, and 3.

If a resource already exists in Azure but is not in Terraform state, import it instead of creating a duplicate. Example:

The import command requires the two required variables to be available, but
the certificate value is not part of the Azure resource ID. For a local CLI
session connected to the HCP workspace, run:

```bash
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
export TF_VAR_vpn_root_certificate="$(base64 < ~/.vpn-root.cer | tr -d '\n')"

terraform import azurerm_resource_group.rg \
	"/subscriptions/c3c90939-5b92-421c-a37c-55fb5fa73aff/resourceGroups/TFlearning02"

terraform import azurerm_virtual_network_gateway.vpn \
	"/subscriptions/<subscription-id>/resourceGroups/TFlearning02/providers/Microsoft.Network/virtualNetworkGateways/myTFVpnGateway"
```

If the HCP workspace already has `ssh_public_key` and `vpn_root_certificate`
configured as Terraform variables, do not export them locally. Run the import
from the directory initialized against that HCP workspace. Alternatively, use
the workspace state-management import workflow. Importing into a local-only
state file does not update HCP Terraform.

## VPN Connection

The gateway supports both authentication modes:

- Microsoft Entra ID through the Azure VPN Client
- Azure certificate authentication through the client certificate

After applying changes to the VPN gateway, download a fresh client profile from:

```text
Azure Portal -> Virtual network gateways -> myTFVpnGateway
-> Point-to-site configuration -> Download VPN client
```

For Entra authentication, use the generated `azurevpnconfig_aad.xml` profile. To make private Blob DNS resolution work from the Mac, the profile must contain exactly one `clientconfig` block:

```xml
<clientconfig>
	<dnsservers>
		<dnsserver>10.0.254.4</dnsserver>
	</dnsservers>
</clientconfig>
```

On macOS:

1. Disconnect and remove the old Azure VPN Client profile.
2. Import the edited AAD XML profile.
3. Sign in with Entra ID when prompted.
4. Reconnect the VPN.
5. Flush the local DNS cache:

	 ```bash
	 sudo dscacheutil -flushcache
	 sudo killall -HUP mDNSResponder
	 ```

The Azure Private DNS Resolver receives the request and resolves the Blob hostname through the VNet-linked private zone.

## Verify Private DNS and Blob Access

Check the resolver directly:

```bash
nslookup mytfstorageacct02.blob.core.windows.net 10.0.254.4
```

Expected result:

```text
mytfstorageacct02.privatelink.blob.core.windows.net
Address: 10.0.1.5
```

Then check the system resolver used by macOS:

```bash
scutil --dns | grep -A5 -B2 '10.0.254.4'
nslookup mytfstorageacct02.blob.core.windows.net
```

If the normal lookup returns a public Azure address such as `20.x.x.x`, the VPN profile is not applying the custom DNS server. Re-import the profile and confirm the `clientconfig` block is not duplicated.

Storage account access is private-only:

```hcl
public_network_access_enabled = false
```

Storage Explorer must be connected through the VPN or another network path into the VNet. Your Entra identity also needs an Azure role such as **Storage Blob Data Contributor** on the storage account or container.

## SSH to the VM

The VM uses:

- Username: `azureuser`
- Private key: `~/.ssh/id_ed25519`
- Private IP: retrieve it from the Azure portal or CLI

The NSG permits TCP 22 only from the VPN client pool `172.16.0.0/24` and targets the application ASG. Connect while the VPN is active:

```bash
ssh -i ~/.ssh/id_ed25519 azureuser@<vm-private-ip>
```

If SSH fails:

```bash
az vm show -d \
	--resource-group TFlearning02 \
	--name myTFVm \
	--query '{powerState:powerState,privateIps:privateIps}' \
	-o json

az network nic show \
	--resource-group TFlearning02 \
	--name myTFVmNic \
	--query 'ipConfigurations[].privateIpAddress' \
	-o tsv
```

Also verify that the VM is running and that SSH is listening inside the VM:

```bash
sudo systemctl status ssh
sudo ss -lntp | grep ':22'
```

## Terraform Outputs

Display deployed values with:

```bash
terraform output
```

Available outputs:

- `resource_group_id`
- `load_balancer_public_ip`
- `vm_id`
- `storage_account_name`
- `blob_container_name`
- `vpn_gateway_public_ip`
- `dns_resolver_inbound_ip`

## Security Notes

- Keep private keys such as `~/.vpn-root.key`, `~/.vpn-client.key`, and `~/.ssh/id_ed25519` private.
- Keep public network access disabled on the storage account unless temporary troubleshooting requires otherwise.
- Do not put private keys, client certificates with private keys, or Terraform state in Git.
- `terraform.tfstate` can contain sensitive infrastructure metadata and is ignored by this repository.
- The NSG has an explicit inbound deny-all rule at priority 4096. New inbound rules must have a lower priority number than 4096.
- `GatewaySubnet` and `DnsResolverSubnet` are reserved service subnets and should not receive the application NSG.
- The current configuration uses one VM, so it is not horizontally scalable. The load balancer is present, but adding more VM instances requires an additional VM or a future VM Scale Set design.

## Cleanup

Destroying the stack removes the Azure resources managed by this Terraform state:

```bash
terraform plan -destroy
terraform destroy
```

Review the destroy plan carefully. The VPN gateway and storage resources may have operational dependencies or data that should be retained before cleanup.
