#!/usr/bin/env bash
# Audite la VM avec Lynis et affiche sa note de durcissement (sur 100).
# Le rapport complet est copié dans build/lynis-report.dat.
set -euo pipefail
cd "$(dirname "$0")/.."
source ./config.sh

echo "Audit Lynis en cours (une à deux minutes)..."
vm_sudo lynis audit system --quick --no-colors >/dev/null
vm_sudo cat /var/log/lynis-report.dat > "$BUILD_DIR/lynis-report.dat"

report=$BUILD_DIR/lynis-report.dat
score=$(grep '^hardening_index=' "$report" | cut -d= -f2)
version=$(grep '^lynis_version=' "$report" | cut -d= -f2)
echo
echo "Avertissements :"
grep '^warning\[\]=' "$report" | cut -d'|' -f1,2 | sed 's/^warning\[\]=/  /; s/|/ : /' || echo "  aucun"
echo
echo "Suggestions restantes : $(grep -c '^suggestion\[\]=' "$report")"
echo
echo "Note de durcissement Lynis $version : $score/100"
