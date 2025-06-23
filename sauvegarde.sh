#!/bin/bash
export LC_ALL=C
#===============================================================
# Sauvegarde des données
# Auteur : enRIKO (modifié par geole, iznobe, Watael, steph810 pour production)
# Date : 2025-06-23
# Version : 6.0 Beta 
# Description : Script de sauvegarde incrémentale des fichiers
#               personnels et de configuration sur un disque externe,
#               utilisant la méthode --link-dest de rsync pour optimiser l'espace.
#===============================================================

# --- PARAMÈTRES ET OPTIONS DU SHELL ---
set -o errexit   # Quitte le script si une commande échoue
set -o nounset   # Traite les variables non définies comme des erreurs (TRÈS IMPORTANT pour ce script)
set -o pipefail  # Détecte les erreurs dans les pipelines (ex: cmd1 | cmd2)

# --- VARIABLES GLOBALES DE BASE ---
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# --- INTÉGRATION DU FICHIER DE CONFIGURATION (config.sh) ---
# Vérifie l'existence et source le fichier de configuration.
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "ERREUR CRITIQUE [$(date '+%Y-%m-%d %H:%M:%S')]: Le fichier de configuration '$SCRIPT_DIR/config.sh' est introuvable ou inaccessible." >&2
    echo "IMPOSSIBLE DE CHARGER LA CONFIGURATION. Arret du script." >&2
    exit 1
fi

# Validation variables critiques
validate_critical_vars

# Vérification des dépendances
check_dependencies

# --- INTÉGRATION DU FICHIER DE DIAGNOSTIC (fonctions_erreur.sh) ---
# Le chemin est maintenant défini dans config.sh et est relatif.
if [ -f "$CHEMIN_FONCTIONS_ERREUR" ]; then
    source "$CHEMIN_FONCTIONS_ERREUR"
    log_info "Fichier de fonctions d'erreur '$CHEMIN_FONCTIONS_ERREUR' source avec succes."
else
    echo "ERREUR CRITIQUE [$(date '+%Y-%m-%d %H:%M:%S')]: Le fichier de fonctions d'erreur '$CHEMIN_FONCTIONS_ERREUR' est introuvable." >&2
    echo "Impossible de charger les fonctions de diagnostic. Arret du script." >&2
    exit 1
fi

# --- DÉFINITION DES FONCTIONS DE JOURNALISATION ---
# Ces fonctions utilisent log_message pour formater la sortie des logs.
log_message() {
    local type="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ "$DEFAULT_JOURNAUX_DESACTIVES" -eq 0 ]; then
        case "$type" in
            INFO) echo "[$timestamp] [INFO] $message" ;;
            DEBUG) [ "$DEFAULT_MODE_DEBOGAGE" -eq 1 ] && echo "[$timestamp] [DEBUG] $message" ;;
            SUCCESS) echo "[$timestamp] [SUCCES] $message" ;;
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


log_info "Fichier de configuration '$SCRIPT_DIR/config.sh' source avec succes."

# --- VERROUILLAGE DU SCRIPT (Méthode flock) ---
# Empêche l'exécution simultanée de plusieurs instances du script.
LOCK_DIR="/var/lock"
if ! mkdir -p "$LOCK_DIR"; then
    log_error "Impossible de creer ou acceder au repertoire de verrouillage : $LOCK_DIR. Verifiez les permissions."
    exit 1
fi

LOCK_FILE="$LOCK_DIR/${DEFAULT_NOM_SCRIPT:-sauvegarde}.lock"

# Tente d'acquérir un verrou non-bloquant sur le fichier.
# Le descripteur de fichier 200 est arbitrairement choisi.
exec 200>"$LOCK_FILE" || { log_error "Impossible d'ouvrir le fichier de verrouillage: $LOCK_FILE. Verifiez les permissions ou l'integrité du systeme de fichiers."; exit 1; }

if ! flock -n 200; then
    log_error "Une autre instance du script de sauvegarde est deja en cours d'execution. Abandon."
    exit 1
fi
log_success "Verrou acquis sur le fichier: $LOCK_FILE"

# --- FONCTIONS GÉNÉRALES ---

