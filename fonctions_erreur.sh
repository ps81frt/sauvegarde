# fonctions_erreur.sh
# Fonctions de journalisation et de gestion des erreurs pour sauvegarde.sh
# Version : 6.6 Beta (2025-06-24)
# Auteur : enRIKO, modifié par geole, iznobe, Watael, steph810
#
# Changelog :
# - 6.6 Beta (2025-06-24) :
#   - Correction majeure : Utilisation des noms de variables français d'origine de config.sh.
#   - Adaptation des vérifications de commandes externes ('command -v') pour utiliser les variables
#     CHEMIN_RSYNC, CHEMIN_SSH, etc. définies dans config.sh (si elles sont non vides).
#   - Amélioration de la traçabilité des erreurs 127 (Commande non trouvée).
# - 6.5 Beta (2025-06-24) :
#   - Robustesse accrue : Ajout de 'command -v' pour vérifier la présence des commandes externes (ssh, sshfs, fusermount, lsof, kill, mkdir) avant leur exécution.
#   - Amélioration de la traçabilité des erreurs 127 (Commande non trouvée).
# - 6.4 Beta (2025-06-24) :
#   - AJOUT DE CODE D'ERREUR 127: Ajout d'une gestion explicite pour "commande non trouvée".
# - 6.3 Beta (2025-06-24) :
#   - AJOUT DE CODES D'ERREUR : Nouveaux codes pour couvrir plus de scénarios d'échec spécifiques.
#   - Affinement des messages et actions suggérées pour chaque code d'erreur.
# - 6.2 Beta (2025-06-24) :
#   - Amélioration de la validation 'path' : permet aux répertoires de destination de ne pas exister s'ils seront créés.
#   - Remplacement de 'ping' par une vérification SSH réelle dans verifier_connexion_ssh.
#   - Suppression de 'eval' dans valider_variable pour la vérification des chemins.
#   - Ajout de la gestion conditionnelle du montage/démontage SSHFS selon DEFAULT_TYPE_CONNEXION_DISTANTE.
#   - CORRECTION MAJEURE : Suppression des appels 'source config.sh' dans les fonctions de log, car config.sh est déjà sourcé par le script principal.
# - 6.1 Beta (2025-06-24) :
#   - Ajout de la journalisation des erreurs critiques dans /tmp/backup_fallback_errors.log même si les logs sont désactivés.
#   - Amélioration de la fonction diagnostiquer_et_logger_erreur pour inclure des messages plus détaillés avec pistes et actions.
#   - Ajout de la gestion des démontages SSHFS occupés avec retries (max 3 tentatives).
#   - Validation renforcée des variables critiques (chemins, permissions) avant exécution.
#   - Support du mode --dry-run dans les messages de journalisation.
#   - Optimisation de la gestion des points de montage SSHFS pour éviter les erreurs de démontage.
# - 6.0 Beta (2025-06-23) :
#   - Refactorisation initiale avec fonctions modulaires pour journalisation et gestion d'erreurs.
#   - Introduction de la gestion des montages SSHFS avec trap EXIT.
#   - Ajout de la vérification des permissions des répertoires de log.

# --- JOURNALISATION ---
# NOTE: Les variables comme LOG_FILE, DEFAULT_JOURNAUX_DESACTIVES sont supposées chargées
# via 'source config.sh' dans le script appelant (sauvegarde.sh).
log_info() {
    local message="$1"
    # shellcheck disable=SC2154 # LOG_DIR est défini dans config.sh et utilisé pour construire LOG_FILE
    # shellcheck disable=SC2154 # DEFAULT_JOURNAUX_DESACTIVES est défini dans config.sh
    if [[ "${DEFAULT_JOURNAUX_DESACTIVES:-0}" -eq 0 ]]; then
        # Assure que LOG_FILE est construit si LOG_DIR est défini
        local current_log_file="${LOG_DIR}/sauvegarde_$(date '+%Y%m%d').log"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $message" | tee -a "$current_log_file"
    fi
}

