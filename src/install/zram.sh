#!/bin/bash
# install/zram.sh — Optimisation RAM & protection SD pour RPi
#
# Montages RAM configurés :
#   /dev/shm       déjà tmpfs par défaut (50% RAM) — FIFOs Snapcast, WAV TTS, frames cam
#   zramswap       swap compressé (lz4 sur Zero 2W, zstd sur Pi 4)
#   log2ram        /var/log en RAM — protection SD critique
#   /tmp           tmpfs — écriture SD évitée
#   /var/tmp       tmpfs — écriture SD évitée
#
# Profils automatiques :
#   Pi Zero 2W / Pi 3 (≤ 1GB)  → lz4 25%,  log2ram 64M,  /tmp 64m
#   Pi 4 / Pi 5    (≥ 2GB)     → zstd 20%, log2ram 192M, /tmp 128m

setup_zram() {
    hdr "Optimisation RAM (ZRAM + log2ram + tmpfs)"

    # ── Détection hardware ────────────────────────────────────────
    local total_ram_mb
    total_ram_mb=$(awk '/MemTotal/{printf "%d", $2/1024}' /proc/meminfo)
    local pi_model
    pi_model=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo "inconnu")

    local zram_algo zram_pct log2ram_size tmp_size hw_label
    # Seuil 1500MB : Pi 4 2GB (≈1844MB visible après réservation GPU) détecté correctement
    if [ "$total_ram_mb" -ge 1500 ]; then
        # Pi 4 / Pi 5 ≥ 2GB : CPU disponible → zstd (meilleur ratio que lz4)
        zram_algo="zstd"
        zram_pct=20          # 20% de 1844MB = 368MB compressés → ~736MB swap effectif
        log2ram_size="192M"
        tmp_size="128m"
        hw_label="Pi 4/5 ≥ 2GB (${total_ram_mb}MB RAM)"
    elif [ "$total_ram_mb" -ge 700 ]; then
        # Pi 3 / Pi 4 1GB : lz4 rapide, RAM modérée
        zram_algo="lz4"
        zram_pct=20
        log2ram_size="96M"
        tmp_size="64m"
        hw_label="Pi 3 / Pi 4 1GB (${total_ram_mb}MB RAM)"
    else
        # Pi Zero 2W (≈491MB) : CPU limité → lz4 ultra-rapide, swap modeste
        zram_algo="lz4"
        zram_pct=20          # 20% de 491MB = 98MB compressés → ~196MB swap effectif
        log2ram_size="48M"
        tmp_size="48m"
        hw_label="Pi Zero 2W (${total_ram_mb}MB RAM)"
    fi

    log "Hardware : ${hw_label} — Modèle : ${pi_model}"
    log "ZRAM    : algo=${zram_algo}  swap=${zram_pct}% (~$((total_ram_mb * zram_pct / 100))MB)"
    log "log2ram : ${log2ram_size}  /tmp : ${tmp_size}"

    # ── Désactiver le swap SD (protège la carte micro-SD) ─────────
    dphys-swapfile swapoff 2>/dev/null || true
    systemctl disable --now dphys-swapfile 2>/dev/null || true

    # ── zramswap (format Bookworm : ALGO + PERCENT + PRIORITY) ────
    # Note : variables correctes pour zram-tools ≥ 0.5 (Bookworm)
    # ALGO (pas ALGORITHM), PERCENT (pas SIZE)
    cat > /etc/default/zramswap <<EOF
