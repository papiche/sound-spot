#!/bin/bash
# Script matériel d'impression pour la Brother QL-700
# Lancé par www-data (via sudo)

SOUNDSPOT_USER=$(grep "SOUNDSPOT_USER" /opt/soundspot/soundspot.conf 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "pi")
USER_HOME=$(getent passwd "$SOUNDSPOT_USER" | cut -d: -f6)

IMG_IN="$USER_HOME/.zen/Astroport.ONE/images/QR.png"
BIN_OUT="$USER_HOME/.zen/tmp/toprint.bin"

# 1. Vérification de l'image source
if [ ! -f "$IMG_IN" ]; then
    echo "Erreur: Image $IMG_IN introuvable !" >&2
    exit 1
fi

# 2. Détection du port de l'imprimante (USB)
# Souvent /dev/usb/lp0 sous Linux pour les imprimantes
LP=$(ls /dev/usb/lp* 2>/dev/null | head -n 1)
if [ -z "$LP" ]; then
    # Fallback sur l'adresse USB raw si lp0 n'est pas monté
    LP="usb://0x04f9:0x2042" 
fi

# 3. Traitement et Impression (On utilise le chemin absolu des exécutables python)
# Si tu les as installés via `pip install brother_ql`, ils sont dans ~/.local/bin ou /usr/local/bin
BROTHER_CREATE="$USER_HOME/.astro/bin/brother_ql_create"
BROTHER_PRINT="$USER_HOME/.astro/bin/brother_ql_print"

if[ -z "$BROTHER_CREATE" ] || [ -z "$BROTHER_PRINT" ]; then
    echo "Erreur: Utilitaires brother_ql introuvables." >&2
    exit 1
fi

# Conversion de l'image en données binaires Brother
$BROTHER_CREATE --model QL-700 --label-size 62 "$IMG_IN" > "$BIN_OUT" 2>/dev/null

# Envoi à l'imprimante (avec droits root pour l'accès /dev/usb)
$BROTHER_PRINT "$BIN_OUT" "$LP"