# Check des dependences
check_dependencies() {
    local deps=("rsync" "flock" "sshfs")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "ERREUR CRITIQUE : Dépendance manquante : $dep" >&2
            exit 1
        fi
    done
}
# Contrôle des variables CRITIQUE
validate_critical_vars() {
    [[ -n "${UUID_DISQUE_SAUVEGARDE}" ]] || { echo "Erreur : UUID_DISQUE_SAUVEGARDE non défini."; exit 1; }
    [[ -n "${DEST_BASE_SAUVEGARDES}" ]] || { echo "Erreur : DEST_BASE_SAUVEGARDES non défini."; exit 1; }
    [[ -n "${DEFAULT_RSYNC_OPTIONS}" ]] || { echo "Erreur : DEFAULT_RSYNC_OPTIONS non défini."; exit 1; }
    [[ -n "${DEFAULT_TYPE_CONNEXION_DISTANTE}" ]] || { echo "Erreur : DEFAULT_TYPE_CONNEXION_DISTANTE non défini."; exit 1; }
    [[ -n "${DEFAULT_SELECTIONS_SAUVEGARDES}" ]] || { echo "Erreur : DEFAULT_SELECTIONS_SAUVEGARDES non défini."; exit 1; }
    [[ -n "${MONTAGE_SSHFS_PHOTOS}" ]] || { echo "Erreur : MONTAGE_SSHFS_PHOTOS non défini."; exit 1; }
    [[ -n "${MONTAGE_SSHFS_IMAGES}" ]] || { echo "Erreur : MONTAGE_SSHFS_IMAGES non défini."; exit 1; }
    [[ -n "${MONTAGE_SSHFS_MUSIQUES}" ]] || { echo "Erreur : MONTAGE_SSHFS_MUSIQUES non défini."; exit 1; }
    [[ -n "${userVM}" ]] || { echo "Erreur : userVM non défini."; exit 1; }
    [[ -n "${ipVM}" ]] || { echo "Erreur : ipVM non défini."; exit 1; }
    [[ -n "${portVM}" ]] || { echo "Erreur : portVM non défini."; exit 1; }
    [[ -n "${userPortable}" ]] || { echo "Erreur : userPortable non défini."; exit 1; }
    [[ -n "${ipPortable}" ]] || { echo "Erreur : ipPortable non défini."; exit 1; }
    [[ -n "${portPortable}" ]] || { echo "Erreur : portPortable non défini."; exit 1; }
    [[ -n "${pathPortable}" ]] || { echo "Erreur : pathPortable non défini."; exit 1; }
    [[ -n "${userServeur}" ]] || { echo "Erreur : userServeur non défini."; exit 1; }
    [[ -n "${ipServeur}" ]] || { echo "Erreur : ipServeur non défini."; exit 1; }
    [[ -n "${portServeur}" ]] || { echo "Erreur : portServeur non défini."; exit 1; }
}
# Fonction pour trouver le dernier répertoire de sauvegarde incremental pour --link-dest
# Cherche le répertoire daté le plus récent (AAAA-MM-JJ) dans un chemin de base donné.
# Arguments: $1 = chemin de base ou chercher (ex: /media/disk/SAUVEGARDES/incremental-DocumentsEric/)
find_latest_backup_dir() {
    local base_path_for_search="$1"
    local latest_backup_path=""
    local latest_timestamp=0

    log_debug "Recherche de la derniere sauvegarde dans: $base_path_for_search"

    if [[ ! -d "$base_path_for_search" ]]; then
        log_debug "Le repertoire de base de recherche '$base_path_for_search' n'existe pas ou n'est pas un repertoire."
        # Retourne silencieusement si le dossier de base n'existe pas, ce qui est normal pour la premiere sauvegarde.
        return
    fi

    # Trouver les sous-repertoires qui sont des dates AAAA-MM-JJ
    while IFS= read -r -d $'\0' dir; do
        local dir_name=$(basename "$dir")
        # Verifie si le nom du repertoire correspond au format AAAA-MM-JJ
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
        log_debug "Derniere sauvegarde trouvee: $latest_backup_path"
    else
        log_debug "Aucune sauvegarde precedente trouvee dans $base_path_for_search."
    fi
}

# Fonction pour verifier l'existence et les permissions d'ecriture d'un repertoire.
# Cree le repertoire s'il n'existe pas.
# Arguments: $1 = chemin du repertoire a verifier/creer
verifier_permissions_ecriture() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_debug "Creation du repertoire de destination: $dir"
        if ! mkdir -p "$dir"; then
            diagnostiquer_et_logger_erreur "Echec de la creation du repertoire de destination: $dir. Verifiez les permissions." $?
            return 1
        fi
    fi
    if [[ ! -w "$dir" ]]; then
        diagnostiquer_et_logger_erreur "Le repertoire de destination '$dir' n'est pas accessible en ecriture. Verifiez les permissions." 1
        return 1
    fi
    return 0
}

# Fonction pour verifier l'espace disque disponible.
# Arguments: $1 = chemin du point de montage, $2 = espace minimum requis en Go
verifier_espace_disque() {
    local path="$1"
    local min_gb="$2"
    local available_gb=$(df -BG "$path" | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ -z "$available_gb" ]]; then
        diagnostiquer_et_logger_erreur "Impossible de determiner l'espace disque disponible pour '$path'." 1
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