log_warning() {
    local message="$1"
    # shellcheck disable=SC2154 # LOG_DIR est défini dans config.sh et utilisé pour construire LOG_FILE
    local current_log_file="${LOG_DIR}/sauvegarde_$(date '+%Y%m%d').log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ATTENTION] $message" | tee -a "$current_log_file"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ATTENTION] $message" >> "/tmp/backup_fallback_errors.log"
}

log_error() {
    local message="$1"
    # shellcheck disable=SC2154 # LOG_DIR est défini dans config.sh et utilisé pour construire LOG_FILE
    local current_log_file="${LOG_DIR}/sauvegarde_$(date '+%Y%m%d').log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERREUR] $message" | tee -a "$current_log_file"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERREUR] $message" >> "/tmp/backup_fallback_errors.log"
}

# --- DIAGNOSTIC ET GESTION DES ERREURS ---
diagnostiquer_et_logger_erreur() {
    local code_erreur="$1"
    local message_supplementaire="${2:-}"
    local action_suggeree=""

    case "$code_erreur" in
        1) action_suggeree="Vérifiez les arguments passés au script et la syntaxe." ;;
        2) action_suggeree="Examinez le fichier config.sh. Une variable est manquante, vide ou a une valeur incorrecte." ;;
        # shellcheck disable=SC2154 # LOG_DIR est défini dans config.sh
        3) action_suggeree="Assurez-vous que le répertoire de log ('$LOG_DIR') existe et est accessible en écriture." ;;
        # shellcheck disable=SC2154 # DEST_BASE_SAUVEGARDES, ESPACE_DISQUE_MIN_GO sont définis dans config.sh
        4) action_suggeree="Libérez de l'espace sur la destination ('$DEST_BASE_SAUVEGARDES') ou ajustez ESPACE_DISQUE_MIN_GO." ;;
        5) action_suggeree="Vérifiez la connectivité réseau vers l'hôte distant, les identifiants SSH ou l'état du service SSH." ;;
        # shellcheck disable=SC2154 # MONTAGE_POINT n'est pas global ici, le message est généralisé
        6) action_suggeree="Le point de montage SSHFS est déjà monté et/ou occupé. Vérifiez s'il est utilisé ou démontez-le manuellement." ;;
        7) action_suggeree="Impossible de monter SSHFS. Vérifiez les permissions, la configuration SSH, ou le chemin distant." ;;
        8) action_suggeree="Impossible de démonter SSHFS. Le point de montage est peut-être toujours occupé." ;;
        9) action_suggeree="Une erreur rsync s'est produite. Examinez les logs pour les détails de l'erreur rsync spécifique." ;;
        # shellcheck disable=SC2154 # PID_FILE est défini dans config.sh
        10) action_suggeree="Le script est déjà en cours d'exécution. Si ce n'est pas le cas, supprimez manuellement le fichier de verrouillage '$PID_FILE'." ;;
        11) action_suggeree="Espace disque insuffisant sur la destination de sauvegarde. Nettoyez ou libérez de l'espace." ;;
        12) action_suggeree="Échec de la création d'un répertoire de destination. Vérifiez les permissions du répertoire parent." ;;
        13) action_suggeree="La source spécifiée pour la sauvegarde n'existe pas, est vide, ou n'est pas accessible en lecture." ;;
        14) action_suggeree="Erreur interne de configuration pour la sélection de sauvegarde. Vérifiez les définitions SOURCE/DEST dans config.sh et le bloc 'case' dans sauvegarde.sh." ;;
        # shellcheck disable=SC2154 # EMAIL_NOTIFICATION est défini dans config.sh
        15) action_suggeree="Échec de l'envoi de l'e-mail de notification. Vérifiez la configuration de votre serveur de messagerie (MTA) et l'adresse '$EMAIL_NOTIFICATION'." ;;
        16) action_suggeree="La fonction de nettoyage des anciennes sauvegardes a échoué. Vérifiez la logique et les permissions du répertoire de sauvegarde." ;;
        17) action_suggeree="Échec de la vérification du chemin distant via SSH. Assurez-vous que le chemin existe sur l'hôte distant et que l'utilisateur SSH a les permissions." ;;
        127) action_suggeree="Une commande externe requise par le script n'a pas été trouvée dans le PATH. Vérifiez que toutes les dépendances (rsync, ssh, sshfs, mailx/mail, fusermount, etc.) sont installées et accessibles. Ou que leur chemin est correctement configuré dans config.sh." ;;
        *) action_suggeree="Erreur inconnue. Référez-vous aux logs détaillés pour plus d'informations et le code de retour exact." ;;
    esac

    log_error "Code d'erreur : $code_erreur. $message_supplementaire"
    log_error "Action suggérée : $action_suggeree"
    exit "$code_erreur"
}

