# Fiche de données – `base_connaissances.jsonl`

**Brouillon à relire et compléter par Vincent** (chiffres à confirmer après
la régénération de l'export).

**Provenance.** Base PostgreSQL `tp1_vincent_trudel`, schéma `commerce`
(commerce en ligne fictif). Données générées par `03_donnees.sql` (graine
0,75), exportées par `export/export_connaissances.sql` (psql, lecture seule).
Toutes les données sont fictives.

**Période couverte.** Les 365 jours précédant l'exécution de `03_donnees.sql`
(les dates sont relatives au moment du chargement). Recréer la base un autre
jour donne les mêmes `source_id`, mais des dates différentes.

**Contenu.** Une unité documentaire par ligne (JSON Lines), 55 à 66 unités
(66 attendues) :

| Type | Sélection | Nombre |
|---|---|---|
| produit | 2 plus petits `id_produit` de chaque catégorie | 12 |
| categorie | toutes | 6 |
| commande | 2 premières de chaque statut contenant ≥ 1 des 12 produits | 12 |
| client | clients de ces commandes (pseudonymisés) | 1 à 12 |
| evaluation | 24 premières de la table | 24 |

**Champs.**

- `source_id` : identifiant stable (`produit-3`, `categorie-2`,
  `commande-118`, `client-0042`, `evaluation-7`), tiré de la clé primaire.
- `content` : résumé en français, compréhensible sans les tables.
- `metadata` : `type`, `source` (tables d'origine), puis selon le type :
  catégorie, marque, prix, spécifications JSONB brutes, date (ISO), statut,
  ville, total, note, commentaire complet, liens `client_ref`,
  `produit_ref`, `produits_ref`.

**Valeurs manquantes.** Évaluation sans commentaire → `"aucun commentaire"`.
Produit sans évaluation → « Aucune évaluation », `note_moyenne` = `null`.
Adresse sans ville reconnaissable → « ville non précisée ».

**Limites.**

- Tranche volontairement petite : ce n'est pas un échantillon représentatif.
- Références hors export : certaines évaluations et commandes pointent vers
  des produits ou clients absents de la tranche (normal, liens seulement).
- Montants sans séparateur de milliers (`30933842,58 $`).
- Les ventes et revenus excluent les commandes annulées et utilisent le prix
  figé au moment de la commande.

**Données personnelles.** Aucun nom, courriel, téléphone, adresse complète,
hachage de mot de passe ni utilisateur de l'audit. Les clients sont
pseudonymisés (`client-NNNN`); seule la ville de livraison est conservée. Le
script refuse d'écrire le fichier si un `@` ou un nom de client s'y trouve.

**Utilisations prévues.** Base de connaissances pour une recherche assistée
par IA (RAG) : questions sur le catalogue, les ventes par catégorie, le suivi
d'une commande, l'avis des clients. À ne pas utiliser pour des décisions
réelles (données fictives).
