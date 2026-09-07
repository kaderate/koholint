# Décisions

Une entrée par choix structurant : contexte, options, choix, et la condition qui l'invaliderait.
Statuts : `ratifiée` (validée par le propriétaire), `mesurée` (établie empiriquement, à ratifier),
`prise sans validation` (héritée du spike, à revoir), `à trancher` (ouverte, propriétaire).

## D1 — Source de position et de salle : HRAM, pas OAM

- **Statut** : ratifiée (7 septembre 2026).
- **Contexte** : le spike lisait la position de Link dans l'OAM par exclusion et détection de
  tuile, et nommait les écrans par ordre de découverte. Deux chasses par diff mémoire avaient
  échoué en ne scannant que la WRAM. Un diff sur tout l'espace `0x0000-0xFFFF`, fait le 7 septembre
  après la revue, a trouvé les octets en HRAM.
- **Choix** : `0xFF98` (X), `0xFF99` (Y), `0xFF9E` (direction), `0xFFF6` (salle), `0xFFF7` (carte)
  sont la source primaire. Détail et `verified_count` dans `data/ram_registry.json`. L'OAM devient
  un cross-check, jamais la source.
- **Invalidée si** : une salle où ces octets ne suivent pas Link, ou deux salles distinctes avec le
  même `0xFFF6`+`0xFFF7`.

## D2 — Position par OAM

- **Statut** : prise sans validation pendant le spike, **obsolète** par D1.
- Conservée pour mémoire : elle a coûté `find_link`, `cell_for`, la détection de scroll par
  SCX/SCY, `clear_entry_lock!` et une part des budgets de retries. Ne pas réintroduire.

## D3 — Mode matériel : DMG

- **Statut** : tranchée (7 septembre 2026) — **DMG**.
- **Contexte** : la ROM DX tourne en DMG faute de flag `--cgb`, découvert incidemment. Le contenu
  DX (donjon des couleurs, photographe) est verrouillé derrière le mode CGB. Les checkpoints et le
  catalogue de tuiles (hash incluant la palette) sont spécifiques au mode.
- **Choix** : rester en DMG. Checkpoints et données actuels réutilisables ; le contenu DX reste
  inaccessible tant que ce choix n'est pas révisé.
- **Invalidée si** : le propriétaire décide que l'accès au contenu DX-only justifie de tout
  régénérer. Coût connu et accepté au moment de la bascule : chaque checkpoint/donnée créée en DMG
  d'ici là est à refaire.

## D4 — Exploration exhaustive par écran

- **Statut** : à trancher, **différée**. Condition de tranchage : le résultat de la Session 1 du
  plan (`PLAN.md`) — si la collision se lit en WRAM, l'exhaustif perd son objet et D4 penche vers
  "à la demande" quasi automatiquement. Recommandation formelle soumise au propriétaire en
  Session 3 (réviseur), sur la base du résultat de Session 1. Différer n'a pas de coût identifié :
  aucune session du plan initial ne dépend de D4 avant Session 3.
- **Contexte** : `ScreenMap.build` sonde toutes les cases d'un écran, 1,5 à 5 h par écran, avec un
  plancher d'une sonde live par case. Le concept demande une exploration scriptée, pas exhaustive.
- **Options** : cartographier ce que le prochain objectif exige, en lisant le terrain depuis l'état
  du jeu ; ou tout cartographier, avec le nouvel outil sur snapshot.
- **Recommandation de la revue** : à la demande.

## D5 — `legacy/` se remplace, ne s'étend pas

- **Statut** : ratifiée (7 septembre 2026).
- **Choix** : le code importé du spike sert à régénérer les checkpoints de `Zelda::Scenarios` et à
  produire le rapport, jusqu'à ce que `lib/` couvre ces deux usages. On n'y ajoute ni composant ni
  correctif au-delà de ce qu'exige une régénération. Ses grilles JSON servent d'oracle une fois,
  pour valider le nouvel outil de navigation, puis sont supprimées.
- **Invalidée si** : la parité "régénérer tous les checkpoints" n'est pas atteinte au plus tard à
  la 2e revue à froid suivant le début de la construction de `lib/` — dans le plan initial
  (`PLAN.md`), Session 6. Passé ce point sans parité, retour au propriétaire plutôt que
  prolongation silencieuse. Délai proposé par le planificateur, ajustable par le propriétaire.

## D6 — API de session headless côté gemboy, dépendance en gem épinglée

- **Statut** : ratifiée (7 septembre 2026).
- **Choix** : gemboy expose un objet session (avancer de N frames, touches, lecture mémoire,
  snapshot/restore en mémoire, `Motherboard` dessous). Le save state devient une fonctionnalité de
  l'émulateur. Ce dépôt en dépend comme d'une gem à version épinglée ; un changement de timing de
  l'émulateur invalide explicitement les checkpoints au lieu de le faire silencieusement.
- **Écriture** : par un agent côté gemboy, hors périmètre des sessions koholint. C'est un bloqueur
  externe pour toute session koholint qui en dépend (Session 2 du plan initial) : signalé au
  propriétaire dès qu'une telle session est prête à démarrer mais ne peut pas, plutôt que contourné
  en réimplémentant un bout de session-object ici.
- **Invalidée si** : gemboy refuse cette API dans son périmètre ; alors elle vit ici, en
  s'appuyant sur `Motherboard` uniquement.

## D7 — Sonde de collision par snapshot, pas par marche-retour

- **Statut** : ratifiée (7 septembre 2026).
- **Choix** : toute mesure sur une case part d'un snapshot en mémoire de l'état à cette case ;
  chaque direction est testée depuis ce même état puis restaurée. Plus de retour à pied, plus de
  budget de récupération, plus d'ordre de directions.
- **Invalidée si** : le coût mémoire d'un snapshot rend impraticable d'en garder un par case
  d'écran ; mesurer avant de conclure.