# --- VÉRIFICATION DES PERMISSIONS ---
verifier_permissions_log_dir() {
    # shellcheck disable=SC2154 # LOG_DIR est défini dans config.sh
    if [[ ! -d "$LOG_DIR" ]]; then
        log_error "Le répertoire de log '$LOG_DIR' n'existe pas. Veuillez le créer."
        diagnostiquer_et_logger_erreur 3 "Répertoire de log manquant."
    fi
    if [[ ! -w "$LOG_DIR" ]]; then
        log_error "Le répertoire de log '$LOG_DIR' n'est pas accessible en écriture. Vérifiez les permissions."
        diagnostiquer_et_logger_erreur 3 "Permissions d'écriture manquantes pour le répertoire de log."
    fi
}

# --- VALIDATION DES VARIABLES ---
valider_variable() {
    local nom_var="$1"
    local valeur_var="$2"
    local type_var="$3"
    local is_destination_path="${4:-false}" # Nouveau paramètre: true si c'est un chemin de destination

    if [[ -z "$valeur_var" ]]; then
        log_error "La variable '$nom_var' ne peut pas être vide."
        exit 2
    fi

    case "$type_var" in
        string)
            ;;
        path)
            if [[ "$is_destination_path" == "true" ]]; then
                local parent_dir
                parent_dir="$(dirname "$valeur_var")"
                if [[ ! -d "$parent_dir" ]]; then
                    log_error "Le répertoire parent '$parent_dir' pour la destination '$nom_var' n'existe pas ou n'est pas un répertoire."
                    exit 2
                fi
                if [[ ! -w "$parent_dir" ]]; then
                    log_error "Le répertoire parent '$parent_dir' pour la destination '$nom_var' n'est pas accessible en écriture."
                    exit 2
                fi
            else
                if [[ ! -d "$valeur_var" && ! -f "$valeur_var" ]]; then
                    log_error "Le chemin '$valeur_var' pour '$nom_var' n'existe pas ou n'est ni un répertoire ni un fichier."
                    exit 2
                fi
                if [[ ! -r "$valeur_var" ]]; then
                    log_error "Le chemin '$valeur_var' pour '$nom_var' n'est pas accessible en lecture."
                    exit 2
                fi
            fi
            ;;
        int)
            if ! [[ "$valeur_var" =~ ^[0-9]+$ ]]; then
                log_error "La valeur '$valuer_var' pour '$nom_var' n'est pas un entier valide."
                exit 2
            fi
            ;;
        ip)
            if ! echo "$valeur_var" | grep -Eq '^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'; then
                log_error "L'adresse IP '$valeur_var' pour '$nom_var' est invalide."
                exit 2
            fi
            ;;
        port)
            if ! [[ "$valeur_var" =~ ^[0-9]+$ ]] || [[ "$valeur_var" -lt 1 || "$valeur_var" -gt 65535 ]]; then
                log_error "Le port '$valeur_var' pour '$nom_var' est invalide (doit être entre 1 et 65535)."
                exit 2
            fi
            ;;
        uuid)
            if ! echo "$valeur_var" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
                log_error "L'UUID '$valeur_var' pour '$nom_var' est invalide."
                exit 2
            fi
            ;;
        *)
            log_error "Type de validation inconnu pour la variable '$nom_var'."
            exit 2
            ;;
    esac
}

