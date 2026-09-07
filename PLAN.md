# Plan — depuis la réinitialisation du 7 septembre 2026

Suite de SESSIONS, pas de tâches. Chaque session suit le format et les rôles d'`AGENTS.md` : une
question falsifiable, un critère de fin observable, un budget, un indicateur de but visé. Le plan
s'arrête à la première session qui fait tourner la boucle de décision du concept (déclencheur sur
état RAM, planner, executor, action log) sur un objectif de jeu réel — pas plus loin, ce qui suit
dépend de ce qu'on y aura appris.

Contraintes valables pour tout ce plan :

- Aucune session n'étend `legacy/` ni ne lance `ScreenMap.build` (D5, et NEXT.md "Ce qu'il ne faut
  PAS refaire").
- Aucune session autonome (sans humain) n'est planifiée. Le propriétaire attend d'avoir posé les
  bases (au plus tôt après la Session 4) avant de donner un feu vert à l'autonomie.
- Revue à froid toutes les 3 sessions — traduction en cadencement de plan du "chaque matin ou si
  gros blocage" du propriétaire. Un vrai blocage déclenche une revue hors cadence, sans attendre le
  3e créneau.
- D6 (API de session headless) est écrite côté gemboy par un autre agent, hors périmètre des
  sessions koholint. Toute session qui en dépend le note explicitement ; le propriétaire est averti
  dès qu'une session est prête à démarrer mais bloquée sur cette dépendance.

**Point d'attention avant Session 1** (constat de cette session de planification, pas une
décision) : l'import initial (`koholint-init`, commit `42f1f0e`) vient de `gemboy@claude/usage-
2mr345` au commit `c952ded`, mais cette branche a un commit de plus non importé (`5ee7949`,
"Archive the HRAM diff and other reusable scratchpad diagnostics into experiments/"). Il ajoute les
scripts qui ont produit D1 (`ram_diff_hram.rb`, `ram_diff_hram2.rb`, `diag_scx_scy.rb`,
`diag_scx_scy2.rb`, `house2_dialogue.rb`, `house2_sprite2.rb`) et une note dans `ram_registry.json`
indiquant explicitement que Session 1 doit réutiliser la même technique de diff complet. Ni le code
de `legacy/` ni les données ne sont affectés (vérifié identique par ailleurs). À importer ou non :
décision du propriétaire, pas de cette session.

---

## Session 1 — Le terrain est-il lisible depuis l'état du jeu ?

```
Rôle : explorateur
Question : le jeu décode-t-il chaque salle en une grille d'objets 16×16 (10×8) en WRAM, avec la
           collision de chaque type d'objet lue dans une table ROM — au lieu d'être sondée ?
Critère de fin : pour front_yard et starting_house (déjà cartographiés), une lecture WRAM prédit
           les arêtes :blocked/:ok des grilles legacy/.../screen_maps/ avec un taux d'accord
           mesuré et chaque désaccord expliqué.
Budget : 3 h
Dépend de : D1 (ratifiée)
Livrable : entrée data/ram_registry.json promue ou réfutée, taux d'accord dans le rapport
Indicateur visé : faits vérifiés — c'est directement une entrée de registre RAM à statuer
```

Déjà entièrement spécifiée dans `NEXT.md` ; reprise ici sans changement, sous réserve du choix D3
(DMG, confirmé — n'invalide rien : les checkpoints utilisés sont en DMG).

## Session 2 — Outil de navigation par snapshot (D7), validé une fois contre l'oracle

```
Rôle : constructeur
Question : un outil de navigation dans lib/, qui teste chaque direction depuis un snapshot en
           mémoire puis restaure (D7), reproduit-il les arêtes :blocked/:ok des grilles oracle
           legacy/.../screen_maps/ pour front_yard et starting_house ?
Critère de fin : 100% d'accord avec l'oracle sur ces deux écrans, ou chaque désaccord documenté et
           expliqué (contamination connue du coin [3,3], notamment) avant d'être accepté.
Budget : 6 h
Dépend de : D6 livré côté gemboy (EXTERNE — bloquant, voir note en tête de plan), D7 (ratifiée),
           conclusion de Session 1
Livrable : code dans lib/, specs sur checkpoint, JSON oracle des deux écrans marqués consommés
Indicateur visé : trajet A→B — première traversée mesurée en frames, sans sonde live, sur un
           écran connu
```

Si D6 n'a pas atterri côté gemboy quand cette session est prête à démarrer : ne pas contourner en
réimplémentant un bout de session-object dans koholint. Signaler le blocage au propriétaire et
attendre.

## Session 3 — Revue à froid : sessions 1–2, et statut de D4

```
Rôle : réviseur
Question : les livrables des sessions 1 et 2 sont-ils conformes à docs/CONCEPT.md et aux décisions
           ratifiées (D1, D6, D7) ? Le résultat de la Session 1 permet-il de trancher D4
           (exploration exhaustive contre à la demande), et dans quel sens ?