# SoundSpot — généré par setup_zram() — ne pas éditer manuellement
# Format zram-tools Bookworm : ALGO / PERCENT / PRIORITY
ALGO=${zram_algo}
PERCENT=${zram_pct}
PRIORITY=100
EOF

    # Si zram0 est déjà actif (swap en cours), il faut le libérer avant de reconfigurer.
    # `swapoff /dev/zram0` peut échouer si de la mémoire swap est en cours d'utilisation :
    # on ajoute temporairement RAM libre pour permettre le vidage.
    if swapon --show --noheadings 2>/dev/null | grep -q "/dev/zram"; then
        log "zram0 déjà actif — tentative de libération pour reconfiguration…"
        swapoff /dev/zram0 2>/dev/null || {
            warn "swapoff impossible (swap en cours d'usage) — la config sera appliquée au prochain reboot"
            log "zramswap : config écrite, actuelle conservée jusqu'au reboot ✓"
            return 0
        }
        systemctl stop zramswap 2>/dev/null || true
    fi

    if systemctl start zramswap 2>/dev/null; then
        log "zramswap actif : ${zram_algo}, ${zram_pct}% de ${total_ram_mb}MB ✓"
    else
        warn "zramswap.service a échoué — vérifier : journalctl -xeu zramswap"
        warn "Fallback : activation manuelle du device zram0"
        if [ -f /sys/block/zram0/comp_algorithm ]; then
            echo "${zram_algo}" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
            local zram_bytes=$(( total_ram_mb * 1024 * 1024 * zram_pct / 100 ))
            echo "${zram_bytes}" > /sys/block/zram0/disksize 2>/dev/null || true
            mkswap /dev/zram0 2>/dev/null && swapon -p 100 /dev/zram0 2>/dev/null \
                && log "zram0 activé manuellement ✓" \
                || warn "zram0 inaccessible — reboot requis pour appliquer la nouvelle config"
        fi
    fi

    # ── log2ram : /var/log en RAM (zéro écriture log sur SD) ──────
    if ! command -v log2ram &>/dev/null; then
        local keyring="/usr/share/keyrings/azlux-archive-keyring.gpg"
        if wget -qO "${keyring}" https://azlux.fr/repo.gpg 2>/dev/null; then
            echo "deb [signed-by=${keyring}] http://packages.azlux.fr/debian/ bookworm main" \
                > /etc/apt/sources.list.d/azlux.list
            apt-get update -qq 2>/dev/null && apt-get install -y -q log2ram 2>/dev/null \
                && log "log2ram installé ✓" || warn "log2ram non installé — logs sur SD"
        else
            warn "Impossible de télécharger la clé azlux — log2ram non installé"
        fi
    else
        log "log2ram déjà présent ✓"
    fi
    if command -v log2ram &>/dev/null; then
        sed -i \
            "s|^SIZE=.*|SIZE=${log2ram_size}|;s|^MAIL=true|MAIL=false|" \
            /etc/log2ram.conf 2>/dev/null || true
        log "log2ram configuré : SIZE=${log2ram_size} ✓"
    fi

    # ── tmpfs /tmp et /var/tmp (fstab idempotent) ─────────────────
    local fstab_changed=false

    if ! grep -qE "tmpfs[[:space:]]+/tmp[[:space:]]" /etc/fstab; then
        echo "tmpfs  /tmp      tmpfs  defaults,noatime,nosuid,nodev,mode=1777,size=${tmp_size}  0 0" \
            >> /etc/fstab
        fstab_changed=true
        log "/tmp tmpfs (${tmp_size}) ajouté au fstab ✓"
    else
        # Mettre à jour la taille si elle a changé
        sed -i "s|tmpfs[[:space:]]*/tmp[[:space:]].*|tmpfs  /tmp      tmpfs  defaults,noatime,nosuid,nodev,mode=1777,size=${tmp_size}  0 0|" \
            /etc/fstab
    fi

    if ! grep -qE "tmpfs[[:space:]]+/var/tmp[[:space:]]" /etc/fstab; then
        echo "tmpfs  /var/tmp  tmpfs  defaults,noatime,nosuid,nodev,mode=1777,size=32m         0 0" \
            >> /etc/fstab
        fstab_changed=true
        log "/var/tmp tmpfs (32m) ajouté au fstab ✓"
    fi

    # Monter immédiatement
    mount /tmp 2>/dev/null || true
    mount /var/tmp 2>/dev/null || true
    $fstab_changed && log "Nouveaux montages tmpfs actifs (persistent après reboot) ✓"

    # ── Récapitulatif final ────────────────────────────────────────
    log "─── Montages RAM actifs ───────────────────────────────"
    log "  /dev/shm  : $(df -h /dev/shm 2>/dev/null | awk 'NR==2{print $2}') (tmpfs système)"
    log "  /tmp      : $(df -h /tmp     2>/dev/null | awk 'NR==2{print $2}') (tmpfs)"
    log "  /var/tmp  : $(df -h /var/tmp 2>/dev/null | awk 'NR==2{print $2}') (tmpfs)"
    swapon --show 2>/dev/null | grep -q zram \
        && log "  zramswap  : $(swapon --show --noheadings 2>/dev/null | grep zram)" \
        || warn "  zramswap  : non actif"
    log "───────────────────────────────────────────────────────"
}
