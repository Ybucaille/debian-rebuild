#!/usr/bin/env bash
# Vérifie, depuis l'hôte et depuis la VM, chaque point de la configuration.
set -uo pipefail
cd "$(dirname "$0")/.."
source ./config.sh
# Les sous-shells « bash -c » ont besoin de vm_ssh, vm_sudo et de leurs variables.
export -f vm_ssh vm_sudo
export VM_IP LAB_KEY KNOWN_HOSTS ADMIN_PASSWORD_FILE

passed=0
failed=0
check() {
  local label=$1; shift
  if "$@" >/dev/null 2>&1; then
    echo "[OK]    $label"; passed=$((passed + 1))
  else
    echo "[ÉCHEC] $label"; failed=$((failed + 1))
  fi
}
not() { ! "$@"; }

# Réseau
check "La VM a l'IP réservée $VM_IP (bail DHCP)" \
  bash -c "virsh net-dhcp-leases $VM_NETWORK | grep -q '$VM_MAC.*$VM_IP/'"
check "La VM répond au ping" ping -c 1 -W 2 "$VM_IP"
check "La VM sort sur Internet via le NAT (deb.debian.org)" \
  vm_ssh curl -sfI --max-time 10 https://deb.debian.org/
check "La VM résout les noms DNS" vm_ssh getent hosts deb.debian.org

# SSH
check "SSH par clé fonctionne pour admin" vm_ssh true
check "SSH ne propose pas l'authentification par mot de passe" \
  bash -c "/usr/bin/ssh -o BatchMode=yes -o PubkeyAuthentication=no \
    -o UserKnownHostsFile=$KNOWN_HOSTS -o StrictHostKeyChecking=no \
    admin@$VM_IP true 2>&1 | grep -q 'Permission denied (publickey)'"
check "Connexion root refusée" \
  not /usr/bin/ssh -o BatchMode=yes -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -i "$LAB_KEY" "root@$VM_IP" true
check "sshd : PermitRootLogin no, PasswordAuthentication no" \
  bash -c "vm_sudo sshd -T | grep -q '^permitrootlogin no' && \
    vm_sudo sshd -T | grep -q '^passwordauthentication no'"
check "SSH : aucun transfert de ports, d'agent ni d'affichage X11" \
  bash -c "vm_sudo sshd -T | grep -qx 'allowtcpforwarding no' && \
    vm_sudo sshd -T | grep -qx 'allowagentforwarding no' && \
    vm_sudo sshd -T | grep -qx 'x11forwarding no'"

# Privilèges
check "sudo refusé sans mot de passe" not vm_ssh sudo -n true
check "sudo accepté avec le mot de passe d'admin" vm_sudo true

# Pare-feu
check "nftables actif, politique d'entrée à drop" \
  bash -c "vm_sudo nft list chain inet filter input | grep -q 'policy drop'"
check "HTTP (80) ouvert : la page d'état répond" \
  bash -c "curl -sf --max-time 5 http://$VM_IP/ | grep -q deb-rebuild"

# Un service écoute sur 8080 dans la VM : il répond en local mais le pare-feu le bloque de l'extérieur.
vm_ssh "nohup python3 -m http.server 8080 >/dev/null 2>&1 & sleep 1"
check "Port 8080 joignable depuis la VM elle-même" vm_ssh curl -sf --max-time 3 http://localhost:8080/
check "Port 8080 bloqué depuis l'hôte par le pare-feu" \
  not curl -sf --max-time 3 "http://$VM_IP:8080/"
vm_ssh "pkill -f 'http.server 8080'"

# Services de sécurité
check "fail2ban surveille sshd" vm_sudo fail2ban-client status sshd
check "Mises à jour de sécurité automatiques activées" \
  bash -c "vm_ssh apt-config dump | grep -q 'APT::Periodic::Unattended-Upgrade \"1\"' && \
    vm_ssh systemctl is-enabled apt-daily-upgrade.timer"
check "Aucune mise à jour en attente" \
  bash -c "[[ \$(vm_ssh apt-get -s upgrade | grep -c '^Inst ') -eq 0 ]]"

# Système
check "Noyau : filtrage anti-usurpation, redirections refusées (sysctl)" \
  bash -c "[[ \$(vm_ssh /sbin/sysctl -n net.ipv4.conf.all.rp_filter net.ipv4.conf.all.accept_redirects \
    net.ipv4.conf.all.send_redirects net.ipv4.conf.all.log_martians kernel.kptr_restrict | tr '\n' ' ') \
    == '1 0 0 1 2 ' ]]"
check "Modules inutiles bloqués (stockage USB, dccp, sctp...)" \
  bash -c "vm_ssh /sbin/modprobe -n -v usb-storage | grep -q /bin/false && \
    vm_ssh /sbin/modprobe -n -v dccp | grep -q /bin/false"
check "AppArmor actif" bash -c "[[ \$(vm_ssh cat /sys/module/apparmor/parameters/enabled) == Y ]]"
check "auditd surveille comptes, sudo, SSH et pare-feu" \
  bash -c "[[ \$(vm_sudo auditctl -l | grep -c -- '-k ') -ge 8 ]]"

echo
echo "$passed tests réussis, $failed en échec."
[[ $failed -eq 0 ]]
