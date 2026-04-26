#!/bin/bash

# Script d'analyse de la consommation mémoire et des fichiers ouverts par IPFS

# 1. Trouver les PIDs des processus IPFS
PIDS=$(pgrep -f ipfs)

if [ -z "$PIDS" ]; then
    echo "Aucun processus IPFS trouvé."
    exit 1
fi

echo "PIDs des processus IPFS : $PIDS"
echo "----------------------------------------"

# 2. Consommation mémoire pour chaque PID
echo "Consommation mémoire des processus IPFS :"
MEM_TOTAL_KB=0
for PID in $PIDS; do
    echo "PID $PID :"
    ps -p $PID -o %mem,rss,cmd --no-headers
    MEM_KB=$(ps -p $PID -o rss=)
    MEM_TOTAL_KB=$((MEM_TOTAL_KB + MEM_KB))
done

MEM_TOTAL_MB=$(echo "scale=2; $MEM_TOTAL_KB / 1024" | bc)
echo "Mémoire totale utilisée par tous les processus IPFS : $MEM_TOTAL_MB Mo"
echo "----------------------------------------"

# 3. Nombre de fichiers ouverts pour chaque PID
for PID in $PIDS; do
    NB_FICHIERS=$(ls -l /proc/$PID/fd 2>/dev/null | wc -l)
    if [ -n "$NB_FICHIERS" ]; then
        echo "Nombre de fichiers ouverts par le processus IPFS (PID $PID) : $NB_FICHIERS"
    else
        echo "Impossible d'accéder aux fichiers ouverts pour le PID $PID (droits insuffisants ou processus introuvable)."
    fi
done
echo "----------------------------------------"
