# Koholint — brief d'évolution : boucle d'auto-amélioration modeste

> **Pour l'agent chargé de faire évoluer le dépôt.** Ce document est un brief de conception et d'implémentation, pas une autorisation de réécrire l'architecture. Inspecte d'abord le code actuel, puis propose et réalise la plus petite tranche verticale testable. Préserve la boucle de jeu existante.

## 1. Intention

Faire évoluer Koholint vers un environnement de recherche sur les agents capables d'accomplir des tâches longues dans un monde partiellement connu, dynamique et mécaniquement riche, et qui peuvent **étendre progressivement leurs propres capacités** à partir de l'expérience.

La question ciblée pour la première itération :

> Un agent de jeu déjà opérationnel peut-il découvrir une nouvelle affordance, en tirer une compétence réutilisable, la valider et l'intégrer à son répertoire sans intervention humaine dans le processus normal — tout en gardant un noyau déterministe, une mémoire auditable et un contrôle strict des régressions ?

Ce n'est pas l'objectif de construire un agent généraliste auto-modifiant. Le terrain est Link's Awakening DX ; l'agent n'a pas besoin de prévoir initialement toutes les mécaniques du jeu. Il doit pouvoir les acquérir lorsqu'elles deviennent pertinentes (nouvel objet, nouvel obstacle, nouvelle interaction, nouvelle famille de situations).

## 2. Contexte et acquis à préserver

Dépôt : https://github.com/kaderate/koholint

Lire en priorité :
- `README.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `AGENTS.md` de la branche courante ;
- les specs/plans actuels pertinents sous `docs/superpowers/` ;
- le tag historique `v1-archive`, notamment `AGENTS.md`, `METAPLANNER.md`, `METAPLANNER_ESCALATIONS.md`, `docs/CONCEPT.md`, `docs/AUTONOMOUS_RECOVERY.md`, `lib/autonomous_recovery.rb` et sa suite de tests.

### Architecture actuelle (à confirmer dans le code avant tout changement)

La version courante repose sur un moteur déterministe headless, des appels agent à des points de décision et des skills déterministes exécutées entre appels. Les traces sont rejouables à partir du journal d'inputs ; les runs peuvent être repris/forkés, vérifiés, visualisés et comparés. Les runs sont bornés par frames, temps et coût. L'agent conserve notamment un plan, un objectif long terme, des leads issus de textes cités verbatim, un modèle du monde et des informations de navigation. L'autopilot délègue certaines explorations bénignes au moteur sans coût LLM.

La priorité est de **prolonger** cette architecture : le moteur reste responsable de la vérité d'exécution et de la sécurité ; le modèle propose des décisions et des hypothèses ; les changements au répertoire de capacités sont explicites, versionnés et testables.

### Ce que V1 apporte — et ce qu'il ne faut pas recopier

Dans le tag `v1-archive`, le MetaPlanner n'était pas un méta-agent de gameplay. C'était un rôle pair, déclenché par événement, chargé d'amender le processus et la coordination : `AGENTS.md`, règles structurelles de `NEXT.md`, `PLAN.md`, conventions de sous-agents. Le planner ajoutait une escalade `open` à `METAPLANNER_ESCALATIONS.md) ; MetaPlanner analysait le problème, choisissait une modification, consignait le contexte, les options, la décision et une condition d'invalidation dans `METAPLANNER.md), puis résolvait l'escalade. Sa frontière d'accès séparait explicitement processus et connaissances du jeu.

V1 contenait aussi `AutonomousRecovery` : blocage de gameplay transformé en `ResearchTask` durable, hypothèses falsifiables, expériences bornées depuis checkpoint, fingerprint de l'état durable, budget, déduplication des tentatives et seuil de deux expériences indépendantes pour soutenir une hypothèse. Les résultats de recherche n'étaient pas automatiquement promus comme faits du monde. Ce mécanisme est une inspiration intéressante pour la découverte ; il ne constituait pas encore une boucle d'acquisition de skills intégrée au gameplay.

