# RoFinder V3 — Discord Bot

Bot Discord (discord.js v14) de modération, sécurité (anti-nuke), utilitaires, mini-jeux et fun.
Tout fonctionne avec un préfixe (par défaut `?`).

## ✨ Fonctionnalités

- **Sécurité / Anti-nuke (fonctionnelle)** : `antibot`, `antichannel`, `antilink`, `antiban`, `antiguildupdate`, `anticreateinvite`, `antikick`, `antimassban`, `antimasskick`, `antiraid`, `anti-mass-mention`, `spam` (anti-spam).
  - `secur-on` / `secur-max` : tout activer · `secur-off` : tout désactiver · `secur` : voir l'état.
  - `whitelist add/remove @user` et `whitelist list` : exempter des membres de confiance. Le propriétaire du serveur et l'owner du bot sont toujours exemptés.
- **Modération** : `ban`, `tempban`, `unban`, `kick`, `mute`, `unmute`, `warn`, `sanction`, `clearwarns`, `clear`, `prune`, `lock`, `unlock`, `renew`, `snipe`, `gban`/`gunban` (owner).
- **Logs** : `setup-logs #salon` — toutes les actions de modération et de sécurité y sont enregistrées.
- **Vérification (captcha)** : `setup-captcha #salon @role` — poste un bouton « Verify » qui donne le rôle.
- **Bienvenue** : `greet #salon [message]` (placeholders `{user}`, `{username}`, `{server}`, `{count}`), `greet-list`.
- **Rôle automatique / membre** : `setup-autorole @role` + `scan-membre` pour appliquer le rôle à TOUS les membres existants.
- **Rôle selon statut** : `set-statut @role <mot-clé>` — donne un rôle aux membres ayant ce mot dans leur statut personnalisé.
- **Tickets** : `setup-ticket #salon`.
- **Utilitaires** : `serverinfo`, `userinfo`, `pp`, `pp-serveur`, `pp-random`, `banner`, `member`, `vc`, `sondage`, `say`, `embed`, `invite-guild`, `alladmin`, `stat`.
- **Mini-jeux** : `poker`, `chess`, `youtube`, etc. (activités vocales Discord).
- **Fun** : `8ball`, `pf`, `gay`, `politique`.
- **Bot** : `help` (menu paginé), `ping`, `setprefix`, `patch-note`, `set-bio`, `join`/`leave`/`allserveur` (owner).

> Tape `?help` dans Discord pour le menu complet et paginé.

## ⚙️ Prérequis Discord (IMPORTANT)

Sur le [Developer Portal](https://discord.com/developers/applications) → ton application → **Bot**, active les 3 **Privileged Gateway Intents** :
- ✅ Presence Intent
- ✅ Server Members Intent
- ✅ Message Content Intent

Sans ça, le bot ne démarre pas. Invite le bot avec la permission **Administrator** (nécessaire pour l'anti-nuke).

## 🔧 Configuration

Crée/édite `config.json` (voir `config.example.json`) :

```json
{
    "token": "TON_TOKEN",
    "default_prefix": "?",
    "owner_id": "TON_ID_DISCORD"
}
```

## 🚀 Lancer en local

```bash
npm install
npm start
```

## 🖥️ Déploiement VPS 24/7 (Ubuntu/Debian)

```bash
# 1. Dépendances système (Node + outils de build pour better-sqlite3)
sudo apt update && sudo apt install -y curl git build-essential python3
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# 2. Récupérer le bot
git clone <ton-repo> rofinder   # ou: scp le dossier vers le VPS
cd rofinder
# (crée config.json avec ton token ici)
npm install

# 3. PM2 pour tourner en permanence + redémarrage auto
sudo npm install -g pm2
pm2 start ecosystem.config.js      # ou: pm2 start index.js --name rofinder
pm2 save
pm2 startup                        # exécute la commande affichée pour démarrer au boot
```

Commandes PM2 utiles :

```bash
pm2 logs rofinder      # voir les logs en direct
pm2 restart rofinder   # redémarrer
pm2 stop rofinder      # arrêter
pm2 status             # état
```

## 🔁 Réactiver le rôle « membre » après inactivité

1. `?setup-autorole @membre` (définit le rôle donné aux nouveaux membres).
2. `?scan-membre` — parcourt tous les membres et ajoute le rôle à ceux qui ne l'ont pas.
   - Tu peux aussi faire directement `?scan-membre @membre`.

> Le rôle du bot doit être **au-dessus** du rôle `@membre` dans la hiérarchie des rôles.

## ⚠️ Sécurité du token

Ton token était présent dans `config.json`. Comme il a été partagé, **régénère-le** (Developer Portal → Bot → Reset Token) puis remets le nouveau dans `config.json`. Le fichier `config.json` est dans `.gitignore` pour éviter de le publier.
