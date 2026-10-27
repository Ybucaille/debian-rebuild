# debian-rebuild

Un serveur Debian 13 durci, créé et configuré entièrement par script sous KVM/libvirt, puis vérifié par 22 tests. Une seule commande le détruit et le reconstruit à l'identique. Lynis lui donne une note de durcissement de **84/100**, contre 67 pour la même VM avant durcissement.

```
scripts/rebuild.sh
```

```
>> Destruction : 1 s
>> Déploiement : 139 s
>> Tests : 10 s
Reconstruction complète et testée en 2 min 30 s.
```

## Ce que fait le serveur

Tout est décrit dans [cloud-init/user-data.yaml](cloud-init/user-data.yaml) et appliqué au premier démarrage.

**Accès**
- Un seul compte, `admin`, joignable uniquement par clé SSH. Root et les mots de passe sont refusés en SSH.
- SSH n'autorise ni le transfert de ports, ni celui de l'agent, ni l'affichage X11. Il limite les sessions et journalise en détail.
- `sudo` demande le mot de passe d'`admin` pour toute commande, sans exception. Ce mot de passe est généré aléatoirement au déploiement et ne sert qu'à `sudo`.
- La politique de mot de passe est renforcée (passwdqc, hachage, durée de vie), et l'`umask` par défaut passe à 027.

**Réseau**
- Pare-feu nftables en liste blanche : tout ce qui entre est refusé, sauf SSH (22), HTTP (80), le ping et les réponses aux connexions sortantes.
- fail2ban : 3 échecs SSH en 10 minutes valent un bannissement d'une heure.
- Noyau : filtrage des adresses usurpées (`rp_filter`), redirections ICMP refusées, paquets impossibles journalisés.

**Système**
- Les modules noyau inutiles sont bloqués : stockage USB, firewire, protocoles réseau rares (dccp, sctp, rds, tipc) et iptables, puisque le pare-feu passe par nftables.
- auditd trace toute modification des comptes, de sudo, de SSH et du pare-feu.
- Les mises à jour de sécurité s'installent automatiquement (unattended-upgrades), needrestart signale les services à redémarrer, et debsums vérifie chaque semaine les fichiers des paquets.
- Les fichiers sensibles (`grub.cfg`, `sshd_config`, dossiers cron) ne sont lisibles que par root.
- nginx sert une page d'état qui indique la date de construction.

## Réseau

```
VM 192.168.122.40 ──► virbr0 192.168.122.1 ──► NAT de l'hôte ──► box ──► Internet
```

La VM est sur le réseau NAT `default` de libvirt. Une réservation DHCP associe sa MAC (`52:54:00:a1:00:40`) à l'IP `192.168.122.40`, qui reste la même à chaque reconstruction. La VM peut sortir sur Internet, mais seul l'hôte peut la joindre.

## Installation

### Prérequis

- Linux avec KVM et libvirt (`qemu:///system`, utilisateur dans le groupe `libvirt`) ;
- `virt-install` 4 ou plus ;
- le firmware UEFI OVMF ;
- `openssl` sur l'hôte.

### 1. Récupérer l'image Debian

Placez l'image cloud officielle dans un dossier déclaré comme pool libvirt, puis vérifiez sa somme :

```
curl -LO https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
curl -LO https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
grep ' debian-13-genericcloud-amd64.qcow2$' SHA512SUMS | sha512sum -c -
```

### 2. Régler la configuration

Les paramètres sont dans [config.sh](config.sh) : nom, MAC, IP, mémoire, taille du disque. Indiquez votre pool et le chemin de l'image dans `BASE_POOL` et `BASE_IMAGE`.

### 3. Lancer

```
scripts/rebuild.sh
scripts/audit.sh
```

Au premier lancement, `deploy.sh` crée dans `build/`, un dossier ignoré par git, une clé SSH dédiée au labo et le mot de passe d'`admin`. Si `~/.ssh/id_ed25519.pub` existe, cette clé est aussi autorisée sur la VM.

## Les scripts

| Script | Rôle |
|---|---|
| `scripts/deploy.sh` | Prépare le fichier cloud-init, ajoute la réservation DHCP si elle manque, crée un disque adossé à l'image Debian, lance la VM et attend la fin de cloud-init. |
| `scripts/test.sh` | Vérifie la configuration depuis l'hôte et depuis la VM. |
| `scripts/destroy.sh` | Supprime la VM et son disque, et uniquement eux. L'image de base n'est jamais touchée. |
| `scripts/rebuild.sh` | Enchaîne les trois précédents et chronomètre chaque étape. |
| `scripts/audit.sh` | Lance Lynis dans la VM et affiche la note de durcissement. Il est à part, car un audit prend environ une minute. |

Le disque de la VM est adossé à l'image de base : il n'enregistre que les différences. Reconstruire ne retélécharge donc pas l'image.

Les commandes root des tests passent par `sudo` avec le mot de passe d'`admin`, envoyé dans le canal SSH chiffré. Aucune commande n'est autorisée sans mot de passe.

