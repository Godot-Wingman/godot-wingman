# Godot Pilot

**Un serveur MCP qui fonctionne sur votre ordinateur et permet à n'importe quel assistant IA d'utiliser l'éditeur Godot comme le ferait une personne.** Il peut voir l'éditeur, construire des scènes, modifier des propriétés dans l'inspecteur, écrire et vérifier des scripts, jouer au jeu avec de vraies touches du clavier, lire les erreurs et les corriger.

> **Non officiel.** Godot Pilot est un projet communautaire. Il n'a aucun lien avec la Godot Foundation ni avec le projet Godot Engine. « Godot » est une marque de la Godot Foundation.

> **Statut : développement précoce (0.x).** La version 1.0 ne sortira pas avant que le projet soit stable et testé par de vrais utilisateurs.

Pour plus de détails, voir le [README en anglais](README.md) et le [guide d'installation](docs/INSTALL.md).

## En bref

- Les changements se font dans l'éditeur ouvert et entrent dans l'historique d'annulation de Godot : on peut les annuler avec Ctrl+Z.
- L'IA voit l'éditeur, les vues 2D et 3D et le jeu en cours.
- Elle joue avec de vraies entrées : maintenir une touche, gérer le timing, avancer image par image, « attendre jusqu'à ce que ... ».
- Elle lit la documentation de la version de Godot installée et les classes de vos GDExtension.
- Le panneau Godot Pilot en bas de l'éditeur liste chaque changement fait par l'IA. Il peut remettre les scripts, scènes, ressources et réglages dans leur état d'avant l'étape choisie.
- Quand vous appuyez sur Ctrl+Z, modifiez quelque chose à la main ou revenez en arrière depuis le panneau, l'IA l'apprend à son étape suivante. Elle ne continue pas à travailler sur un état qui n'existe plus.
- Plusieurs IA dans le même éditeur (par exemple Claude Code et Cursor) peuvent se dire ce qu'elles vont modifier. Vous pouvez aussi écrire à toutes depuis le panneau.
- Les outils sont regroupés : 120 outils dans 20 groupes (scène, inspecteur, script, animation, tilemap, interface, 3D, shader, son, export, lancer le jeu...). L'IA n'active que les groupes dont elle a besoin.

## Modes d'autorisation

| Mode | Ce que l'IA peut faire |
|---|---|
| `full` (par défaut) | Utilise tous les outils activés. |
| `confirm` | Regarde librement. Avant chaque modification, Godot montre ce que l'IA veut faire (pour le GDScript, le code entier) et vous choisissez Autoriser ou Refuser. |
| `read-only` | Regarde seulement. Les outils qui modifient des fichiers, exécutent du GDScript, lancent le jeu ou envoient des entrées sont masqués. |

Vous pouvez choisir le mode quand vous ajoutez Godot Pilot à votre client IA (`--mode`), ou dans Godot, depuis le panneau Godot Pilot. Si les deux diffèrent, c'est le mode le plus strict qui s'applique. Dans la fenêtre de confirmation, vous pouvez aussi autoriser un outil pour le reste de la session. Ainsi, une longue série de modifications semblables ne demande pas la permission à chaque fois.

## Langages

- **GDScript** : prise en charge complète.
- **C#** : l'IA peut écrire et modifier des scripts C# quand le projet est ouvert avec la version .NET de Godot.
- **GDExtension (Rust, C++)** : l'IA voit les classes ajoutées par vos extensions, avec leurs propriétés, méthodes et signaux.

Les principaux tests de bout en bout utilisent un projet GDScript. Chaque nuit, et avant chaque version, des tests séparés vérifient aussi un projet C# (Godot .NET 4.7.2 : un script C# est écrit, compilé avec `dotnet build`, attaché à un nœud et exécuté dans le jeu) et une GDExtension écrite en Rust avec godot-rust (sa classe est documentée, ajoutée à une scène, modifiée et appelée dans le jeu).

## Confidentialité

Godot Pilot fonctionne sur votre ordinateur et n'envoie rien sur vous ou sur votre projet, où que ce soit : pas de compte, pas de cloud, **aucune collecte de données**.

Pour vous prévenir des nouvelles versions, il télécharge au plus une fois par jour la liste des versions de Godot Pilot depuis GitHub. C'est comme ouvrir la page des versions dans un navigateur. Rien n'est envoyé. Vous pouvez désactiver cette vérification avec `--no-update-check`. Quand une nouvelle version sort, l'IA vous le dit et peut l'installer si vous êtes d'accord. Vous pouvez aussi lancer `godot-pilot update`.

Votre client IA est un sujet à part : ce que l'IA lit via Godot Pilot (code, scènes, captures d'écran, erreurs) est envoyé au modèle d'IA que vous utilisez, selon les règles de ce fournisseur. Seul un modèle qui tourne sur votre propre ordinateur garde tout en local.

Godot 4.5 ou plus récent est requis. Chaque modification est testée avec Godot 4.5.2, 4.6.3 et 4.7.2.

## Licence

[GNU AGPL-3.0](LICENSE). Vous pouvez utiliser, étudier, modifier et partager Godot Pilot. Si vous distribuez une version modifiée, ou si vous la proposez à d'autres via un réseau, vous devez partager son code source sous la même licence.

**Les jeux que vous créez avec Godot Pilot ne sont pas concernés par cette licence.** L'addon est un outil de l'éditeur. Il n'est pas inclus dans les jeux exportés, donc votre jeu peut avoir la licence de votre choix et être vendu librement.

- **Le code écrit par l'IA pour moi est-il sous AGPL ?** Non. L'AGPL couvre seulement les fichiers de Godot Pilot lui-même : le serveur et le dossier `addons/godot_pilot`. Ce que vous et l'IA créez dans votre projet vous appartient.
- **Puis-je l'utiliser au travail, dans une entreprise ?** Oui. Utiliser Godot Pilot ne vous oblige à rien partager.
- **Quand dois-je partager le code source ?** Seulement quand vous donnez Godot Pilot lui-même à d'autres, modifié ou non, ou quand vous laissez d'autres utiliser une version modifiée via un réseau.

Ceci est un résumé, pas un avis juridique. Ce qui fait foi, c'est le [texte de la licence](LICENSE).