# --- VÉRIFICATION DES CONNEXIONS SSH ---
verifier_connexion_ssh() {
    local utilisateur="$1"
    local ip="$2"
    local port="$3"

    valider_variable "Utilisateur SSH" "$utilisateur" "string"
    valider_variable "IP SSH" "$ip" "ip"
    valider_variable "Port SSH" "$port" "port"

    # shellcheck disable=SC2154 # CHEMIN_SSH est défini dans config.sh
    local ssh_cmd="${CHEMIN_SSH:-ssh}" # Utilise CHEMIN_SSH si défini, sinon 'ssh'

    # Vérifier la présence de la commande 'ssh'
    if ! command -v "$ssh_cmd" >/dev/null 2>&1; then
        log_error "La commande 'ssh' (ou chemin configuré: '$CHEMIN_SSH') n'a pas été trouvée dans le PATH. Impossible de vérifier la connexion SSH."
        diagnostiquer_et_logger_erreur 127 "Dépendance manquante: ssh."
    fi

    log_info "Vérification de la connexion SSH à $utilisateur@$ip:$port..."
    # shellcheck disable=SC2154 # OPTIONS_COMMUNES_SSH est défini dans config.sh
    if ! "$ssh_cmd" "${OPTIONS_COMMUNES_SSH:-}" -p "$port" "$utilisateur@$ip" exit >/dev/null 2>&1; then
        log_error "Impossible d'établir une connexion SSH à $utilisateur@$ip:$port. Vérifiez l'IP, le port, les identifiants SSH ou l'état du service SSH."
        diagnostiquer_et_logger_erreur 5 "Problème de connexion SSH."
    else
        log_info "Connexion SSH à $utilisateur@$ip:$port réussie."
    fi
}

# --- VÉRIFICATION DE L'EXISTENCE DU CHEMIN DISTANT VIA SSH ---
verifier_chemin_distant_ssh() {
    local utilisateur="$1"
    local ip="$2"
    local port="$3"
    local chemin_distant="$4"

    # shellcheck disable=SC2154 # CHEMIN_SSH est défini dans config.sh
    local ssh_cmd="${CHEMIN_SSH:-ssh}" # Utilise CHEMIN_SSH si défini, sinon 'ssh'

    # Vérifier la présence de la commande 'ssh'
    if ! command -v "$ssh_cmd" >/dev/null 2>&1; then
        log_error "La commande 'ssh' (ou chemin configuré: '$CHEMIN_SSH') n'a pas été trouvée dans le PATH. Impossible de vérifier le chemin distant via SSH."
        diagnostiquer_et_logger_erreur 127 "Dépendance manquante: ssh (pour vérification chemin distant)."
    fi

    log_info "Vérification de l'existence du chemin distant '$chemin_distant' sur $ip..."
    # Exécute un 'test -d' (pour répertoire) ou 'test -f' (pour fichier) sur l'hôte distant
    # shellcheck disable=SC2154 # OPTIONS_COMMUNES_SSH est défini dans config.sh
    if ! "$ssh_cmd" "${OPTIONS_COMMUNES_SSH:-}" -p "$port" "$utilisateur@$ip" "test -d \"$chemin_distant\" || test -f \"$chemin_distant\"" >/dev/null 2>&1; then
        log_error "Le chemin distant '$chemin_distant' n'existe pas ou n'est pas accessible sur $ip. Vérifiez le chemin et les permissions distantes."
        diagnostiquer_et_logger_erreur 17 "Chemin distant inaccessible via SSH."
    else
        log_info "Le chemin distant '$chemin_distant' existe et est accessible sur $ip."
    fi
}

