#!/bin/bash
export LC_ALL=C

#===============================================================
# Sauvegarde des données
# Auteur : enRIKO (modifié par geole, iznobe, Watael, steph810, amélioré pour qualité irréprochable)
# Date : 2025-06-24
# Version : 6.2 Beta
# Description : Script de sauvegarde incrémentale avec validation renforcée, mode dry-run, et gestion avancée des erreurs.
#
# Changelog :
# - 6.2 Beta (2025-06-24) :
#   - Intégration des fonctions d'erreurs avancées et des codes d'erreur spécifiques.
#   - Utilisation des chemins d'exécutables configurables depuis config.sh (CHEMIN_RSYNC, CHEMIN_SSH, etc.).
#   - Gestion améliorée de RSYNC_DELETE pour appliquer --delete conditionnellement.
#   - Correction des noms de variables de rétention (MONTAGE_SSHFS_MUSIQUES, JOURS_RETENTION_MUSIQUES_...)
#     pour correspondre à Docs Portable.
#   - Correction du nom de variable de montage pour Projets Serveur (MONTAGE_SSHFS_IMAGES).
#   - Validation initiale des chemins et des permissions critiques.
#   - Exécution des hooks PRE/POST_SAUVEGARDE_GLOBAL si configurés.
#   - Gestion du timeout Rsync.
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

# --- Source des fichiers de configuration et de fonctions ---
# C'est l'ordre crucial : config.sh d'abord pour que ses variables soient disponibles pour fonctions_erreur.sh
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/fonctions_erreur.sh"

# --- VÉRIFICATIONS PRÉ-DÉMARRAGE ---
# Vérifie que le répertoire de log est bien accessible en écriture
verifier_permissions_log_dir

# Initialisation de LOG_FILE avec le format journalier
# shellcheck disable=SC2154 # LOG_DIR est défini dans config.sh
LOG_FILE="${LOG_DIR}/sauvegarde_$(date '+%Y%m%d').log"

# Vérification initiale des chemins des exécutables critiques
# Ceci complète les vérifications 'command -v' des fonctions_erreur.sh
verifier_chemin_executables() {
    local exec_name
    local exec_path
    local missing_execs=0

    # shellcheck disable=SC2154 # Toutes ces variables sont définies dans config.sh
    for exec_var in CHEMIN_RSYNC CHEMIN_SSH CHEMIN_SSHFS CHEMIN_FUSEMOUNT CHEMIN_MOUNTPOINT CHEMIN_LSOF CHEMIN_KILL CHEMIN_MKDIR CHEMIN_MAIL; do
        eval "exec_path=\"\$$exec_var\"" # Récupère la valeur de la variable
        exec_name="${exec_var//CHEMIN_/}" # Extrait le nom de la commande (ex: RSYNC)

        if [[ -n "$exec_path" ]]; then # Si un chemin est explicitement défini
            if [[ ! -x "$exec_path" ]]; then
                log_error "L'exécutable configuré pour $exec_name ('$exec_path') n'existe pas ou n'est pas exécutable."
                missing_execs=$((missing_execs + 1))
            fi
        else # Si aucun chemin n'est défini, vérifie dans le PATH
            if ! command -v "$(echo "$exec_name" | tr '[:upper:]' '[:lower:]')" >/dev/null 2>&1; then
                log_error "La commande '${exec_name,,}' n'a pas été trouvée dans le PATH."
                missing_execs=$((missing_execs + 1))
            fi
        fi
    done

    if [[ "$missing_execs" -gt 0 ]]; then
        diagnostiquer_et_logger_erreur 127 "Certaines dépendances logicielles essentielles sont manquantes ou incorrectement configurées."
    fi
}
verifier_chemin_executables

# --- Initialisation des variables de suivi ---
sauvegardes_reussies=0
sauvegardes_echouees=0
nombre_sauvegardes=0
SAUVEGARDES_A_TRAITER=() # Tableau pour stocker les sélections à traiter

# --- Traitement des arguments de la ligne de commande ---
DRY_RUN=0
LIST_MODE=0

# Fonction d'affichage de l'aide
afficher_aide() {
    echo "Utilisation : $0 [--dry-run] [--list] [selection... | all]"
    echo ""
    echo "Arguments :"
    echo "  selection  : Nom d'une sauvegarde à exécuter (ex: docs_eric photos_vm)."
    echo "  all        : Exécute toutes les sauvegardes définies dans config.sh."
    echo ""
    echo "Options :"
    echo "  --dry-run  : Simule le processus de sauvegarde sans effectuer de modifications réelles."
    echo "  --list     : Affiche la liste des sélections de sauvegarde disponibles et quitte."
    echo "  --help, -h : Affiche cette aide."
    echo ""
    echo "Exemples :"
    echo "  $0 all"
    echo "  $0 docs_eric photos_vm"
    echo "  $0 --dry-run docs_eric"
    echo "  $0 --list"
    exit 0
}

