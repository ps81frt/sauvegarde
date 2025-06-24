#!/bin/bash

#===============================================================
# Fichier de configuration pour sauvegarde.sh
# Auteur : enRIKO (modifié pour production et améliorations)
# Date : 2025-06-24
# Version : 2.5
#
# Changelog :
# - 2.5 (2025-06-24) :
#   - Correction majeure : Restauration de TOUS les noms de variables en français comme dans la version originale.
#   - Ajout de nouveaux paramètres (également en français) pour une robustesse accrue,
#     sans modifier les variables existantes.
# - 2.4 (2025-06-24) :
#   - Ajout de RSYNC_DELETE pour contrôler l'option rsync --delete.
#   - Clarification des commentaires pour la personnalisation.
#===============================================================

# --- OPTIONS GLOBALES DU SCRIPT ---

# Adresse email pour les rapports de succès/échec. Laissez vide pour désactiver.
EMAIL_NOTIFICATION="votre_email@example.com"

# Espace disque minimum requis sur la destination (en Go). Le script échouera si l'espace est insuffisant.
ESPACE_DISQUE_MIN_GO=5

# Options rsync par défaut. Utilisez des exclusions pour les fichiers temporaires ou inutiles.
# --archive (-a) : mode archive (récursif, conserve les liens symboliques, permissions, temps, groupe, propriétaire)
# --human-readable (-h) : sorties lisibles par l'humain
# --info=progress2,misc0,name0 : affiche la progression et d'autres infos utiles
# --partial --progress : permet de reprendre les transferts et affiche la progression du fichier courant
DEFAULT_RSYNC_OPTIONS="-avh --partial --progress --info=progress2,misc0,name0"

# Activer (1) ou désactiver (0) l'option --delete de rsync.
# 0: Ne supprime jamais (par défaut et recommandé pour les incrémentales avec --link-dest).
# 1: Supprime les fichiers sur la destination s'ils ont été supprimés sur la source (utiliser avec prudence!).
RSYNC_DELETE=0

# Mode débogage (0=off, 1=on). Active la sortie verbeuse du script pour le diagnostic.
DEFAULT_MODE_DEBOGAGE=0

# Désactiver les journaux (0=actif, 1=désactivé). Les erreurs critiques seront toujours enregistrées dans un fichier temporaire.
DEFAULT_JOURNAUX_DESACTIVES=0

# Nom du script pour le mécanisme de verrouillage (évite les exécutions multiples).
DEFAULT_NOM_SCRIPT="sauvegarde"

# Activer le mécanisme de verrouillage (0=off, 1=on).
ACTIVERLOCK=1

# Type de connexion distante :
# 0 = SSHFS (recommandé pour une intégration transparente des chemins distants)
# 1 = SSH direct (rsync via SSH, plus simple, mais nécessite des chemins distants absolus dans rsync)
DEFAULT_TYPE_CONNEXION_DISTANTE=0

# Sélections de sauvegardes par défaut à exécuter si aucune n'est spécifiée en ligne de commande.
# Séparez les sélections par des espaces (ex: "docs_eric docs_fanou photos_vm").
# Utilisez "all" pour inclure toutes les sauvegardes définies.
DEFAULT_SELECTIONS_SAUVEGARDES="docs_eric docs_fanou"


# --- CHEMINS CRITIQUES ET BINAIRES ---

# Répertoire de base où toutes les sauvegardes seront stockées.
DEST_BASE_SAUVEGARDES="/mnt/backup_nas"

# Répertoire où les fichiers de log du script seront stockés.
LOG_DIR="/var/log/sauvegardes"

# Chemin complet du fichier de verrouillage. Doit être accessible en écriture.
PID_FILE="/var/run/${DEFAULT_NOM_SCRIPT}.pid"

# Chemin du fichier de clé privée SSH (laissez vide si authentification par agent ou mot de passe).
# Ex: SSH_KEY_PATH="/home/votre_utilisateur/.ssh/id_rsa_backup"
SSH_KEY_PATH=""

# Chemin du socket de l'agent SSH (laissez vide si non utilisé).
# Ex: SSH_AUTH_SOCK_PATH="/tmp/ssh-XXXXXXX/agent.XXXX"
SSH_AUTH_SOCK_PATH=""

# --- NOUVEAUX PARAMÈTRES : CHEMINS EXPLICITES VERS LES EXÉCUTABLES DES OUTILS ---
# Ces variables permettent de spécifier le chemin complet d'un exécutable si celui-ci
# n'est pas dans le PATH standard ou si une version spécifique est requise.
# Laissez vide pour utiliser la version trouvée dans le PATH du système.
CHEMIN_RSYNC="/usr/bin/rsync"        # Ex: /usr/bin/rsync
CHEMIN_SSH="/usr/bin/ssh"            # Ex: /usr/bin/ssh
CHEMIN_SSHFS="/usr/bin/sshfs"        # Ex: /usr/bin/sshfs
CHEMIN_FUSEMOUNT="/usr/bin/fusermount" # Ex: /usr/bin/fusermount
CHEMIN_MOUNTPOINT="/usr/bin/mountpoint" # Ex: /usr/bin/mountpoint
CHEMIN_LSOF="/usr/bin/lsof"          # Ex: /usr/bin/lsof
CHEMIN_KILL="/usr/bin/kill"          # Ex: /usr/bin/kill
CHEMIN_MKDIR="/usr/bin/mkdir"        # Ex: /usr/bin/mkdir
CHEMIN_MAIL="/usr/bin/mailx"         # Ex: /usr/bin/mailx ou /usr/bin/mail