# Verifie que le disque de destination est bien le bon en comparant son UUID.
verifier_disque_de_sauvegarde() {
    log_info "Verification du disque de destination..."
    # S'assure que la variable de destination est bien definie
    if [ -z "${DEST_BASE_SAUVEGARDES:-}" ]; then
        gerer_erreur_fatale "La variable DEST_BASE_SAUVEGARDES n'est pas definie dans config.sh. Le script ne peut pas continuer sans chemin de destination valide." 1
    fi

    # Recupere le nom du peripherique (ex: /dev/sdb1) correspondant au point de montage
    local device
    device=$(findmnt -n -o SOURCE --target "$DEST_BASE_SAUVEGARDES")
    
    if [ -z "$device" ]; then
        gerer_erreur_fatale "Le repertoire de destination '$DEST_BASE_SAUVEGARDES' n'est pas un point de montage valide." 1
        return 1
    fi

    # Recupere l'UUID du peripherique monte
    local current_uuid
    current_uuid=$(lsblk -n -o UUID "$device")

    if [ "$current_uuid" == "$UUID_DISQUE_SAUVEGARDE" ]; then
        log_success "Le disque de sauvegarde est correct (UUID: $current_uuid)."
        return 0
    else
        gerer_erreur_fatale "ERREUR DE SECURITE ! Le disque monte sur '$DEST_BASE_SAUVEGARDES' n'est PAS le bon disque de sauvegarde. UUID attendu: '$UUID_DISQUE_SAUVEGARDES', UUID trouve: '$current_uuid'. Arret immediat." 1
        return 1
    fi
}

# Envoie un rapport final par email si EMAIL_NOTIFICATION est configure.
envoyer_rapport_final() {
    # Verifie si la commande 'mail' est disponible
    if ! command -v mail &> /dev/null; then
        log_warning "La commande 'mail' n'est pas installee. Impossible d'envoyer le rapport par email. Installez 'mailutils' ou 'postfix' si necessaire."
        return 1
    fi

    if [ -z "$EMAIL_NOTIFICATION" ]; then
        log_info "Aucune adresse email de notification configuree. Le rapport final ne sera pas envoye par email."
        return 0
    fi

    local sujet="[Sauvegarde] Rapport du $(date +'%Y-%m-%d %H:%M')"
    local corps
    corps=$(cat <<EOF
Rapport de sauvegarde termine.

Reussies : $sauvegardes_reussies
Echouees : $sauvegardes_echouees
Total     : $nombre_sauvegardes

Consultez les logs pour plus de details.
EOF
)
    if [ "$sauvegardes_echouees" -gt 0 ]; then
        sujet="[Sauvegarde] ECHEC - Rapport du $(date +'%Y-%m-%d %H:%M')"
    fi
    
    echo "$corps" | mail -s "$sujet" "$EMAIL_NOTIFICATION"
    log_info "Rapport de sauvegarde envoye a $EMAIL_NOTIFICATION."
}

# --- Fonctions SSHFS ---
# Elles gerent le montage, le demontage et l'ajout a une liste pour le demontage final.
monter_sshfs() {
    local user_dist="$1"
    local ip_dist="$2"
    local port_dist="$3"
    local source_path_dist="$4"  # Doit etre le chemin sur la machine distante
    local mount_point="$5"

    log_debug "Tentative de montage SSHFS de $user_dist@$ip_dist:$source_path_dist vers $mount_point via port $port_dist"

    if mountpoint -q "$mount_point"; then
        log_debug "Point de montage $mount_point deja monte."
        return 0
    fi

    mkdir -p "$mount_point" || { diagnostiquer_et_logger_erreur "Echec de creation du point de montage: $mount_point" $? ; return 1 ; }
    # Options SSHFS : reconnect, default_permissions, allow_other, ServerAliveInterval, ServerAliveCountMax
    # Ces options sont generalement bonnes pour la stabilite.
    sshfs "$user_dist@$ip_dist:$source_path_dist" "$mount_point" -o reconnect,default_permissions,allow_other -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -p "$port_dist"
    local sshfs_exit_code=$?

    if [ $sshfs_exit_code -eq 0 ]; then
        log_success "SSHFS monte avec succes sur $mount_point."
        return 0
    else
        diagnostiquer_et_logger_erreur "Echec du montage SSHFS (code: $sshfs_exit_code)." $sshfs_exit_code
        return 1
    fi
}

# Detection de la commande fusermount
detect_fusermount_cmd() {
    if command -v fusermount3 >/dev/null 2>&1; then
        echo "fusermount3"
    elif command -v fusermount >/dev/null 2>&1; then
        echo "fusermount"
    else
        echo ""Aucune commande fusermount disponible." >&2"
    fi
}

FUSERMOUNT_CMD=$(detect_fusermount_cmd)

if [[ -z "$FUSERMOUNT_CMD" ]]; then
    echo "Erreur critique : ni fusermount ni fusermount3 n'est disponible sur ce système." >&2
    exit 1
