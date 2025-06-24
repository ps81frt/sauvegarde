# fonctions_erreur.sh
# Fonctions de journalisation et de gestion des erreurs pour sauvegarde.sh
# Version : 6.1 Beta (2025-06-24)
# Auteur : enRIKO, modifié par geole, iznobe, Watael, steph810
#
# Changelog :
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
log_info() {
    local message="$1"
    if [[ "${DEFAULT_JOURNAUX_DESACTIVES:-0}" -eq 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $message" >> "$LOG_FILE"
    fi
    if [[ "${DEFAULT_MODE_DEBOGAGE:-0}" -eq 1 || -z "${DEFAULT_JOURNAUX_DESACTIVES:-0}" ]]; then
        echo "[INFO] $message"
    fi
}

log_warning() {
    local message="$1"
    if [[ "${DEFAULT_JOURNAUX_DESACTIVES:-0}" -eq 0 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $message" >> "$LOG_FILE"
    fi
    echo "[WARNING] $message" >&2
}

log_error() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $message" >> "/tmp/backup_fallback_errors.log"
    if [[ "${DEFAULT_JOURNAUX_DESACTIVES:-0}" -eq 0 && -n "${LOG_FILE:-}" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $message" >> "$LOG_FILE"
    fi
    echo "[ERROR] $message" >&2
}

log_debug() {
    local message="$1"
    if [[ "${DEFAULT_MODE_DEBOGAGE:-0}" -eq 1 ]]; then
        if [[ "${DEFAULT_JOURNAUX_DESACTIVES:-0}" -eq 0 ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') [DEBUG] $message" >> "$LOG_FILE"
        fi
        echo "[DEBUG] $message"
    fi
}

# --- VÉRIFICATION DU FICHIER DE LOG ---
verifier_fichier_log() {
    if [[ "${DEFAULT_JOURNAUX_DESACTIVES:-0}" -eq 1 ]]; then
        log_debug "Journalisation désactivée, sauf pour les erreurs critiques."
        return 0
    fi

    LOG_DIR="${LOG_DIR:-/var/log/sauvegardes}"
    LOG_FILE="$LOG_DIR/sauvegarde_$(date '+%Y-%m-%d').log"
    LAST_LOG_FILE="$LOG_DIR/sauvegarde_dernier.log"

    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" || { log_error "Impossible de créer le répertoire de logs $LOG_DIR"; exit 2; }
    fi

    if [[ ! -w "$LOG_DIR" ]]; then
        log_error "Le répertoire de logs $LOG_DIR n'est pas accessible en écriture"
        exit 2
    fi

    touch "$LOG_FILE" || { log_error "Impossible de créer le fichier de log $LOG_FILE"; exit 2; }
    ln -sf "$LOG_FILE" "$LAST_LOG_FILE" || log_warning "Impossible de mettre à jour le lien symbolique $LAST_LOG_FILE"
}

# --- DIAGNOSTIC DES ERREURS ---
diagnostiquer_et_logger_erreur() {
    local code_retour="$1"
    local commande="$2"
    local message="$3"
    local pistes="$4"
    local actions="$5"

    log_error "$message"
    log_error "Code de retour : $code_retour"
    log_error "Commande : $commande"
    if [[ -n "$pistes" ]]; then
        log_error "Pistes : $pistes"
    fi
    if [[ -n "$actions" ]]; then
        log_error "Actions : $actions"
    fi

    if [[ "$code_retour" -eq 0 ]]; then
        log_info "Aucune erreur détectée pour $commande"
        return 0
    fi

    case "$commande" in
        rsync*)
            case "$code_retour" in
                23) log_error "rsync : Erreur partielle (fichiers non accessibles ou permissions insuffisantes)"
                    log_error "Piste : Vérifiez les permissions des fichiers sources et destinations"
                    log_error "Action : Exécutez 'chmod' ou 'chown' pour corriger les permissions"
                    ;;
                24) log_error "rsync : Certains fichiers ont disparu pendant le transfert"
                    log_error "Piste : Les fichiers sources peuvent avoir été supprimés ou déplacés"
                    log_error "Action : Vérifiez l'intégrité des fichiers sources"
                    ;;
                *) log_error "rsync : Erreur inconnue (code $code_retour)"
                   log_error "Action : Consultez 'man rsync' pour le code de retour $code_retour"
                   ;;
            esac
            ;;
        sshfs*)
            case "$code_retour" in
                1) log_error "sshfs : Échec de la connexion SSH"
                   log_error "Piste : Problème avec les clés SSH, l'adresse IP, ou le port"
                   log_error "Action : Testez 'ssh -p <port> <utilisateur>@<ip>' manuellement"
                   ;;
                *) log_error "sshfs : Erreur inconnue (code $code_retour)"
                   log_error "Action : Vérifiez les logs système et la configuration SSHFS"
                   ;;
            esac
            ;;
        mount* | umount* | fusermount*)
            log_error "Erreur de montage/démontage SSHFS"
            log_error "Piste : Le point de montage peut être occupé ou mal configuré"
            log_error "Action : Vérifiez avec 'lsof +D <point_de_montage>' et utilisez 'fusermount -uz'"
            ;;
        *) log_error "Erreur non spécifique pour $commande (code $code_retour)"
           ;;
    esac
    return "$code_retour"
}

