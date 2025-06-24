#!/bin/bash

#===============================================================
# Fichier de fonctions d'erreur et de diagnostic pour sauvegarde.sh
# Auteur : enRIKO (modifié pour production et améliorations)
# Date : 2025-06-24
# Version : 1.3
#
# Changelog :
# - 1.3 (2025-06-24) :
#   - Ajout d'une clause par défaut pour les erreurs inconnues.
#   - Amélioration des messages de diagnostic pour plus de clarté.
#===============================================================

diagnostiquer_et_logger_erreur() {
    local message="$1"
    local exit_code="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="/var/log/sauvegarde_fallback_errors.log"

    echo "[$timestamp] [ERREUR] $message (Code: $exit_code)" >> "$log_file"
    case $exit_code in
        1) echo "[$timestamp] [DIAGNOSTIC] Erreur générale ou syntaxe incorrecte. Vérifiez les paramètres et la configuration." >> "$log_file" ;;
        3) echo "[$timestamp] [DIAGNOSTIC] Erreur rsync : problème de permissions ou fichier manquant. Vérifiez les accès." >> "$log_file" ;;
        11) echo "[$timestamp] [DIAGNOSTIC] Erreur rsync : répertoire source/destination inaccessible. Vérifiez les chemins." >> "$log_file" ;;
        23) echo "[$timestamp] [DIAGNOSTIC] Erreur rsync : transfert partiel (espace disque ou permissions). Vérifiez l'espace disponible." >> "$log_file" ;;
        255) echo "[$timestamp] [DIAGNOSTIC] Erreur SSH : connexion refusée ou clé invalide. Vérifiez les identifiants et la configuration SSH." >> "$log_file" ;;
        100) echo "[$timestamp] [DIAGNOSTIC] Erreur SSHFS : échec de montage. Vérifiez fusermount et les permissions." >> "$log_file" ;;
        *) echo "[$timestamp] [DIAGNOSTIC] Erreur inconnue (code: $exit_code). Consultez les logs pour plus de détails." >> "$log_file" ;;
    esac
}

gerer_erreur_fatale() {
    local message="$1"
    local exit_code="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="/var/log/sauvegarde_fallback_errors.log"

    echo "[$timestamp] [ERREUR FATALE] $message (Code: $exit_code)" >> "$log_file"
    echo "[$timestamp] [ERREUR FATALE] Arrêt du script." >> "$log_file"
    exit "$exit_code"
}
