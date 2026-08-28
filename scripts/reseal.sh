#!/usr/bin/env bash
# Erzeugt/aktualisiert die SealedSecrets dieses Repos.
#
#   ./scripts/reseal.sh wave1     Authentik, Qdrant, LiteLLM, MLflow, GHCR
#   ./scripts/reseal.sh wave2     Langfuse, Open WebUI, Grafana  (braucht Authentik-OIDC-Daten)
#   ./scripts/reseal.sh wave3     SDLC Pilot                     (braucht Langfuse-API-Keys)
#   ./scripts/reseal.sh show      zeigt, welche Werte bekannt sind (ohne die Werte selbst)
#
# Klartext-Werte liegen ausschliesslich lokal in $LAB_SECRETS_FILE (chmod 600),
# niemals im Repo. Die erzeugten *-sealed-secret.yaml sind verschluesselt und
# duerfen committet werden.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES="${LAB_SECRETS_FILE:-$HOME/.lab-secrets.env}"
CONTROLLER_NS="${CONTROLLER_NS:-kube-system}"
CONTROLLER_NAME="${CONTROLLER_NAME:-sealed-secrets-controller}"
GHCR_USER="${GHCR_USER:-aymenmastouri}"

command -v kubeseal >/dev/null || { echo "kubeseal fehlt"; exit 1; }
command -v kubectl  >/dev/null || { echo "kubectl fehlt";  exit 1; }

touch "$VALUES"; chmod 600 "$VALUES"
# shellcheck disable=SC1090
source "$VALUES"

gen() { openssl rand -base64 64 | tr -dc 'A-Za-z0-9' | head -c "${1:-40}"; }

save() {
  local k=$1 v=$2
  [[ -s "$VALUES" ]] && sed -i "\|^export ${k}=|d" "$VALUES"
  printf 'export %s=%q\n' "$k" "$v" >> "$VALUES"
  export "${k}=${v}"
}

# ensure_gen KEY [laenge] - wuerfelt einen Wert, falls noch keiner existiert
ensure_gen() {
  local k=$1
  if [[ -z "${!k:-}" ]]; then save "$k" "$(gen "${2:-40}")"; echo "   generiert  $k"
  else echo "   vorhanden  $k"; fi
}

# ensure_ask KEY "Beschreibung" [default] - fragt still nach (kein Echo)
ensure_ask() {
  local k=$1 desc=$2 def=${3:-} v=
  if [[ -n "${!k:-}" ]]; then echo "   vorhanden  $k"; return; fi
  if [[ -n "$def" ]]; then
    printf '   %s [%s]: ' "$desc" "$def"; read -r v; v=${v:-$def}
  else
    printf '   %s: ' "$desc"; read -rs v; echo
  fi
  [[ -z "$v" ]] && { echo "   -> leer, abgebrochen"; exit 1; }
  save "$k" "$v"; echo "   gesetzt    $k"
}

# seal NAME NAMESPACE ZIELDATEI KEY...
seal() {
  local name=$1 ns=$2 out=$3; shift 3
  local args=() k
  for k in "$@"; do
    [[ -z "${!k:-}" ]] && { echo "   !! $k fehlt, $out uebersprungen"; return; }
    args+=( "--from-literal=${k}=${!k}" )
  done
  mkdir -p "$(dirname "$REPO/$out")"
  kubectl create secret generic "$name" -n "$ns" "${args[@]}" --dry-run=client -o yaml \
    | kubeseal --controller-namespace "$CONTROLLER_NS" \
               --controller-name "$CONTROLLER_NAME" --format yaml > "$REPO/$out"
  echo "   versiegelt $out"
}