La rétrospective V1 est un avertissement majeur : beaucoup de rôles, de règles et de documentation ont été construits avant la boucle de jeu ; l'activité méta a pu devenir une forme de progrès facile alors que la progression réelle stagnait. **Ne pas réintroduire cette complexité.** Un MetaPlanner est utile seulement s'il améliore le comportement de l'agent de jeu et si cet effet est mesuré.

## 3. Vocabulaire : séparer trois apprentissages

Ne pas confondre :

1. **Apprendre le monde** : salles, portes, PNJ, objets, faits, états, objectifs et relations.
2. **Apprendre une capacité** : découvrir comment réaliser une nouvelle interaction ou action (ou une composition d'actions), puis la rendre réutilisable.
3. **Apprendre à améliorer le processus** : modifier une procédure de décision ou une règle du harness parce que l'expérience indique un défaut récurrent.

Le système actuel contient déjà beaucoup de mécanismes du niveau 1. La première tranche de recherche doit porter surtout sur le niveau 2. Le niveau 3 doit rester étroit : un MetaPlanner qui identifie les lacunes du processus et propose des changements ciblés, sans libre réécriture de l'architecture.

## 4. Architecture cible minimale

Conserver le Game Agent et le moteur actuels. Ajouter, seulement si le code existant ne fournit pas déjà l'équivalent, une boucle méta hors du chemin critique :

```
Game Agent / deterministic engine
        |
        | notable experience / new item / repeated blocker / successful novel action
        v
Experience evidence (trace + checkpoint + state delta)
        |
        v
Capability candidate (hypothesis, not yet trusted)
        |
        v
bounded experiment / replay / fork validation
        |
        +---- rejected / inconclusive -> retain evidence, no promotion
        |
        v
validated capability specification
        |
        v
versioned skill registry (available to Game Agent)
        |
        v
observe real use, success, failure, regression
        |
        v
(optional) MetaPlanner process amendment
```

### Rôles

- **Game Agent** : poursuit le but du jeu, choisit parmi les capacités disponibles, constate les limites et émet des traces structurées. Ne modifie pas directement son propre code ou son registry.
- **Capability learner** (peut être un module/prompt appelé ponctuellement, pas nécessairement un agent permanent) : formule les hypothèses sur les nouvelles affordances, propose une skill candidate et un protocole de validation.
- **Validator / engine** : exécute les tests de manière bornée et vérifie objectivement l'effet annoncé quand le moteur/perception le permet. Aucun changement gameplay durable pendant les essais.
- **MetaPlanner** : seulement pour les défauts récurrents du processus/harness (ex. le Game Agent n'explore jamais les affordances d'un nouvel objet, ou la validation échoue systématiquement à distinguer interaction réussie et message de refus). Il propose une amélioration ciblée ; il ne planifie pas Zelda et n'édite pas directement la connaissance du monde.

Ces responsabilités peuvent être implémentées dans un seul processus LLM avec des phases/prompt distincts au début. Ne pas multiplier les agents ou sessions sans preuve que cela apporte un bénéfice.

## 5. Boucle de découverte de capacité

### 5.1 Déclencheurs

Ne pas invoquer l'apprentissage méta à chaque décision. Déclencheurs possibles, à adapter aux événements réellement disponibles dans Koholint :

- acquisition ou changement d'objet/inventaire ;
- rencontre d'une interaction inconnue ou d'un objet non résolu ;
- action inédite qui produit un effet significatif ;
- blocage répété malgré plusieurs actions distinctes ;
- nouvelle classe de situation qui invalide une hypothèse ou une procédure existante.

Les déclencheurs doivent être dédupliqués et soumis à cooldown/budget. Un nouvel objet est un signal d'exploration, pas la preuve qu'une skill doit être créée.

### 5.2 Candidate de capacité

Une candidate est une hypothèse structurée, pas un paragraphe libre. Schéma indicatif (à adapter aux conventions existantes) :

```json
{
  "id": "candidate:lift-object",
  "name": "lift_object",
  "status": "hypothesis",
  "description": "Attempt to lift a nearby liftable object",
  "trigger": "object nearby and lifting capability available",
  "preconditions": ["Link is ready", "object is in interaction range"],
  "parameters": ["target"],
  "procedure": ["face target", "press interaction button"],
  "expected_effect": "object is lifted or displaced",
  "success_observations": ["verified state delta or unambiguous game response"],
  "failure_observations": ["explicit refusal text", "no state change after bounded attempt"],
  "evidence": [],
  "source_run_ids": [],
  "created_from": "experience/event reference",
  "version": 1
}
```

Cet exemple est illustratif. Ne pas supposer que la skill existe ou qu'elle est possible dans le jeu. Ne pas coder en dur la mécanique « soulever » : la valeur de la recherche est de permettre l'arrivée de mécaniques imprévues.

Distinguer trois statuts au minimum :
- `hypothesis` : plausible, non vérifiée ;
- `validated` : testée selon un protocole défini, avec observations et bornes explicites ;
- `operational` : publiée et utilisable par le Game Agent.

Un candidat peut aussi être `rejected`, `inconclusive` ou `deprecated`. Une observation positive unique ne doit pas automatiquement produire une skill opérationnelle.

### 5.3 Expérimentation

Réutiliser le plus possible les capacités existantes de replay/fork/checkpoint et les mécanismes d'isolation. Les essais doivent :
- partir d'un état reproductible ;
- avoir un budget explicite (frames, essais, appels LLM, coût) ;
- annoncer à l'avance l'effet attendu et les observations qui le réfuteraient ;
- changer une variable à la fois autant que possible ;
- enregistrer état initial, action, résultat observé, état final, frame, source run/checkpoint et coût ;
- protéger l'état durable du run principal ;
- ne jamais faire de RAM writes gameplay pour forcer le résultat ;
- conserver les résultats négatifs : ils évitent de répéter des expériences invalidées.

Utiliser deux observations indépendantes comme seuil par défaut uniquement si elles sont réellement indépendantes. Deux répétitions identiques au même checkpoint ne constituent pas nécessairement deux preuves indépendantes. Le seuil peut dépendre du type d'effet et de sa vérifiabilité. Les effets directement lisibles en RAM peuvent être validés autrement que les effets sémantiques interprétés dans du texte/image.

Un skill candidat doit décrire :
- préconditions et mode de jeu requis ;
- paramètres autorisés ;
- séquence d'actions déterministe ;
- critère explicite de succès ;
- raisons d'arrêt / erreurs attendues ;
- budget maximal ;
- provenance et tests réussis ;
- contexte(s) dans lesquels il a été testé et limites connues.

**Privilégier des compositions de primitives déjà existantes** plutôt que de générer arbitrairement du Ruby. Si une skill implique du code nouveau, ne l'exécuter qu'après validation statique, tests, limites de ressources et tests isolés. Le LLM ne doit pas pouvoir publier/exécuter librement du code arbitraire.

### 5.4 Promotion et usage

Le registry doit être versionné et chargé par le moteur à des points sûrs. Une promotion :
- ne doit pas modifier la logique fondamentale de l'engine ;
- doit être atomique et traçable ;
- doit conserver l'ancienne version ;
- doit associer chaque skill à ses preuves et à ses limites ;
- doit être annulable (rollback).

Le Game Agent ne reçoit dans son contexte que les capacités opérationnelles pertinentes, avec des descriptions compactes et leurs préconditions. Le contexte doit aussi indiquer qu'une capacité peut être indisponible ou connue comme non applicable dans certains modes.

Après publication, tracer chaque invocation avec l'identifiant/version de skill, ses arguments, son résultat, son coût et le contexte. Une skill validée en isolation peut échouer dans le monde réel : ces échecs doivent rétrograder son niveau de confiance ou la déprécier, pas être masqués.

## 6. MetaPlanner : mandat étroit inspiré de V1

Réutiliser les bons principes du MetaPlanner V1 :
- déclenchement événementiel, pas une boucle permanente ;
- un problème méta précis par invocation ;
- lecture froide des traces et artefacts persistés, pas dépendance au contexte conversationnel ;
- séparer les changements de processus des faits et décisions du jeu ;
- journaliser contexte, options considérées, choix et condition d'invalidation ;
- conserver un point de contrôle humain pour les changements à haut risque.

Mais changer le mandat pour l'axe de recherche : il peut proposer des modifications **limitées au harness/processus d'apprentissage**, par exemple :
- ajouter une procédure de découverte d'affordances après acquisition d'un objet ;
- améliorer les critères de détection de capacité manquante ;
- changer le protocole de validation quand des faux positifs sont observés ;
- ajuster le moment de déclenchement ou le budget d'expérimentation ;
- modifier le format de contexte transmis au Game Agent.

Il ne doit pas :
- modifier les faits du jeu ni les registres de connaissance à la place de leur pipeline de provenance ;
- changer le moteur de gameplay pour contourner une validation ;
- créer des agents/roles supplémentaires par défaut ;
- modifier librement les prompts ou code de production sans diff, tests et évaluation ;
- optimiser des métriques intermédiaires (nombre de skills, volume de traces, nombre d'escalades) au détriment de la progression dans le jeu.

### Protocole d'amendement

Pour chaque proposition :
1. décrire le symptôme observé et ses références de trace ;
2. identifier le mécanisme causal supposé ;
3. comparer au moins une option « ne rien changer » et une option minimale ;
4. annoncer l'effet attendu et une condition d'invalidation ;
5. implémenter la modification sur une branche/version candidate ;
6. exécuter les tests et, lorsque possible, une comparaison replay/fork contrôlée ;
7. conserver le diff et la décision, qu'elle soit acceptée ou rejetée.

Les changements au comportement du harness sont des expériences : ne pas les promouvoir uniquement parce que leur auteur LLM les juge élégants.

## 7. Évaluation : mesurer le jeu, pas l'activité méta

La métrique primaire reste la progression du jeu (milestones/objectifs atteints) sous budgets comparables. Métriques secondaires :
- progression par 1 000 frames ;
- progression par dollar ou appel LLM ;
- taux de réussite des skills opérationnelles ;
- temps/calls nécessaires pour apprendre une nouvelle capacité ;
- réutilisation correcte dans un contexte différent de celui de découverte ;
- taux de régression sur les capacités précédemment validées ;
- coût de la phase de découverte et de validation ;
- proportion de candidates rejetées / inconclusives.

Les expériences devraient comparer, à état initial équivalent via fork :
1. baseline actuelle, sans apprentissage de capacités ;
2. baseline + mémoire/hypothèses de capacités ;
3. acquisition/validation de skills ;
4. acquisition de skills + MetaPlanner limité.

Pré-enregistrer les critères de comparaison avant de regarder les résultats. Plusieurs forks par condition sont préférables lorsqu'il existe de la stochasticité ou des appels modèles non déterministes. Ne pas attribuer à l'auto-amélioration un gain dû à une meilleure route de départ, un budget plus élevé ou un modèle différent.

## 8. Stabilité visée et critère d'arrêt

L'objectif n'est pas que le système cesse d'apprendre le monde. Il doit pouvoir découvrir de nouvelles choses pendant toute la partie.

Le critère de stabilité concerne plutôt **le mécanisme d'intégration des nouvelles capacités** : les composants, interfaces, états, validation, promotion, rollback et traces deviennent assez stables pour que la boucle puisse tourner de façon autonome. De nouvelles mécaniques ajoutent alors surtout des données/candidates/skills conformes à ces interfaces, au lieu de nécessiter une modification de l'architecture.

Indicateurs de stabilité possibles :
- plusieurs acquisitions/mécaniques nouvelles intégrées de bout en bout ;
- nouvelles skills créées et réutilisées dans des contextes différents ;
- taux de régression sous un seuil convenu ;
- aucune modification du moteur ou du protocole de validation nécessaire pour chaque nouvelle capacité ;
- coût d'intégration par capacité qui diminue ou reste borné ;
- le système tourne sur plusieurs objectifs longs sans intervention manuelle de conception.

Ne pas fixer de seuils numériques arbitraires avant d'avoir une baseline. Instrumenter d'abord.

## 9. Scope de la première implémentation (MVP)

**Avant de coder :**
1. cartographier les points d'extension existants (skill dispatch, trace events, notable, inventory, object/entity context, run fork/replay, world model, persistence) ;
2. vérifier si la structure actuelle permet déjà d'exprimer une skill nouvelle par configuration/composition sans changer le moteur ;
3. identifier les risques d'état partagé entre parent/fork et les contrats d'archive/replay ;
4. proposer une architecture courte et un plan de test. Ne pas poser de question si le dépôt permet de trancher.

**MVP recommandé :**
- ajouter une représentation durable minimale des *capability candidates* et des preuves, ou réutiliser un store existant si approprié ;
- produire des candidates à partir de quelques événements significatifs (pas tous) ;
- faire une phase de validation bornée sur fork/checkpoint ;
- promouvoir uniquement des compositions de skills/primitives déjà disponibles (pas de code arbitraire généré) ;
- rendre ces skills visibles au Game Agent et tracer leurs utilisations ;
- permettre de désactiver/rollback une skill ;
- ajouter un rapport d'expérience comparant baseline et capacité acquise sur un scénario contrôlé.

Si le moteur actuel ne permet pas de valider une nouvelle action sans mutation durable, commencer par la découverte structurée et la validation en mode shadow/supervisé. Ne pas construire un nouveau framework d'émulation ou une nouvelle runtime pour débloquer le MVP.

### Hors scope explicite

- apprentissage ou fine-tuning des poids du modèle ;
- auto-modification libre du Ruby/du moteur ;
- génération et exécution libre de code LLM ;
- architecture multi-agent complexe ;
- réécriture globale des prompts ;
- MetaPlanner tournant à chaque tour ;
- nouvelle couche de mémoire générale ;
- automatisation de progression à tout prix avant que la boucle principale soit stable.

## 10. Critères d'acceptation

Une implémentation initiale est acceptable si :
- la boucle principale existante fonctionne sans régression ;
- une candidate peut être créée et persistée avec sa provenance ;
- la candidate peut être validée ou rejetée par un protocole borné, reproductible et isolé ;
- une capacité validée peut être publiée dans un registry versionné et désactivée ;
- le Game Agent peut la découvrir et l'utiliser sans modifier son prompt/code à la main à chaque nouvelle skill ;
- traces et rapports permettent de reconstruire pourquoi elle a été créée, validée, publiée ou retirée ;
- les métriques séparent progrès du jeu et activité d'apprentissage ;
- les tests couvrent persistence, validation, budgets, duplication, rollback, et non-régression.

## 11. Instructions à l'agent implémenteur

- Inspecte le dépôt courant et adapte le brief à la réalité du code ; les chemins/noms ci-dessus ne sont pas des exigences d'API.
- Ne touche pas à la boucle de gameplay stable sauf nécessité démontrée.
- Pas de grande refonte, pas de nouveau framework, pas de code généré arbitrairement.
- Commence par un plan en quelques étapes et identifie la tranche verticale la plus petite.
- Implémente, teste et documente cette tranche ; lance les tests pertinents, et signale clairement ceux non exécutés.
- Garde une séparation stricte entre faits observés, hypothèses et conclusions.
- Si une décision de design est réellement bloquante et non déductible du dépôt, pose une seule question précise. Sinon, fais une hypothèse conservatrice, note-la et avance.
- Termine par : fichiers changés, comportement nouveau, tests lancés/résultats, limites et prochaine expérience recommandée.

**Principe directeur :** rendre le système capable d'ajouter de nouvelles compétences sans devoir se réinventer à chaque découverte. Le MetaPlanner doit préserver et améliorer ce mécanisme, pas devenir le projet à la place de l'agent qui joue.
