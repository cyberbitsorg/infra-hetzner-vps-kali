#!/usr/bin/env bash
set -euo pipefail

VAULT_PASS_FILE=".vault_pass"
VAULT_FILE="ansible/group_vars/all/vault.yaml"

if [ ! -f "$VAULT_PASS_FILE" ]; then
  if grep -q '^\$ANSIBLE_VAULT' "$VAULT_FILE" 2>/dev/null; then
    echo "ERROR: $VAULT_FILE exists and is encrypted but .vault_pass is missing."
    echo ""
    echo "  - If you intended to overwrite it: restore .vault_pass first, then re-run."
    echo "  - If this is a fresh setup (cloned repo): delete $VAULT_FILE and re-run."
    exit 1
  fi
  read -rsp "Enter vault passphrase: " passphrase
  echo
  echo "$passphrase" > "$VAULT_PASS_FILE"
  chmod 600 "$VAULT_PASS_FILE"
  echo "Created $VAULT_PASS_FILE"
fi

{
  printf "vault_deployacc_sudo_passwords:\n"
  tofu output -json deployacc_sudo_password | jq -r 'to_entries[] | "  \(.key): \(.value)"'
} > /tmp/vault.tmp
ansible-vault encrypt /tmp/vault.tmp --output "$VAULT_FILE"
rm /tmp/vault.tmp

echo "Vault written to $VAULT_FILE"