fi
demonter_sshfs() {
    local mount_point="$1"
    log_debug "Tentative de demontage SSHFS de $mount_point"
    if mountpoint -q "$mount_point"; then
        fusermount -u "$mount_point"
        local umount_exit_code=$?
        if [ $umount_exit_code -eq 0 ]; then
            log_success "SSHFS demonte avec succes."
            return 0
        else
            diagnostiquer_et_logger_erreur "Echec du demontage SSHFS (code: $umount_exit_code)." $umount_exit_code
            return 1
        fi
    else
        log_debug "Point de montage $mount_point n'est pas monte. Pas de demontage necessaire."
        return 0
    fi
}

declare -a mounted_sshfs_points # Tableau pour garder une trace des points de montage SSHFS

# Fonction pour ajouter un point de montage SSHFS a la liste
add_mounted_sshfs_point() {
    local mount_point="$1"
    mounted_sshfs_points+=("$mount_point")
}

# Fonction pour demonter tous les points SSHFS montes par le script a la sortie
demonter_tous_les_sshfs_a_la_sortie() {
    log_info "Demontage de tous les points SSHFS montes par ce script..."
    for mp in "${mounted_sshfs_points[@]}"; do
        if mountpoint -q "$mp"; then
            demonter_sshfs "$mp"
        else
            log_debug "Le point de montage $mp n'est plus monte. Pas de demontage necessaire."
        fi
    done
    log_info "Tous les points SSHFS ont ete demontes."
}

# Démonter SSHFS en fin d’exécution ou interruption
cleanup_sshfs() {
    for mount_point in "$MONTAGE_SSHFS_PHOTOS" "$MONTAGE_SSHFS_IMAGES" "$MONTAGE_SSHFS_MUSIQUES"; do
        if mountpoint -q "$mount_point"; then
             log_info "Démontage de SSHFS sur $mount_point..."
             fusermount -u "$mount_point" || fusermount3 -u "$mount_point"
        fi
    done
}

# Assurez-vous que demonter_tous_les_sshfs_a_la_sortie est appele a la sortie du script
# C'est une excellente pratique pour garantir le nettoyage.
trap demonter_tous_les_sshfs_a_la_sortie EXIT
trap cleanup_sshfs EXIT

# --- Fonctions de Sauvegarde ---

# executer_sauvegarde_locale : Execute une sauvegarde locale avec rsync.
# Arguments:
# $1: nom_sauvegarde (pour les logs)
# $2: source_path (chemin absolu de la source)
# $3: dest_main_path (chemin de la destination pour la copie complete/courante)
# $4: dest_incr_base_path (chemin de base pour les sauvegardes incrementales datees)
# $5: incremental_mode (0 pour complet, 1 pour incremental --link-dest)
executer_sauvegarde_locale() {
    local nom_sauvegarde="$1"
    local source_path="$2"
    local dest_main_path="$3"
    local dest_incr_base_path="$4"
    local incremental_mode="$5"

    local current_date=$(date +%Y-%m-%d)
    local new_backup_full_path="${dest_incr_base_path}${current_date}/"

    log_info "Demarrage de la sauvegarde locale : $nom_sauvegarde"
    log_debug "Source: $source_path"

    if [[ ! -d "$source_path" ]]; then
        diagnostiquer_et_logger_erreur "La source locale '$source_path' n'existe pas ou n'est pas un repertoire." 1
        return 1
    fi

    local target_dir_for_checks # Repertoire sur lequel verifier permissions et espace

    if [ "$incremental_mode" -eq 1 ]; then
        target_dir_for_checks="$dest_incr_base_path"
        log_debug "Destination Finale (Incrementale Datee): $new_backup_full_path"
    else
        target_dir_for_checks="$dest_main_path"
        log_debug "Destination Principale (Complete): $dest_main_path"
    fi

    if ! verifier_permissions_ecriture "$target_dir_for_checks"; then
        log_error "Pre-requis (permissions/creation du repertoire de base: $target_dir_for_checks) non satisfaits pour '$nom_sauvegarde'. Sauvegarde ignoree."
        return 1
    fi

    if ! verifier_espace_disque "$target_dir_for_checks" "$ESPACE_DISQUE_MIN_GO"; then
        log_error "Pre-requis (espace disque) non satisfaits pour '$nom_sauvegarde'. Sauvegarde ignoree."
        return 1
    fi

    local rsync_final_options="$DEFAULT_RSYNC_OPTIONS --delete"

    if [ "$incremental_mode" -eq 1 ]; then
        mkdir -p "$new_backup_full_path" || { diagnostiquer_et_logger_erreur "Echec de la creation du repertoire de destination datee: $new_backup_full_path" $? ; return 1 ; }

        local previous_backup_dir=$(find_latest_backup_dir "$dest_incr_base_path")

        if [[ -n "$previous_backup_dir" && "$previous_backup_dir" != "$new_backup_full_path" ]]; then
            rsync_final_options+=" --link-dest=\"$previous_backup_dir\""
            log_debug "Mode incremental: Liens crees vers la sauvegarde precedente: $previous_backup_dir"
        else
            log_info "Mode incremental: Aucune sauvegarde precedente valide trouvee pour '$nom_sauvegarde'. Effectue une sauvegarde complete (premiere sauvegarde incrementale ou repertoire vide)."
        fi
        log_debug "Commande Rsync: rsync $rsync_final_options \"$source_path/\" \"$new_backup_full_path\""
        rsync $rsync_final_options "$source_path/" "$new_backup_full_path"
    else
        log_info "Mode complet: Sauvegarde complete de '$nom_sauvegarde' vers '$dest_main_path'."
        log_debug "Commande Rsync: rsync $rsync_final_options \"$source_path/\" \"$dest_main_path\""
        rsync $rsync_final_options "$source_path/" "$dest_main_path"
    fi

    local rsync_exit_code=$?
    if [ $rsync_exit_code -eq 0 ]; then
        log_success "Sauvegarde locale '$nom_sauvegarde' terminee avec succes."
        return 0
    else
        diagnostiquer_et_logger_erreur "Echec de la sauvegarde locale '$nom_sauvegarde' (code: $rsync_exit_code)." $rsync_exit_code
        return 1
    fi
}

