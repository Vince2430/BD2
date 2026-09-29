# Étape 4 — Justification des requêtes

Document compagnon de `07_requetes.sql`. Pour chaque requête écrite jusqu'ici,
on explique l'exigence couverte, la question métier retenue et les choix de
conception (avec les alternatives écartées et pourquoi).

Ce document sera complété au fur et à mesure que les requêtes restantes sont
écrites et validées.

---

## Requête 1 — Jointure d'au moins 3 tables

**Question métier** : Pour chaque produit, quelles sont ses informations de
base, le nom de sa catégorie et sa fiche de spécifications (JSONB) ?

**Tables jointes** : `produit` → `categorie` → `specification_produit`.

**Choix** :
- `INNER JOIN` partout plutôt que `LEFT JOIN` : on part du principe que
  chaque produit a une catégorie et une fiche de spécifications (contrainte
  `UNIQUE` sur `specification_produit.id_produit`). Un `INNER JOIN` exclurait
  silencieusement un produit sans fiche — c'est voulu ici, mais c'est un
  point à vérifier dans les données (le nombre de lignes retournées doit
  égaler le nombre total de produits).
- On retourne la colonne JSONB complète (`specifications_produit`) plutôt que
  d'extraire des clés précises, parce que la requête sert à *afficher toute
  l'information disponible* pour un produit, pas à filtrer sur un critère
  précis (ça, c'est le rôle des requêtes JSONB, points 9 et 10).

**Vérification suggérée** : comparer le nombre de lignes retournées à
`SELECT count(*) FROM commerce.produit`.

---

## Requête 2 — Agrégation GROUP BY + HAVING

**Question métier** : Quelles catégories de produits génèrent un revenu
total (commandes non annulées) supérieur à un certain seuil ?

**Tables jointes** : `categorie` → `produit` → `info_commande` → `commande`
→ `statut`.

**Choix** :
- Le revenu est calculé comme `SUM(quantite * prix_unitaire)` sur
  `info_commande`, en utilisant le prix unitaire *figé au moment de la
  commande* plutôt que `produit.prix_produit` (qui peut avoir changé depuis).
  C'est plus fidèle à l'historique réel des ventes.
- Exclusion des commandes au statut `Annulée` (jointure avec `statut` +
  `WHERE`) : une commande annulée ne représente pas un revenu réel, même si
  ses lignes existent toujours dans `info_commande`. Alternative écartée :
  ignorer le statut et compter toutes les lignes — rejetée parce que ça
  gonflerait artificiellement le revenu des catégories touchées par des
  annulations.
- Le seuil dans `HAVING` (`1000`) est arbitraire pour l'instant — à ajuster
  une fois les résultats réels observés dans pgAdmin, pour qu'il sépare
  effectivement les catégories en deux groupes significatifs plutôt que de
  toutes les inclure ou toutes les exclure.

**Vérification suggérée** : recalculer le revenu d'une catégorie
manuellement (sous-total de quelques commandes connues) et confirmer que les
commandes annulées ne sont pas comptées.

---

## Requête 3 — Sous-requête corrélée ou EXISTS

**Question métier** : Quel(s) client(s) ont dépensé le plus au total
(commandes non annulées) ?

**Choix de technique** :
- L'objectif est de trouver le/les maximum(s) d'une valeur agrégée
  (le total dépensé par client) *sans utiliser de fonction de fenêtre*,
  celle-ci étant réservée à la requête 5 pour garder les techniques
  distinctes d'une requête à l'autre.
- Technique retenue : une sous-requête dérivée calcule le total dépensé par
  client (jointure `client` → `commande` → `info_commande`, filtrée sur les
  commandes non annulées), puis un `NOT EXISTS` corrélé élimine tout client
  pour lequel il existe un autre client avec un total plus élevé. Il ne
  reste que le(s) client(s) au sommet — s'il y a égalité, ils apparaissent
  tous les deux, ce qui est le comportement voulu (contrairement à
  `ORDER BY ... LIMIT 1`, qui ne garderait qu'une seule ligne arbitraire en
  cas d'égalité).
- Alternative écartée : une sous-requête scalaire simple comparant chaque
  total à `(SELECT MAX(total) FROM ...)`. Ça fonctionnerait aussi, mais ce
  serait une sous-requête *non corrélée* (elle ne référence pas la ligne
  externe) — ça ne répond pas correctement à l'exigence d'une sous-requête
  *corrélée*.
- Le calcul du total est dupliqué dans les deux sous-requêtes dérivées
  (interne et externe) plutôt que factorisé avec `WITH`, pour garder cette
  requête clairement distincte de la requête CTE (point 4).
- Même exclusion des commandes annulées que dans la requête 2, pour rester
  cohérent sur la définition de « dépensé ».

**Vérification suggérée** : retirer temporairement le `NOT EXISTS` pour voir
le classement complet des clients par total dépensé, et confirmer que le(s)
client(s) retourné(s) par la requête finale correspond(ent) bien au sommet de
ce classement.

---

## Requête 4 — Expression de table commune (WITH)

**Question métier** : Pour chaque client, combien de commandes a-t-il
passées (non annulées), sur quelle période, combien a-t-il dépensé au
total, et combien de produits différents met-il en moyenne dans une même
commande ?

**Choix** :
- CTE `commande_totaux` : une ligne par commande (non annulée), avec son
  total (`SUM(quantite * prix_unitaire)`) et son nombre de produits
  différents (`COUNT(DISTINCT id_produit)`). La requête principale joint
  cette CTE à `client` et agrège par client (`COUNT`, `MIN`/`MAX` sur la
  date, `SUM` du total, `AVG` du nombre de produits différents).
- Le `COUNT(DISTINCT id_produit)` par commande a été ajouté sur demande de
  Vincent, pour avoir une idée de la taille moyenne du panier d'un client
  (commande-t-il souvent plusieurs produits à la fois, ou un seul ?), en
  plus du nombre de commandes et du total dépensé.
- Validée par Vincent le 24 sept.

**Vérification suggérée** : prendre un client au hasard et recalculer
manuellement son nombre de commandes et son total à partir de `commande` +
`info_commande`; vérifier qu'un client ayant commandé plusieurs produits
dans une même commande a bien une `moyenne_produits_par_commande` > 1.

---

## Requête 5 — Fonction de fenêtre (OVER)

**Question métier** : Quel est le classement complet des clients selon le
montant total dépensé (commandes non annulées) ?

**Choix** :
- Reprend délibérément la question de la requête 3 (client ayant le plus
  dépensé), mais cette fois avec la technique qu'on avait mise de côté à ce
  moment-là : `RANK() OVER (ORDER BY SUM(quantite * prix_unitaire) DESC)`.
  Contrairement au `NOT EXISTS` de la requête 3 qui ne retourne que le(s)
  client(s) au sommet, celle-ci retourne **tous** les clients avec leur rang.
- Pas besoin de CTE ici : PostgreSQL calcule les fonctions de fenêtre après
  le `GROUP BY`/agrégation, donc `RANK()` peut porter directement sur
  `SUM(...)` group par groupe, sans étape intermédiaire.
- `RANK()` plutôt que `DENSE_RANK()` ou `ROW_NUMBER()` : en cas d'égalité,
  `RANK()` donne le même rang aux ex-aequo et saute le(s) rang(s) suivant(s)
  — comportement volontairement cohérent avec le résultat de la requête 3
  (si deux clients sont premiers ex-aequo, les deux doivent apparaître au
  rang 1 ici aussi).
- Même exclusion des commandes annulées que dans les requêtes 2, 3 et 4.

**Vérification** : validée par Vincent le 24 sept — le rang 1 correspond
bien au(x) client(s) trouvé(s) par la requête 3.

---

## Requête 6 — UNION, INTERSECT ou EXCEPT

**Question métier** : Quels clients sont « à risque », soit parce qu'ils ont
au moins une commande annulée, soit parce qu'une de leurs commandes annulées
a en plus laissé un paiement non complété derrière elle ?

**Historique de la décision** :
- Première idée : combiner « commande annulée » et « évaluation basse »
  (note ≤ 2) — écartée parce que ce sont deux signaux d'affaires qui n'ont
  pas vraiment de lien entre eux (une évaluation basse ne dit rien sur le
  risque financier d'un client).
- Deuxième idée : combiner « commande annulée » et « paiement non
  complété » (`est_complete = FALSE`) — plus logique, les deux touchent au
  cycle commande/paiement. Mais en creusant : `paiement.est_complete =
  FALSE` veut seulement dire « autorisé, jamais capturé ». Le schéma n'a
  **aucune colonne de statut ou de raison** sur `paiement` — impossible de
  distinguer un paiement réellement échoué d'un paiement simplement en
  attente de traitement normal. Dans `03_donnees.sql`, ces paiements
  incomplets ne sont générés que pour des commandes « En attente » ou
  « Annulée » — donc lié à une commande « En attente », `est_complete =
  FALSE` n'est pas un signal de risque, juste un état normal en cours.
- **Version retenue** : le deuxième critère de la requête ne compte que les
  paiements non complétés **dont la commande est déjà annulée**
  (`statut = 'Annulée' AND est_complete = FALSE`) — le seul cas où
  « non complété » représente vraiment un problème (le client a été
  autorisé mais rien n'a abouti, et la commande n'ira nulle part).

**Choix** :
- `UNION` de deux `SELECT` : (1) clients avec ≥ 1 commande annulée,
  (2) clients avec ≥ 1 commande annulée dont le paiement associé est resté
  non complété. Le deuxième ensemble est un sous-ensemble du premier —
  fait exprès, pour que les clients dans cette situation plus grave
  apparaissent **deux fois** (une ligne par raison), ce qui les distingue
  visuellement des clients qui ont juste une commande annulée avec un
  paiement complété (ex. remboursé) ou sans paiement du tout.
- Une colonne `raison` distincte par `SELECT`, pour identifier la source de
  chaque ligne après la fusion.

**⚠ Question ouverte notée pour plus tard** (voir aussi
`claude/notes_suivi_tp1.md`, question ouverte #3) : faudrait-il ajouter une
vraie colonne de statut/raison sur `paiement` (ex. 'en_attente', 'echoue',
'capture') plutôt que de déduire le risque à partir du statut de la
commande ? Ou un délai (ex. paiement non complété depuis plus de X jours)
pour détecter un échec même sur une commande encore « En attente » ?

**Vérification suggérée** : prendre un client avec une commande annulée
connue et confirmer qu'il apparaît avec « Commande annulée »; trouver une
commande annulée dont le paiement associé a `est_complete = FALSE` et
confirmer que son client apparaît aussi avec la deuxième raison (donc deux
fois au total).

---

## Requête 7 — Appel à une vue, une vue matérialisée ou une routine

**Question métier** : Quels sont les produits les plus vendus dans les 7
derniers jours, selon le dernier rafraîchissement de la vue matérialisée
`mv_ventes_produit_7j` ?

**Choix** :
- `SELECT` direct sur `mv_ventes_produit_7j` (construite à l'étape 3),
  filtré sur `quantite_vendue_7j > 0` pour ne garder que les produits
  effectivement vendus, trié décroissant, `LIMIT 10`.
- Choisie plutôt que `v_commandes` ou `details_commande(id_commande)` parce
  que c'est l'objet le plus riche à démontrer ici : une vue matérialisée
  rafraîchie périodiquement (pgAgent/cron), pas juste une vue classique.
- Le résultat dépend de `date_rafraichissement` : si la vue n'a pas été
  rafraîchie récemment, les chiffres peuvent être décalés par rapport aux
  données actuelles — c'est un point à surveiller en testant.

**Vérification suggérée** : comparer la quantité vendue d'un produit du top
avec un calcul manuel sur `info_commande` + `commande` pour les 7 derniers
jours (commandes non annulées); au besoin, faire d'abord
`REFRESH MATERIALIZED VIEW CONCURRENTLY commerce.mv_ventes_produit_7j;`.

**Vérification** : validée par Vincent le 24 sept.

---

## Requête 8 — Écriture paramétrée exécutée par l'application

**Question métier** : Recherche de commandes selon 2 critères (client +
statut) — gabarit de ce que l'application (étape 5) exécutera avec de vrais
paramètres liés.

**Choix** :
- Placeholders `%s` (style psycopg2, positionnels) plutôt qu'un littéral en
  dur, pour représenter fidèlement ce que fera `cursor.execute(requete,
  (id_client, nom_statut))` dans l'application Python — ou l'équivalent
  `@nom_parametre` si l'application finale est en C#/Npgsql.
- Cette requête sert aussi de point de départ pour l'exigence « recherche
  selon ≥ 2 critères » de l'étape 5 (application cliente) : pas besoin de
  la réécrire de zéro.
- **Limite reconnue** : la logique de la requête est testable dès
  maintenant dans pgAdmin (en remplaçant les `%s` par des valeurs
  littérales), mais le vrai comportement paramétré (protection contre
  l'injection SQL via des paramètres liés plutôt qu'une concaténation de
  chaînes) ne pourra être confirmé qu'une fois l'application cliente codée
  à l'étape 5. Marquée « En cours » dans le suivi jusque-là.

**Vérification** : logique validée par Vincent le 24 sept (test avec
valeurs littérales dans pgAdmin); comportement paramétré réel à confirmer
à l'étape 5.

---

## Requête 9 — JSONB : recherche par contenance @>

**Question métier** : Quels produits ont la marque recherchée par
l'utilisateur ?

**Choix** :
- `WHERE specifications_produit @> jsonb_build_object('marque', %s)` —
  construit le fragment JSON à comparer à partir du paramètre plutôt que
  d'écrire un littéral JSON en dur (`@> '{"marque": "Samsung"}'`), sur
  demande de Vincent, pour que la requête reste générique et que
  l'application (étape 5) puisse y faire passer n'importe quelle marque
  choisie par l'utilisateur.
- Profite directement de l'index GIN `idx_specification_produit_gin`
  (`jsonb_path_ops`, créé dans `01_create_schema.sql`) : `jsonb_path_ops`
  est justement optimisé pour l'opérateur `@>`. Bon candidat potentiel pour
  une des 2 requêtes EXPLAIN ANALYZE avant/après index demandées à la fin
  de l'étape 4, si on veut réutiliser celle-ci plutôt que d'en écrire une
  11e séparée.

**Vérification** : validée par Vincent le 24 sept (testée avec 'Samsung'
comme valeur littérale à la place de `%s`).

---

## Requête 10 — JSONB : manipulation d'une structure imbriquée

**Question métier** : Corriger la largeur (`dimensions.largeur`) d'un
produit précis dans ses spécifications, sans toucher au reste du JSON.

**Choix** :
- `UPDATE` classique (`WHERE id_produit = ...` cible une seule ligne), sauf
  que la nouvelle valeur de `specifications_produit` est calculée par
  `jsonb_set(colonne, chemin, nouvelle_valeur, create_missing)` plutôt
  qu'écrite en dur — ça remplace uniquement la clé imbriquée visée
  (`{dimensions,largeur}`) et laisse tout le reste du JSON intact.
- `create_missing = false` (4e argument) : n'ajoute PAS la clé `dimensions`
  si elle n'existe pas déjà pour ce produit. Décision prise parce que tous
  les produits n'ont pas les mêmes spécifications selon leur catégorie
  (certains n'ont pas de `dimensions` du tout) — on veut corriger une
  valeur existante, pas en créer une par accident sur un produit qui n'en
  a pas.
- Cible **un produit précis** plutôt qu'une catégorie entière, pour la même
  raison : les spécifications varient trop d'un produit à l'autre pour
  qu'une mise à jour en masse ait du sens ici.

**Vérification suggérée** : trouver d'abord un `id_produit` qui a bien une
clé `dimensions.largeur` (`... WHERE specifications_produit -> 'dimensions'
? 'largeur'`), exécuter l'`UPDATE`, puis confirmer par un `SELECT` que
seule `largeur` a changé et que le reste du JSON (marque, hauteur, etc.)
est intact. Optionnel : réessayer sur un produit sans `dimensions` pour
confirmer que rien n'est ajouté.

**Vérification** : validée par Vincent le 24 sept.

---

## 11-12. Analyse des plans d'exécution (2 requêtes améliorables par un index)

**Question méthodologique** : le jeu de données de base (~500 commandes)
était trop petit pour observer un vrai changement de plan — PostgreSQL
préfère presque toujours un `Seq Scan` sur une petite table, index ou pas.
Pour un test honnête et démonstratif, le jeu de données a été augmenté à
**50 000 commandes et 1500 clients (graine 0.75)** via le paramètre
`nb_commandes` de `03_donnees.sql`.

### Candidat A : `commande.id_statut`

**Question métier** : Quelles commandes ont le statut `'Annulée'` ?

**Pourquoi cette colonne** : `id_statut` est filtré (via jointure sur
`statut`) dans la majorité des requêtes de ce fichier (2, 3, 4, 5, 6, 7),
donc un index dessus a un intérêt réel au-delà de ce seul test.

```sql
EXPLAIN ANALYZE
SELECT c.id_commande, c.date_commande, c.id_client
FROM commerce.commande c
JOIN commerce.statut s ON s.id_statut = c.id_statut
WHERE s.nom_statut = 'Annulée';
```

**Avant l'index** : `Seq Scan` complet sur `commande` (50 000 lignes lues),
puis `Hash Join` avec le statut trouvé par index sur `statut`.
Coût `8.18..3530.19`, 3996 lignes retournées, **Execution Time = 21.423 ms**.

**Index créé** :
```sql
CREATE INDEX idx_commande_id_statut ON commerce.commande(id_statut);
```

**Après l'index** : le plan change réellement — `Bitmap Index Scan` sur
`idx_commande_id_statut` suivi d'un `Bitmap Heap Scan`, dans un
`Nested Loop`. Coût `97.02..3182.53`, mêmes 3996 lignes,
**Execution Time = 10.855 ms**.

**Comparaison et interprétation honnête** : le coût estimé baisse
légèrement (3530 → 3183), mais surtout le temps réel est quasiment divisé
par deux (21.4 ms → 10.9 ms). Avec un jeu de données assez volumineux,
l'index devient rentable et le planificateur change effectivement de
stratégie de parcours (Seq Scan → Bitmap Scan) — contrairement à ce
qu'on aurait observé sur le jeu de données initial de ~500 lignes.

### Candidat B : `paiement.est_complete`

**Question métier** : Quels paiements sont restés non complétés ?

**Pourquoi cette colonne** : `est_complete` est le critère central de la
requête 6 (commandes annulées avec paiement non complété).

```sql
EXPLAIN ANALYZE
SELECT p.id_paiement, p.id_commande, p.mode_paiement, p.montant_paiement
FROM commerce.paiement p
WHERE p.est_complete = FALSE;
```

**Avant l'index** : `Seq Scan` sur `paiement`, le filtre élimine 45 412
lignes sur ~47 710 pour n'en garder que 2298. **Execution Time = 8.722 ms**.

**Index créé** (index partiel, car seule la valeur `FALSE` est recherchée
dans ce contexte) :
```sql
CREATE INDEX idx_paiement_incomplet
    ON commerce.paiement(id_commande)
    WHERE est_complete = FALSE;
```

**Après l'index** : `Index Scan using idx_paiement_incomplet`. Le coût
estimé chute radicalement (`885.10` → `92.91`), **Execution Time = 6.283 ms**
(vs 8.722 ms).

**Comparaison et interprétation honnête** : le plan change bien
(Seq Scan → Index Scan) et le coût estimé chute fortement, mais le gain de
temps réel est plus discret que pour le candidat A. Les `Buffers: shared
hit` élevés dans les deux plans indiquent que les données étaient déjà
largement en cache mémoire — le `Seq Scan` n'était donc pas si coûteux en
pratique ici, même sur 47 710 lignes. L'avantage de l'index serait
probablement plus marqué sur une table trop grande pour tenir en cache, ou
sous une charge concurrente plus réaliste. C'est exactement le genre de
nuance que l'énoncé demande d'expliquer honnêtement : un index qui change
le plan et le coût estimé n'apporte pas toujours un gain de temps
proportionnel en pratique.

**Vérification** : validée par Vincent le 25 sept (captures et export CSV
des plans avant/après conservés dans `Doc/` : `Commande_avant_Index.png`,
`Commande_apres_index.png`, `Paiement_avant_Index.png`,
`Paiement_apres_index.png`, et les CSV correspondants).

---

## Requêtes restantes (à documenter au fur et à mesure)

Aucune — les 10 requêtes et l'analyse des plans d'exécution (11-12) sont
maintenant toutes documentées ci-dessus.
