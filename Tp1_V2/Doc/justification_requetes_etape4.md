# Étape 4 – Justification des requêtes et analyse des plans

Référence : `07_requetes.sql`. Choix communs à toutes les requêtes :

- Les revenus et dépenses **excluent les commandes « Annulée »**.
- Ils utilisent le **prix figé** (`info_commande.prix_unitaire`), pas le prix
  actuel du catalogue (`produit.prix_produit`) : on mesure ce qui a vraiment
  été vendu, même si un prix change plus tard.

## Les 10 requêtes

| # | Notion | Question | Choix et alternatives écartées |
|---|---|---|---|
| 1 | Jointure ≥ 3 tables | Catalogue complet avec catégorie et spécifications | `INNER JOIN` : chaque produit a une catégorie (NOT NULL) et des spécifications (1-1). |
| 2 | GROUP BY + HAVING | Catégories ayant rapporté plus de 1000 $ | Le filtre sur l'agrégat va dans `HAVING` (un `WHERE` ne peut pas filtrer une somme). Seuil à ajuster selon les données. |
| 3 | Sous-requête corrélée / EXISTS | Client(s) ayant le plus dépensé | `NOT EXISTS` corrélé : « il n'existe pas de client ayant dépensé plus ». Garde les ex æquo. Pas de fenêtre (réservée à 5) ni de `WITH` (réservé à 4). |
| 4 | WITH | Résumé par client (nb de commandes, dates, total, produits différents par commande) | La CTE résume d'abord **par commande**, puis la requête principale regroupe **par client** : deux niveaux d'agrégation lisibles. |
| 5 | Fenêtre OVER | Classement des clients par montant dépensé | `RANK() OVER` sur l'agrégat groupé. Même question que la 3 avec une autre technique : le rang 1 = le résultat de la 3. `RANK` plutôt que `ROW_NUMBER` pour garder les ex æquo. |
| 6 | UNION | Clients « à risque » et la raison | `UNION` (et non `UNION ALL`) élimine les doublons dans chaque raison. Limite : le schéma ne distingue pas un paiement « échoué » d'un paiement pas encore complété (question ouverte #3). |
| 7 | Vue / vue matérialisée / fonction | Top 10 des produits vendus sur 7 jours | Lecture de `mv_ventes_produit_7j` (calcul coûteux fait au rafraîchissement). 7b : appel de `details_commande`. |
| 8 | Écriture paramétrée par l'application | Ajouter une évaluation | L'`INSERT` de l'option 6 de l'application, avec paramètres Npgsql. Dans le script : `PREPARE` / `EXECUTE` ($1 à $4). 8b : la recherche client + statut de l'option 2 (lecture paramétrée). |
| 9 | JSONB `@>` | Produits d'une marque donnée | `@> jsonb_build_object('marque', $1)` : paramètre, pas de JSON écrit à la main. Utilise l'index GIN `jsonb_path_ops`. |
| 10 | JSONB imbriqué | Corriger `dimensions.largeur` d'un produit | `jsonb_set(..., '{dimensions,largeur}', ..., false)` : modifie une seule clé; `create_missing = false` ne crée rien si le produit n'a pas de dimensions. |

> **À décider (requête 8)** : l'énoncé demande une requête *d'écriture*
> paramétrée exécutée par l'application. La recherche client + statut
> (ancienne requête 8) est une *lecture* : elle est gardée en 8b.

## Index

| Index | Colonne(s) | Requêtes servies |
|---|---|---|
| `idx_commande_id_client` | `commande(id_client)` | option 2, requêtes 3-6, déclencheur d'évaluation |
| `idx_commande_date_commande` | `commande(date_commande)` | `v_commandes` (tri), vue matérialisée (7 jours) |
| `idx_info_commande_id_produit` | `info_commande(id_produit)` | ventes par produit, déclencheur d'évaluation |
| `idx_info_expedition_id_expedition` | `info_expedition(id_expedition)` | procédure `avancer_commande` (livraison) |
| `idx_specification_produit_gin` | GIN `jsonb_path_ops` | requête 9, option 3 |
| `idx_commande_id_statut` | `commande(id_statut)` | candidat A (section 11) |
| `idx_paiement_incomplet` | `paiement(id_commande) WHERE est_complete = FALSE` | candidat B (section 12), requête 6 |

## Analyse des plans d'exécution (sections 11 et 12)

Jeu de données : 50 000 commandes / 1 500 clients (graine 0,75). Le jeu
initial (~500 commandes) était trop petit : PostgreSQL préfère presque
toujours un parcours séquentiel sur une petite table, index ou pas.

> **Les mesures ci-dessous datent du 25 septembre (ancienne version des
> scripts). Relancer les sections 11 et 12 sur la base recréée et remplacer
> les chiffres.**

### Candidat A – `commande.id_statut` (commandes annulées)

| | Avant | Après |
|---|---|---|
| Parcours | Seq Scan sur `commande` + Hash Join | Bitmap Index Scan + Bitmap Heap Scan |
| Coût estimé | _à remplir_ | _à remplir_ |
| Lignes (estimées / réelles) | _à remplir_ | _à remplir_ |
| Temps mesuré | 21,423 ms | 10,855 ms |

Gain net (environ 2 fois plus rapide) : environ 7 % des commandes sont
annulées, assez peu pour que lire l'index puis seulement les pages utiles
coûte moins cher que lire toute la table.

### Candidat B – paiements non complétés (index partiel)

| | Avant | Après |
|---|---|---|
| Parcours | Seq Scan sur `paiement` (filtre) | Index Scan sur `idx_paiement_incomplet` |
| Coût estimé | _à remplir_ | _à remplir_ |
| Lignes (estimées / réelles) | _à remplir_ | _à remplir_ |
| Temps mesuré | 8,722 ms | 6,283 ms |

Le parcours change et le coût estimé baisse beaucoup, mais le gain de temps
réel est plus modeste : les données étaient déjà en mémoire (beaucoup de
`shared hit` des deux côtés). Un changement de plan ne donne pas toujours un
gain de temps proportionnel. L'index partiel ne contient que la petite
minorité de paiements non complétés : il est minuscule et ne coûte rien à
maintenir pour les paiements déjà capturés.
