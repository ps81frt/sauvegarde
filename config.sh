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
#   - Correction des noms de variables de montage SSHFS pour plus de clarté.
#   - Ajout des politiques de rétention pour les nouvelles sauvegardes.
#   - Mise à jour de la liste DEFAULT_SELECTIONS_SAUVEGARDES.
#===============================================================

# --- OPTIONS GLOBALES ---
EMAIL_NOTIFICATION="votre_email@example.com"  # Adresse email pour les rapports
ESPACE_DISQUE_MIN_GO=5                       # Espace disque minimum requis sur la destination (Go)
DEFAULT_RSYNC_OPTIONS="-avh --exclude='.Trash' --exclude='.thumbnails'"  # Options rsync par défaut
RSYNC_DELETE=0                               # Activer (1) ou désactiver (0) l'option --delete de rsync
DEFAULT_MODE_DEBOGAGE=0                      # Mode débogage (0=off, 1=on)
DEFAULT_JOURNAUX_DESACTIVES=0                # Désactiver les journaux (0=actif, 1=désactivé)
DEFAULT_NOM_SCRIPT="sauvegarde"              # Nom du script pour le fichier de verrouillage
ACTIVERLOCK=1                                # Activer (1) ou désactiver (0) le verrouillage du script
DEFAULT_TYPE_CONNEXION_DISTANTE=0             # Type de connexion distante par défaut (0=SSHFS, 1=SSH direct)
DEFAULT_SELECTIONS_SAUVEGARDES="docs_eric docs_fanou photos_vm projets_serveur docs_portable"  # Liste des sélections de sauvegarde par défaut

# --- CHEMINS DE LOGS ET FICHIERS TEMPORAIRES ---
LOG_DIR="/var/log/sauvegarde"                # Répertoire principal pour les fichiers de log
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d)-sauvegarde.log"  # Chemin complet vers le fichier de log principal
PID_FILE="/var/run/$DEFAULT_NOM_SCRIPT.pid"  # Chemin vers le fichier PID du script

# --- CONFIGURATION DES SAUVEGARDES SPÉCIFIQUES ---

# --- Sauvegarde des documents d'Eric ---
SOURCE_DOCS_ERIC="/home/enriko/Documents"
DEST_MAIN_DOCS_ERIC="/mnt/SauvegardesBackup/DocumentsEric/"
DEST_INCR_BASE_DOCS_ERIC="/mnt/SauvegardesBackup/incremental-DocumentsEric/"

# --- Sauvegarde des documents de Fanou ---
SOURCE_DOCS_FANOU="/home/fanou/Documents"
DEST_MAIN_DOCS_FANOU="/mnt/SauvegardesBackup/DocumentsFanou/"
DEST_INCR_BASE_DOCS_FANOU="/mnt/SauvegardesBackup/incremental-DocumentsFanou/"

# --- Sauvegarde des PhotosVM (distante) ---
USER_SSH_PHOTOS="votre_utilisateur_photos"   # Utilisateur SSH sur la machine distante
IP_SSH_PHOTOS="192.168.1.10"                 # Adresse IP de la machine distante
PORT_SSH_PHOTOS=22                           # Port SSH
SOURCE_DIST_PHOTOS="/var/lib/libvirt/images" # Chemin de la source sur la machine distante
MONTAGE_SSHFS_PHOTOS="/tmp/sshfs_mounts/photos_vm" # Point de montage local pour SSHFS
DEST_MAIN_PHOTOS="/mnt/SauvegardesBackup/PhotosVM/"
DEST_INCR_BASE_PHOTOS="/mnt/SauvegardesBackup/incremental-PhotosVM/"

# --- Sauvegarde des Projets Serveur (distant) ---
USER_SSH_PROJETS="votre_utilisateur_projets"
IP_SSH_PROJETS="192.168.1.20"
PORT_SSH_PROJETS=22
SOURCE_DIST_PROJETS_SERVEUR="/Projets/Serveur/"
MONTAGE_SSHFS_PROJETS_SERVEUR="/tmp/sshfs_mounts/projets_serveur" # Correction du nom de variable
DEST_MAIN_PROJETS="/mnt/SauvegardesBackup/ProjetsServeur/"
DEST_INCR_BASE_PROJETS="/mnt/SauvegardesBackup/incremental-ProjetsServeur/"

# --- Sauvegarde des Documents Portable (distant) ---
USER_SSH_DOCS_PORTABLE="votre_utilisateur_portable"
IP_SSH_DOCS_PORTABLE="192.168.1.30"
PORT_SSH_DOCS_PORTABLE=22
SOURCE_DIST_DOCS_PORTABLE="/home/votre_utilisateur_portable/Documents/"
MONTAGE_SSHFS_DOCS_PORTABLE="/tmp/sshfs_mounts/docs_portable" # Correction du nom de variable
DEST_MAIN_DOCS_PORTABLE="/mnt/SauvegardesBackup/DocumentsPortable/"
DEST_INCR_BASE_DOCS_PORTABLE="/mnt/SauvegardesBackup/incremental-DocumentsPortable/"

# --- POLITIQUES DE RÉTENTION ---
JOURS_RETENTION_DOCS_ERIC_QUOTIDIEN=7
JOURS_RETENTION_DOCS_ERIC_HEBDO=4
JOURS_RETENTION_DOCS_ERIC_MENSUEL=12

JOURS_RETENTION_DOCS_FANOU_QUOTIDIEN=7
JOURS_RETENTION_DOCS_FANOU_HEBDO=4
JOURS_RETENTION_DOCS_FANOU_MENSUEL=12

JOURS_RETENTION_PHOTOS_QUOTIDIEN=7
JOURS_RETENTION_PHOTOS_HEBDO=4
JOURS_RETENTION_PHOTOS_MENSUEL=12

JOURS_RETENTION_PROJETS_SERVEUR_QUOTIDIEN=7
JOURS_RETENTION_PROJETS_SERVEUR_HEBDO=4
JOURS_RETENTION_PROJETS_SERVEUR_MENSUEL=12

JOURS_RETENTION_DOCS_PORTABLE_QUOTIDIEN=7
JOURS_RETENTION_DOCS_PORTABLE_HEBDO=4
JOURS_RETENTION_DOCS_PORTABLE_MENSUEL=12

# --- CHEMINS DE BASE DES SAUVEGARDES ---
DEST_BASE_SAUVEGARDES="/mnt/SauvegardesBackup" # Répertoire racine des sauvegardes

# --- CHANGELOG DU FICHIER DE CONFIGURATION ---
# Mettez à jour cette section lorsque des modifications sont apportées à ce fichier.
# - 2.4 (2025-06-24) :
#   - Ajout des variables pour les nouvelles sélections de sauvegarde (PhotosVM, ProjetsServeur, DocumentsPortable).
#   - Correction des noms de variables de montage SSHFS pour plus de clarté.
#   - Ajout des politiques de rétention pour les nouvelles sauvegardes.