## Les tests

```
[OK]    La VM a l'IP réservée 192.168.122.40 (bail DHCP)
[OK]    La VM répond au ping
[OK]    La VM sort sur Internet via le NAT (deb.debian.org)
[OK]    La VM résout les noms DNS
[OK]    SSH par clé fonctionne pour admin
[OK]    SSH ne propose pas l'authentification par mot de passe
[OK]    Connexion root refusée
[OK]    sshd : PermitRootLogin no, PasswordAuthentication no
[OK]    SSH : aucun transfert de ports, d'agent ni d'affichage X11
[OK]    sudo refusé sans mot de passe
[OK]    sudo accepté avec le mot de passe d'admin
[OK]    nftables actif, politique d'entrée à drop
[OK]    HTTP (80) ouvert : la page d'état répond
[OK]    Port 8080 joignable depuis la VM elle-même
[OK]    Port 8080 bloqué depuis l'hôte par le pare-feu
[OK]    fail2ban surveille sshd
[OK]    Mises à jour de sécurité automatiques activées
[OK]    Aucune mise à jour en attente
[OK]    Noyau : filtrage anti-usurpation, redirections refusées (sysctl)
[OK]    Modules inutiles bloqués (stockage USB, dccp, sctp...)
[OK]    AppArmor actif
[OK]    auditd surveille comptes, sudo, SSH et pare-feu

22 tests réussis, 0 en échec.
```

Le test du port 8080 lance un petit serveur web dans la VM. Il répond en local, mais pas depuis l'hôte : c'est la preuve que le pare-feu filtre vraiment, et pas seulement qu'aucun service n'écoute.

Pour vérifier que les tests savent aussi échouer, j'ai vidé les règles nftables de la VM. Deux tests sont alors bien passés en échec (20 réussis, 2 en échec) : celui de la politique `drop` et celui du port 8080.

## Audit Lynis

| | Note | Avertissements | Suggestions |
|---|---|---|---|
| Image Debian + première version | 67/100 | 2 | 47 |
| Version durcie | 84/100 | 1 | 16 |

Mesuré avec Lynis 3.1.4 (`lynis audit system --quick`). La note de 84 est la même sur deux reconstructions successives.

L'avertissement restant est un faux positif. Lynis ne trouve pas de dépôt de sécurité, alors qu'il est bien configuré (`trixie-security`), mais au format `.sources` que cette version de Lynis ne lit pas.

Des suggestions restantes ont été écartées volontairement :
- **Changer le port SSH** : cela cache le service sans le protéger.
- **Mot de passe GRUB** : la console de la VM n'est accessible que depuis l'hôte.
- **Partitions séparées pour `/home` et `/var`** : l'image cloud n'a qu'une partition.
- **HTTPS sur nginx** : la page d'état n'est joignable que depuis l'hôte.
- **Journalisation vers une machine distante** : il n'y a pas de serveur de logs dans ce labo.
- **`kernel.modules_disabled = 1`** : plus aucun module ne pourrait se charger, ce qui casserait nftables dès que les règles évoluent.
- **apt-listbugs** : il pose des questions pendant les installations, ce qui bloquerait les mises à jour automatiques.
- **Antivirus et contrôle d'intégrité (rkhunter, AIDE)** : ce serait la prochaine étape.

## Durées mesurées

Reconstructions complètes de la version durcie (destruction, création, configuration et 22 tests), sur un i7-11800H :

| Essai | 1 | 2 | 3 |
|---|---|---|---|
| Durée | 2 min 30 | 2 min 07 | 1 min 38 |

La première version, sans durcissement, prenait de 0 min 39 à 1 min 36 sur cinq essais. L'écart vient surtout du téléchargement des paquets Debian.

## Problèmes rencontrés

- **Démarrage en boucle juste après GRUB.** En BIOS (SeaBIOS), la VM redémarrait sans fin. Elle démarre normalement en UEFI, d'où le `--boot uefi`.
- **`Storage volume not found`.** libvirt ne voit pas un fichier ajouté à un pool tant que celui-ci n'a pas été rafraîchi, d'où le `virsh pool-refresh`.
- **Connexion SSH coupée pendant le déploiement.** cloud-init redémarre sshd à la fin de la configuration, alors le script réessaie.
- **Image de base effacée.** `virsh undefine --remove-all-storage` supprime tous les disques rattachés à la VM, pas seulement le sien. Il a effacé l'image Debian. `destroy.sh` ne supprime plus que le disque qu'il a créé, désigné par son nom.
- **Correctifs sans effet.** Debian 13 n'a plus de ligne `UMASK` dans `login.defs`, donc le `sed` ne changeait rien : il faut l'ajouter. Et Lynis ne reconnaît une bannière que si elle contient certains mots-clés en anglais, d'où la bannière bilingue.

## Arborescence

```
cloud-init/user-data.yaml   configuration appliquée au premier démarrage
config.sh                   paramètres de la VM
scripts/                    deploy, test, destroy, rebuild, audit
docs/                       site de présentation (GitHub Pages)
```
