#!/usr/bin/env bash
# Crée la VM à partir de l'image cloud Debian et attend la fin de cloud-init.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config.sh

mkdir -p "$BUILD_DIR"

# Clé SSH dédiée au labo, générée une seule fois.
[[ -f $LAB_KEY ]] || ssh-keygen -q -t ed25519 -N "" -C "debian-rebuild-lab" -f "$LAB_KEY"

# Clés autorisées sur la VM : la clé de labo, plus la clé personnelle si elle existe.
keys=("$(cat "$LAB_KEY.pub")")
[[ -f $HOME/.ssh/id_ed25519.pub ]] && keys+=("$(cat "$HOME/.ssh/id_ed25519.pub")")
while IFS= read -r line; do
  if [[ $line == *__SSH_KEY__* ]]; then
    for k in "${keys[@]}"; do echo "${line/__SSH_KEY__/$k}"; done
  else
    echo "$line"
  fi
done < cloud-init/user-data.yaml > "$BUILD_DIR/user-data.yaml"

# Réservation DHCP : la MAC de la VM reçoit toujours la même IP.
if ! virsh net-dumpxml "$VM_NETWORK" | grep -q "mac='$VM_MAC'"; then
  virsh net-update "$VM_NETWORK" add ip-dhcp-host \
    "<host mac='$VM_MAC' name='$VM_NAME' ip='$VM_IP'/>" --live --config
fi

# Disque adossé à l'image de base : seules les différences sont écrites.
virsh pool-refresh "$BASE_POOL" >/dev/null
virsh vol-create-as "$VM_POOL" "$VM_NAME.qcow2" "$VM_DISK_SIZE" --format qcow2 \
  --backing-vol "$BASE_IMAGE" --backing-vol-format qcow2 >/dev/null

virt-install --name "$VM_NAME" --memory "$VM_MEMORY" --vcpus "$VM_VCPUS" \
  --osinfo debian13 --boot uefi --import \
  --disk "vol=$VM_POOL/$VM_NAME.qcow2,bus=virtio" \
  --network "network=$VM_NETWORK,mac=$VM_MAC,model=virtio" \
  --cloud-init "user-data=$BUILD_DIR/user-data.yaml" \
  --graphics none --noautoconsole >/dev/null

echo "VM créée, attente de SSH sur $VM_IP..."
rm -f "$KNOWN_HOSTS"
for _ in $(seq 1 100); do
  vm_ssh true 2>/dev/null && break
  sleep 3
done

# cloud-init redémarre sshd en fin de configuration : on réessaie si la connexion saute.
echo "Attente de la fin de cloud-init..."
for _ in $(seq 1 10); do
  status=0
  vm_ssh cloud-init status --wait >/dev/null 2>&1 || status=$?
  [[ $status -ne 255 ]] && break
  sleep 3
done
if [[ $status -ne 0 ]]; then
  echo "cloud-init a terminé avec des erreurs (code $status) :" >&2
  vm_ssh cloud-init status --long >&2 || true
  exit 1
fi
echo "VM prête."