# --- GESTION DES POINTS DE MONTAGE SSHFS ---
demonter_tous_les_sshfs_a_la_sortie() {
    local retries=3
    local delay=5
    local attempt=1

    log_debug "Démontage des points de montage SSHFS..."
    for mount_point in "${MONTAGE_SSHFS_PHOTOS:-}" "${MONTAGE_SSHFS_PROJETS:-}" "${MONTAGE_SSHFS_DOCS_PORTABLE:-}"; do
        if [[ -n "$mount_point" && -d "$mount_point" ]]; then
            while [[ $attempt -le $retries ]]; do
                if findmnt "$mount_point" > /dev/null 2>&1; then
                    log_debug "Tentative $attempt de démontage de $mount_point"
                    fusermount -uz "$mount_point" || fusermount3 -uz "$mount_point" || {
                        log_warning "Échec du démontage de $mount_point (tentative $attempt)"
                        if [[ $attempt -eq $retries ]]; then
                            log_error "Impossible de démonter $mount_point après $retries tentatives"
                        else
                            sleep "$delay"
                        fi
                    }
                else
                    log_debug "$mount_point n'est pas monté"
                    break
                fi
                ((attempt++))
            done
            rmdir "$mount_point" 2>/dev/null || log_debug "Le répertoire $mount_point n'a pas été supprimé (peut être non vide)"
        fi
    done
}

# --- VALIDATION DES VARIABLES ---
valider_variable() {
    local nom_var="$1"
    local valeur_var="$2"
    local type_attendu="$3"

    if [[ -z "$valeur_var" ]]; then
        log_error "La variable $nom_var est vide ou non définie"
        exit 2
    fi

    case "$type_attendu" in
        chemin)
            if [[ ! -d "$valeur_var" && ! -f "$valeur_var" ]]; then
                log_error "Le chemin $valeur_var pour $nom_var n'existe pas"
                exit 2
            fi
            ;;
        ip)
            if ! echo "$valeur_var" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' > /dev/null; then
                log_error "L'adresse IP $valeur_var pour $nom_var est invalide"
                exit 2
            fi
            ;;
        port)
            if ! [[ "$valeur_var" =~ ^[0-9]+$ ]] || [[ "$valeur_var" -lt 1 || "$valeur_var" -gt 65535 ]]; then
                log_error "Le port $valeur_var pour $nom_var est invalide"
                exit 2
            fi
            ;;
        uuid)
            if ! echo "$valeur_var" | grep -E '^[0-9a-fA-F-]{36}$' > /dev/null; then
                log_error "L'UUID $valeur_var pour $nom_var est invalide"
                exit 2
            fi
            ;;
        *) log_error "Type de validation inconnu pour $nom_var"
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

    if ! ping -c 1 -W 2 "$ip" > /dev/null 2>&1; then
        log_error "Impossible de joindre l'hôte $ip"
        exit 2
    fi

    if ! ssh -o BatchMode=yes -p "$port" "$utilisateur@$ip" true 2>/dev/null; then
        log_error "Échec de la connexion SSH à $utilisateur@$ip:$port"
        log_error "Piste : Vérifiez les clés SSH et la configuration du serveur SSH"
        log_error "Action : Testez avec 'ssh -p $port $utilisateur@$ip'"
        exit 2
    fi
}
