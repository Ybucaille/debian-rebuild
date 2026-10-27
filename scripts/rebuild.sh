#!/usr/bin/env bash
# Détruit la VM, la recrée et la teste, en chronométrant chaque étape.
set -euo pipefail
cd "$(dirname "$0")/.."

step() {
  local label=$1; shift
  local start=$SECONDS
  "$@"
  echo ">> $label : $((SECONDS - start)) s"
  echo
}

total=$SECONDS
step "Destruction" scripts/destroy.sh
step "Déploiement" scripts/deploy.sh
step "Tests" scripts/test.sh
elapsed=$((SECONDS - total))
echo "Reconstruction complète et testée en $((elapsed / 60)) min $((elapsed % 60)) s."
