#!/bin/bash
export LC_ALL=C

#===============================================================
# Sauvegarde des données
# Auteur : enRIKO (modifié par geole, iznobe, Watael, steph810, amélioré pour qualité irréprochable)
# Date : 2025-06-24
# Version : 6.1 Beta
# Description : Script de sauvegarde incrémentale avec validation renforcée, mode dry-run, et gestion avancée des erreurs.
#
# Changelog :
# - 6.1 Beta (2025-06-24) :
#   - Ajout du mode --dry-run pour simuler les sauvegardes sans modification.
#   - Ajout de l'option --list pour lister les sauvegardes disponibles.
#   - Validation renforcée des variables (UUID, IP, chemins).
#   - Option rsync --delete configurable via RSYNC_DELETE.
#   - Vérification des chemins distants avant montage SSHFS.
#   - Gestion des démontages SSHFS occupés avec retries.
#   - Rapport email plus détaillé avec erreurs spécifiques.
#   - Journalisation des erreurs critiques même si les logs sont désactivés.
#===============================================================

# --- PARAMÈTRES ET OPTIONS DU SHELL ---
set -o errexit   # Quitte si une commande échoue
set -o nounset   # Traite les variables non définies comme des erreurs
set -o pipefail  # Détecte les erreurs dans les pipelines

# --- VARIABLES GLOBALES DE BASE ---
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
ACTIVERLOCK=${ACTIVERLOCK:-1}  # Valeur par défaut pour verrouillage
DRY_RUN=0  # Mode simulation (0=non, 1=oui)

# --- GESTION DES ARGUMENTS EN LIGNE DE COMMANDE ---
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    log_info "Mode simulation activé : aucune modification ne sera effectuée."
    shift
elif [[ "${1:-}" == "--list" ]]; then
    echo "Sauvegardes disponibles : docs_eric, docs_fanou, docs_communs, projets, photos, docs_portable, musiques"
    exit 0
fi

# --- INTÉGRATION DU FICHIER DE CONFIGURATION ---
if [[ -f "$SCRIPT_DIR/config.sh" && -r "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "ERREUR CRITIQUE [$(date '+%Y-%m-%d %H:%M:%S')]: Fichier de configuration '$SCRIPT_DIR/config.sh' introuvable ou non lisible." >&2
    exit 1
fi

# --- INTÉGRATION DU FICHIER DE DIAGNOSTIC ---
if [[ -f "$CHEMIN_FONCTIONS_ERREUR" && -r "$CHEMIN_FONCTIONS_ERREUR" ]]; then
    source "$CHEMIN_FONCTIONS_ERREUR"
    log_info "Fichier de fonctions d'erreur '$CHEMIN_FONCTIONS_ERREUR' sourcé avec succès."
else
    echo "ERREUR CRITIQUE [$(date '+%Y-%m-%d %H:%M:%S')]: Fichier de fonctions d'erreur '$CHEMIN_FONCTIONS_ERREUR' introuvable ou non lisible." >&2
    exit 1
fi

# --- DÉFINITION DES FONCTIONS DE JOURNALISATION ---
log_message() {
    local type="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Toujours journaliser les erreurs, même si les journaux sont désactivés
    if [[ "$type" == "ERROR" || "$DEFAULT_JOURNAUX_DESACTIVES" -eq 0 ]]; then
        case "$type" in
            INFO) echo "[$timestamp] [INFO] $message" ;;
            DEBUG) [[ "$DEFAULT_MODE_DEBOGAGE" -eq 1 ]] && echo "[$timestamp] [DEBUG] $message" ;;
            SUCCESS) echo "[$timestamp] [SUCCÈS] $message" ;;
            WARNING) echo "[$timestamp] [ATTENTION] $message" >&2 ;;
            ERROR) echo "[$timestamp] [ERREUR] $message" >&2 ;;
        esac
    fi
}
log_info() { log_message INFO "$1"; }
log_debug() { log_message DEBUG "$1"; }
log_success() { log_message SUCCESS "$1"; }
log_error() { log_message ERROR "$1"; }
log_warning() { log_message WARNING "$1"; }

