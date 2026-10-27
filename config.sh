# Paramètres de la VM, lus par tous les scripts.
export LIBVIRT_DEFAULT_URI=qemu:///system

VM_NAME=deb-rebuild
VM_MAC=52:54:00:a1:00:40
VM_IP=192.168.122.40
VM_NETWORK=default
VM_MEMORY=1024
VM_VCPUS=2
VM_DISK_SIZE=10G
VM_POOL=default

BASE_POOL=iso
BASE_IMAGE=$HOME/Documents/autres/iso/debian-13-genericcloud-amd64.qcow2

BUILD_DIR=build
LAB_KEY=$BUILD_DIR/lab_ed25519
KNOWN_HOSTS=$BUILD_DIR/known_hosts

# ssh vers la VM avec la clé de labo (sans passphrase, ne sert qu'ici).
vm_ssh() {
  /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=5 \
    -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -i "$LAB_KEY" "admin@$VM_IP" "$@"
}