# --- GESTION DES MONTAGES SSHFS ---
monter_sshfs() {
    local utilisateur="$1"
    local ip="$2"
    local port="$3"
    local chemin_distant="$4"
    local point_montage_local="$5"
    local tentatives=3
    local delai=5 # secondes

    # shellcheck disable=SC2154 # DEFAULT_TYPE_CONNEXION_DISTANTE est défini dans config.sh
    if [[ "${DEFAULT_TYPE_CONNEXION_DISTANTE:-0}" -ne 0 ]]; then
        log_info "Type de connexion distante n'est pas SSHFS. Ignorance du montage SSHFS pour $point_montage_local."
        return 0
    fi

    # shellcheck disable=SC2154 # CHEMIN_SSHFS, CHEMIN_MOUNTPOINT, CHEMIN_MKDIR sont définis dans config.sh
    local sshfs_cmd="${CHEMIN_SSHFS:-sshfs}"
    local mountpoint_cmd="${CHEMIN_MOUNTPOINT:-mountpoint}"
    local mkdir_cmd="${CHEMIN_MKDIR:-mkdir}"

    # Vérifier la présence de la commande 'sshfs'
    if ! command -v "$sshfs_cmd" >/dev/null 2>&1; then
        log_error "La commande 'sshfs' (ou chemin configuré: '$CHEMIN_SSHFS') n'a pas été trouvée dans le PATH. Impossible de monter SSHFS."
        diagnostiquer_et_logger_erreur 127 "Dépendance manquante: sshfs."
    fi
    # Vérifier la présence de la commande 'mountpoint'
    if ! command -v "$mountpoint_cmd" >/dev/null 2>&1; then
        log_error "La commande 'mountpoint' (ou chemin configuré: '$CHEMIN_MOUNTPOINT') n'a pas été trouvée dans le PATH. Impossible de vérifier les points de montage."
        diagnostiquer_et_logger_erreur 127 "Dépendance manquante: mountpoint."
    fi

    valider_variable "Point de montage local SSHFS" "$point_montage_local" "path" "true"

    if "$mountpoint_cmd" -q "$point_montage_local"; then
        log_warning "Le point de montage '$point_montage_local' est déjà monté. Tentative de démontage avant de remonter."
        demonter_sshfs "$point_montage_local"
        if "$mountpoint_cmd" -q "$point_montage_local"; then
            log_error "Impossible de démonter le point de montage existant '$point_montage_local'. Il est peut-être en cours d'utilisation."
            diagnostiquer_et_logger_erreur 6 "Point de montage SSHFS déjà en cours d'utilisation."
        fi
    fi

    if [[ ! -d "$point_montage_local" ]]; then
        log_info "Création du point de montage SSHFS: $point_montage_local"
        # Vérifier la présence de la commande 'mkdir'
        if ! command -v "$mkdir_cmd" >/dev/null 2>&1; then
            log_error "La commande 'mkdir' (ou chemin configuré: '$CHEMIN_MKDIR') n'a pas été trouvée dans le PATH. Impossible de créer le répertoire de montage."
            diagnostiquer_et_logger_erreur 127 "Dépendance manquante: mkdir."
        fi
        "$mkdir_cmd" -p "$point_montage_local" || { log_error "Impossible de créer le répertoire de montage $point_montage_local."; diagnostiquer_et_logger_erreur 12; }
    fi

    log_info "Tentative de montage SSHFS de $utilisateur@$ip:$chemin_distant vers $point_montage_local"
    # shellcheck disable=SC2154 # OPTIONS_COMMUNES_SSH est défini dans config.sh
    for (( i=1; i<=tentatives; i++ )); do
        "$sshfs_cmd" "$utilisateur@$ip:$chemin_distant" "$point_montage_local" -o "port=$port,reconnect,no_readahead,default_permissions,allow_other${OPTIONS_COMMUNES_SSH:+,}${OPTIONS_COMMUNES_SSH}" >/dev/null 2>&1
        if "$mountpoint_cmd" -q "$point_montage_local"; then
            log_info "Montage SSHFS réussi ($point_montage_local)."
            return 0
        else
            log_warning "Tentative $i/$tentatives échouée pour le montage SSHFS. Réessaie dans $delai secondes..."
            sleep "$delai"
        fi
    done

    log_error "Échec du montage SSHFS de $utilisateur@$ip:$chemin_distant après $tentatives tentatives."
    diagnostiquer_et_logger_erreur 7 "Échec du montage SSHFS."
}