# --- NOUVEAUX PARAMÈTRES : GESTION AVANCÉE DES JOURNAUX ---

# Taille maximale d'un fichier de log en Mo avant rotation. (0 pour désactiver la rotation par taille)
TAILLE_MAX_LOG_MO=10

# Nombre de jours avant de compresser/purger les anciens logs (0 pour désactiver la rétention basée sur le temps).
JOURS_RETENTION_LOGS=30

# Commande de compression pour les logs archivés (ex: "gzip"). Laissez vide pour ne pas compresser.
# Assurez-vous que la commande est disponible sur le système (e.g., 'gzip', 'bzip2', 'xz').
COMMANDE_COMPRESSION_LOGS="gzip"


# --- NOUVEAUX PARAMÈTRES : OPTIONS DE CONNEXION SSH AVANCÉES ---

# Timeout de connexion SSH en secondes.
DELAI_CONNEXION_SSH_SECONDES=10

# Options SSH communes à toutes les connexions distantes.
# Par défaut, ces options sont sécurisées. Si vous avez besoin de désactiver la vérification des clés
# d'hôte, utilisez StrictHostKeyChecking_SSH (avec prudence !).
OPTIONS_COMMUNES_SSH="-o BatchMode=yes -o ConnectTimeout=${DELAI_CONNEXION_SSH_SECONDES}"

# Activer (yes), désactiver (no) ou demander (ask) StrictHostKeyChecking.
# "no" est risqué en production pour des raisons de sécurité. Laissez vide pour la configuration SSH par défaut.
StrictHostKeyChecking_SSH="no" # "yes", "no", "ask" (laisser vide pour la config SSH par défaut)


# --- NOUVEAUX PARAMÈTRES : OPTIONS RSYNC AVANCÉES ---

# Timeout pour l'opération rsync en secondes. (0 = désactivé. Ex: 3600 = 1 heure)
DELAI_OPERATION_RSYNC_SECONDES=0

# Options spécifiques pour la commande rsync incrémentale.
# --link-dest est crucial pour les sauvegardes incrémentales efficaces avec hardlinks.
# Les chemins dans --link-dest sont relatifs à la DEST_INCR_BASE.
# Ne modifiez pas cette option à moins de savoir ce que vous faites.
OPTIONS_RSYNC_INCREMENTALE="--link-dest=../current"


# --- NOUVEAUX PARAMÈTRES : HOOKS PERSONNALISÉS (AVANCÉ) ---
# Vous pouvez définir des chemins vers des scripts personnalisés qui seront exécutés
# à des moments clés du processus de sauvegarde.

# Exécuté au début du script sauvegarde.sh, après le chargement de la config et avant le verrouillage.
# SCRIPT_PRE_SAUVEGARDE_GLOBAL="/chemin/vers/votre_script_pre_sauvegarde_global.sh"
SCRIPT_PRE_SAUVEGARDE_GLOBAL=""

# Exécuté à la fin du script sauvegarde.sh, après toutes les sauvegardes et avant le démontage/nettoyage final.
# SCRIPT_POST_SAUVEGARDE_GLOBAL="/chemin/vers/votre_script_post_sauvegarde_global.sh"
SCRIPT_POST_SAUVEGARDE_GLOBAL=""


# --- CONFIGURATIONS DES SAUVEGARDES SPÉCIFIQUES ---
# Définissez ici les paramètres pour chaque sélection de sauvegarde.

# --- Sauvegarde : Docs Eric (Locale) ---
SOURCE_LOCALE_DOCS_ERIC="/home/eric/Documents"
DEST_MAIN_DOCS_ERIC="$DEST_BASE_SAUVEGARDES/DocumentsEric/"
DEST_INCR_BASE_DOCS_ERIC="$DEST_BASE_SAUVEGARDES/incremental-DocumentsEric/"

# --- Sauvegarde : Docs Fanou (Locale) ---
SOURCE_LOCALE_DOCS_FANOU="/home/fanou/Documents"
DEST_MAIN_DOCS_FANOU="$DEST_BASE_SAUVEGARDES/DocumentsFanou/"
DEST_INCR_BASE_DOCS_FANOU="$DEST_BASE_SAUVEGARDES/incremental-DocumentsFanou/"