# executer_sauvegarde_distante : Execute une sauvegarde distante (via SSHFS ou SSH Direct) avec rsync.
# Arguments:
# $1: nom_sauvegarde (pour les logs)
# $2: remote_user
# $3: remote_ip
# $4: remote_port
# $5: source_path (chemin sur la machine distante)
# $6: sshfs_mount_point (point de montage SSHFS local, si utilise)
# $7: dest_main_path (chemin de la destination pour la copie complete/courante)
# $8: dest_incr_base_path (chemin de base pour les sauvegardes incrementales datees)
# $9: incremental_mode (0 pour complet, 1 pour incremental --link-dest)
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

    log_info "Demarrage de la sauvegarde distante : $nom_sauvegarde"
    log_debug "Utilisateur distant: $remote_user@$remote_ip:$remote_port"

    local target_dir_for_checks # Repertoire sur lequel verifier permissions et espace

    if [ "$incremental_mode" -eq 1 ]; then
        target_dir_for_checks="$dest_incr_base_path"
        log_debug "Destination Finale (Incrementale Datee): $new_backup_full_path"
    else
        target_dir_for_checks="$dest_main_path"
        log_debug "Destination Principale (Complete): $dest_main_path"
    fi

    if ! verifier_permissions_ecriture "$target_dir_for_checks"; then
        log_error "Pre-requis (permissions/creation du repertoire de base: $target_dir_for_checks) non satisfaits pour '$nom_sauvegarde'. Sauvegarde ignoree."
        return 1
    fi

    if ! verifier_espace_disque "$target_dir_for_checks" "$ESPACE_DISQUE_MIN_GO"; then
        log_error "Pre-requis (espace disque) non satisfaits pour '$nom_sauvegarde'. Sauvegarde ignoree."
        return 1
    fi

    local remote_source_for_rsync # Comment rsync voit la source
    local rsync_exit_code=0

    if [ "$DEFAULT_TYPE_CONNEXION_DISTANTE" -eq 0 ]; then # SSHFS
        log_info "Tentative de montage SSHFS pour '$nom_sauvegarde'..."
        # Ordre des arguments corrige: user, ip, port, remote_path, local_mount_point
        if ! monter_sshfs "$remote_user" "$remote_ip" "$remote_port" "$source_path" "$sshfs_mount_point"; then
            log_error "Echec du montage SSHFS pour '$nom_sauvegarde'. Sauvegarde distante annulee."
            return 1
        fi
        remote_source_for_rsync="${sshfs_mount_point}/"
        add_mounted_sshfs_point "$sshfs_mount_point" # Ajoute a la liste pour demontage final
    else # SSH Direct
        log_info "Connexion SSH directe pour '$nom_sauvegarde'..."
        remote_source_for_rsync="${remote_user}@${remote_ip}:${source_path}/"
    fi

    local rsync_final_options="$DEFAULT_RSYNC_OPTIONS --delete"

    if [ "$incremental_mode" -eq 1 ]; then
        mkdir -p "$new_backup_full_path" || { diagnostiquer_et_logger_erreur "Echec de la creation du repertoire de destination datee: $new_backup_full_path" $? ; return 1 ; }

        local previous_backup_dir=$(find_latest_backup_dir "$dest_incr_base_path")

        if [[ -n "$previous_backup_dir" && "$previous_backup_dir" != "$new_backup_full_path" ]]; then
            rsync_final_options+=" --link-dest=\"$previous_backup_dir\""
            log_debug "Mode incremental: Liens crees vers la sauvegarde precedente: $previous_backup_dir"
        else
            log_info "Mode incremental: Aucune sauvegarde precedente valide trouvee pour '$nom_sauvegarde'. Effectue une sauvegarde complete (premiere sauvegarde incrementale ou repertoire vide)."
        fi
        log_debug "Commande Rsync: rsync $rsync_final_options \"$remote_source_for_rsync\" \"$new_backup_full_path\""
        rsync $rsync_final_options "$remote_source_for_rsync" "$new_backup_full_path"
    else
        log_info "Mode complet: Sauvegarde complete de '$nom_sauvegarde' vers '$dest_main_path'."
        log_debug "Commande Rsync: rsync $rsync_final_options \"$remote_source_for_rsync\" \"$dest_main_path\""
        rsync $rsync_final_options "$remote_source_for_rsync" "$dest_main_path"
    fi

    rsync_exit_code=$?

    # Le demontage SSHFS est gere par le trap EXIT final, pour s'assurer que tous les points sont demontes.
    # Ceci est plus robuste que de demonter immediatement apres chaque sauvegarde.

    if [ $rsync_exit_code -eq 0 ]; then
        log_success "Sauvegarde distante '$nom_sauvegarde' terminee avec succes."
        return 0
    else
        diagnostiquer_et_logger_erreur "Echec de la sauvegarde distante '$nom_sauvegarde' (code: $rsync_exit_code)." $rsync_exit_code
        return 1
    fi
}

