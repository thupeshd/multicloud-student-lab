#!/usr/bin/env bash
# Run inside Ubuntu 24.04 WSL. Installs tools only; creates no cloud resources.
set -euo pipefail
sudo apt-get update
sudo apt-get install -y curl ca-certificates gnupg lsb-release git unzip jq openssh-client dnsutils
sudo install -d -m 755 /usr/share/keyrings /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
printf 'deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com %s main\n' "$(lsb_release -cs)" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
sudo chmod a+r /etc/apt/keyrings/microsoft.gpg
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ %s main\n' "$(dpkg --print-architecture)" "$(lsb_release -cs)" | sudo tee /etc/apt/sources.list.d/azure-cli.list >/dev/null
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/cloud.google.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main' | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
sudo apt-get update
sudo apt-get install -y terraform azure-cli google-cloud-cli
if ! command -v aws >/dev/null 2>&1; then
  installer=$(mktemp)
  curl -fsSL https://awscli.amazonaws.com/v2/install.sh -o "$installer"
  bash "$installer"
  rm -f "$installer"
fi
export PATH="$HOME/.local/bin:$PATH"
terraform version
aws --version
az version
gcloud version
printf '\nIf aws is not found in a new terminal, add $HOME/.local/bin to PATH.\n'