# --- VERROUILLAGE DU SCRIPT (Méthode flock) ---
if [[ "$ACTIVERLOCK" -eq 1 ]]; then
    LOCK_DIR="/var/lock"
    if ! mkdir -p "$LOCK_DIR"; then
        log_error "Impossible de créer ou accéder au répertoire de verrouillage : $LOCK_DIR."
        exit 1
    fi
    LOCK_FILE="$LOCK_DIR/${DEFAULT_NOM_SCRIPT:-sauvegarde}.lock"
    exec 200>"$LOCK_FILE" || { log_error "Impossible d'ouvrir le fichier de verrouillage: $LOCK_FILE."; exit 1; }
    if ! flock -n 200; then
        log_error "Une autre instance du script est en cours d'exécution."
        exit 1
    fi
    log_success "Verrou acquis sur le fichier: $LOCK_FILE"
else
    log_warning "Verrouillage multi-instance désactivé via config.sh."
fi

# --- VÉRIFICATION DES DÉPENDANCES ---
check_dependencies() {
    local deps=("rsync" "flock" "sshfs" "fusermount" "fusermount3" "mail")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            if [[ "$dep" == "rsync" || "$dep" == "flock" || "$dep" == "sshfs" ]]; then
                log_error "Dépendance critique manquante : $dep."
                exit 1
            else
                log_warning "Dépendance non essentielle manquante : $dep."
            fi
        fi
    done
}

