# Fiche de données — `base_connaissances.jsonl`

> **Base de travail (proposée par Claude le 25 sept 2026) — à relire et reformuler par Vincent avant de l'intégrer à `rapport.pdf`.** Chiffres tirés de l'export du 2026-09-25.

**Fichier** : `export/base_connaissances.jsonl` (JSONL, UTF-8, une unité documentaire par ligne) · **66 unités** · **Régénération** : `export/lancer_export.command` (exécute `export_connaissances.sql` avec psql).

## 1. Provenance

- Base PostgreSQL `tp1_vincent_trudel`, schéma `commerce` (scénario : commerce en ligne d'électronique).
- **Données entièrement fictives**, générées par `03_donnees.sql` (graine 0.75, 50 000 commandes, 1 500 clients, 24 produits, 6 catégories).
- Tables sources : `produit`, `categorie`, `specification_produit` (JSONB), `commande`, `info_commande`, `paiement`, `expedition`, `info_expedition`, `audit_statut_commande`, `client`, `evaluation`.
- **Sélection (tranche déterministe)** : 2 premiers produits (`id_produit`) de chaque catégorie; toutes les catégories; 2 premières commandes (`id_commande`) de chaque statut contenant au moins un de ces produits; les clients de ces commandes; les 24 premières évaluations de la table.
- **Champs exclus ou transformés (confidentialité)** : nom, courriel, téléphone, adresse et hash du mot de passe des clients jamais exportés; client remplacé par un pseudonyme `client-NNNN`; adresse de livraison réduite à la ville; colonne `utilisateur` de l'audit (rôles PostgreSQL) exclue.

## 2. Période couverte

- Commandes : du **2025-05-16** au **2026-09-25**; évaluations : du **2025-04-17** au **2025-12-15**; statistiques par client : depuis le 2025-04-25.
- Ensemble des données : environ 18 mois précédant la création de la base. Date d'export : **2026-09-25**.

## 3. Champs

| Champ | Contenu |
|---|---|
| `source_id` | Identifiant stable `<type>-<id>` (ex. `produit-1`, `commande-63`, `client-0007`) |
| `content` | Texte autoportant en français (montants `1234,56 $`, dates AAAA-MM-JJ) |
| `metadata.type`, `source`, `date_export` | Type d'unité, tables d'origine, date de génération (toutes les unités) |
| Produit (12) | `categorie`, `categorie_ref`, `prix`, **`specifications`** (document JSONB brut, semi-structuré) |
| Catégorie (6) | `nb_produits`, `produits_ref` |
| Commande (12) | `statut`, `date`, `total`, `ville`, `client_ref`, `produits_ref` |
| Client (12) | `nb_commandes`, `total_depense`, `commandes_ref` |
| Évaluation (24) | `note`, `date`, `produit_ref`, `client_ref`, **`commentaire`** (texte libre, non structuré) |

## 4. Valeurs manquantes

- `commentaire` : `"aucun commentaire"` lorsque le client n'a rien écrit (3 évaluations).
- `specifications` : une clé peut être absente (sans objet) ou `null` (valeur inconnue) — aucun cas dans les données actuelles.
- Commandes : « aucun paiement enregistré » (1) et « aucune expédition » (8, normal avant l'expédition ou après une annulation).
- `ville` : « ville non précisée » si l'adresse ne suit pas le format attendu (0 cas).
- Références vers des unités absentes de l'export : 24 `client_ref` et 10 `produit_ref` (évaluations), 12 `produits_ref` (commandes). Le nom du produit reste écrit dans `content`.

## 5. Limites

- Échantillon de 66 unités, non représentatif statistiquement; les statistiques (ventes, notes, totaux) portent pourtant sur **toute** la base.
- Données fictives : ne reflètent aucun comportement réel.
- Dates calculées à partir du jour de création de la base : recréer la base un autre jour décale les dates (les `source_id` restent les mêmes).
- `source_id` stables tant que la base est créée par les mêmes scripts : l'ordre des `id_produit` dépend du plan d'insertion de PostgreSQL (non garanti).
- Instantané de la base au moment de l'export (les modifications faites ensuite par l'application n'y sont pas).
- Un paiement « non complété » ne distingue pas un échec d'une attente (pas de statut de paiement dans le schéma).

## 6. Utilisations prévues

- **Prévue** : alimenter une recherche assistée par IA sur le catalogue (caractéristiques techniques, avis), le cycle de vie des commandes et les règles métier (annulation, paiement, expédition), en filtrant par `metadata`.
- **Non prévue** : analyses statistiques ou décisions commerciales réelles; identification de clients.
