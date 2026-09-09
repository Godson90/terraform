import os
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential


def get_secret(key_vault_name: str, secret_name: str) -> str:
	"""Retrieve a secret from an Azure Key Vault."""
	key_vault_uri = f"https://{key_vault_name}.vault.azure.net"
	secret_client = SecretClient(
		vault_url=key_vault_uri,
		credential=DefaultAzureCredential(),
	)
	return secret_client.get_secret(secret_name).value


def main() -> None:
	"""Retrieve and print the configured secret."""
	key_vault_name = os.environ["KEY_VAULT_NAME"]
	secret_name = os.environ["SECRET_NAME"]
	print(get_secret(key_vault_name, secret_name))


if __name__ == "__main__":
	main()