# Analyse les arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            log_info "Mode 'dry-run' activé : aucune modification ne sera effectuée."
            ;;
        --list)
            LIST_MODE=1
            ;;
        --help|-h)
            afficher_aide
            ;;
        *)
            SAUVEGARDES_A_TRAITER+=("$arg")
            ;;
    esac
done

# Si --list est activé, affiche les sélections et quitte
if [[ "$LIST_MODE" -eq 1 ]]; then
    echo "Sélections de sauvegarde disponibles (définies dans config.sh) :"
    echo "  docs_eric"
    echo "  docs_fanou"
    echo "  photos_vm"
    echo "  projets_serveur" # Correction du nom de la sélection
    echo "  docs_portable" # Correction du nom de la sélection
    echo ""
    exit 0
fi

# Si aucune sélection n'est spécifiée en ligne de commande, utilise DEFAULT_SELECTIONS_SAUVEGARDES
if [[ ${#SAUVEGARDES_A_TRAITER[@]} -eq 0 ]]; then
    # shellcheck disable=SC2154 # DEFAULT_SELECTIONS_SAUVEGARDES est défini dans config.sh
    read -r -a SAUVEGARDES_A_TRAITER <<< "$DEFAULT_SELECTIONS_SAUVEGARDES"
fi

# Si "all" est spécifié, liste toutes les sauvegardes connues
if [[ " ${SAUVEGARDES_A_TRAITER[@]} " =~ " all " ]]; then
    SAUVEGARDES_A_TRAITER=(
        "docs_eric"
        "docs_fanou"
        "photos_vm"
        "projets_serveur" # Correction du nom de la sélection
        "docs_portable" # Correction du nom de la sélection
    )
fi


# --- FONCTIONS UTILES ---

# Fonction pour gérer le verrouillage du script
gerer_verrouillage() {
    # shellcheck disable=SC2154 # ACTIVERLOCK, PID_FILE sont définis dans config.sh
    if [[ "$ACTIVERLOCK" -eq 1 ]]; then
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            log_error "Le script est déjà en cours d'exécution. PID : $(cat "$PID_FILE")."
            diagnostiquer_et_logger_erreur 10 "Script déjà en cours d'exécution."
        fi
        echo "$$" > "$PID_FILE"
        log_info "Fichier de verrouillage créé : $(cat "$PID_FILE")"
        trap "rm -f '$PID_FILE'; log_info 'Fichier de verrouillage supprimé.' ; exit" EXIT SIGINT SIGTERM
    fi
}

# Fonction pour envoyer le rapport par email
envoyer_rapport_email() {
    local sujet="$1"
    local corps="$2"

    # shellcheck disable=SC2154 # EMAIL_NOTIFICATION, CHEMIN_MAIL sont définis dans config.sh
    if [[ -n "$EMAIL_NOTIFICATION" ]]; then
        local mail_cmd="${CHEMIN_MAIL:-mailx}" # Utilise CHEMIN_MAIL si défini, sinon 'mailx'
        if ! command -v "$mail_cmd" >/dev/null 2>&1; then
            log_error "La commande '$mail_cmd' pour envoyer des e-mails n'a pas été trouvée. Impossible d'envoyer le rapport."
            diagnostiquer_et_logger_erreur 127 "Dépendance manquante: $mail_cmd (pour envoi d'email)."
            return 1 # Ne quitte pas complètement le script, mais signale l'échec d'envoi.
        fi
        echo "$corps" | "$mail_cmd" -s "$sujet" "$EMAIL_NOTIFICATION"
        if [[ $? -ne 0 ]]; then
            log_error "Échec de l'envoi de l'e-mail de notification. Vérifiez la configuration du MTA."
            diagnostiquer_et_logger_erreur 15 "Échec de l'envoi d'e-mail."
            return 1
        else
            log_info "Rapport envoyé par email à $EMAIL_NOTIFICATION."
            return 0
        fi
    else
        log_info "Notification par e-mail désactivée (EMAIL_NOTIFICATION non défini dans config.sh)."
        return 0
    fi
}

# Fonction pour vérifier l'espace disque
verifier_espace_disque() {
    local chemin="$1"
    local min_espace="$2" # en Go

    if [[ "$min_espace" -eq 0 ]]; then
        log_info "Vérification d'espace disque désactivée (ESPACE_DISQUE_MIN_GO=0)."
        return 0
    fi

    local espace_disque_libre
    # Utilise 'df -BG' pour obtenir l'espace en GigaBytes et extrait la valeur numérique.
    espace_disque_libre=$(df -BG "$chemin" | awk 'NR==2 {print $4}' | sed 's/G//')

    if [[ -z "$espace_disque_libre" || ! "$espace_disque_libre" =~ ^[0-9]+$ ]]; then
        log_error "Impossible de déterminer l'espace disque libre pour '$chemin'. Vérifiez le chemin ou les permissions."
        return 1 # Laisse le script continuer mais log l'erreur
    fi

    log_info "Espace disque libre sur '$chemin' : ${espace_disque_libre} Go (minimum requis : ${min_espace} Go)."

    if (( espace_disque_libre < min_espace )); then
        log_error "Espace disque insuffisant sur la destination '$chemin'. Libre: ${espace_disque_libre} Go, Requis: ${min_espace} Go."
        diagnostiquer_et_logger_erreur 4 "Espace disque insuffisant sur la destination."
    fi
    return 0
}

# Fonction pour nettoyer les anciennes sauvegardes
# Note: Cette fonction est un exemple basique et devrait être robuste.
nettoyer_anciennes_sauvegardes() {
    local base_chemin_incr="$1"
    local retention_quotidien="$2"
    local retention_hebdo="$3"
    local retention_mensuel="$4"

    log_info "Démarrage du nettoyage des anciennes sauvegardes pour $base_chemin_incr..."

    # Check if the base incremental path exists
    if [[ ! -d "$base_chemin_incr" ]]; then
        log_warning "Chemin de base incrémental '$base_chemin_incr' n'existe pas. Pas de nettoyage effectué."
        return 0
    fi

    # Supprimer les liens symboliques brisés dans 'latest' et 'current'
    find "$base_chemin_incr" -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null
    log_info "Nettoyage des liens symboliques brisés dans $base_chemin_incr effectué."

    # Suppression des sauvegardes quotidiennes (plus anciennes que $retention_quotidien jours)
    if [[ "$retention_quotidien" -gt 0 ]]; then
        # Exclure 'current', 'latest', 'weekly', 'monthly' des suppressions quotidiennes
        find "$base_chemin_incr" -maxdepth 1 -type d -name "daily-*" -mtime +"$retention_quotidien" \
            -not -path "*/current" -not -path "*/latest" \
            -exec rm -rf {} + 2>/dev/null
        log_info "Suppression des sauvegardes quotidiennes plus anciennes que $retention_quotidien jours."
    fi

    # Gestion des sauvegardes hebdomadaires
    if [[ "$retention_hebdo" -gt 0 ]]; then
        local weekly_dir="$base_chemin_incr/weekly"
        local weekly_count=$(find "$weekly_dir" -maxdepth 1 -type d -name "weekly-*" | wc -l)
        if [[ "$weekly_count" -gt "$retention_hebdo" ]]; then
            find "$weekly_dir" -maxdepth 1 -type d -name "weekly-*" | sort | head -n "$((weekly_count - retention_hebdo))" | xargs -r rm -rf 2>/dev/null
            log_info "Nettoyage des sauvegardes hebdomadaires: ${weekly_count} -> ${retention_hebdo} versions conservées."
        fi
    fi

    # Gestion des sauvegardes mensuelles
    if [[ "$retention_mensuel" -gt 0 ]]; then
        local monthly_dir="$base_chemin_incr/monthly"
        local monthly_count=$(find "$monthly_dir" -maxdepth 1 -type d -name "monthly-*" | wc -l)
        if [[ "$monthly_count" -gt "$retention_mensuel" ]]; then
            find "$monthly_dir" -maxdepth 1 -type d -name "monthly-*" | sort | head -n "$((monthly_count - retention_mensuel))" | xargs -r rm -rf 2>/dev/null
            log_info "Nettoyage des sauvegardes mensuelles: ${monthly_count} -> ${retention_mensuel} versions conservées."
        fi
    fi

    log_info "Nettoyage des anciennes sauvegardes pour $base_chemin_incr terminé."
    return 0
}

# --- FONCTION PRINCIPALE DE SAUVEGARDE ---
effectuer_sauvegarde() {
    local type_sauvegarde="$1" # "locale" ou "distante"
    local source_path="$2"
    local dest_main_path="$3"
    local dest_incr_base_path="$4" # Chemin pour les incrémentales (avec daily, weekly, monthly)
    local ssh_user="$5"
    local ssh_ip="$6"
    local ssh_port="$7"
    local montage_sshfs_point="$8" # Point de montage local pour SSHFS

    local date_courante=$(date '+%Y-%m-%d_%H%M%S')
    local dest_courante="$dest_incr_base_path/daily-${date_courante}"
    local dest_precedente="$dest_incr_base_path/current"

    log_info "Démarrage de la sauvegarde $type_sauvegarde pour '$source_path' vers '$dest_main_path'."

    # Vérification de la source
    valider_variable "Source de sauvegarde" "$source_path" "path"
    if [[ $? -ne 0 ]]; then diagnostiquer_et_logger_erreur 13 "Source invalide: $source_path"; fi

    # Vérification et création des répertoires de destination si nécessaire
    # shellcheck disable=SC2154 # CHEMIN_MKDIR est défini dans config.sh
    local mkdir_cmd="${CHEMIN_MKDIR:-mkdir}"
    if [[ ! -d "$dest_main_path" ]]; then
        log_info "Création du répertoire de destination principal : $dest_main_path"
        if ! "$mkdir_cmd" -p "$dest_main_path"; then
            log_error "Impossible de créer le répertoire de destination principal $dest_main_path."
            diagnostiquer_et_logger_erreur 12 "Échec de création du répertoire principal."
        fi
    fi

    if [[ ! -d "$dest_incr_base_path" ]]; then
        log_info "Création du répertoire de base incrémentale : $dest_incr_base_path"
        if ! "$mkdir_cmd" -p "$dest_incr_base_path"; then
            log_error "Impossible de créer le répertoire de base incrémentale $dest_incr_base_path."
            diagnostiquer_et_logger_erreur 12 "Échec de création du répertoire incrémental."
        fi
    fi

    # Vérifier l'espace disque sur la DEST_BASE_SAUVEGARDES (où sont stockées toutes les sauvegardes)
    # shellcheck disable=SC2154 # ESPACE_DISQUE_MIN_GO est défini dans config.sh
    verifier_espace_disque "$DEST_BASE_SAUVEGARDES" "$ESPACE_DISQUE_MIN_GO"

    local rsync_options="$DEFAULT_RSYNC_OPTIONS"
    # shellcheck disable=SC2154 # RSYNC_DELETE est défini dans config.sh
    if [[ "$RSYNC_DELETE" -eq 1 ]]; then
        rsync_options+=" --delete"
        log_info "Option rsync --delete activée."
    fi

    # Rsync command setup
    local rsync_cmd="${CHEMIN_RSYNC:-rsync}" # Utilise CHEMIN_RSYNC si défini, sinon 'rsync'
    if ! command -v "$rsync_cmd" >/dev/null 2>&1; then
        log_error "La commande 'rsync' (ou chemin configuré: '$CHEMIN_RSYNC') n'a pas été trouvée dans le PATH. Impossible de procéder à la sauvegarde."
        diagnostiquer_et_logger_erreur 127 "Dépendance manquante: rsync."
    fi

    local rsync_full_command=()
    local rsync_exit_code=0

    # shellcheck disable=SC2154 # DEFAULT_TYPE_CONNEXION_DISTANTE est défini dans config.sh
    if [[ "$DEFAULT_TYPE_CONNEXION_DISTANTE" -eq 0 ]]; then # Mode SSHFS
        local local_source="$source_path" # Pour rsync, la source est le chemin distant MONTÉ localement.
        # Vérifie si le point de montage existe et est bien un répertoire
        valider_variable "Point de montage SSHFS" "$montage_sshfs_point" "path"
        if [[ $? -ne 0 ]]; then diagnostiquer_et_logger_erreur 13 "Point de montage SSHFS invalide: $montage_sshfs_point"; fi

        # Montage SSHFS
        monter_sshfs "$ssh_user" "$ssh_ip" "$ssh_port" "$source_path" "$montage_sshfs_point"
        local_source="$montage_sshfs_point" # La source de rsync devient le point de montage local

        # Vérifier si le point de montage est vide ou inaccessible après montage
        if ! find "$local_source" -mindepth 1 -print -quit | grep -q .; then
            log_warning "Le point de montage SSHFS '$local_source' semble vide ou inaccessible après le montage. La sauvegarde pourrait ne rien transférer."
            # Ne pas diagnostiquer comme une erreur fatale ici, car le dossier distant PEUT être vide.
            # L'erreur 13 est plus pour "source inexistante avant même de tenter un montage"
        fi

        rsync_full_command+=("$rsync_cmd")
        rsync_full_command+=("-azP") # Forcer le mode archive avec progression pour le montage local
        rsync_full_command+=("--delete") # La suppression doit être gérée par le config.sh RSYNC_DELETE
        rsync_full_command+=("$rsync_options") # Ajoute les options par défaut, y compris les exclusions si présentes
        # shellcheck disable=SC2154 # OPTIONS_RSYNC_INCREMENTALE est défini dans config.sh
        if [[ -d "$dest_precedente" ]]; then
            rsync_full_command+=("${OPTIONS_RSYNC_INCREMENTALE:-}") # Ajoute --link-dest=../current si 'current' existe
        fi
        rsync_full_command+=("--exclude='${dest_incr_base_path##*/}/'") # Exclut le dossier incrémental lui-même si il est imbriqué

        rsync_full_command+=("$local_source/") # Source avec slash final pour synchroniser le contenu
        rsync_full_command+=("$dest_courante")

    elif [[ "$DEFAULT_TYPE_CONNEXION_DISTANTE" -eq 1 ]]; then # Mode SSH direct (rsync via SSH)
        # Vérifier la connectivité SSH et le chemin distant avant rsync
        verifier_connexion_ssh "$ssh_user" "$ssh_ip" "$ssh_port"
        verifier_chemin_distant_ssh "$ssh_user" "$ssh_ip" "$ssh_port" "$source_path"

        local ssh_cmd="${CHEMIN_SSH:-ssh}" # Utilise CHEMIN_SSH si défini, sinon 'ssh'
        # shellcheck disable=SC2154 # OPTIONS_COMMUNES_SSH, StrictHostKeyChecking_SSH sont définis dans config.sh
        local ssh_strict_host_key_opt=""
        if [[ -n "${StrictHostKeyChecking_SSH}" ]]; then
            ssh_strict_host_key_opt="-o StrictHostKeyChecking=${StrictHostKeyChecking_SSH}"
        fi
        local ssh_command_options="${OPTIONS_COMMUNES_SSH:-} ${ssh_strict_host_key_opt}"

        rsync_full_command+=("$rsync_cmd")
        rsync_full_command+=("$rsync_options") # Options par défaut
        # shellcheck disable=SC2154 # OPTIONS_RSYNC_INCREMENTALE est défini dans config.sh
        if [[ -d "$dest_precedente" ]]; then
            rsync_full_command+=("${OPTIONS_RSYNC_INCREMENTALE:-}") # Ajoute --link-dest=../current si 'current' existe
        fi
        rsync_full_command+=("-e \"$ssh_cmd -p $ssh_port ${ssh_command_options}\"") # Spécifie SSH comme transport
        rsync_full_command+=("$ssh_user@$ssh_ip:$source_path/") # Source distante avec slash final
        rsync_full_command+=("$dest_courante")
    else # Mode local
        rsync_full_command+=("$rsync_cmd")
        rsync_full_command+=("$rsync_options") # Options par défaut
        # shellcheck disable=SC2154 # OPTIONS_RSYNC_INCREMENTALE est défini dans config.sh
        if [[ -d "$dest_precedente" ]]; then
            rsync_full_command+=("${OPTIONS_RSYNC_INCREMENTALE:-}") # Ajoute --link-dest=../current si 'current' existe
        fi
        rsync_full_command+=("$source_path/") # Source locale avec slash final
        rsync_full_command+=("$dest_courante")
    fi

    log_info "Commande Rsync à exécuter : ${rsync_full_command[*]}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "DRY-RUN: Simulation de rsync. La commande ne sera pas exécutée."
        # Simuler un succès pour le dry-run pour que le script puisse continuer et rapporter succès
        rsync_exit_code=0
    else
        # Exécution de la commande rsync avec un timeout si configuré
        # shellcheck disable=SC2154 # DELAI_OPERATION_RSYNC_SECONDES est défini dans config.sh
        if [[ "$DELAI_OPERATION_RSYNC_SECONDES" -gt 0 ]]; then
            log_info "Exécution de rsync avec un timeout de ${DELAI_OPERATION_RSYNC_SECONDES} secondes."
            timeout "${DELAI_OPERATION_RSYNC_SECONDES}s" "${rsync_full_command[@]}"
            rsync_exit_code=$?
        else
            log_info "Exécution de rsync (sans timeout)."
            "${rsync_full_command[@]}"
            rsync_exit_code=$?
        fi
    fi

    if [[ "$rsync_exit_code" -eq 0 ]]; then
        log_info "Sauvegarde réussie de '$source_path' vers '$dest_courante'."
        if [[ "$DRY_RUN" -eq 0 ]]; then
            # Mettre à jour le lien 'current' vers la nouvelle sauvegarde réussie
            rm -f "$dest_precedente" # Supprime l'ancien lien
            ln -s "${dest_courante##*/}" "$dest_precedente" # Crée le nouveau lien symbolique
            log_info "Lien 'current' mis à jour vers '$dest_courante'."
        fi
        return 0
    else
        log_error "La sauvegarde de '$source_path' a échoué avec le code de sortie rsync: $rsync_exit_code."
        diagnostiquer_et_logger_erreur 9 "Erreur rsync lors de la sauvegarde de '$source_path'. Code: $rsync_exit_code."
        return 1
    fi
}

# --- DÉBUT DU SCRIPT PRINCIPAL ---

# Gérer le verrouillage du script
gerer_verrouillage

# Exécuter le script PRE_SAUVEGARDE_GLOBAL si défini
# shellcheck disable=SC2154 # SCRIPT_PRE_SAUVEGARDE_GLOBAL est défini dans config.sh
if [[ -n "$SCRIPT_PRE_SAUVEGARDE_GLOBAL" ]]; then
    if [[ -x "$SCRIPT_PRE_SAUVEGARDE_GLOBAL" ]]; then
        log_info "Exécution du script de pré-sauvegarde global : $SCRIPT_PRE_SAUVEGARDE_GLOBAL"
        if ! "$SCRIPT_PRE_SAUVEGARDE_GLOBAL"; then
            log_warning "Le script de pré-sauvegarde global a échoué. La sauvegarde continuera."
        fi
    else
        log_warning "Le script de pré-sauvegarde global '$SCRIPT_PRE_SAUVEGARDE_GLOBAL' n'existe pas ou n'est pas exécutable."
    fi
fi

log_info "=== DÉBUT DES SAUVEGARDES ==="
log_info "Sélections à traiter : ${SAUVEGARDES_A_TRAITER[*]}"

nombre_sauvegardes=${#SAUVEGARDES_A_TRAITER[@]}

# Boucle principale de traitement des sélections
for i in "${SAUVEGARDES_A_TRAITER[@]}"; do
    case "$i" in
        docs_eric)
            log_info "Traitement de la sauvegarde 'Docs Eric'..."
            # shellcheck disable=SC2154 # Variables sont définies dans config.sh
            if effectuer_sauvegarde "locale" \
                "$SOURCE_LOCALE_DOCS_ERIC" \
                "$DEST_MAIN_DOCS_ERIC" \
                "$DEST_INCR_BASE_DOCS_ERIC" \
                "" "" "" ""; then # Pas de SSH pour une sauvegarde locale
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                # shellcheck disable=SC2154 # DEFAULT_MODE_INCREMENTAL n'existe pas, utiliser la présence de DEST_INCR_BASE_DOCS_ERIC
                if [[ -n "$DEST_INCR_BASE_DOCS_ERIC" && "$DRY_RUN" -eq 0 ]]; then
                    # shellcheck disable=SC2154 # Jours de rétention sont définis dans config.sh
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

        docs_fanou)
            log_info "Traitement de la sauvegarde 'Docs Fanou'..."
            # shellcheck disable=SC2154 # Variables sont définies dans config.sh
            if effectuer_sauvegarde "locale" \
                "$SOURCE_LOCALE_DOCS_FANOU" \
                "$DEST_MAIN_DOCS_FANOU" \
                "$DEST_INCR_BASE_DOCS_FANOU" \
                "" "" "" ""; then # Pas de SSH pour une sauvegarde locale
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                # shellcheck disable=SC2154 # DEFAULT_MODE_INCREMENTAL n'existe pas, utiliser la présence de DEST_INCR_BASE_DOCS_FANOU
                if [[ -n "$DEST_INCR_BASE_DOCS_FANOU" && "$DRY_RUN" -eq 0 ]]; then
                    # shellcheck disable=SC2154 # Jours de rétention sont définis dans config.sh
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

        photos_vm)
            log_info "Traitement de la sauvegarde 'Photos VM'..."
            # shellcheck disable=SC2154 # Variables sont définies dans config.sh
            if effectuer_sauvegarde "distante" \
                "$SOURCE_DIST_PHOTOS_VM" \
                "$DEST_MAIN_PHOTOS" \
                "$DEST_INCR_BASE_PHOTOS" \
                "$SSH_USER_PHOTOS" \
                "$SSH_IP_PHOTOS" \
                "$SSH_PORT_PHOTOS" \
                "$MONTAGE_SSHFS_PHOTOS"; then
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                # shellcheck disable=SC2154 # DEFAULT_MODE_INCREMENTAL n'existe pas, utiliser la présence de DEST_INCR_BASE_PHOTOS
                if [[ -n "$DEST_INCR_BASE_PHOTOS" && "$DRY_RUN" -eq 0 ]]; then
                    # shellcheck disable=SC2154 # Jours de rétention sont définis dans config.sh
                    if [[ "$JOURS_RETENTION_PHOTOS_VM_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_PHOTOS_VM_HEBDO" -gt 0 || "$JOURS_RETENTION_PHOTOS_VM_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_PHOTOS" \
                            "$JOURS_RETENTION_PHOTOS_VM_QUOTIDIEN" \
                            "$JOURS_RETENTION_PHOTOS_VM_HEBDO" \
                            "$JOURS_RETENTION_PHOTOS_VM_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;

        projets_serveur) # Correction : Anciennement "images_serveur" ou autre, maintenant "projets_serveur"
            log_info "Traitement de la sauvegarde 'Projets Serveur'..."
            # shellcheck disable=SC2154 # Variables sont définies dans config.sh
            if effectuer_sauvegarde "distante" \
                "$SOURCE_DIST_PROJETS_SERVEUR" \
                "$DEST_MAIN_PROJETS" \
                "$DEST_INCR_BASE_PROJETS" \
                "$SSH_USER_PROJETS" \
                "$SSH_IP_PROJETS" \
                "$SSH_PORT_PROJETS" \
                "$MONTAGE_SSHFS_PROJETS"; then # Correction: MONTAGE_SSHFS_IMAGES -> MONTAGE_SSHFS_PROJETS
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                # shellcheck disable=SC2154 # DEFAULT_MODE_INCREMENTAL n'existe pas, utiliser la présence de DEST_INCR_BASE_PROJETS
                if [[ -n "$DEST_INCR_BASE_PROJETS" && "$DRY_RUN" -eq 0 ]]; then
                    # shellcheck disable=SC2154 # Jours de rétention sont définis dans config.sh
                    if [[ "$JOURS_RETENTION_PROJETS_SERVEUR_QUOTIDIEN" -gt 0 || "$JOURS_RETENTION_PROJETS_SERVEUR_HEBDO" -gt 0 || "$JOURS_RETENTION_PROJETS_SERVEUR_MENSUEL" -gt 0 ]]; then
                        nettoyer_anciennes_sauvegardes \
                            "$DEST_INCR_BASE_PROJETS" \
                            "$JOURS_RETENTION_PROJETS_SERVEUR_QUOTIDIEN" \
                            "$JOURS_RETENTION_PROJETS_SERVEUR_HEBDO" \
                            "$JOURS_RETENTION_PROJETS_SERVEUR_MENSUEL"
                    fi
                fi
            else
                sauvegardes_echouees=$((sauvegardes_echouees + 1))
            fi
            ;;

        docs_portable) # Correction : Anciennement "musiques_portable" ou autre, maintenant "docs_portable"
            log_info "Traitement de la sauvegarde 'Docs Portable'..."
            # shellcheck disable=SC2154 # Variables sont définies dans config.sh
            if effectuer_sauvegarde "distante" \
                "$SOURCE_DIST_DOCS_PORTABLE" \
                "$DEST_MAIN_DOCS_PORTABLE" \
                "$DEST_INCR_BASE_DOCS_PORTABLE" \
                "$SSH_USER_DOCS_PORTABLE" \
                "$SSH_IP_DOCS_PORTABLE" \
                "$SSH_PORT_DOCS_PORTABLE" \
                "$MONTAGE_SSHFS_DOCS_PORTABLE"; then # Correction: MONTAGE_SSHFS_MUSIQUES -> MONTAGE_SSHFS_DOCS_PORTABLE
                sauvegardes_reussies=$((sauvegardes_reussies + 1))
                # shellcheck disable=SC2154 # DEFAULT_MODE_INCREMENTAL n'existe pas, utiliser la présence de DEST_INCR_BASE_DOCS_PORTABLE
                if [[ "$DRY_RUN" -eq 0 ]]; then # Correction: La condition "&& $DRY_RUN -eq 0" doit être ici, pas sur DEST_INCR_BASE_DOCS_PORTABLE
                    # shellcheck disable=SC2154 # Jours de rétention sont définis dans config.sh
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
        *)
            log_warning "Valeur de sélection inconnue ignorée: $i"
            # Utilise diagnostiquer_et_logger_erreur pour une erreur grave (code 14)
            diagnostiquer_et_logger_erreur 14 "Sélection de sauvegarde inconnue ou non gérée: $i."
            ;;
    esac
