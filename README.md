# 📘 Manuel Utilisateur – Script de Sauvegarde

## 📁 Structure des fichiers

# Organisez les fichiers dans un répertoire comme suit :
# /opt/sauvegarde/
# ├── sauvegarde.sh
# ├── config.sh
# ├── fonctions_erreur.sh
# └── README.md

## 📝 Description des fichiers

# sauvegarde.sh       : Script principal à exécuter
# config.sh           : Fichier de configuration (répertoires, options)
# fonctions_erreur.sh : Fonctions de gestion des erreurs
# README.md           : Documentation générale (optionnelle)

## 1. Prérequis / Dépendances

        sudo apt update && sudo apt install -y rsync sshfs fuse mailutils util-linux coreutils findutils gawk sed

## ⚙️ Installation

### 1. Créer le dossier cible

        sudo mkdir -p /opt/sauvegarde

### 2. Télécharger les fichiers

        cd /opt/sauvegarde
        sudo curl -O https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/sauvegarde.sh
        sudo curl -O https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/config.sh
        sudo curl -O https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/fonctions_erreur.sh
        sudo curl -O https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/README.md

### 3. Rendre le script exécutable

        sudo chmod +x sauvegarde.sh

## 🚀 Utilisation

### 1. Configurer config.sh

        sudo nano /opt/sauvegarde/config.sh
        # ➤ Modifiez les chemins à sauvegarder, les destinations, etc.

### 2. Lancer manuellement

        cd /opt/sauvegarde
        sudo ./sauvegarde.sh
        # Lancer une sauvegarde manuelle et vérifier le retour

## ⏰ Automatiser avec Cron

        sudo crontab -e
        # Ajoutez la ligne suivante pour une sauvegarde quotidienne à 2h00 :
        # 0 2 * * * /opt/sauvegarde/sauvegarde.sh >> /var/log/sauvegarde.log 2>&1

## 🔐 Sécurité

# Protégez l’accès aux fichiers :

        sudo chown -R root:root /opt/sauvegarde
        sudo chmod -R 700 /opt/sauvegarde

## 🧪 Tests recommandés

# Vérifier les droits d’accès aux fichiers

        ls -l /opt/sauvegarde

# Lancer une sauvegarde manuelle

        cd /opt/sauvegarde
        sudo ./sauvegarde.sh

# Vérifier les logs (ajoutez si nécessaire un fichier de log dans config.sh)

        tail -n 20 /var/log/sauvegarde.log

# Tester la restauration depuis une sauvegarde (selon vos procédures spécifiques)

## ℹ️ Aide

# Pour plus d’informations, consultez le fichier README.md fourni avec le projet.