Critère de fin : rapport écrit, jugement conforme/non conforme par livrable, recommandation
           explicite sur D4 soumise au propriétaire (le réviseur ne tranche pas D4 lui-même,
           voir AGENTS.md "les décisions de fond appartiennent au propriétaire")
Budget : 3 h, session fraîche, aucun code écrit
Dépend de : Sessions 1, 2
Livrable : DECISIONS.md (statut D4 mis à jour si le propriétaire tranche sur la recommandation),
           note NEXT.md
Indicateur visé : faits vérifiés — vérifie que ce que les sessions 1–2 déclarent "vérifié" ou
           "validé" tient à la relecture
```

## Session 4 — Régénérer les 7 checkpoints avec l'outil lib/, retirer legacy/ (D5)

```
Rôle : constructeur
Question : les 7 checkpoints connus (after_shield_interior, front_yard, overworld_screen2,
           villager_screen, shop_screen, screen3_north, house2_interior) sont-ils traversables
           A→B via lib/ seul, sans aucun fichier de legacy/ ?
Critère de fin : les 7 checkpoints régénérés et traversés par lib/ ; legacy/ supprimé dans le même
           commit que le dernier checkpoint atteignant la parité (condition d'invalidation de D5).
Budget : 9 h (3 blocs de 3 h), un commit par checkpoint migré
Dépend de : Session 2 (outil de navigation), D5 (ratifiée, délai : voir DECISIONS.md)
Livrable : code lib/, specs sur les 7 checkpoints, suppression de legacy/
Indicateur visé : trajet A→B — les 7 trajets connus, mesurés en frames, sans legacy/
```

## Session 5 — Squelette de la boucle de décision (sans objectif réel encore)

```
Rôle : constructeur
Question : un déclencheur sur changement d'état RAM (salle, santé, texte ouvert) peut-il suspendre
           l'exécution scriptée, appeler un planner minimal, journaliser l'action dans un fichier
           JSONL, puis reprendre — sur un scénario jouet (ex. changement de salle simple) ?
Critère de fin : un run de bout en bout produit un action log JSONL exploitable, avec au moins un
           déclenchement réel et une décision de planner enregistrée avec sa provenance.
Budget : 9 h (3 blocs de 3 h)
Dépend de : Session 4 (lib/ à parité, legacy/ retiré)
Livrable : code lib/ (déclencheurs, planner minimal, executor, action log), specs
Indicateur visé : faits vérifiés — l'action log devient la nouvelle source de provenance des
           décisions prises, aucun indicateur de jeu n'est censé bouger ici (justifié : squelette
           mécanique, pas encore d'objectif de jeu)
```

## Session 6 — Revue à froid : sessions 4–5, prêt pour un objectif réel ?

```
Rôle : réviseur
Question : lib/ couvre-t-il la parité de régénération des 7 checkpoints sans dérive depuis
           Session 4 ? Le squelette de Session 5 respecte-t-il le découplage exécution/décision de
           docs/CONCEPT.md (peu d'appels LLM, à des points de décision précis, faits en RAM) ?
Critère de fin : rapport écrit, jugement conforme/non conforme, feu vert ou non pour Session 7.
Budget : 3 h, session fraîche, aucun code écrit
Dépend de : Sessions 4, 5
Livrable : note NEXT.md, DECISIONS.md si un écart structurant est trouvé
Indicateur visé : faits vérifiés — même logique que Session 3
```

## Session 7 — Premier objectif de jeu réel via la boucle de décision

```
Rôle : constructeur
Question : la boucle de décision (déclencheurs RAM, planner, executor, action log) peut-elle mener
           Link d'un point A à un objectif de jeu réel non trivial (ex. obtenir l'épée, ou sortir
           de la maison de départ si pas déjà acquis à ce stade) en s'appuyant sur les faits en RAM
           et un minimum d'appels LLM aux points de décision ?
Critère de fin : l'objectif choisi est atteint au moins une fois, reproductible, avec action log
           complet et provenance de chaque décision.
Budget : 9 h (3 blocs de 3 h)
Dépend de : Session 6 (feu vert), tous les livrables précédents
Livrable : code lib/, action log JSONL de la run réussie, entrée NEXT.md avec le nouveau jalon
Indicateur visé : progression dans le jeu — premier jalon de jeu réel atteint par la boucle de
           décision elle-même, pas par un script de spike. C'est l'objectif du projet ; le plan
           s'arrête ici.
```

---

Le plan s'arrête à la Session 7. La suite dépend de ce que cette première boucle réelle aura appris
— nouvelle question, nouvelle session, décidée à froid par le propriétaire sur la base du rapport
de Session 7.
