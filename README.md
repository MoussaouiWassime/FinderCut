# FinderCut

Un équivalent natif et open-source de **Command X** pour macOS : coupez (`⌘X`) et collez (`⌘V`) des fichiers et dossiers dans le Finder exactement comme sur Windows et Linux.

## Fonctionnalités

- **Couper & Coller natif dans le Finder** : appuyez sur `⌘X` sur un ou plusieurs fichiers, puis `⌘V` dans le dossier de destination pour les déplacer.
- **100 % sûr (moteur natif du Finder)** : transforme `⌘X` en copie Finder et `⌘V` en `⌘⌥V` (*Déplacer l'élément ici*). Vous conservez intégralement :
  - L'annulation native (`⌘Z`)
  - Les boîtes de dialogue de conflit (Conserver les deux / Remplacer / Arrêter)
  - Les barres de progression et transferts iCloud / disques externes / SMB
- **Respecte la saisie de texte** : n'interfère jamais lorsque vous renommez un fichier, tapez dans la recherche Finder, « Aller au dossier » (`⌘⇧G`) ou Lire les informations (`⌘I`).
- **Compatible tous claviers** : AZERTY, QWERTY, BÉPO, Dvorak, Colemak.
- **Annulation rapide** : appuyez sur `Échap` (ou copiez autre chose avec `⌘C`) pour annuler la coupe.
- **Indicateur visuel (HUD) & barre des menus** : affiche discrètement les éléments coupés, leur compteur dans la barre des menus, et permet d'annuler ou mettre en pause en un clic.
- **Lancement à l'ouverture de session** (`SMAppService`) et option pour masquer l'icône de la barre des menus.

## Compilation et installation

Pour générer l'installeur `.dmg` (glisser-déposer vers Applications) :

```bash
./Scripts/build-dmg.sh
```

L'image disque est générée dans `build/FinderCut.dmg` (et le bundle dans `build/FinderCut.app`).

Pour compiler et installer directement dans `/Applications` sans passer par le `.dmg` :

```bash
./Scripts/build-app.sh --install
```

## Première utilisation

1. Ouvrez `FinderCut.app`.
   > **Note (Gatekeeper)** : l'application n'étant pas notarisée via un compte Apple Developer payant, macOS peut bloquer le premier lancement. Si c'est le cas, faites un clic droit sur `FinderCut.app` → **Ouvrir** (ou autorisez-la dans **Réglages Système → Confidentialité et sécurité**), ou exécutez `xattr -cr /Applications/FinderCut.app`.
2. Cliquez sur **Ouvrir Réglages d'Accessibilité** et activez **FinderCut** dans **Réglages Système → Confidentialité et sécurité → Accessibilité**.
3. Dès que l'autorisation est activée, FinderCut passe automatiquement au vert et fonctionne immédiatement dans le Finder.

## Licence

Distribué sous licence [MIT](LICENSE).
