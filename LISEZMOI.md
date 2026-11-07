# PerfManager

Petite appli Windows pour basculer ton PC en mode **Stream + Jeu**, **Jeu seul** ou **Bureau** en un clic.

## Installation

1. Dézippe le dossier où tu veux (ex. `C:\Outils\PerfManager`).
2. Double-clique sur **PerfManager.bat**, accepte la demande admin (nécessaire pour arrêter des services).
3. Optionnel : clic droit sur `PerfManager.bat` → *Envoyer vers → Bureau (créer un raccourci)*.

Rien à installer : c'est du PowerShell + l'interface Windows intégrée.

## Utilisation

- Clique sur un profil à gauche : la liste des actions s'affiche.
- Décoche ce que tu ne veux pas cette fois-ci, puis **Appliquer le profil**.
- **Tout restaurer** (ou le profil *Bureau / Normal*) relance les services arrêtés, rouvre les apps fermées (OneDrive…), remet ton plan d'alimentation et les notifications.
- En haut : CPU, RAM, GPU (charge + température) et VRAM en direct. À droite : les programmes qui consomment le plus de mémoire.

L'appli ne **désactive** jamais un service : elle l'arrête seulement. Au pire, un redémarrage du PC remet tout par défaut.

## Personnaliser

Bouton **Modifier les profils** → ouvre `profiles.json` dans le Bloc-notes, puis **Recharger**.

- `killProcesses` : apps à fermer (nom du processus sans `.exe`, visible dans le Gestionnaire des tâches → onglet Détails). `"default": false` = décoché par défaut.
- `stopServices` : services à arrêter (nom court du service, visible dans `services.msc`).
- `launch` : apps à lancer. **Vérifie les chemins d'OBS et Steam** si tu les as installés ailleurs.
- `priorities` : priorité CPU (`AboveNormal`, `High`…). Évite `High` sur le jeu + OBS en même temps.
- `protectedProcesses` : jamais fermés, même par erreur (OBS, Discord, Steam, Canon EOS Webcam Utility…).
- `powerPlan` : `high`, `ultimate` ou `balanced`.

## Ligne de commande (raccourci, Stream Deck…)

```
powershell -ExecutionPolicy Bypass -File PerfManager.ps1 -Profil "Stream + Jeu"
powershell -ExecutionPolicy Bypass -File PerfManager.ps1 -Restaurer
```

## Conseils pour ta config

- **RTX 4060 + OBS** : encodeur *NVENC AV1* (ou *NVENC H.264* pour Twitch), préréglage P5/P6. Le CPU (5800X) reste libre pour le jeu.
- **Souris Scyrox V8 en 8000 Hz** : ce taux coûte du CPU. Pendant un stream, 2000–4000 Hz est souvent un meilleur compromis.
- **RAM Corsair 3600 C18** : vérifie dans le BIOS MSI que l'**A-XMP** est activé, sinon elle tourne en 2133 MHz.
- **Écran Odyssey G4 240 Hz** : active G-Sync compatible dans le panneau NVIDIA et choisis bien 240 Hz dans Windows.
- **Canon EOS M6** : si tu passes par *EOS Webcam Utility*, il est protégé ; ne l'ajoute pas aux apps à fermer.
- Windows Update peut parfois se relancer tout seul ; c'est normal et sans danger.

Le journal complet est dans `perfmanager.log`, l'état à restaurer dans `state.json`.

---

# PerfDeck : ton S24 Ultra en Stream Deck

Une appli pour téléphone qui pilote **OBS** (live, enregistrement, clips, scènes, sources, volumes) et tes **profils PerfManager**.

## Mise en route (une seule fois)

1. **OBS** : *Outils → Paramètres du serveur WebSocket* → coche **Activer le serveur WebSocket** (port 4455). Clique sur **Afficher les informations de connexion** et garde le mot de passe sous la main.
2. **PC** : double-clique sur **PerfRemote.bat** et accepte la demande admin. Une page s'ouvre avec un **QR code**.
3. **Téléphone** (même Wi-Fi que le PC) : scanne le QR code avec l'appareil photo, ça ouvre PerfDeck dans Chrome.
4. Dans PerfDeck : bouton **⚙** → colle le **mot de passe OBS** → Enregistrer.
5. Chrome : menu **⋮** → **Ajouter à l'écran d'accueil**. L'icône PerfDeck apparaît comme une appli.