wave1() {
  echo "== Authentik =="
  ensure_gen AUTHENTIK_SECRET_KEY 50
  ensure_gen AUTHENTIK_BOOTSTRAP_PASSWORD 24
  ensure_gen AUTHENTIK_BOOTSTRAP_TOKEN 40
  ensure_gen AUTHENTIK_OUTPOST_TOKEN 40
  ensure_gen POSTGRES_PASSWORD 32
  seal authentik-secrets apps apps/authentik/sealed-secret.yaml \
       AUTHENTIK_BOOTSTRAP_PASSWORD AUTHENTIK_BOOTSTRAP_TOKEN \
       AUTHENTIK_OUTPOST_TOKEN AUTHENTIK_SECRET_KEY POSTGRES_PASSWORD

  echo "== Qdrant =="
  ensure_gen QDRANT_API_KEY 40           # geteilt mit Open WebUI + SDLC Pilot
  QDRANT__SERVICE__API_KEY="$QDRANT_API_KEY"; export QDRANT__SERVICE__API_KEY
  seal qdrant-secrets apps apps/qdrant/sealed-secret.yaml QDRANT__SERVICE__API_KEY

  echo "== LiteLLM =="
  ensure_gen LITELLM_MASTER_KEY 40       # geteilt mit Open WebUI + SDLC Pilot
  ensure_gen LITELLM_UI_PASSWORD 24
  ensure_ask LITELLM_UI_USERNAME "Benutzername fuer die LiteLLM-Oberflaeche" "admin"
  # Nur fuer die HuggingFace-Cloud-Modelle noetig; lokale Ollama-Modelle laufen ohne.
  # Der Pod braucht aber einen Wert, sonst startet er nicht -> Platzhalter.
  if [[ -z "${HUGGINGFACE_API_KEY:-}" ]]; then
    printf '   HuggingFace API-Key (leer = Platzhalter, Cloud-Modelle dann inaktiv): '
    read -rs _hf; echo
    save HUGGINGFACE_API_KEY "${_hf:-hf-not-configured}"
    [[ -n "$_hf" ]] && echo "   gesetzt    HUGGINGFACE_API_KEY" \
                    || echo "   platzhalter HUGGINGFACE_API_KEY (spaeter nachtragbar)"
  else
    echo "   vorhanden  HUGGINGFACE_API_KEY"
  fi
  seal litellm-secrets apps apps/litellm/sealed-secret.yaml \
       HUGGINGFACE_API_KEY LITELLM_MASTER_KEY LITELLM_UI_PASSWORD LITELLM_UI_USERNAME

  echo "== MLflow =="
  ensure_gen MLFLOW_DB_PASSWORD 32
  seal mlflow-secrets apps apps/mlflow/sealed-secret.yaml MLFLOW_DB_PASSWORD

  echo "== GHCR Pull-Secret (nur fuer private Images noetig, z.B. ai-lab-portal) =="
  if [[ -z "${GHCR_TOKEN:-}" ]]; then
    printf '   GitHub-Token mit read:packages (leer lassen = ueberspringen): '
    read -rs _t; echo
    [[ -n "$_t" ]] && save GHCR_TOKEN "$_t"
  fi
  if [[ -n "${GHCR_TOKEN:-}" ]]; then
    kubectl create secret docker-registry ghcr-credentials -n apps \
        --docker-server=ghcr.io --docker-username="$GHCR_USER" \
        --docker-password="$GHCR_TOKEN" --dry-run=client -o yaml \
      | kubeseal --controller-namespace "$CONTROLLER_NS" \
                 --controller-name "$CONTROLLER_NAME" --format yaml \
        > "$REPO/infrastructure/sealed-secrets/ghcr-credentials.yaml"
    echo "   versiegelt infrastructure/sealed-secrets/ghcr-credentials.yaml"
  else
    echo "   uebersprungen - spaeter mit './scripts/reseal.sh wave1' nachholbar"
  fi
}

wave2() {
  echo "== Langfuse =="
  ensure_gen LANGFUSE_DB_PASSWORD 32
  ensure_gen LANGFUSE_NEXTAUTH_SECRET 40
  ensure_gen LANGFUSE_SALT 32
  ensure_ask LANGFUSE_OAUTH_CLIENT_ID     "Langfuse OIDC Client-ID aus Authentik"
  ensure_ask LANGFUSE_OAUTH_CLIENT_SECRET "Langfuse OIDC Client-Secret aus Authentik"
  seal langfuse-secrets apps apps/langfuse/sealed-secret.yaml \
       LANGFUSE_DB_PASSWORD LANGFUSE_NEXTAUTH_SECRET \
       LANGFUSE_OAUTH_CLIENT_ID LANGFUSE_OAUTH_CLIENT_SECRET LANGFUSE_SALT

  echo "== Open WebUI =="
  ensure_gen OPEN_WEBUI_SECRET_KEY 40
  ensure_ask OPENWEBUI_OAUTH_CLIENT_ID     "Open-WebUI OIDC Client-ID aus Authentik"
  ensure_ask OPENWEBUI_OAUTH_CLIENT_SECRET "Open-WebUI OIDC Client-Secret aus Authentik"
  seal open-webui-secrets apps apps/open-webui/sealed-secret.yaml \
       LITELLM_MASTER_KEY OPENWEBUI_OAUTH_CLIENT_ID OPENWEBUI_OAUTH_CLIENT_SECRET \
       OPEN_WEBUI_SECRET_KEY QDRANT_API_KEY

  echo "== Grafana OIDC =="
  ensure_ask GF_AUTH_GENERIC_OAUTH_CLIENT_ID     "Grafana OIDC Client-ID aus Authentik"
  ensure_ask GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET "Grafana OIDC Client-Secret aus Authentik"
  seal grafana-oidc monitoring infrastructure/monitoring/grafana-oidc-sealed-secret.yaml \
       GF_AUTH_GENERIC_OAUTH_CLIENT_ID GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET
}

wave3() {
  echo "== SDLC Pilot =="
  ensure_ask LANGFUSE_PUBLIC_KEY "Langfuse Public Key (pk-lf-...) aus der Langfuse-UI"
  ensure_ask LANGFUSE_SECRET_KEY "Langfuse Secret Key (sk-lf-...) aus der Langfuse-UI"
  LITELLM_API_KEY="${LITELLM_API_KEY:-$LITELLM_MASTER_KEY}"; export LITELLM_API_KEY
  seal sdlc-pilot-secrets apps apps/sdlc-pilot/sealed-secret.yaml \
       LANGFUSE_PUBLIC_KEY LANGFUSE_SECRET_KEY LITELLM_API_KEY QDRANT_API_KEY
}

show() {
  echo "Werte-Datei: $VALUES"
  echo "Bekannte Schluessel (Werte werden nicht angezeigt):"
  grep -oE '^export [A-Z_]+' "$VALUES" 2>/dev/null | awk '{print "   " $2}' || echo "   (noch keine)"
}

case "${1:-}" in
  wave1) wave1 ;;
  wave2) wave2 ;;
  wave3) wave3 ;;
  show)  show  ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac

echo
echo "Fertig. Die erzeugten Dateien sind verschluesselt und koennen committet werden:"
echo "  git -C $REPO status --short"
