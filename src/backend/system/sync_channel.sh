#!/bin/bash
# sync_channel.sh — Met à jour le canal hostapd au démarrage.
# En Mono-WiFi (uap0) : copie le canal de wlan0.
# En Dual-WiFi (wlan1) : scanne et choisit le meilleur canal (1, 6, 11).

source /opt/soundspot/soundspot.conf 2>/dev/null || true
IFACE_AP="${IFACE_AP:-uap0}"
IFACE_WAN="${IFACE_WAN:-wlan0}"

log() { echo "[sync_channel] $*"; }

# Attendre que wlan0 soit associé au réseau amont (max 60 s)
for i in $(seq 1 30); do
    iwgetid "$IFACE_WAN" --raw 2>/dev/null | grep -q . && break
    sleep 2
done

# Lire le canal courant du réseau amont
UPSTREAM_CHAN=$(iw dev "$IFACE_WAN" info 2>/dev/null | awk '/channel/{print $2; exit}')
UPSTREAM_CHAN=$(echo "$UPSTREAM_CHAN" | tr -d '[:space:]')

if [ -z "$UPSTREAM_CHAN" ]; then
    log "Canal réseau amont non détecté — hostapd.conf inchangé"
    exit 0
fi

BEST_CHAN="$UPSTREAM_CHAN"

if [ "$IFACE_AP" != "uap0" ]; then
    log "Mode Dual-WiFi : Recherche du meilleur canal au démarrage..."
    
    # Scan des réseaux existants
    SCAN_RAW=$(iw "$IFACE_WAN" scan dump 2>/dev/null | grep "primary channel" | awk '{print $4}' || true)
    if [ -z "$SCAN_RAW" ]; then
        SCAN_RAW=$(iw "$IFACE_WAN" scan 2>/dev/null | grep "primary channel" | awk '{print $4}' || true)
    fi
    
    BEST_CHAN=1
    [ "$UPSTREAM_CHAN" == "1" ] && BEST_CHAN=6
    
    # Sécurité : Si le scan a échoué ou qu'il n'y a aucun réseau
    if [ -z "$SCAN_RAW" ] || [ "$SCAN_RAW" = " " ]; then
        log "Aucun réseau détecté (zone blanche ou carte occupée). Canal de repli : CH${BEST_CHAN}"
    else
        MIN_RESEAUX=999
        for CH in 1 6 11; do
            # On ignore le canal utilisé par la connexion Internet (pour éviter l'auto-brouillage)
            if [ "$CH" != "$UPSTREAM_CHAN" ]; then

                COUNT=$(grep -cw "$CH" <<< "$SCAN_RAW" || echo 0)
                
                if [ "$COUNT" -lt "$MIN_RESEAUX" ]; then
                    MIN_RESEAUX=$COUNT
                    BEST_CHAN=$CH
                fi
            fi
        done
        log "Meilleur canal dégagé trouvé : CH${BEST_CHAN} (Réseau amont sur CH${UPSTREAM_CHAN})"
    fi
else
    log "Mode Mono-WiFi : Canal AP forcé sur CH${BEST_CHAN} pour suivre ${IFACE_WAN}"
fi

CURRENT=$(grep "^channel=" /etc/hostapd/hostapd.conf 2>/dev/null | cut -d= -f2)

if [ "$BEST_CHAN" = "$CURRENT" ]; then
    log "Canal ${BEST_CHAN} déjà correct — aucun changement"
    exit 0
fi

log "Mise à jour hostapd.conf : ${CURRENT:-?} → ${BEST_CHAN}"
sed -i "s/^channel=.*/channel=${BEST_CHAN}/" /etc/hostapd/hostapd.conf