Si Windows indique que ton réseau est **Public**, passe-le en **Privé** (Paramètres → Réseau et Internet → ta connexion), sinon le pare-feu bloque le téléphone.

## Ce que tu as sur le téléphone

- **Onglet OBS** : touches *Lancer/Couper le live* (confirmation avant de couper), *Enregistrer*, *Pause rec*, *Clip* (sauvegarde le replay buffer), chronos du live et de l'enregistrement, FPS et images perdues. Grille des **scènes**, interrupteurs pour **afficher/cacher les sources** (ex. caméra Canon), **muet et volume** de chaque source audio.
- **Onglet PC** : CPU, RAM, GPU (charge + température), VRAM en direct, tes **profils** en un appui (avec confirmation), **Tout restaurer** et le journal.
- **Onglet Jeux** : tes jeux Steam installés (tous disques confondus), avec jaquettes, triés du plus récemment joué. Un appui → *Lancer*, ou *Stream + Jeu, puis lancer* pour appliquer d'abord un profil.
- Bouton **⛶** : plein écran.

Pour la touche **Clip**, active le *Replay Buffer* dans OBS (Paramètres → Sortie → Replay Buffer).

## Démarrage automatique

Double-clique sur **PerfRemote-Autostart.bat** : le serveur se lance tout seul en arrière-plan à chaque ouverture de session, sans demande admin. Pour l'enlever : `PerfRemote-Autostart.bat retirer` dans une invite de commandes ouverte dans le dossier.

## Bon à savoir

- Ça ne marche que sur ton réseau local. Le code d'accès (dans le QR code, stocké dans `remote.json`) empêche les autres appareils du Wi-Fi de piloter ton PC. Supprime `remote.json` et relance PerfRemote pour en générer un nouveau.
- Pour une vraie appli plein écran sans barre Chrome, et l'écran qui reste allumé : dans Chrome Android, ouvre `chrome://flags`, cherche **Insecure origins treated as secure**, ajoute l'adresse affichée par PerfRemote (ex. `http://192.168.1.20:8765`), relance Chrome puis menu **⋮ → Installer l'application**.

---

# Nouveautés (v3)

## Vumètres audio
Dans l'onglet OBS, chaque source audio a son vumètre en direct (vert, jaune, rouge comme dans OBS). Quand le micro est coupé, son vumètre reste affiché **en gris** : tu vois que tu parles alors que personne ne t'entend.

Les vumètres ne tournent que quand l'onglet OBS est affiché, pour économiser la batterie et la 4G.

## Alertes
Une bannière apparaît en haut de l'écran et le téléphone vibre quand :
- le stream **perd des images** (connexion), ou qu'OBS en saute à l'**encodage** ou au **rendu** (seuil réglable, 1 % par défaut) ;
- la **RTX 4060 dépasse 80 °C** ou le **processeur reste au-dessus de 90 %** plus de 10 s ;
- tu **parles micro coupé**, ou ton micro est coupé depuis plus de 30 s **pendant le live** ;
- le **stream se reconnecte**, ou OBS ou le PC deviennent injoignables.

Tout se règle dans **⚙ → Alertes** (seuils, activer/désactiver, vibration) avec un bouton *Tester une alerte*. Le ✕ d'une bannière la masque 2 minutes.

Les alertes marchent tant que PerfDeck est **ouvert à l'écran** : Chrome met en pause les pages en arrière-plan. Pendant un stream, laisse le S24 sur un support avec PerfDeck en plein écran.

## Utiliser PerfDeck hors de chez toi (NordVPN Meshnet ou Tailscale)
1. Active **NordVPN Meshnet** sur le PC et sur le S24 (déjà fait pour SalonOS), ou installe Tailscale sur les deux avec le même compte.
2. Le PC détecte tout seul son adresse Meshnet (100.x.x.x).
3. Relance **PerfRemote.bat** : la page d'appairage affiche maintenant un 2e QR code **« Partout »**.
4. Scanne-le, ajoute-le à l'écran d'accueil et colle une fois le mot de passe OBS dans ⚙.

