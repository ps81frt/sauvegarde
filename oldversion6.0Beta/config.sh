#!/bin/bash
#
# Fichier de configuration pour le script de sauvegarde 'sauvegarde.sh'
# Auteur : enRIKO ^^ =D
# Date : 2025-06-23
# Version : 2.3 (Améliorations de la gestion de la rétention et portabilité)
# Description : Configuration centralisée pour les sauvegardes avec nouvelle structure :
#               - Dossiers principaux pour les copies courantes
#               - Dossiers incrementaux séparés pour l'historique

### SECTION 1 - OPTIONS GLOBALES DU SCRIPT ###
DEFAULT_NOM_SCRIPT="sauvegarde_script" # Nom de base pour le fichier de verrouillage (évite les conflits)

# Adresse email pour recevoir les rapports de sauvegarde. Laisser vide pour désactiver.
EMAIL_NOTIFICATION=""

# Espace disque minimum requis sur la destination (en Go)
ESPACE_DISQUE_MIN_GO=5

# Options rsync
DEFAULT_RSYNC_OPTIONS="-avh --exclude '*/.Trash-*' --exclude '*/.thumbnails' --exclude '*.bak' --exclude '*~' --exclude 'Thumbs.db' --exclude '.DS_Store' --exclude 'lost+found'"


# Mode debug (0=désactivé, 1=activé)
# Activez-le (1) si vous rencontrez des problèmes pour avoir des logs détaillés.
DEFAULT_MODE_DEBOGAGE=0

# Type de connexion pour les sauvegardes distantes :
# 0 = SSHFS (montage du système de fichiers distant - plus robuste pour rsync)
# 1 = SSH Direct (rsync via SSH - plus simple à configurer, potentiellement plus lent sur beaucoup de petits fichiers)
DEFAULT_TYPE_CONNEXION_DISTANTE=0

# Désactivation des journaux (0=activés, 1=désactivés)
# Mettez à 1 pour désactiver la journalisation des opérations. Non recommandé en production.
DEFAULT_JOURNAUX_DESACTIVES=0

# Sélection des sauvegardes à exécuter (combinaison binaire)
# Chaque chiffre représente une sauvegarde spécifique (voir sauvegarde.sh pour la correspondance).
# Exemple : "1 2" pour Documents Eric et Documents Fanou. "ALL" pour toutes les sauvegardes.
DEFAULT_SELECTIONS_SAUVEGARDES="1 2 4 8 16 32"

# Mode de sauvegarde (0=complète, 1=incrémentale)
# Mettre à 1 pour activer les sauvegardes incrémentales par défaut (recommandé pour --link-dest).
DEFAULT_MODE_INCREMENTAL=1

### SECTION 2 - INFORMATIONS D'ACCÈS (SSH/VM/Portable/Serveur) ###
# Ces informations sont pour se connecter aux machines distantes.

# Accès à la VM (Virtual Machine)
userVM="Multimedias"      # Nom d'utilisateur SSH sur la VM
ipVM="192.168.1.128"   # Adresse IP de la VM
portVM="22"           # Port SSH de la VM

# Accès au Portable
userPortable="fanou" # Nom d'utilisateur SSH sur le portable
ipPortable="192.168.1.60"    # Adresse IP du portable
portPortable="22"            # Port SSH du portable
pathPortable="" # Chemin de base des données sur le portable

# Accès au Serveur
userServeur="devUser" # Nom d'utilisateur SSH sur le serveur
ipServeur="192.168.1.100"   # Adresse IP du serveur
portServeur="22"           # Port SSH du serveur

### SECTION 3 - CHEMINS DES SAUVEGARDES LOCALES ET DISTANTES ###

# Dossier de base pour toutes les sauvegardes sur le disque externe (destination principale)
# C'est le point de montage de votre disque de sauvegarde externe.
# VÉRIFIEZ ET ADAPTEZ CE CHEMIN SI NÉCESSAIRE.
DEST_BASE_SAUVEGARDES="/mnt/usb-Hdd/Sauvegardes"

# UUID du disque de sauvegarde cible (pour vérification de sécurité)
# À récupérer avec 'sudo blkid' ou 'lsblk -f' sur votre système.
UUID_DISQUE_SAUVEGARDE="35bb9ca2-2022-4dfa-a201-1a2dde7ce1aa" # UUID fourni

# --- Sources locales sur cette machine (à adapter) ---
# REMPLACEZ '/home/kubu/...' par les chemins réels de vos dossiers si différents.
SOURCE_LOCAL_DOCS_ERIC="/home/kubu/Documents/Eric/"
SOURCE_LOCAL_DOCS_FANOU="/home/kubu/Documents/Fanou/"
SOURCE_LOCAL_DOCS_COMMUNS="/home/kubu/Documents/Commun/"
SOURCE_LOCAL_MUSIQUES="/home/kubu/Musiques/"

# --- Sources distantes sur les autres machines (à adapter) ---
# Ce sont les chemins sur les machines VM, Portable, Serveur.
# VÉRIFIEZ ET ADAPTEZ CES CHEMINS EN FONCTION DE VOS CONFIGURATIONS.
SOURCE_DIST_PHOTOS_VM="/home/$userVM/PhotosVM/"
SOURCE_DIST_PROJETS_SERVEUR="/var/www/projets/"
SOURCE_DIST_DOCS_PORTABLE="/home/$userPortable/Documents/"

### SECTION 4 - CHEMINS DES DESTINATIONS DES SAUVEGARDES PRINCIPALES (NON INCREMENTALES) ###
# Ces chemins sont les destinations pour les sauvegardes complètes (mode 0)
# ou les dernières versions synchronisées (mode 1, après la création des liens).
# Ils sont situés directement sous DEST_BASE_SAUVEGARDES.