demonter_sshfs() {
    local point_montage_local="$1"
    local tentatives=3
    local delai=5 # secondes

    # shellcheck disable=SC2154 # DEFAULT_TYPE_CONNEXION_DISTANTE est défini dans config.sh
    if [[ "${DEFAULT_TYPE_CONNEXION_DISTANTE:-0}" -ne 0 ]]; then
        log_info "Type de connexion distante n'est pas SSHFS. Ignorance du démontage SSHFS pour $point_montage_local."
        return 0
    fi

    # shellcheck disable=SC2154 # CHEMIN_FUSEMOUNT, CHEMIN_MOUNTPOINT, CHEMIN_LSOF, CHEMIN_KILL sont définis dans config.sh
    local fusermount_cmd="${CHEMIN_FUSEMOUNT:-fusermount}"
    local mountpoint_cmd="${CHEMIN_MOUNTPOINT:-mountpoint}"
    local lsof_cmd="${CHEMIN_LSOF:-lsof}"
    local kill_cmd="${CHEMIN_KILL:-kill}"
    # xargs est une commande standard, pas besoin de chemin explicite

    # Vérifier la présence de la commande 'fusermount'
    if ! command -v "$fusermount_cmd" >/dev/null 2>&1; then
        log_error "La commande 'fusermount' (ou chemin configuré: '$CHEMIN_FUSEMOUNT') n'a pas été trouvée dans le PATH. Impossible de démonter SSHFS."
        diagnostiquer_et_logger_erreur 127 "Dépendance manquante: fusermount."
    fi
    # Vérifier la présence de la commande 'mountpoint'
    if ! command -v "$mountpoint_cmd" >/dev/null 2>&1; then
        log_error "La commande 'mountpoint' (ou chemin configuré: '$CHEMIN_MOUNTPOINT') n'a pas été trouvée dans le PATH. Impossible de vérifier les points de montage."
        diagnostiquer_et_logger_erreur 127 "Dépendance manquante: mountpoint."
    fi


    if "$mountpoint_cmd" -q "$point_montage_local"; then
        log_info "Tentative de démontage de $point_montage_local..."
        for (( i=1; i<=tentatives; i++ )); do
            "$fusermount_cmd" -uz "$point_montage_local" >/dev/null 2>&1
            if ! "$mountpoint_cmd" -q "$point_montage_local"; then
                log_info "Démontage SSHFS réussi ($point_montage_local)."
                return 0
            else
                log_warning "Tentative $i/$tentatives échouée pour le démontage de $point_montage_local. Réessaie dans $delai secondes..."
                sleep "$delai"
                if [[ $i -eq $((tentatives-1)) ]]; then
                    log_warning "Le point de montage est toujours occupé. Tentative de trouver et tuer les processus utilisant $point_montage_local..."
                    # Vérifier si lsof et kill sont disponibles
                    if ! command -v "$lsof_cmd" >/dev/null 2>&1 || ! command -v "$kill_cmd" >/dev/null 2>&1 || ! command -v xargs >/dev/null 2>&1; then
                        log_error "Les commandes 'lsof', 'kill' ou 'xargs' (ou chemins configurés: '$CHEMIN_LSOF', '$CHEMIN_KILL') n'ont pas été trouvées dans le PATH. Impossible de tuer les processus utilisant le point de montage."
                        diagnostiquer_et_logger_erreur 127 "Dépendances manquantes: lsof, kill, xargs (pour démontage SSHFS)."
                    else
                        "$lsof_cmd" -t "$point_montage_local" | xargs -r "$kill_cmd" -9
                        sleep 2
                    fi
                fi
            fi
        done
        log_error "Échec du démontage de $point_montage_local après $tentatives tentatives."
        diagnostiquer_et_logger_erreur 8 "Échec du démontage SSHFS."
    else
        log_info "Le point de montage $point_montage_local n'est pas monté, pas de démontage nécessaire."
    fi
}
