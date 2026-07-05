#!/bin/bash
# api/core/eye.sh — Dernière photo capturée par mon-oeil.py (+ lien IPFS)
#
# GET /api.sh?action=eye
# Réponse : {"caption":"...","ipfs_url":"...","ipfs_cid":"...","ts":1730000000.0}
# ipfs_url/ipfs_cid valent null tant qu'aucune photo n'a encore été publiée.

EYE_LAST="/dev/shm/eye_last.json"

if [ -s "$EYE_LAST" ]; then
    cat "$EYE_LAST"
else
    printf '{"caption":null,"ipfs_url":null,"ipfs_cid":null,"ts":0}\n'
fi
