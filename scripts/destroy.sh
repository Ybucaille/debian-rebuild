#!/usr/bin/env bash
# Supprime la VM et son disque. L'image de base Debian n'est pas touchée.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config.sh

if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
  virsh destroy "$VM_NAME" >/dev/null 2>&1 || true
  virsh undefine "$VM_NAME" --remove-all-storage --nvram >/dev/null
  echo "VM $VM_NAME supprimée."
else
  echo "Aucune VM $VM_NAME à supprimer."
fi
rm -f "$KNOWN_HOSTS"
