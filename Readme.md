# 📘 Manuel Utilisateur – Script de Sauvegarde

## 📁 Structure des fichiers

Organisez les fichiers dans un répertoire comme suit :

/opt/sauvegarde/
├── sauvegarde.sh
├── config.sh
├── fonctions_erreur.sh
└── README.md



## 📝 Description des fichiers

| Fichier              | Rôle                                         |
|----------------------|----------------------------------------------|
| `sauvegarde.sh`      | Script principal à exécuter                  |
| `config.sh`          | Fichier de configuration (répertoires, etc.)|
| `fonctions_erreur.sh`| Fonctions de gestion des erreurs            |
| `README.md`          | Documentation générale (optionnelle)        |

---

## ⚙️ Installation

### 1. Créer le dossier cible

```bash
sudo mkdir -p /opt/sauvegarde

'''
2. Télécharger les fichiers
```bash
cd /opt/sauvegarde

sudo curl -O https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/sauvegarde.sh
sudo curl -O https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/config.sh
sudo curl -O https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/fonctions_erreur.sh
sudo curl -O https://raw.githubusercontent.com/ps81frt/sauvegarde/refs/heads/main/README.md
'''

3. Rendre le script exécutable

```bash
sudo chmod +x sauvegarde.sh
'''

🚀 Utilisation

1. Configurer config.sh

```bash
sudo nano /opt/sauvegarde/config.sh
'''
  ➤ Modifiez les chemins à sauvegarder, les destinations, etc.

2. Lancer manuellement
```bash
cd /opt/sauvegarde
sudo ./sauvegarde.sh
'''

⏰ Automatiser avec Cron


Exemple pour exécuter la sauvegarde chaque jour à 2h00 du matin :

****
sudo crontab -e
'''

Ajoutez la ligne suivante :
```bash
0 2 * * * /opt/sauvegarde/sauvegarde.sh >> /var/log/sauvegarde.log 2>&1
'''

🔐 Sécurité

Protégez l’accès aux fichiers :

```bash
sudo chown -R root:root /opt/sauvegarde
sudo chmod -R 700 /opt/sauvegarde
'''

🧪 Tests recommandés

✅ Vérifier les droits d’accès aux fichiers

✅ Lancer une sauvegarde manuelle

✅ Vérifier les logs (ajoutez si nécessaire un fichier de log dans config.sh)

✅ Tester la restauration depuis une sauvegarde

ℹ️ Aide

Pour plus d’informations, consultez le fichier README.md fourni avec le projet.


---