# --- FONCTION DE NETTOYAGE DES ANCIENNES SAUVEGARDES INCRÉMENTALES ---
# Supprime les répertoires de sauvegarde incrémentale datés selon une politique de rétention.
# Args: $1 = base_path (le repertoire de base des sauvegardes incrementales, ex: /mnt/sauvegardes/DocsEric_incr/)
# $2 = retention_quotidien_jours (nombre de jours pour les copies quotidiennes)
# $3 = retention_hebdo_semaines (nombre de semaines pour les copies hebdomadaires - les lundis)
# $4 = retention_mensuel_mois (nombre de mois pour les copies mensuelles - les 1ers du mois)
nettoyer_anciennes_sauvegardes() {
    local base_dir="$1"
    local retention_quotidien_jours="$2"
    local retention_hebdo_semaines="$3"
    local retention_mensuel_mois="$4"

    log_info "Debut du nettoyage des anciennes sauvegardes dans: $base_dir (Quotidien: ${retention_quotidien_jours}j, Hebdo: ${retention_hebdo_semaines}s, Mensuel: ${retention_mensuel_mois}m)"

    if [[ ! -d "$base_dir" ]]; then
        log_debug "Le repertoire de base '$base_dir' n'existe pas. Pas de nettoyage a effectuer."
        return 0
    fi

    # Fonction interne pour determiner si une date est un lundi
    est_lundi() {
        local date_str="$1"
        local day_of_week=$(date -d "$date_str" +%u 2>/dev/null) # %u: Lundi=1, Dimanche=7
        [ "$day_of_week" -eq 1 ]
    }

    # Fonction interne pour determiner si une date est le premier jour du mois
    est_premier_du_mois() {
        local date_str="$1"
        local day_of_month=$(date -d "$date_str" +%d 2>/dev/null) # %d: jour du mois (01-31)
        [ "$day_of_month" -eq 01 ]
    }

    local current_timestamp=$(date +%s)
    local one_day_sec=$((24*60*60))
    local delete_count=0

    # Collecter tous les repertoires de sauvegarde datee
    # Le `-mindepth 1 -maxdepth 1` s'assure que seuls les sous-repertoires directs sont pris.
    find "$base_dir" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d $'\0' dir; do
        local dir_name=$(basename "$dir")
        # Ne traiter que les repertoires au format AAAA-MM-JJ
        if [[ "$dir_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            local dir_timestamp=$(date -d "$dir_name" +%s 2>/dev/null)
            if [[ -z "$dir_timestamp" ]]; then
                log_warning "Nom de repertoire '$dir_name' non valide pour une date. Ignore."
                continue
            fi

            local age_days=$(( (current_timestamp - dir_timestamp) / one_day_sec ))
            local to_delete=0

            # Logique de retention: conserver les plus recents, puis certains hebdomadaires et mensuels.
            if (( age_days > retention_quotidien_jours )); then
                to_delete=1 # Marque pour suppression par defaut

                if [ "$retention_hebdo_semaines" -gt 0 ] && est_lundi "$dir_name"; then
                    local age_weeks=$(( age_days / 7 ))
                    if (( age_weeks <= retention_hebdo_semaines )); then
                        to_delete=0 # Garde si c'est un lundi dans la fenetre hebdo
                    fi
                fi

                if [ "$retention_mensuel_mois" -gt 0 ] && est_premier_du_mois "$dir_name"; then
                    # Calcul approx. du mois, plus complexe mais suffisant pour la logique
                    local current_month=$(date +%Y%m)
                    local dir_month=$(date -d "$dir_name" +%Y%m)
                    local age_months=$(( ( ( $(date +%Y) - $(date -d "$dir_name" +%Y) ) * 12 ) + ( $(date +%m) - $(date -d "$dir_name" +%m) ) ))
                    if (( age_months <= retention_mensuel_mois )); then
                        to_delete=0 # Garde si c'est un 1er du mois dans la fenetre mensuelle
                    fi
                fi
            fi

            if [ "$to_delete" -eq 1 ]; then
                log_info "Suppression de l'ancienne sauvegarde: $dir (age: ${age_days} jours)"
                if rm -rf "$dir"; then
                    log_success "Supprime: $dir"
                    delete_count=$((delete_count + 1))
                else
                    diagnostiquer_et_logger_erreur "Echec de la suppression de: $dir. Verifiez les permissions." $?
                fi
            else
                log_debug "Garde la sauvegarde: $dir (age: ${age_days} jours)"
            fi
        fi
    done
    log_info "Nettoyage termine dans $base_dir. Total supprime: $delete_count repertoires."
}


# --- GESTION DES ARGUMENTS EN LIGNE DE COMMANDE ---
# Permet de specifier quelles sauvegardes executer ou 'all' pour toutes.
declare -a selections # Tableau pour stocker les selections

# Si des arguments sont passes, les utiliser comme selections
if [ "$#" -gt 0 ]; then
    if [[ "$1" == "all" ]]; then
        log_info "Option 'all' detectee. Toutes les sauvegardes definies seront executees."
        # Les selections seront generees a partir des cas du 'case' plus bas.
        selections=("docs_eric" "docs_fanou" "docs_communs" "projets" "photos" "docs_portable" "musiques") # Liste explicite pour 'all'
    else
        log_info "Options specifiques detectees: $*"
        selections=("$@")
    fi
else
    log_info "Aucune option specifique fournie. Utilisation des selections par defaut de config.sh: $DEFAULT_SELECTIONS_SAUVEGARDES"
    # Convertir la chaine DEFAULT_SELECTIONS_SAUVEGARDES en tableau
    read -r -a selections <<< "$DEFAULT_SELECTIONS_SAUVEGARDES"
fi

# --- BOUCLE PRINCIPALE DES SAUVEGARDES ---
# Initialisation des compteurs de statut
sauvegardes_reussies=0
sauvegardes_echouees=0
nombre_sauvegardes=0

log_info "=== DEBUT DES SAUVEGARDES ==="

# Verifie le disque de sauvegarde au debut de l'execution
# Ceci est critique pour la securite. Si l'UUID ne correspond pas, le script s'arrete.
verifier_disque_de_sauvegarde || exit 1 # Arret fatal si le disque n'est pas bon

# Boucle a travers les selections et execute les sauvegardes correspondantes.
for i in "${selections[@]}"; do
    nombre_sauvegardes=$((nombre_sauvegardes + 1))
    case "$i" in
        # Sauvegarde des Documents Eric (Locale)
        "1"|"docs_eric")
            log_info "Traitement de la sauvegarde : Documents Eric (Locale)"
            if executer_sauvegarde_locale \
                "Documents Eric" \
                "$SOURCE_LOCAL_DOCS_ERIC" \
                "$DEST_MAIN_DOCS_ERIC" \
                "$DEST_INCR_BASE_DOCS_ERIC" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                # Nettoyage seulement si la sauvegarde est incrementale et que la retention est active
                if [ "$DEFAULT_MODE_INCREMENTAL" -eq 1 ]; then
                    if [ "$JOURS_RETENTION_DOCS_ERIC_QUOTIDIEN" -gt 0 ] || \
                       [ "$JOURS_RETENTION_DOCS_ERIC_HEBDO" -gt 0 ] || \
                       [ "$JOURS_RETENTION_DOCS_ERIC_MENSUEL" -gt 0 ]; then
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
        # Sauvegarde des Documents Fanou (Locale)
        "2"|"docs_fanou")
            log_info "Traitement de la sauvegarde : Documents Fanou (Locale)"
            if executer_sauvegarde_locale \
                "Documents Fanou" \
                "$SOURCE_LOCAL_DOCS_FANOU" \
                "$DEST_MAIN_DOCS_FANOU" \
                "$DEST_INCR_BASE_DOCS_FANOU" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [ "$DEFAULT_MODE_INCREMENTAL" -eq 1 ]; then
                    if [ "$JOURS_RETENTION_DOCS_FANOU_QUOTIDIEN" -gt 0 ] || \
                       [ "$JOURS_RETENTION_DOCS_FANOU_HEBDO" -gt 0 ] || \
                       [ "$JOURS_RETENTION_DOCS_FANOU_MENSUEL" -gt 0 ]; then
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
        # Sauvegarde des Documents Communs (Locale)
        "4"|"docs_communs")
            log_info "Traitement de la sauvegarde : Documents Communs (Locale)"
            if executer_sauvegarde_locale \
                "Documents Communs" \
                "$SOURCE_LOCAL_DOCS_COMMUNS" \
                "$DEST_MAIN_DOCS_COMMUNS" \
                "$DEST_INCR_BASE_DOCS_COMMUNS" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [ "$DEFAULT_MODE_INCREMENTAL" -eq 1 ]; then
                    if [ "$JOURS_RETENTION_DOCS_COMMUNS_QUOTIDIEN" -gt 0 ] || \
                       [ "$JOURS_RETENTION_DOCS_COMMUNS_HEBDO" -gt 0 ] || \
                       [ "$JOURS_RETENTION_DOCS_COMMUNS_MENSUEL" -gt 0 ]; then
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
        # Sauvegarde des Projets Serveur (Distante)
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
                if [ "$DEFAULT_MODE_INCREMENTAL" -eq 1 ]; then
                    if [ "$JOURS_RETENTION_PROJETS_QUOTIDIEN" -gt 0 ] || \
                       [ "$JOURS_RETENTION_PROJETS_HEBDO" -gt 0 ] || \
                       [ "$JOURS_RETENTION_PROJETS_MENSUEL" -gt 0 ]; then
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
        # Sauvegarde des Photos VM (Distante)
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
                if [ "$DEFAULT_MODE_INCREMENTAL" -eq 1 ]; then
                    if [ "$JOURS_RETENTION_PHOTOS_QUOTIDIEN" -gt 0 ] || \
                       [ "$JOURS_RETENTION_PHOTOS_HEBDO" -gt 0 ] || \
                       [ "$JOURS_RETENTION_PHOTOS_MENSUEL" -gt 0 ]; then
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
        # Sauvegarde des Documents Portable (Distante)
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
                if [ "$DEFAULT_MODE_INCREMENTAL" -eq 1 ]; then
                    if [ "$JOURS_RETENTION_DOCS_PORTABLE_QUOTIDIEN" -gt 0 ] || \
                       [ "$JOURS_RETENTION_DOCS_PORTABLE_HEBDO" -gt 0 ] || \
                       [ "$JOURS_RETENTION_DOCS_PORTABLE_MENSUEL" -gt 0 ]; then
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
        # Sauvegarde des Musiques (Locale)
        "64"|"musiques")
            log_info "Traitement de la sauvegarde : Musiques (Locale)"
            if executer_sauvegarde_locale \
                "Musiques" \
                "$SOURCE_LOCAL_MUSIQUES" \
                "$DEST_MAIN_MUSIQUES" \
                "$DEST_INCR_BASE_MUSIQUES" \
                "$DEFAULT_MODE_INCREMENTAL"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                if [ "$DEFAULT_MODE_INCREMENTAL" -eq 1 ]; then
                    if [ "$JOURS_RETENTION_MUSIQUES_QUOTIDIEN" -gt 0 ] || \
                       [ "$JOURS_RETENTION_MUSIQUES_HEBDO" -gt 0 ] || \
                       [ "$JOURS_RETENTION_MUSIQUES_MENSUEL" -gt 0 ]; then
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
            log_warning "Valeur de selection inconnue ignoree: $i"
            ;;
    esac
