# NEXT

Point d'entrée de toute reprise. Une page, pas plus.

## État au 7 septembre 2026

Dépôt initialisé depuis le spike gemboy (`claude/usage-2mr345` @ `c952ded`). `lib/` est vide, tout
le code est dans `legacy/`, tout le savoir dans `data/` et `docs/`.

**Indicateurs**

| Indicateur | Valeur |
|---|---|
| Progression dans le jeu | Bouclier niveau 1 obtenu, maison de départ quittée, 4 PNJ du village avec dialogue capturé (Tarin, la 2e habitante de la maison, le villageois de screen3, Pépé le Ramollo dans house2). Pas d'épée. |
| Trajet A vers B | Non mesuré en frames. `ScreenMap.navigate!` fonctionne sur les 7 écrans cartographiés, au prix du code `legacy/`. |
| Faits vérifiés (registre RAM) | 6 entrées HRAM `verified` : X, Y, ombre de X, direction, salle, carte. Voir `data/ram_registry.json`. |

**Checkpoints reproductibles** (`legacy/game_agents/zelda/scenarios.rb`, fichiers dans
`/tmp/zelda_checkpoints`, non versionnés) : `after_shield_interior`, `front_yard`,
`overworld_screen2`, `villager_screen`, `shop_screen`, `screen3_north`, `house2_interior`.
Identifiants de salle lus en `0xFFF6` : front_yard 162, overworld_screen2 178, villager_screen 177,
screen3_north 161, shop_screen 179, house2_interior 169.

## Décisions en vigueur

D1 ratifiée (HRAM). D2 (OAM) obsolète. D3 tranchée : DMG. D4 à trancher, différée au résultat de
Session 1 (voir `PLAN.md`, tranchage formel en Session 3). D5, D6, D7 ratifiées. Voir
`DECISIONS.md`.

## Dette d'import à combler (constat du 7 septembre 2026, pas encore traité)

`koholint-init` a été importé depuis `gemboy@claude/usage-2mr345` au commit `c952ded`, un cran
avant le dernier commit de cette branche (`5ee7949`, "Archive the HRAM diff and other reusable
scratchpad diagnostics into experiments/"). Ce commit manquant ajoute les scripts qui ont produit
D1 (`ram_diff_hram.rb`, `ram_diff_hram2.rb`, `diag_scx_scy.rb`, `diag_scx_scy2.rb`,
`house2_dialogue.rb`, `house2_sprite2.rb`, absents de `legacy/game_agents/experiments/`) et une
note dans `ram_registry.json` disant explicitement de réutiliser la même technique de diff complet
pour la question ci-dessous. Le code de `legacy/` lui-même est identique par ailleurs (vérifié).
À importer ou non : décision du propriétaire.

## Prochaine question proposée (Session 1 du plan, voir `PLAN.md`)

**Le terrain est-il lisible depuis l'état du jeu ?** Hypothèse d'ingénierie, à vérifier : le jeu
décode chaque salle en une grille d'objets 16×16 (10×8) en WRAM et lit la collision de chaque type
d'objet dans une table ROM. Si c'est vrai, la collision se lit au lieu de se sonder, et D4 se
tranche presque seule.

- **Rôle** : explorateur.
- **Critère** : pour deux écrans déjà cartographiés (`front_yard`, `starting_house`), une lecture
  WRAM prédit les arêtes `:blocked` et `:ok` des grilles de `legacy/.../screen_maps/` avec un taux
  d'accord mesuré et expliqué pour chaque désaccord.
- **Budget** : une session, 3 h.
- **Comment** : depuis un checkpoint, diff WRAM entre deux salles (`0xFFF6` différent) pour isoler
  la zone qui change en bloc ; corréler sa disposition 10×8 avec la tilemap visible ; puis
  confronter aux grilles oracle.
- **Livrable** : entrée `data/ram_registry.json` promue ou réfutée, plus le taux d'accord dans le
  rapport de session.
- **Indicateur visé** : faits vérifiés.

Session suivante si celle-ci est confirmée (ou réfutée) : Session 2 du plan, l'outil de navigation
par snapshot (D7) — bloquée tant que l'API de session headless (D6) n'a pas atterri côté gemboy
(externe, hors périmètre koholint, voir `DECISIONS.md`).

## Ce qu'il ne faut PAS refaire

- Chercher la position de Link ailleurs qu'en HRAM. C'est trouvé.
- Étendre `ScreenMap`, `TileClassifier` ou `TileCatalog`. Ils sont remplacés, pas améliorés.
- Lancer `ScreenMap.build` sur un nouvel écran "en attendant". 1,5 à 5 h par écran pour une
  donnée que D4 peut rendre inutile.
- Lire `docs/archive/EXPLORATION_LOG.md` en entier pour reprendre. Y chercher un fait, au plus.

## Rapport de la dernière session

```
Question : la position de Link et l'identifiant de salle sont-ils en HRAM ?
Réponse : confirmée. 0xFF98/0xFF99 (X/Y, verified_count 8), 0xFF9E (direction), 0xFFF6 (salle,
          6 écrans distincts), 0xFFF7 (carte : 0 extérieur, 16 pour house2).
Indicateurs : jeu = 4 PNJ, pas d'épée | trajet A→B = non mesuré | faits vérifiés = 6 HRAM
Décisions prises : D1 (mesurée, à ratifier). Trois écrans supplémentaires cartographiés avec le
          code legacy avant la revue (shop_screen, screen3_north, house2_interior).
Prochaine question proposée : voir ci-dessus.
Ce qu'il ne faut PAS refaire : voir ci-dessus.
```
