# debian-rebuild

Un serveur Debian 13 durci, créé et configuré entièrement par script sous KVM/libvirt, puis vérifié par 15 tests. Une seule commande le détruit et le reconstruit à l'identique.

```
scripts/rebuild.sh
```

```
>> Destruction : 1 s
>> Déploiement : 82 s
>> Tests : 8 s
Reconstruction complète et testée en 1 min 31 s.
```

## Ce que fait le serveur

Tout est décrit dans [cloud-init/user-data.yaml](cloud-init/user-data.yaml) et appliqué au premier démarrage :

- **Accès** : un seul compte, `admin`, joignable uniquement par clé SSH. Root et les mots de passe sont refusés en SSH.
- **Pare-feu** : nftables en liste blanche. Tout ce qui entre est refusé, sauf SSH (22), HTTP (80), le ping et les réponses aux connexions sortantes.
- **fail2ban** : 3 échecs SSH en 10 minutes valent un bannissement d'une heure.
- **Mises à jour** : les mises à jour de sécurité s'installent automatiquement (unattended-upgrades).
- **Page d'état** : nginx sert une page qui indique la date de construction.

## Réseau

```
VM 192.168.122.40 ──► virbr0 192.168.122.1 ──► NAT de l'hôte ──► box ──► Internet
```

La VM est sur le réseau NAT `default` de libvirt. Une réservation DHCP associe sa MAC (`52:54:00:a1:00:40`) à l'IP `192.168.122.40`, qui reste la même à chaque reconstruction. La VM peut sortir sur Internet, mais seul l'hôte peut la joindre.

## Installation

### Prérequis

- Linux avec KVM et libvirt (`qemu:///system`, utilisateur dans le groupe `libvirt`) ;
- `virt-install` 4 ou plus ;
- le firmware UEFI OVMF.

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
```

Au premier lancement, `deploy.sh` génère une clé SSH dédiée au labo dans `build/`, un dossier ignoré par git. Si `~/.ssh/id_ed25519.pub` existe, cette clé est aussi autorisée sur la VM.

## Les scripts

| Script | Rôle |
|---|---|
| `scripts/deploy.sh` | Prépare le fichier cloud-init, ajoute la réservation DHCP si elle manque, crée un disque adossé à l'image Debian, lance la VM et attend la fin de cloud-init. |
| `scripts/test.sh` | Vérifie la configuration depuis l'hôte et depuis la VM. |
| `scripts/destroy.sh` | Supprime la VM et son disque, et uniquement eux. L'image de base n'est jamais touchée. |
| `scripts/rebuild.sh` | Enchaîne les trois et chronomètre chaque étape. |

Le disque de la VM est adossé à l'image de base : il n'enregistre que les différences. Reconstruire ne retélécharge donc pas l'image.

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
[OK]    nftables actif, politique d'entrée à drop
[OK]    HTTP (80) ouvert : la page d'état répond
[OK]    Port 8080 joignable depuis la VM elle-même
[OK]    Port 8080 bloqué depuis l'hôte par le pare-feu
[OK]    fail2ban surveille sshd
[OK]    Mises à jour de sécurité automatiques activées
[OK]    Aucune mise à jour en attente

15 tests réussis, 0 en échec.
```

Le test du port 8080 lance un petit serveur web dans la VM. Il répond en local, mais pas depuis l'hôte : c'est la preuve que le pare-feu filtre vraiment, et pas seulement qu'aucun service n'écoute.

Pour vérifier que les tests savent aussi échouer, j'ai vidé les règles nftables de la VM. Deux tests sont alors bien passés en échec : celui de la politique `drop` et celui du port 8080.

## Durées mesurées

Mes cinq premières reconstructions complètes (destruction, création, configuration et 15 tests), sur un i7-11800H :

| Lot | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| Durée | 1 min 31 | 1 min 03 | 1 min 03 | 0 min 39 | 1 min 36 |

L'écart vient surtout du téléchargement des paquets Debian.

## Problèmes rencontrés

- **Démarrage en boucle juste après GRUB.** En BIOS (SeaBIOS), la VM redémarrait sans fin. Elle démarre normalement en UEFI, d'où le `--boot uefi`.
- **`Storage volume not found`.** libvirt ne voit pas un fichier ajouté à un pool tant que celui-ci n'a pas été rafraîchi, d'où le `virsh pool-refresh`.
- **Connexion SSH coupée pendant le déploiement.** cloud-init redémarre sshd à la fin de la configuration, alors le script réessaie.
- **Image de base effacée.** `virsh undefine --remove-all-storage` supprime tous les disques rattachés à la VM, pas seulement le sien. Il a effacé l'image Debian. `destroy.sh` ne supprime plus que le disque qu'il a créé, désigné par son nom.

## Arborescence

```
cloud-init/user-data.yaml   configuration appliquée au premier démarrage
config.sh                   paramètres de la VM
scripts/                    deploy, test, destroy, rebuild
docs/                       site de présentation (GitHub Pages)
```