Garde cette icône-là : elle marche aussi à la maison (Tailscale passe en direct sur ton Wi-Fi). Seuls tes appareils connectés à ton compte Tailscale peuvent joindre le PC, et le code d'accès reste exigé. Aucun port n'est ouvert sur ta box.


---

# Nouveautés (v5)

## Démarrer / Fin du stream en un bouton
En haut de l'onglet OBS :
- **▶ Démarrer le stream** : applique le profil du PC (Stream + Jeu), attend qu'OBS soit prêt, passe sur la scène d'attente, lance le live, compte à rebours, puis bascule sur la scène du live.
- **■ Fin du stream** : scène de fin, compte à rebours, coupe le live et l'enregistrement, puis profil du PC au choix (ex. Bureau / Normal).

Les scènes et les durées se règlent dans **⚙ → Macros** (PerfDeck devine tes scènes « Démarrage », « Jeu », « Fin » d'après leur nom). Bouton *Annuler* à tout moment.

## Raccourcis personnalisables
Grille de boutons colorés sous les commandes : **＋ Ajouter** puis choisis le type :
- changer de scène ;
- **Pause (BRB)** : scène de pause + micro coupé, et un 2e appui te ramène sur ta scène, micro rouvert ;
- afficher ou cacher une source (webcam…) ;
- activer ou couper un **filtre** (flou, chroma…) ;
- micro muet / actif ;
- n'importe quel **raccourci clavier d'OBS** (capture d'écran, transition, sauver le replay…) ;
- **chapitre** d'enregistrement (OBS 30.2+, format « MP4 hybride »).

**Appui long** sur un bouton pour le renommer, changer sa couleur ou le supprimer.

## Aperçu de la scène
Une miniature de ce que voient tes viewers, rafraîchie toutes les 1,5 s (désactivable dans ⚙ → OBS).

## Profil automatique selon le jeu
Onglet **PC → Automatique** : quand tu lances un jeu Steam (depuis le PC ou le téléphone), PerfManager applique tout seul *Stream + Jeu* si OBS est ouvert, sinon *Jeu seul*, et restaure le PC quand tu fermes le jeu. Les deux profils se choisissent dans *Choisir les profils*.

## Appli Android 1.0.3
- **Boutons de volume** du S24 : Volume − = micro muet/actif, Volume + = clip (réglable dans ⚙ → Boutons de volume, actif quand PerfDeck est à l'écran).
- **Tuile « Micro OBS »** dans les réglages rapides (glisse deux fois du haut → crayon → ajoute *Micro OBS*) : coupe le micro sans ouvrir l'appli.
- **Widget** d'écran d'accueil (appui long sur l'écran d'accueil → Widgets → PerfDeck) : micro, clip, état.
- **Alertes écran éteint** : ⚙ → Alertes → *Même écran éteint*. PerfDeck envoie de vraies notifications Android (images perdues, micro coupé, GPU chaud, PC injoignable) même téléphone en poche. Autorise les notifications quand Android le demande ; une notification discrète « PerfDeck surveille ton live » reste affichée tant que c'est actif.
- **Micro principal** (⚙ → OBS) : celui que coupent la tuile, le widget, les raccourcis et les boutons de volume.
- **Mises à jour de l'appli** : quand le PC a une version plus récente (après une mise à jour PerfManager), l'onglet PC affiche *Nouvelle version de l'appli → Installer*. Pour cette première fois, installe la 1.0.3 depuis la page « Connecter le téléphone » du PC (QR code de l'appli) : elle remplace l'ancienne sans perdre l'association.

---

# Mises à jour automatiques (GitHub)

L'appli se met à jour toute seule depuis le dépôt GitHub `Lucas-tsl/Perfmanager`, avec ta clé GitHub existante (droit **Contents : lecture** sur ce dépôt).

## Mise en route (une seule fois)
1. Sur GitHub : *Settings → Developer settings → Fine-grained tokens* → ta clé → **Repository access** : ajoute `Perfmanager` → **Permissions → Contents : Read-only**.
2. Sur le PC : double-clique sur **PerfUpdate.bat**, colle la clé (clic droit), Entrée. Elle est **chiffrée par Windows** dans `update.json` : lisible seulement par ta session, sur ce PC, et jamais envoyée sur le dépôt.
3. PerfUpdate installe la dernière version. C'est tout.

## Ensuite, tout est automatique
- **PerfDeck Remote** vérifie GitHub au démarrage puis toutes les 30 minutes. Une nouvelle version s'installe toute seule **quand aucun profil n'est actif** (jamais en plein stream), puis le serveur redémarre en quelques secondes et le téléphone recharge l'appli.
- **Sur le téléphone** (onglet PC) : carte « Mise à jour disponible » avec un bouton *Installer*, et *Vérifier les mises à jour* en bas de l'onglet.
- **PerfManager** affiche un bouton « Mise à jour disponible » en haut à droite.
- À la main : relance **PerfUpdate.bat**.

Tes fichiers personnels ne sont jamais écrasés : `profiles.json`, `remote.json` (code d'accès du téléphone), `update.json` (clé), `state.json`, `perfmanager.log`.

Changer de clé : `PerfUpdate.bat -Setup` dans une invite de commandes ouverte dans le dossier. Si la clé expire, l'onglet PC du téléphone l'indique.

---

# Applis Windows et Android

Les deux applis se téléchargent dans **Releases** sur la page GitHub du dépôt (dernière version en haut).

## Windows : PerfManager-Setup.exe
1. Lance l'installateur. Windows SmartScreen peut afficher « Windows a protégé votre ordinateur » (l'appli n'est pas signée) : *Informations complémentaires → Exécuter quand même*.
2. Coche si tu veux une icône sur le bureau et le démarrage avec Windows.
3. PerfManager s'installe dans ton dossier utilisateur et s'ouvre. Une icône apparaît près de l'horloge :
   - double-clic : ouvre PerfManager ;
   - clic droit : appliquer un profil, tout restaurer, connecter le téléphone (QR code), rechercher les mises à jour, démarrer avec Windows, quitter.
4. L'appli lance aussi le serveur du téléphone : plus besoin de PerfRemote.bat. Si tu avais activé PerfRemote-Autostart, l'option « Démarrer avec Windows » de l'appli le remplace.

Tes profils, ton code d'accès et ta clé GitHub sont conservés. Les scripts se mettent toujours à jour tout seuls depuis GitHub.

## Android : PerfDeck (appli)
L'APK est servie directement par ton PC, pas besoin de GitHub ni d'Android Studio :
1. Sur le PC : clic droit sur l'icône PerfManager → **Connecter le téléphone** (ou lance `PerfRemote.bat`). La page affiche un QR code « Appli Android » et un **code à 6 chiffres**.
2. Scanne le QR code avec le S24 : `PerfDeck.apk` se télécharge depuis le PC. Ouvre-la et autorise l'installation.
3. Ouvre PerfDeck : il **trouve le PC tout seul sur le Wi-Fi**. Touche-le et tape le code à 6 chiffres.
4. Colle une fois le mot de passe OBS dans ⚙ : il est gardé par l'appli.

Ensuite l'appli passe **toute seule** par le Wi-Fi à la maison et par **NordVPN Meshnet** (ou Tailscale) dehors : le PC lui donne son adresse Meshnet au moment de l'association. Si tu actives Meshnet plus tard, associe à nouveau le téléphone (touche retour → *Associer un autre PC*).

Dans l'appli : écran toujours allumé, vibrations pour les alertes, touche retour → *Recharger*, *Associer un autre PC*, *Quitter*.

Le code à 6 chiffres change après chaque association et après 5 essais faux.

## Construire les applis soi-même
- **APK** : `bash android/build.sh` sous Linux (outils listés en tête du script, même méthode que salonos-mobile). La clé de signature `android/keystore/` n'est jamais dans le dépôt : garde-la, les mises à jour de l'appli doivent être signées avec la même clé.
- **Windows** : `powershell -ExecutionPolicy Bypass -File windows\build.ps1` sur le PC (compilateur C# fourni avec Windows ; Inno Setup pour l'installateur).
