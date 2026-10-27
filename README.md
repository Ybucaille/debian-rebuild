# debian-rebuild

Un serveur Debian 13 durci, créé et configuré entièrement par script sous KVM/libvirt, puis vérifié par une batterie de tests. On peut le détruire et le reconstruire à l'identique en une commande.

Présentation : https://ybucaille.github.io/debian-rebuild/

```
scripts/rebuild.sh
```

Sur ma machine (i7-11800H), une reconstruction complète (destruction, création, configuration, 15 tests) prend entre 1 min 03 s et 1 min 31 s : c'est l'écart entre mes trois premiers essais. La durée dépend surtout du téléchargement des paquets.

## Ce que fait le serveur

Tout est décrit dans [cloud-init/user-data.yaml](cloud-init/user-data.yaml), appliqué au premier démarrage :

- un seul compte, `admin`, accessible uniquement par clé SSH ; root et les mots de passe sont refusés en SSH ;
- un pare-feu nftables en liste blanche : tout ce qui entre est refusé, sauf SSH (22), HTTP (80), le ping et les réponses aux connexions sortantes ;
- fail2ban sur SSH : 3 échecs en 10 minutes donnent un bannissement d'une heure ;
- les mises à jour de sécurité automatiques (unattended-upgrades) ;
- nginx, qui sert une page d'état indiquant la date de construction.

## Réseau

```
VM 192.168.122.40 ──► virbr0 192.168.122.1 ──► NAT de l'hôte ──► box ──► Internet
```

La VM est sur le réseau NAT `default` de libvirt. Une réservation DHCP associe sa MAC (`52:54:00:a1:00:40`) à l'IP `192.168.122.40`. Elle peut sortir sur Internet, mais seul l'hôte peut la joindre.

## Les scripts

| Script | Rôle |
|---|---|
| `scripts/deploy.sh` | Génère la clé SSH du labo, prépare le fichier cloud-init, ajoute la réservation DHCP si elle manque, crée un disque adossé à l'image Debian, lance la VM et attend la fin de cloud-init. |
| `scripts/test.sh` | Vérifie la configuration depuis l'hôte et depuis la VM (voir ci-dessous). |
| `scripts/destroy.sh` | Supprime la VM et son disque. L'image de base n'est pas touchée. |
| `scripts/rebuild.sh` | Enchaîne les trois et chronomètre chaque étape. |

Les paramètres (nom, MAC, IP, mémoire, image) sont dans [config.sh](config.sh).

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

Le test du port 8080 lance un petit serveur web dans la VM : il répond en local, mais pas depuis l'hôte. C'est la preuve que le pare-feu filtre vraiment, et pas seulement qu'aucun service n'écoute. Quand on vide les règles nftables de la VM, ce test et celui de la politique `drop` passent bien en échec.

## Prérequis

- Linux avec KVM, libvirt (`qemu:///system`, utilisateur dans le groupe `libvirt`), `virt-install` 4 ou plus, firmware OVMF ;
- l'image officielle [debian-13-genericcloud-amd64.qcow2](https://cloud.debian.org/images/cloud/trixie/latest/), vérifiée avec `SHA512SUMS`, placée dans un pool libvirt (ici `~/Documents/autres/iso`, pool `iso`).

## Problèmes rencontrés

- **Démarrage en boucle juste après GRUB.** En BIOS (SeaBIOS), la VM redémarrait sans fin. Elle démarre normalement en UEFI : d'où le `--boot uefi`.
- **`Storage volume not found`.** Libvirt ne voit pas un fichier ajouté à un pool tant que celui-ci n'a pas été rafraîchi : d'où le `virsh pool-refresh`.
- **Connexion SSH coupée pendant le déploiement.** cloud-init redémarre sshd à la fin de la configuration, alors le script réessaie.
