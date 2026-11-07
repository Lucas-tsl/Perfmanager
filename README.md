# PerfManager + PerfDeck

Gestion des performances d'un PC de stream/jeu (Windows) et télécommande façon Stream Deck pour téléphone.

- **PerfManager** (`PerfManager.bat`) : profils *Stream + Jeu*, *Jeu seul*, *Bureau* qui coupent les services et applis inutiles, plan d'alimentation, suivi CPU/RAM/GPU, restauration en un clic.
- **PerfDeck** (`PerfRemote.bat`) : appli web installable sur le téléphone pour piloter OBS (live, enregistrement, clips, scènes, sources, audio avec vumètres), les profils, et lancer les jeux Steam. Alertes (images perdues, température GPU, micro coupé…). Accès hors de chez soi via Tailscale.
- **Mises à jour automatiques** depuis ce dépôt (`PerfUpdate.bat`).

Configuration : AMD Ryzen 7 5800X, RTX 4060, 32 Go, OBS + NVENC.

Mode d'emploi complet : [LISEZMOI.md](LISEZMOI.md).

## Téléchargements

**Releases** : `PerfManager-Setup.exe` (Windows 10/11) et `PerfDeck.apk` (Android 8+), compilés automatiquement par GitHub Actions (`windows/`, `android/`).