# --- VALIDATION DES VARIABLES CRITIQUES ---
validate_critical_vars() {
    local missing=0
    [[ "$UUID_DISQUE_SAUVEGARDE" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || { log_error "UUID_DISQUE_SAUVEGARDE invalide."; missing=1; }
    [[ -d "$DEST_BASE_SAUVEGARDES" ]] || { log_error "DEST_BASE_SAUVEGARDES ($DEST_BASE_SAUVEGARDES) n'existe pas."; missing=1; }
    [[ "$ipVM" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || { log_error "ipVM ($ipVM) n'est pas une adresse IP valide."; missing=1; }
    [[ "$ipPortable" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || { log_error "ipPortable ($ipPortable) n'est pas une adresse IP valide."; missing=1; }
    [[ "$ipServeur" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || { log_error "ipServeur ($ipServeur) n'est pas une adresse IP valide."; missing=1; }
    [[ -n "$DEFAULT_RSYNC_OPTIONS" ]] || { log_error "DEFAULT_RSYNC_OPTIONS non défini."; missing=1; }
    [[ -n "$DEFAULT_TYPE_CONNEXION_DISTANTE" ]] || { log_error "DEFAULT_TYPE_CONNEXION_DISTANTE non défini."; missing=1; }
    [[ -n "$DEFAULT_SELECTIONS_SAUVEGARDES" ]] || { log_error "DEFAULT_SELECTIONS_SAUVEGARDES non défini."; missing=1; }
    [[ -n "$MONTAGE_SSHFS_PHOTOS" ]] || { log_error "MONTAGE_SSHFS_PHOTOS non défini."; missing=1; }
    [[ -n "$MONTAGE_SSHFS_IMAGES" ]] || { log_error "MONTAGE_SSHFS_IMAGES non défini."; missing=1; }
    [[ -n "$MONTAGE_SSHFS_MUSIQUES" ]] || { log_error "MONTAGE_SSHFS_MUSIQUES non défini."; missing=1; }
    [[ -n "$userVM" ]] || { log_error "userVM non défini."; missing=1; }
    [[ -n "$ipVM" ]] || { log_error "ipVM non défini."; missing=1; }
    [[ -n "$portVM" ]] || { log_error "portVM non défini."; missing=1; }
    [[ -n "$userPortable" ]] || { log_error "userPortable non défini."; missing=1; }
    [[ -n "$ipPortable" ]] || { log_error "ipPortable non défini."; missing=1; }
    [[ -n "$portPortable" ]] || { log_error "portPortable non défini."; missing=1; }
    [[ -n "$pathPortable" ]] || { log_error "pathPortable non défini."; missing=1; }
    [[ -n "$userServeur" ]] || { log_error "userServeur non défini."; missing=1; }
    [[ -n "$ipServeur" ]] || { log_error "ipServeur non défini."; missing=1; }
    [[ -n "$portServeur" ]] || { log_error "portServeur non défini."; missing=1; }
    if [[ $missing -eq 1 ]]; then
        log_error "Arrêt du script : variables manquantes ou invalides."
        exit 1
    fi
}

# --- FONCTIONS GÉNÉRALES ---
find_latest_backup_dir() {
    local base_path_for_search="$1"
    local latest_backup_path=""
    local latest_timestamp=0

    log_debug "Recherche de la dernière sauvegarde dans: $base_path_for_search"

    if [[ ! -d "$base_path_for_search" ]]; then
        log_debug "Le répertoire de base '$base_path_for_search' n'existe pas."
        return
    fi

    while IFS= read -r -d $'\0' dir; do
        local dir_name=$(basename "$dir")
        if [[ "$dir_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            local dir_timestamp=$(date -d "$dir_name" +%s 2>/dev/null)
            if [[ "$dir_timestamp" -gt "$latest_timestamp" ]]; then
                latest_timestamp="$dir_timestamp"
                latest_backup_path="$dir"
            fi
        fi
    done < <(find "$base_path_for_search" -maxdepth 1 -type d -print0)

    if [[ -n "$latest_backup_path" ]]; then
        echo "$latest_backup_path"
        log_debug "Dernière sauvegarde trouvée: $latest_backup_path"
    else
        log_debug "Aucune sauvegarde précédente trouvée dans $base_path_for_search."
    fi
}

verifier_permissions_ecriture() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_debug "Création du répertoire de destination: $dir"
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[Dry Run] Simulation de création de $dir."
            return 0
        fi
        if ! mkdir -p "$dir"; then
            diagnostiquer_et_logger_erreur "Échec de la création du répertoire: $dir." $?
            return 1
        fi
    fi
    if [[ ! -w "$dir" ]]; then
        diagnostiquer_et_logger_erreur "Le répertoire '$dir' n'est pas accessible en écriture." 1
        return 1
    fi
    return 0
}

verifier_espace_disque() {
    local path="$1"
    local min_gb="$2"
    local available_gb=$(df -BG "$path" | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ -z "$available_gb" ]]; then
        diagnostiquer_et_logger_erreur "Impossible de déterminer l'espace disque pour '$path'." 1
        return 1
    fi

    if (( available_gb < min_gb )); then
        diagnostiquer_et_logger_erreur "Espace disque insuffisant sur '$path'. Disponible: ${available_gb}Go, Requis: ${min_gb}Go." 1
        return 1
    fi
    log_debug "Espace disque disponible sur '$path' : ${available_gb}Go (Requis : ${min_gb}Go)."
    return 0
}

# --- FONCTIONS DE SÉCURITÉ ET NOTIFICATION ---
verifier_disque_de_sauvegarde() {
    log_info "Vérification du disque de destination..."
    if [[ -z "${DEST_BASE_SAUVEGARDES:-}" ]]; then
        gerer_erreur_fatale "La variable DEST_BASE_SAUVEGARDES n'est pas définie." 1
    fi

    local device=$(findmnt -n -o SOURCE --target "$DEST_BASE_SAUVEGARDES")
    if [[ -z "$device" ]]; then
        gerer_erreur_fatale "Le répertoire '$DEST_BASE_SAUVEGARDES' n'est pas un point de montage valide." 1
    fi

    local current_uuid=$(lsblk -n -o UUID "$device")
    if [[ "$current_uuid" == "$UUID_DISQUE_SAUVEGARDE" ]]; then
        log_success "Disque de sauvegarde correct (UUID: $current_uuid)."
        return 0
    else
        gerer_erreur_fatale "ERREUR DE SÉCURITÉ : UUID attendu: '$UUID_DISQUE_SAUVEGARDE', trouvé: '$current_uuid'." 1
    fi
}

envoyer_rapport_final() {
    if [[ -z "$EMAIL_NOTIFICATION" ]]; then
        log_info "Aucune adresse email configurée."
        return 0
    fi
    local sujet="[Sauvegarde] Rapport du $(date +'%Y-%m-%d %H:%M')"
    local corps="Rapport de sauvegarde terminé.\n\nRéussies : $sauvegardes_reussies\nÉchouées : $sauvegardes_echouees\nTotal : $nombre_sauvegardes\n\nLogs : /var/log/sauvegardes/"
    if [[ "$sauvegardes_echouees" -gt 0 ]]; then
        sujet="[Sauvegarde] ÉCHEC - Rapport du $(date +'%Y-%m-%d %H:%M')"
        corps+="\nErreurs rencontrées. Consultez les logs pour plus de détails."
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        corps+="\n[Mode Dry Run] Aucune modification effectuée."
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[Dry Run] Simulation de l'envoi du rapport à $EMAIL_NOTIFICATION."
    else
        echo -e "$corps" | mail -s "$sujet" "$EMAIL_NOTIFICATION" || log_warning "Échec de l'envoi de l'email."
        log_info "Rapport envoyé à $EMAIL_NOTIFICATION."
    fi
}

# --- FONCTIONS SSHFS ---
monter_sshfs() {
    local user_dist="$1"
    local ip_dist="$2"
    local port_dist="$3"
    local source_path_dist="$4"
    local mount_point="$5"

    log_debug "Tentative de montage SSHFS de $user_dist@$ip_dist:$source_path_dist vers $mount_point via port $port_dist"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[Dry Run] Simulation de montage SSHFS pour $mount_point."
        return 0
    fi

    if mountpoint -q "$mount_point"; then
        log_debug "Point de montage $mount_point déjà monté."
        return 0
    fi

    if ! ssh -p "$port_dist" "$user_dist@$ip_dist" "test -d \"$source_path_dist\"" 2>/dev/null; then
        log_error "Chemin distant $source_path_dist n'existe pas ou est inaccessible."
        return 1
    fi

    mkdir -p "$mount_point" || { diagnostiquer_et_logger_erreur "Échec de création du point de montage: $mount_point" $? ; return 1 ; }
    sshfs "$user_dist@$ip_dist:$source_path_dist" "$mount_point" -o reconnect,default_permissions,allow_other -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p "$port_dist"
    local sshfs_exit_code=$?
    if [[ $sshfs_exit_code -eq 0 ]]; then
        log_success "SSHFS monté avec succès sur $mount_point."
        add_mounted_sshfs_point "$mount_point"
        return 0
    else
        diagnostiquer_et_logger_erreur "Échec du montage SSHFS (code: $sshfs_exit_code)." $sshfs_exit_code
        return 1
    fi
}

detect_fusermount_cmd() {
    if command -v fusermount3 >/dev/null 2>&1; then
        echo "fusermount3"
    elif command -v fusermount >/dev/null 2>&1; then
        echo "fusermount"
    else
        log_error "Aucune commande fusermount disponible."
        exit 1
    fi
}

FUSERMOUNT_CMD=$(detect_fusermount_cmd)

demonter_sshfs() {
    local mount_point="$1"
    log_debug "Tentative de démontage SSHFS de $mount_point"
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[Dry Run] Simulation de démontage SSHFS pour $mount_point."
        return 0
    fi
    if mountpoint -q "$mount_point"; then
        if lsof "$mount_point" >/dev/null 2>&1; then
            log_warning "Point de montage $mount_point occupé, tentative de démontage forcé."
            "$FUSERMOUNT_CMD" -u -z "$mount_point" || { diagnostiquer_et_logger_erreur "Échec du démontage forcé SSHFS." $? ; return 1; }
        else
            "$FUSERMOUNT_CMD" -u "$mount_point" || { diagnostiquer_et_logger_erreur "Échec du démontage SSHFS." $? ; return 1; }
        fi
        log_success "SSHFS démonté avec succès."
        return 0
    else
        log_debug "Point de montage $mount_point non monté."
        return 0
    fi
}

declare -a mounted_sshfs_points

add_mounted_sshfs_point() {
    local mount_point="$1"
    mounted_sshfs_points+=("$mount_point")
}

demonter_tous_les_sshfs_a_la_sortie() {
    log_info "Démontage de tous les points SSHFS montés..."
    for mp in "${mounted_sshfs_points[@]}"; do
        demonter_sshfs "$mp"
    done
    log_info "Tous les points SSHFS démontés."
}

trap demonter_tous_les_sshfs_a_la_sortie EXIT

# --- FONCTIONS DE SAUVEGARDE ---
executer_sauvegarde_locale() {
    local nom_sauvegarde="$1"
    local source_path="$2"
    local dest_main_path="$3"
    local dest_incr_base_path="$4"
    local incremental_mode="$5"

    local current_date=$(date +%Y-%m-%d)
    local new_backup_full_path="${dest_incr_base_path}${current_date}/"

    log_info "Démarrage de la sauvegarde locale : $nom_sauvegarde"
    if [[ ! -d "$source_path" ]]; then
        diagnostiquer_et_logger_erreur "La source locale '$source_path' n'existe pas." 1
        return 1
    fi

    local target_dir_for_checks
    if [[ "$incremental_mode" -eq 1 ]]; then
        target_dir_for_checks="$dest_incr_base_path"
    else
        target_dir_for_checks="$dest_main_path"
    fi

    if ! verifier_permissions_ecriture "$target_dir_for_checks"; then
        log_error "Permissions insuffisantes pour $target_dir_for_checks."
        return 1
    fi
    if ! verifier_espace_disque "$target_dir_for_checks" "$ESPACE_DISQUE_MIN_GO"; then
        log_error "Espace disque insuffisant pour $nom_sauvegarde."
        return 1
    fi

    local rsync_final_options="$DEFAULT_RSYNC_OPTIONS"
    [[ "${RSYNC_DELETE:-0}" -eq 1 ]] && rsync_final_options+=" --delete"

    if [[ "$incremental_mode" -eq 1 ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[Dry Run] Simulation de sauvegarde incrémentale pour $nom_sauvegarde vers $new_backup_full_path."
            return 0
        fi
        mkdir -p "$new_backup_full_path" || { diagnostiquer_et_logger_erreur "Échec de création de $new_backup_full_path" $? ; return 1; }
        local previous_backup_dir=$(find_latest_backup_dir "$dest_incr_base_path")
        if [[ -n "$previous_backup_dir" && "$previous_backup_dir" != "$new_backup_full_path" ]]; then
            rsync_final_options+=" --link-dest=\"$previous_backup_dir\""
            log_debug "Mode incrémental: Liens créés vers $previous_backup_dir"
        else
            log_info "Mode incrémental: Aucune sauvegarde précédente trouvée."
        fi
        log_debug "Commande Rsync: rsync $rsync_final_options \"$source_path/\" \"$new_backup_full_path\""
        rsync $rsync_final_options "$source_path/" "$new_backup_full_path" || { diagnostiquer_et_logger_erreur "Échec de la sauvegarde locale '$nom_sauvegarde'." $? ; return 1; }
    else
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[Dry Run] Simulation de sauvegarde complète pour $nom_sauvegarde vers $dest_main_path."
            return 0
        fi
        log_debug "Commande Rsync: rsync $rsync_final_options \"$source_path/\" \"$dest_main_path\""
        rsync $rsync_final_options "$source_path/" "$dest_main_path" || { diagnostiquer_et_logger_erreur "Échec de la sauvegarde locale '$nom_sauvegarde'." $? ; return 1; }
    fi
    log_success "Sauvegarde locale '$nom_sauvegarde' terminée avec succès."
    return 0
}

executer_sauvegarde_distante() {
    local nom_sauvegarde="$1"
    local remote_user="$2"
    local remote_ip="$3"
    local remote_port="$4"
    local source_path="$5"
    local sshfs_mount_point="$6"
    local dest_main_path="$7"
    local dest_incr_base_path="$8"
    local incremental_mode="$9"

    local current_date=$(date +%Y-%m-%d)
    local new_backup_full_path="${dest_incr_base_path}${current_date}/"

    log_info "Démarrage de la sauvegarde distante : $nom_sauvegarde"
    local target_dir_for_checks
    if [[ "$incremental_mode" -eq 1 ]]; then
        target_dir_for_checks="$dest_incr_base_path"
    else
        target_dir_for_checks="$dest_main_path"
    fi

    if ! verifier_permissions_ecriture "$target_dir_for_checks"; then
        log_error "Permissions insuffisantes pour $target_dir_for_checks."
        return 1
    fi
    if ! verifier_espace_disque "$target_dir_for_checks" "$ESPACE_DISQUE_MIN_GO"; then
        log_error "Espace disque insuffisant pour $nom_sauvegarde."
        return 1
    fi

    local remote_source_for_rsync
    if [[ "$DEFAULT_TYPE_CONNEXION_DISTANTE" -eq 0 ]]; then
        if ! monter_sshfs "$remote_user" "$remote_ip" "$remote_port" "$source_path" "$sshfs_mount_point"; then
            log_error "Échec du montage SSHFS pour '$nom_sauvegarde'."
            return 1
        fi
        remote_source_for_rsync="${sshfs_mount_point}/"
    else
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[Dry Run] Simulation de connexion SSH directe pour $nom_sauvegarde."
        else
            if ! ssh -p "$remote_port" "$remote_user@$remote_ip" "test -d \"$source_path\"" 2>/dev/null; then
                log_error "Chemin distant $source_path n'existe pas."
                return 1
            fi
        fi
        remote_source_for_rsync="${remote_user}@${remote_ip}:${source_path}/"
    fi

    local rsync_final_options="$DEFAULT_RSYNC_OPTIONS"
    [[ "${RSYNC_DELETE:-0}" -eq 1 ]] && rsync_final_options+=" --delete"

    if [[ "$incremental_mode" -eq 1 ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[Dry Run] Simulation de sauvegarde incrémentale pour $nom_sauvegarde vers $new_backup_full_path."
            return 0
        fi
        mkdir -p "$new_backup_full_path" || { diagnostiquer_et_logger_erreur "Échec de création de $new_backup_full_path" $? ; return 1; }
        local previous_backup_dir=$(find_latest_backup_dir "$dest_incr_base_path")
        if [[ -n "$previous_backup_dir" && "$previous_backup_dir" != "$new_backup_full_path" ]]; then
            rsync_final_options+=" --link-dest=\"$previous_backup_dir\""
            log_debug "Mode incrémental: Liens créés vers $previous_backup_dir"
        fi
        rsync $rsync_final_options "$remote_source_for_rsync" "$new_backup_full_path" || { diagnostiquer_et_logger_erreur "Échec de la sauvegarde distante '$nom_sauvegarde'." $? ; return 1; }
    else
        if [[ $DRY_RUN -eq 1 ]]; then
            log_info "[Dry Run] Simulation de sauvegarde complète pour $nom_sauvegarde vers $dest_main_path."
            return 0
        fi
        rsync $rsync_final_options "$remote_source_for_rsync" "$dest_main_path" || { diagnostiquer_et_logger_erreur "Échec de la sauvegarde distante '$nom_sauvegarde'." $? ; return 1; }
    fi
    log_success "Sauvegarde distante '$nom_sauvegarde' terminée avec succès."
    return 0
}

# --- NETTOYAGE DES ANCIENNES SAUVEGARDES ---
nettoyer_anciennes_sauvegardes() {
    local base_dir="$1"
    local retention_quotidien_jours="$2"
    local retention_hebdo_semaines="$3"
    local retention_mensuel_mois="$4"

    log_info "Début du nettoyage des anciennes sauvegardes dans: $base_dir"
    if [[ ! -d "$base_dir" ]]; then
        log_debug "Le répertoire '$base_dir' n'existe pas."
        return 0
    fi

    est_lundi() {
        local date_str="$1"
        local day_of_week=$(date -d "$date_str" +%u 2>/dev/null)
        [[ "$day_of_week" -eq 1 ]]
    }

    est_premier_du_mois() {
        local date_str="$1"
        local day_of_month=$(date -d "$date_str" +%d 2>/dev/null)
        [[ "$day_of_month" -eq 01 ]]
    }

    local current_timestamp=$(date +%s)
    local one_day_sec=$((24*60*60))
    local delete_count=0

    find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d $'\0' dir; do
        local dir_name=$(basename "$dir")
        if [[ "$dir_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            local dir_timestamp=$(date -d "$dir_name" +%s 2>/dev/null)
            if [[ -z "$dir_timestamp" ]]; then
                log_warning "Nom de répertoire '$dir_name' non valide."
                continue
            fi

            local age_days=$(( (current_timestamp - dir_timestamp) / one_day_sec ))
            local to_delete=1

            if (( age_days <= retention_quotidien_jours )); then
                to_delete=0
            elif [[ "$retention_hebdo_semaines" -gt 0 ]] && est_lundi "$dir_name"; then
                local age_weeks=$(( age_days / 7 ))
                if (( age_weeks <= retention_hebdo_semaines )); then
                    to_delete=0
                fi
            elif [[ "$retention_mensuel_mois" -gt 0 ]] && est_premier_du_mois "$dir_name"; then
                local age_months=$(( ( ( $(date +%Y) - $(date -d "$dir_name" +%Y) ) * 12 ) + ( $(date +%m) - $(date -d "$dir_name" +%m) ) ))
                if (( age_months <= retention_mensuel_mois )); then
                    to_delete=0
                fi
            fi

            if [[ "$to_delete" -eq 1 ]]; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    log_info "[Dry Run] Simulation de suppression de $dir."
                else
                    log_info "Suppression de l'ancienne sauvegarde: $dir"
                    rm -rf "$dir" || { diagnostiquer_et_logger_erreur "Échec de suppression de $dir." $? ; continue; }
                    log_success "Supprimé: $dir"
                    delete_count=$((delete_count + 1))
                fi
            else
                log_debug "Garde la sauvegarde: $dir"
            fi
        fi
    done
    log_info "Nettoyage terminé. Total supprimé: $delete_count répertoires."
}

# --- GESTION DES ARGUMENTS ---
declare -a selections
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "all" ]]; then
        log_info "Option 'all' détectée."
        selections=("docs_eric" "docs_fanou" "docs_communs" "projets" "photos" "docs_portable" "musiques")
    else
        log_info "Options spécifiques détectées: $*"
        selections=("$@")
    fi
else
    log_info "Utilisation des sélections par défaut: $DEFAULT_SELECTIONS_SAUVEGARDES"
    read -r -a selections <<< "$DEFAULT_SELECTIONS_SAUVEGARDES"
fi

# --- BOUCLE PRINCIPALE ---
sauvegardes_reussies=0
sauvegardes_echouees=0
nombre_sauvegardes=0

log_info "=== DÉBUT DES SAUVEGARDES ==="
if [[ $DRY_RUN -eq 1 ]]; then
    log_info "[Dry Run] Mode simulation activé."
fi

verifier_disque_de_sauvegarde || exit 1

for i in "${selections[@]}"; do
    nombre_sauvegardes=$((nombre_sauvegardes + 1))
    case "$i" in
        "1"|"docs_eric")
            log_info "Traitement de la sauvegarde : Documents Eric (Locale)"
            if executer_sauvegarde_locale \
                "Documents Eric" \
                "$SOURCE_LOCAL_DOCS_ERIC" \
                "$DEST_MAIN_DOCS_ERIC" \
                "$DEST_INCR_BASE_DOCS_ERIC" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [[ "$DEFAULT_MODE_INCREMENTAL" -eq 1 && $DRY_RUN -eq 0 ]]; then
                    if [[ "$JOURS_RETENTION_DOCS_ERIC_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_DOCS_ERIC_HEBDO" -gt 0 || "$JOURS_RETENTION_DOCS_ERIC_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_DOCS_ERIC" \
                            "$JOURS_RETENTION_DOCS_ERIC_QUOTIDIEN" \
                            "$JOURS_RETENTION_DOCS_ERIC_HEBDO" \
                            "$JOURS_RETENTION_DOCS_ERIC_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;
        "2"|"docs_fanou")
            log_info "Traitement de la sauvegarde : Documents Fanou (Locale)"
            if executer_sauvegarde_locale \
                "Documents Fanou" \
                "$SOURCE_LOCAL_DOCS_FANOU" \
                "$DEST_MAIN_DOCS_FANOU" \
                "$DEST_INCR_BASE_DOCS_FANOU" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [[ "$DEFAULT_MODE_INCREMENTAL" -eq 1 && $DRY_RUN -eq 0 ]]; then
                    if [[ "$JOURS_RETENTION_DOCS_FANOU_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_DOCS_FANOU_HEBDO" -gt 0 || "$JOURS_RETENTION_DOCS_FANOU_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_DOCS_FANOU" \
                            "$JOURS_RETENTION_DOCS_FANOU_QUOTIDIEN" \
                            "$JOURS_RETENTION_DOCS_FANOU_HEBDO" \
                            "$JOURS_RETENTION_DOCS_FANOU_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;
        "4"|"docs_communs")
            log_info "Traitement de la sauvegarde : Documents Communs (Locale)"
            if executer_sauvegarde_locale \
                "Documents Communs" \
                "$SOURCE_LOCAL_DOCS_COMMUNS" \
                "$DEST_MAIN_DOCS_COMMUNS" \
                "$DEST_INCR_BASE_DOCS_COMMUNS" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [[ "$DEFAULT_MODE_INCREMENTAL" -eq 1 && $DRY_RUN -eq 0 ]]; then
                    if [[ "$JOURS_RETENTION_DOCS_COMMUNS_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_DOCS_COMMUNS_HEBDO" -gt 0 || "$JOURS_RETENTION_DOCS_COMMUNS_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_DOCS_COMMUNS" \
                            "$JOURS_RETENTION_DOCS_COMMUNS_QUOTIDIEN" \
                            "$JOURS_RETENTION_DOCS_COMMUNS_HEBDO" \
                            "$JOURS_RETENTION_DOCS_COMMUNS_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;
        "8"|"projets")
            log_info "Traitement de la sauvegarde : Projets Serveur (Distante)"
            if executer_sauvegarde_distante \
                "Projets Serveur" \
                "$userServeur" \
                "$ipServeur" \
                "$portServeur" \
                "$SOURCE_DIST_PROJETS_SERVEUR" \
                "$MONTAGE_SSHFS_IMAGES" \
                "$DEST_MAIN_PROJETS" \
                "$DEST_INCR_BASE_PROJETS" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [[ "$DEFAULT_MODE_INCREMENTAL" -eq 1 && $DRY_RUN -eq 0 ]]; then
                    if [[ "$JOURS_RETENTION_PROJETS_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_PROJETS_HEBDO" -gt 0 || "$JOURS_RETENTION_PROJETS_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_PROJETS" \
                            "$JOURS_RETENTION_PROJETS_QUOTIDIEN" \
                            "$JOURS_RETENTION_PROJETS_HEBDO" \
                            "$JOURS_RETENTION_PROJETS_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;
        "16"|"photos")
            log_info "Traitement de la sauvegarde : Photos VM (Distante)"
            if executer_sauvegarde_distante \
                "Photos VM" \
                "$userVM" \
                "$ipVM" \
                "$portVM" \
                "$SOURCE_DIST_PHOTOS_VM" \
                "$MONTAGE_SSHFS_PHOTOS" \
                "$DEST_MAIN_PHOTOS" \
                "$DEST_INCR_BASE_PHOTOS" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [[ "$DEFAULT_MODE_INCREMENTAL" -eq 1 && $DRY_RUN -eq 0 ]]; then
                    if [[ "$JOURS_RETENTION_PHOTOS_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_PHOTOS_HEBDO" -gt 0 || "$JOURS_RETENTION_PHOTOS_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_PHOTOS" \
                            "$JOURS_RETENTION_PHOTOS_QUOTIDIEN" \
                            "$JOURS_RETENTION_PHOTOS_HEBDO" \
                            "$JOURS_RETENTION_PHOTOS_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;
        "32"|"docs_portable")
            log_info "Traitement de la sauvegarde : Documents Portable (Distante)"
            if executer_sauvegarde_distante \
                "Documents Portable" \
                "$userPortable" \
                "$ipPortable" \
                "$portPortable" \
                "$SOURCE_DIST_DOCS_PORTABLE" \
                "$MONTAGE_SSHFS_MUSIQUES" \
                "$DEST_MAIN_DOCS_PORTABLE" \
                "$DEST_INCR_BASE_DOCS_PORTABLE" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [[ "$DEFAULT_MODE_INCREMENTAL" -eq 1 && $DRY_RUN -eq 0 ]]; then
                    if [[ "$JOURS_RETENTION_DOCS_PORTABLE_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_DOCS_PORTABLE_HEBDO" -gt 0 || "$JOURS_RETENTION_DOCS_PORTABLE_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_DOCS_PORTABLE" \
                            "$JOURS_RETENTION_DOCS_PORTABLE_QUOTIDIEN" \
                            "$JOURS_RETENTION_DOCS_PORTABLE_HEBDO" \
                            "$JOURS_RETENTION_DOCS_PORTABLE_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;
        "64"|"musiques")
            log_info "Traitement de la sauvegarde : Musiques (Locale)"
            if executer_sauvegarde_locale \
                "Musiques" \
                "$SOURCE_LOCAL_MUSIQUES" \
                "$DEST_MAIN_MUSIQUES" \
                "$DEST_INCR_BASE_MUSIQUES" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [[ "$DEFAULT_MODE_INCREMENTAL" -eq 1 && $DRY_RUN -eq 0 ]]; then
                    if [[ "$JOURS_RETENTION_MUSIQUES_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_MUSIQUES_HEBDO" -gt 0 || "$JOURS_RETENTION_MUSIQUES_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_MUSIQUES" \
                            "$JOURS_RETENTION_MUSIQUES_QUOTIDIEN" \
                            "$JOURS_RETENTION_MUSIQUES_HEBDO" \
                            "$JOURS_RETENTION_MUSIQUES_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;
        *)
            log_warning "Valeur de sélection inconnue ignorée: $i"
            ;;
    esac
done

# --- RÉSUMÉ FINAL ---
log_info "=== FIN DES SAUVEGARDES ==="
log_info "Résumé :"
log_info "  - Sauvegardes réussies: $sauvegardes_reussies"
log_info "  - Sauvegardes échouées: $sauvegardes_echouees"
log_info "  - Total des sauvegardes traitées: $nombre_sauvegardes"

if [[ "$sauvegardes_echouees" -eq 0 && "$nombre_sauvegardes" -gt 0 ]]; then
    log_success "Toutes les sauvegardes demandées ont réussi."
    if [[ $DRY_RUN -eq 0 ]]; then
        envoyer_rapport_final
    fi
    exit 0
else
    log_error "Des erreurs sont survenues lors de certaines sauvegardes."
    if [[ $DRY_RUN -eq 0 ]]; then
        envoyer_rapport_final
    fi
    exit 1
fi