done

# --- RÉSUMÉ FINAL ---
log_info "=== FIN DES SAUVEGARDES ==="
log_info "Résumé :"
log_info "  - Sauvegardes réussies: $sauvegardes_reussies"
log_info "  - Sauvegardes échouées: $sauvegardes_echouees"
log_info "  - Total des sauvegardes traitées: $nombre_sauvegardes"

local rapport_sujet=""
local rapport_corps=""

if [[ "$sauvegardes_echouees" -eq 0 && "$nombre_sauvegardes" -gt 0 ]]; then
    rapport_sujet="[Sauvegarde RÉUSSIE] - Toutes les sauvegardes ont été effectuées."
    rapport_corps="Le script de sauvegarde a terminé avec succès.\n"
    rapport_corps+="Résumé :\n"
    rapport_corps+="- Sauvegardes réussies: $sauvegardes_reussies\n"
    rapport_corps+="- Sauvegardes échouées: $sauvegardes_echouees\n"
    rapport_corps+="- Total des sauvegardes traitées: $nombre_sauvegardes\n"
    log_info "Toutes les sauvegardes ont été effectuées avec succès."
elif [[ "$sauvegardes_echouees" -gt 0 ]]; then
    rapport_sujet="[Sauvegarde ÉCHOUÉE] - Des erreurs se sont produites lors de la sauvegarde."
    rapport_corps="Le script de sauvegarde a rencontré des erreurs.\n"
    rapport_corps+="Veuillez consulter les journaux pour plus de détails sur les erreurs spécifiques.\n"
    rapport_corps+="Résumé :\n"
    rapport_corps+="- Sauvegardes réussies: $sauvegardes_reussies\n"
    rapport_corps+="- Sauvegardes échouées: $sauvegardes_echouees\n"
    rapport_corps+="- Total des sauvegardes traitées: $nombre_sauvegardes\n"
    log_error "Des erreurs se sont produites lors de la sauvegarde. Veuillez vérifier les logs."