done

# --- Resumé Final ---
# Ces sections sont correctes pour le logging et la gestion de la sortie.
log_info "=== FIN DES SAUVEGARDES ==="
log_info "Resume :"
log_info "  - Sauvegardes reussies: $sauvegardes_reussies"
log_info "  - Sauvegardes echouees: $sauvegardes_echouees"
log_info "  - Total des sauvegardes traitees: $nombre_sauvegardes"

# Liberation du verrou a la fin du script
# La commande 'exec 200>' ferme le descripteur et libere le verrou.
# Il n'y a pas de fonction specifique 'liberer_verrou' a appeler.
# Le verrou est automatiquement libere lorsque le descripteur de fichier 200 est ferme.
# En cas d'arret brutal (exit), le verrou est egalement libere.

# Demontage de tous les SSHFS a la fin du script (via trap EXIT)
# Le trap EXIT assure que cette fonction est appelee meme en cas d'erreur ou de sortie anticipee.

# Sortie avec un code d'etat approprie
if [ "$sauvegardes_echouees" -eq 0 ] && [ "$nombre_sauvegardes" -gt 0 ]; then
    log_success "Toutes les sauvegardes demandees ont reussi."
    if [ -n "$EMAIL_NOTIFICATION" ]; then
        envoyer_rapport_final
    fi
    exit 0
else
    log_error "Des erreurs sont survenues lors de certaines sauvegardes."
    if [ -n "$EMAIL_NOTIFICATION" ]; then
        envoyer_rapport_final
    fi
    exit 1
fi