DEST_MAIN_DOCS_ERIC="${DEST_BASE_SAUVEGARDES}/DocumentsEric/"
DEST_MAIN_DOCS_FANOU="${DEST_BASE_SAUVEGARDES}/DocumentsFanou/"
DEST_MAIN_DOCS_COMMUNS="${DEST_BASE_SAUVEGARDES}/DocumentsCommuns/"
DEST_MAIN_PROJETS="${DEST_BASE_SAUVEGARDES}/ProjetsServeur/"
DEST_MAIN_PHOTOS="${DEST_BASE_SAUVEGARDES}/PhotosVM/"
DEST_MAIN_DOCS_PORTABLE="${DEST_BASE_SAUVEGARDES}/DocumentsPortable/"
DEST_MAIN_MUSIQUES="${DEST_BASE_SAUVEGARDES}/Musiques/"

### SECTION 5 - CHEMINS DES DESTINATIONS DES SAUVEGARDES INCREMENTALES (DATÉES) ###
# Ces chemins sont les bases pour les sauvegardes incrémentales datées (ex: /mnt/usb-Hdd/Sauvegardes/incremental-DocumentsEric/2025-06-23/).
# Ils sont situés directement sous DEST_BASE_SAUVEGARDES.
DEST_INCR_BASE_DOCS_ERIC="${DEST_BASE_SAUVEGARDES}/incremental-DocumentsEric/"
DEST_INCR_BASE_DOCS_FANOU="${DEST_BASE_SAUVEGARDES}/incremental-DocumentsFanou/"
DEST_INCR_BASE_DOCS_COMMUNS="${DEST_BASE_SAUVEGARDES}/incremental-DocumentsCommuns/"
DEST_INCR_BASE_PROJETS="${DEST_BASE_SAUVEGARDES}/incremental-ProjetsServeur/"
DEST_INCR_BASE_PHOTOS="${DEST_BASE_SAUVEGARDES}/incremental-PhotosVM/"
DEST_INCR_BASE_DOCS_PORTABLE="${DEST_BASE_SAUVEGARDES}/incremental-DocumentsPortable/"
DEST_INCR_BASE_MUSIQUES="${DEST_BASE_SAUVEGARDES}/incremental-Musiques/"

### SECTION 5.1 - RÉTENTION DES SAUVEGARDES INCRÉMENTALES (en jours) ###
# Définissez ici le nombre de jours de rétention pour chaque type de sauvegarde.
# Mettre à 0 pour désactiver le nettoyage automatique pour cette catégorie.

# Rétention pour Documents Eric
JOURS_RETENTION_DOCS_ERIC_QUOTIDIEN=7    # Nombre de jours pour les sauvegardes quotidiennes
JOURS_RETENTION_DOCS_ERIC_HEBDO=4      # Nombre de semaines pour les sauvegardes hebdomadaires (Lundi)
JOURS_RETENTION_DOCS_ERIC_MENSUEL=12   # Nombre de mois pour les sauvegardes mensuelles (1er du mois)

# Rétention pour Documents Fanou
JOURS_RETENTION_DOCS_FANOU_QUOTIDIEN=7
JOURS_RETENTION_DOCS_FANOU_HEBDO=4
JOURS_RETENTION_DOCS_FANOU_MENSUEL=12

# Rétention pour Documents Communs
JOURS_RETENTION_DOCS_COMMUNS_QUOTIDIEN=7
JOURS_RETENTION_DOCS_COMMUNS_HEBDO=4
JOURS_RETENTION_DOCS_COMMUNS_MENSUEL=12

# Rétention pour Projets Serveur
JOURS_RETENTION_PROJETS_QUOTIDIEN=14
JOURS_RETENTION_PROJETS_HEBDO=8
JOURS_RETENTION_PROJETS_MENSUEL=24

# Rétention pour Photos VM
JOURS_RETENTION_PHOTOS_QUOTIDIEN=7
JOURS_RETENTION_PHOTOS_HEBDO=4
JOURS_RETENTION_PHOTOS_MENSUEL=12

# Rétention pour Documents Portable
JOURS_RETENTION_DOCS_PORTABLE_QUOTIDIEN=7
JOURS_RETENTION_DOCS_PORTABLE_HEBDO=4
JOURS_RETENTION_DOCS_PORTABLE_MENSUEL=12

# Rétention pour Musiques
JOURS_RETENTION_MUSIQUES_QUOTIDIEN=7
JOURS_RETENTION_MUSIQUES_HEBDO=4
JOURS_RETENTION_MUSIQUES_MENSUEL=12


### SECTION 6 - POINTS DE MONTAGE SSHFS ###

# Dossier de base pour les montages SSHFS temporaires sur cette machine.
BASE_MONTAGE_SSHFS="/tmp/sshfs_mounts"

# Points de montage locaux temporaires pour SSHFS. Ils seront créés/utilisés/démontés par le script.
MONTAGE_SSHFS_PHOTOS="${BASE_MONTAGE_SSHFS}/photos_vm"
MONTAGE_SSHFS_IMAGES="${BASE_MONTAGE_SSHFS}/images_vm" # Ajouté comme exemple si besoin
MONTAGE_SSHFS_MUSIQUES="${BASE_MONTAGE_SSHFS}/musiques_vm" # Ajouté comme exemple si besoin

### SECTION 7 - FICHIERS DE FONCTIONS EXTERNES ###
# Chemin vers le script contenant les fonctions de gestion d'erreur et de journalisation.
# Le chemin est construit dynamiquement basé sur l'emplacement du script principal.
CHEMIN_FONCTIONS_ERREUR="${SCRIPT_DIR}/fonctions_erreur.sh"
