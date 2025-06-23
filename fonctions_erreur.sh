#!/bin/bash
#
# Fichier de fonctions d'erreur et de diagnostic pour les scripts de sauvegarde.
# Auteur : enRIKO ^^ =)
# Date : 2025-06-23
# Version : 1.2 (Suppression des emojis, amélioration des messages)
# Description : Fournit des fonctions pour diagnostiquer et gérer les erreurs,
#               avec des messages clairs et sans formatage excessif pour un environnement de production.

# --- Chemin du fichier de log de fallback (si la fonction log_error n'est pas disponible) ---
# Ce fichier est utilisé uniquement si le script principal ne charge pas les fonctions de journalisation.
FALLBACK_ERROR_LOG="/var/log/sauvegarde_fallback_errors.log"

# --- Fonction de diagnostic d'erreur (NON-FATALE) ---
# Affiche un diagnostic détaillé pour une erreur donnée, mais ne quitte pas le script.
# Permet de logger une erreur et de continuer l'exécution (ex: passer à la sauvegarde suivante).
# Arguments : $1 = message de contexte, $2 = code de retour, $3 = sortie brute de la commande (optionnel)
diagnostiquer_et_logger_erreur() {
    local message_contexte="$1"
    local code_retour="$2"
    local sortie_brute="$3"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Utilise la fonction de log du script principal si elle existe
    if type -t log_error &> /dev/null; then
        log_error "$message_contexte (Code: $code_retour)"
    else
        # Fallback si la fonction de log n'est pas disponible
        echo "[$timestamp] [ERREUR] $message_contexte (Code: $code_retour)" >> "$FALLBACK_ERROR_LOG"
    fi

    echo "" >&2
    echo "------------------- Diagnostic d'Erreur (Non-Fatale) -------------------" >&2
    echo "Message : $message_contexte" >&2
    echo "Code d'erreur : $code_retour" >&2
    echo "" >&2

    local piste=""
    local action=""

    # Le même bloc 'case' ultra-détaillé pour le diagnostic
    case "$code_retour" in
        # Codes de retour Rsync (standards, du manuel rsync)
        1)  piste="Erreur de syntaxe Rsync ou problème général."; action="Vérifiez la syntaxe de la commande rsync et les chemins source/destination." ;;
        3)  piste="Erreurs sur la sélection de fichiers (permissions, chemin introuvable)."; action="Vérifiez les permissions de lecture/écriture et l'existence des chemins." ;;
        11) piste="Erreur d'E/S (Input/Output). Problème de lecture/écriture sur le disque."; action="Vérifiez l'intégrité et l'espace des disques (source et destination)." ;;
        12) piste="Erreur de protocole Rsync, souvent lié à SSH."; action="Assurez-vous que rsync est bien installé sur la machine distante et accessible par l'utilisateur SSH." ;;
        23) piste="Transfert partiel (espace disque insuffisant, permissions, connexion instable)."; action="C'est une erreur fréquente. Vérifiez l'espace disque destination et la stabilité du réseau." ;;
        24) piste="Fichier source disparu pendant le transfert."; action="Des fichiers ont été modifiés/supprimés à la source pendant la sauvegarde." ;;
        30) piste="Erreur de timeout Rsync."; action="Augmentez le timeout de rsync ou vérifiez la stabilité de la connexion réseau." ;;
        35) piste="Erreur inattendue de Rsync."; action="Consultez les logs détaillés de rsync pour plus d'informations." ;;
        # Codes de retour SSH/SSHFS (souvent liés à un code d'erreur SSH sous-jacent)
        255) piste="Erreur SSH. Problème de connexion, d'authentification ou configuration SSH."; action="Vérifiez la connectivité SSH, les clés SSH, et le fichier .ssh/config. Lancez ssh -v pour diagnostiquer." ;;
        # Codes de retour généraux (bash)
        126) piste="La commande invoquée n'est pas exécutable."; action="Vérifiez les permissions d'exécution du script ou de la commande." ;;
        127) piste="Commande introuvable."; action="Vérifiez que la commande est installée et dans le PATH." ;;
        # Codes de retour spécifiques au script de sauvegarde
        100) piste="Point de montage SSHFS non valide ou inaccessible."; action="Vérifiez le chemin du point de montage et ses permissions." ;;
        101) piste="Echec de création du répertoire de destination pour la sauvegarde."; action="Vérifiez les permissions d'écriture dans le dossier parent de la destination." ;;
        # Codes de retour FUSE/SSHFS
        1)  piste="Erreur générique de fusermount/SSHFS."; action="Vérifiez les logs de fusermount ou relancez manuellement le montage." ;;
        # Cas par défaut
        *)  piste="Code d'erreur non spécifié ou inconnu."; action="Activez le MODE_DEBOGAGE=1 dans le script principal pour une analyse détaillée." ;;
    esac

    echo "Piste : $piste" >&2
    echo "Action : $action" >&2

    if [[ -n "$sortie_brute" ]]; then
        echo "" >&2
        echo "--- Sortie d'erreur brute de la commande ---" >&2
        echo "$sortie_brute" >&2
        echo "------------------------------------------" >&2
    fi
    echo "----------------------------------------------------------------------" >&2
    echo "" >&2
}

# --- Fonction de detection de variables INVALIDE  --
validate_critical_vars() {
    local missing=0
    local vars=(UUID_DISQUE_SAUVEGARDE DEST_BASE_SAUVEGARDES DEFAULT_RSYNC_OPTIONS DEFAULT_TYPE_CONNEXION_DISTANTE DEFAULT_SELECTIONS_SAUVEGARDES MONTAGE_SSHFS_PHOTOS MONTAGE_SSHFS_IMAGES MONTAGE_SSHFS_MUSIQUES userVM ipVM portVM userPortable ipPortable portPortable pathPortable userServeur ipServeur portServeur)
    for var in "${vars[@]}"; do [ -z "${!var}" ] && { log_error "Erreur : $var non défini."; missing=1; }; done
    [ $missing -eq 1 ] && { log_error "ARRÊT du script à cause de variables manquantes."; exit 1; }
    log_info "Toutes les variables critiques sont correctement définies."
}

# --- Fonction de gestion des erreurs FATALES --
# Affiche un diagnostic puis quitte le script.
# À utiliser pour les erreurs qui rendent la poursuite de l'exécution impossible.
# Arguments : $1 = message d'erreur, $2 = code de retour (optionnel)
gerer_erreur_fatale() {
    local message_erreur="$1"
    local code_retour="${2:-$?}"

    # Appel à la fonction de diagnostic pour afficher les détails
    diagnostiquer_et_logger_erreur "$message_erreur" "$code_retour"

    echo "" >&2
    echo "======================================================================" >&2
    echo "           ERREUR FATALE - ARRÊT DU SCRIPT" >&2
    echo "======================================================================" >&2
    echo "" >&2

    exit "$code_retour"
}
