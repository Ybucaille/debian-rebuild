#!/usr/bin/env bash
# Supprime la VM et son disque. L'image de base Debian n'est pas touchée.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config.sh

if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
  virsh destroy "$VM_NAME" >/dev/null 2>&1 || true
  # Pas de --remove-all-storage : il effacerait aussi tout disque rattaché à la VM,
  # y compris l'image de base si la VM pointait dessus.
  virsh undefine "$VM_NAME" --nvram >/dev/null
  echo "VM $VM_NAME supprimée."
else
  echo "Aucune VM $VM_NAME à supprimer."
fi

# Seul le disque créé par deploy.sh est supprimé, désigné par son nom dans son pool.
if virsh vol-info --pool "$VM_POOL" "$VM_NAME.qcow2" >/dev/null 2>&1; then
  virsh vol-delete --pool "$VM_POOL" "$VM_NAME.qcow2" >/dev/null
  echo "Disque $VM_NAME.qcow2 supprimé."
fi
rm -f "$KNOWN_HOSTS"
