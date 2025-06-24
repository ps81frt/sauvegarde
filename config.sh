#!/bin/bash

#===============================================================
# Fichier de configuration pour sauvegarde.sh
# Auteur : enRIKO (modifié pour production et améliorations)
# Date : 2025-06-24
# Version : 2.4
#
# Changelog :
# - 2.4 (2025-06-24) :
#   - Ajout de RSYNC_DELETE pour contrôler l'option rsync --delete.
#   - Clarification des commentaires pour la personnalisation.
#===============================================================

# --- OPTIONS GLOBALES ---
EMAIL_NOTIFICATION="votre_email@example.com"  # Adresse pour les rapports
ESPACE_DISQUE_MIN_GO=5                       # Espace minimum requis (Go)
DEFAULT_RSYNC_OPTIONS="-avh --exclude='.Trash' --exclude='.thumbnails'"  # Options rsync par défaut
RSYNC_DELETE=0                               # Activer (1) ou désactiver (0) l'option --delete
DEFAULT_MODE_DEBOGAGE=0                      # Mode débogage (0=off, 1=on)
DEFAULT_JOURNAUX_DESACTIVES=0                # Désactiver journaux (0=actif, 1=désactivé)
DEFAULT_NOM_SCRIPT="sauvegarde"              # Nom du script pour verrouillage
ACTIVERLOCK=1                                # Activer verrouillage (0=off, 1=on)
DEFAULT_TYPE_CONNEXION_DISTANTE=0             # 0=SSHFS, 1=SSH direct
DEFAULT_SELECTIONS_SAUVEGARDES="docs_eric docs_fanou"  # Sauvegardes par défaut
CHEMIN_FONCTIONS_ERREUR="$SCRIPT_DIR/fonctions_erreur.sh"

# --- ACCÈS SSH ---
userVM="Multimedias"
ipVM="192.168.1.128"
portVM="22"
userPortable="votre_utilisateur_portable"
ipPortable="192.168.1.129"
portPortable="22"
pathPortable="/home/votre_utilisateur_portable"
userServeur="votre_utilisateur_serveur"
ipServeur="192.168.1.130"
portServeur="22"

# --- CHEMINS SOURCE ET DESTINATION ---
# À personnaliser selon votre environnement
UUID_DISQUE_SAUVEGARDE="550e8400-e29b-41d4-a716-446655440000"
DEST_BASE_SAUVEGARDES="/mnt/usb-Hdd/Sauvegardes"

SOURCE_LOCAL_DOCS_ERIC="/home/kubu/Documents/Eric/"
DEST_MAIN_DOCS_ERIC="$DEST_BASE_SAUVEGARDES/DocumentsEric/"
DEST_INCR_BASE_DOCS_ERIC="$DEST_BASE_SAUVEGARDES/incremental-DocumentsEric/"

SOURCE_LOCAL_DOCS_FANOU="/home/kubu/Documents/Fanou/"
DEST_MAIN_DOCS_FANOU="$DEST_BASE_SAUVEGARDES/DocumentsFanou/"
DEST_INCR_BASE_DOCS_FANOU="$DEST_BASE_SAUVEGARDES/incremental-DocumentsFanou/"

SOURCE_LOCAL_DOCS_COMMUNS="/home/kubu/Documents/Communs/"
DEST_MAIN_DOCS_COMMUNS="$DEST_BASE_SAUVEGARDES/DocumentsCommuns/"
DEST_INCR_BASE_DOCS_COMMUNS="$DEST_BASE_SAUVEGARDES/incremental-DocumentsCommuns/"

SOURCE_LOCAL_MUSIQUES="/home/kubu/Musiques/"
DEST_MAIN_MUSIQUES="$DEST_BASE_SAUVEGARDES/Musiques/"
DEST_INCR_BASE_MUSIQUES="$DEST_BASE_SAUVEGARDES/incremental-Musiques/"

SOURCE_DIST_PHOTOS_VM="/Photos/VM/"
MONTAGE_SSHFS_PHOTOS="/tmp/sshfs_mounts/photos_vm"
DEST_MAIN_PHOTOS="$DEST_BASE_SAUVEGARDES/PhotosVM/"
DEST_INCR_BASE_PHOTOS="$DEST_BASE_SAUVEGARDES/incremental-PhotosVM/"

SOURCE_DIST_PROJETS_SERVEUR="/Projets/Serveur/"
MONTAGE_SSHFS_IMAGES="/tmp/sshfs_mounts/projets_serveur"
DEST_MAIN_PROJETS="$DEST_BASE_SAUVEGARDES/ProjetsServeur/"
DEST_INCR_BASE_PROJETS="$DEST_BASE_SAUVEGARDES/incremental-ProjetsServeur/"

SOURCE_DIST_DOCS_PORTABLE="/home/votre_utilisateur_portable/Documents/"
MONTAGE_SSHFS_MUSIQUES="/tmp/sshfs_mounts/docs_portable"
DEST_MAIN_DOCS_PORTABLE="$DEST_BASE_SAUVEGARDES/DocumentsPortable/"
DEST_INCR_BASE_DOCS_PORTABLE="$DEST_BASE_SAUVEGARDES/incremental-DocumentsPortable/"

# --- POLITIQUES DE RÉTENTION ---
JOURS_RETENTION_DOCS_ERIC_QUOTIDIEN=7
JOURS_RETENTION_DOCS_ERIC_HEBDO=4
JOURS_RETENTION_DOCS_ERIC_MENSUEL=12

JOURS_RETENTION_DOCS_FANOU_QUOTIDIEN=7
JOURS_RETENTION_DOCS_FANOU_HEBDO=4
JOURS_RETENTION_DOCS_FANOU_MENSUEL=12

JOURS_RETENTION_DOCS_COMMUNS_QUOTIDIEN=7
JOURS_RETENTION_DOCS_COMMUNS_HEBDO=4
JOURS_RETENTION_DOCS_COMMUNS_MENSUEL=12

JOURS_RETENTION_PROJETS_QUOTIDIEN=7
JOURS_RETENTION_PROJETS_HEBDO=4
JOURS_RETENTION_PROJETS_MENSUEL=12

JOURS_RETENTION_PHOTOS_QUOTIDIEN=7
JOURS_RETENTION_PHOTOS_HEBDO=4
JOURS_RETENTION_PHOTOS_MENSUEL=12

JOURS_RETENTION_DOCS_PORTABLE_QUOTIDIEN=7
JOURS_RETENTION_DOCS_PORTABLE_HEBDO=4
JOURS_RETENTION_DOCS_PORTABLE_MENSUEL=12

JOURS_RETENTION_MUSIQUES_QUOTIDIEN=7
JOURS_RETENTION_MUSIQUES_HEBDO=4
JOURS_RETENTION_MUSIQUES_MENSUEL=12