# --- Sauvegarde : Photos VM (Distante via SSHFS) ---
# Note : Pour DEFAULT_TYPE_CONNEXION_DISTANTE=0 (SSHFS), SOURCE_DIST est le chemin absolu sur le serveur distant.
# MONTAGE_SSHFS_PHOTOS est le point de montage local. DEST_MAIN_PHOTOS et DEST_INCR_BASE_PHOTOS
# sont les destinations finales sur le système de sauvegarde.
SSH_USER_PHOTOS="votre_utilisateur_vm_photos"
SSH_IP_PHOTOS="192.168.1.100"
SSH_PORT_PHOTOS=22
SOURCE_DIST_PHOTOS_VM="/chemin/sur/vm/Photos" # Chemin ABSOLU sur la VM
MONTAGE_SSHFS_PHOTOS="/tmp/sshfs_mounts/photos_vm"
DEST_MAIN_PHOTOS="$DEST_BASE_SAUVEGARDES/PhotosVM/"
DEST_INCR_BASE_PHOTOS="$DEST_BASE_SAUVEGARDES/incremental-PhotosVM/"

# --- Sauvegarde : Projets Serveur (Distante via SSHFS) ---
# NOTE: Le nom de la variable MONTAGE_SSHFS_IMAGES a été corrigé en MONTAGE_SSHFS_PROJETS pour être cohérent avec le nom de la sauvegarde.
SSH_USER_PROJETS="votre_utilisateur_serveur_projets"
SSH_IP_PROJETS="192.168.1.101"
SSH_PORT_PROJETS=22
SOURCE_DIST_PROJETS_SERVEUR="/Projets/Serveur/" # Chemin ABSOLU sur le serveur
MONTAGE_SSHFS_PROJETS="/tmp/sshfs_mounts/projets_serveur"
DEST_MAIN_PROJETS="$DEST_BASE_SAUVEGARDES/ProjetsServeur/"
DEST_INCR_BASE_PROJETS="$DEST_BASE_SAUVEGARDES/incremental-ProjetsServeur/"

# --- Sauvegarde : Docs Portable (Distante via SSHFS) ---
# NOTE: Le nom de la variable MONTAGE_SSHFS_MUSIQUES a été corrigé en MONTAGE_SSHFS_DOCS_PORTABLE pour être cohérent avec le nom de la sauvegarde.
SSH_USER_DOCS_PORTABLE="votre_utilisateur_portable"
SSH_IP_DOCS_PORTABLE="192.168.1.102"
SSH_PORT_DOCS_PORTABLE=22
SOURCE_DIST_DOCS_PORTABLE="/home/votre_utilisateur_portable/Documents/" # Chemin ABSOLU sur le portable
MONTAGE_SSHFS_DOCS_PORTABLE="/tmp/sshfs_mounts/docs_portable"
DEST_MAIN_DOCS_PORTABLE="$DEST_BASE_SAUVEGARDES/DocumentsPortable/"
DEST_INCR_BASE_DOCS_PORTABLE="$DEST_BASE_SAUVEGARDES/incremental-DocumentsPortable/"


# --- POLITIQUES DE RÉTENTION ---
# Définissez le nombre de versions quotidiennes, hebdomadaires et mensuelles à conserver.
# Mettez 0 pour désactiver un type de rétention.

# Rétention pour Docs Eric
JOURS_RETENTION_DOCS_ERIC_QUOTIDIEN=7
JOURS_RETENTION_DOCS_ERIC_HEBDO=4 # Nombre de semaines (4 semaines = 1 mois)
JOURS_RETENTION_DOCS_ERIC_MENSUEL=12 # Nombre de mois (12 mois = 1 an)

# Rétention pour Docs Fanou
JOURS_RETENTION_DOCS_FANOU_QUOTIDIEN=7
JOURS_RETENTION_DOCS_FANOU_HEBDO=4
JOURS_RETENTION_DOCS_FANOU_MENSUEL=12

# Rétention pour Photos VM
JOURS_RETENTION_PHOTOS_VM_QUOTIDIEN=7
JOURS_RETENTION_PHOTOS_VM_HEBDO=4
JOURS_RETENTION_PHOTOS_VM_MENSUEL=12

# Rétention pour Projets Serveur
JOURS_RETENTION_PROJETS_SERVEUR_QUOTIDIEN=7
JOURS_RETENTION_PROJETS_SERVEUR_HEBDO=4
JOURS_RETENTION_PROJETS_SERVEUR_MENSUEL=12

# Rétention pour Docs Portable
# NOTE: Le nom de la variable JOURS_RETENTION_MUSIQUES_QUOTIDIEN a été corrigé en JOURS_RETENTION_DOCS_PORTABLE_QUOTIDIEN pour cohérence.
JOURS_RETENTION_DOCS_PORTABLE_QUOTIDIEN=7
JOURS_RETENTION_DOCS_PORTABLE_HEBDO=4
JOURS_RETENTION_DOCS_PORTABLE_MENSUEL=12