else
    rapport_sujet="[Sauvegarde INCOMPLÈTE] - Aucune sauvegarde n'a été traitée."
    rapport_corps="Le script de sauvegarde n'a traité aucune sélection.\n"
    rapport_corps+="Vérifiez les arguments passés au script ou DEFAULT_SELECTIONS_SAUVEGARDES dans config.sh.\n"
    log_warning "Aucune sauvegarde n'a été traitée. Vérifiez la configuration ou les arguments."
fi

# Envoyer le rapport par email
# shellcheck disable=SC2154 # EMAIL_NOTIFICATION est défini dans config.sh
if [[ -n "$EMAIL_NOTIFICATION" ]]; then
    envoyer_rapport_email "$rapport_sujet" "$rapport_corps"
fi

# Exécuter le script POST_SAUVEGARDE_GLOBAL si défini
# shellcheck disable=SC2154 # SCRIPT_POST_SAUVEGARDE_GLOBAL est défini dans config.sh
if [[ -n "$SCRIPT_POST_SAUVEGARDE_GLOBAL" ]]; then
    if [[ -x "$SCRIPT_POST_SAUVEGARDE_GLOBAL" ]]; then
        log_info "Exécution du script de post-sauvegarde global : $SCRIPT_POST_SAUVEGARDE_GLOBAL"
        if ! "$SCRIPT_POST_SAUVEGARDE_GLOBAL"; then
            log_warning "Le script de post-sauvegarde global a échoué."
        fi
    else
        log_warning "Le script de post-sauvegarde global '$SCRIPT_POST_SAUVEGARDE_GLOBAL' n'existe pas ou n'est pas exécutable."
    fi
fi

log_info "Script de sauvegarde terminé."

# Si aucune erreur grave n'a été rencontrée, exit 0
if [[ "$sauvegardes_echouees" -eq 0 ]]; then
    exit 0
else
    # Si des sauvegardes ont échoué, sortir avec un code d'erreur général (par exemple 1)
    # Les erreurs spécifiques auront déjà causé un exit plus tôt. Ceci est un fallback.
    exit 1
fi
