# TP1 – Commerce en ligne (PostgreSQL + JSONB)

Base de données II (420-B56) · Vincent Trudel · Automne 2026

Base de données d'un commerce en ligne : produits (spécifications en JSONB),
catégories, clients, commandes, paiements, expéditions, réceptions
fournisseur, évaluations et audit des statuts. Le cycle de vie d'une commande
(En attente → Payée → En préparation → Expédiée → Livrée, ou Annulée) est
protégé par des déclencheurs.

---

## 1. Prérequis

| Outil | Version utilisée | Rôle |
|---|---|---|
| PostgreSQL (EDB) | 18 | serveur + `psql` (`/Library/PostgreSQL/18/bin`) |
| pgAdmin 4 | 9.x | exécution manuelle de 06 et 07, diagramme ER |
| .NET SDK | 10 | application console (`app/`) |
| pgAgent (facultatif) | — | rafraîchissement planifié de la vue matérialisée |

> Les lanceurs `.command` sont pour macOS. Sur un autre système, exécuter les
> commandes `psql` données à la section 3.

## 2. Contenu

| Fichier | Rôle |
|---|---|
| `00_create_database.sql` | `DROP` + `CREATE DATABASE tp1_vincent_trudel` (connecté à `postgres`) |
| `01_create_schema.sql` | schéma `commerce`, tables, contraintes, JSONB, index (dont GIN) |
| `02_declencheurs.sql` | déclencheurs : stock, évaluation, réceptions, audit, expédition, cycle de vie, annulation |
| `03_donnees.sql` | données fictives (paramètres en haut : 1 500 clients, 50 000 commandes, graine 0,75) |
| `04_vues_fonctions.sql` | `v_commandes`, `v_receptions_attendues`, `mv_ventes_produit_7j`, `details_commande`, `avancer_commande` |
| `05_roles.sql` | groupes `tp1_employe` / `tp1_gestionnaire` / `tp1_admin`, utilisateurs `demo_*` |
| `06_transactions.sql` | démonstration COMMIT / ROLLBACK (**à la main**, bloc par bloc) |
| `07_requetes.sql` | les 10 requêtes + `EXPLAIN ANALYZE` avant/après index (**à la main**) |
| `08_tests.sql` | 17 tests automatisés (transaction terminée par `ROLLBACK`) |
| `creer_bd.command` | lanceur principal : 00 → 05, arrêt à la première erreur |
| `lancer_tests.command` | lanceur des tests : `[OK]` / `[ECHEC]` par test + bilan |
| `app/` | application console C# (Npgsql) |
| `export/` | export JSONL de la base de connaissances + script + lanceur |
| `Doc/` | justification des requêtes et des plans, fiche de données |

## 3. Créer la base

**Attention : destructif.** La base `tp1_vincent_trudel` est supprimée puis
recréée. Fermer les onglets pgAdmin connectés à cette base avant.

### Méthode 1 – lanceur (macOS)

Double-cliquer `creer_bd.command`, puis répondre aux questions (hôte, port,
utilisateur `postgres`, mot de passe). Le script s'arrête à la première erreur.
Le chargement des données prend une à deux minutes.

### Méthode 2 – psql

```bash
cd "chemin/vers/le/dossier"
psql -X -v ON_ERROR_STOP=1 -U postgres -d postgres           -f 00_create_database.sql
psql -X -v ON_ERROR_STOP=1 -U postgres -d tp1_vincent_trudel -f 01_create_schema.sql
psql -X -v ON_ERROR_STOP=1 -U postgres -d tp1_vincent_trudel -f 02_declencheurs.sql
psql -X -v ON_ERROR_STOP=1 -U postgres -d tp1_vincent_trudel -f 03_donnees.sql
psql -X -v ON_ERROR_STOP=1 -U postgres -d tp1_vincent_trudel -f 04_vues_fonctions.sql
psql -X -v ON_ERROR_STOP=1 -U postgres -d tp1_vincent_trudel -f 05_roles.sql
```

### Après chaque création : mots de passe des utilisateurs de démonstration

`05_roles.sql` supprime et recrée les rôles `demo_*` **sans mot de passe**
(aucun secret dans les scripts). Les définir à la main, dans pgAdmin
(*Login/Group Roles*, au niveau du serveur) ou dans psql :

```sql
ALTER ROLE demo_gestionnaire WITH PASSWORD 'votre_mot_de_passe';
ALTER ROLE demo_employe      WITH PASSWORD 'votre_mot_de_passe';
```

> `05_roles.sql` doit aussi être relancé après `01` ou `04` (recréer un objet
> efface ses privilèges).

## 4. Tests

Double-cliquer `lancer_tests.command` (utilisateur `postgres`), ou :

```bash
psql -X -v ON_ERROR_STOP=1 -U postgres -d tp1_vincent_trudel -f 08_tests.sql
```

Résultat attendu : `Bilan : 17 / 17 test(s) reussi(s)`. Les tests ne modifient
pas la base (`ROLLBACK` final). Couverture : contraintes (T01–T04),
déclencheurs (T05–T11), fonction et procédure (T12–T13), transaction (T14),
vues et vue matérialisée (T15), rôles (T16–T17).

## 5. Application console (`app/`)

Variables d'environnement :

| Variable | Obligatoire | Défaut |
|---|---|---|
| `PGUSER` | oui | — (`demo_gestionnaire` ou `demo_employe`) |
| `PGPASSWORD` | oui | — |
| `PGHOST` | non | `localhost` |
| `PGPORT` | non | `5432` |
| `PGDATABASE` | non | `tp1_vincent_trudel` |

```bash
cd "chemin/vers/le/dossier/app"
export PGUSER=demo_gestionnaire
export PGPASSWORD='...'          # jamais écrit dans un fichier du projet
dotnet run
```

Menu : 1) commandes récentes (vue) · 2) recherche client + statut ·
3) produits par marque (JSONB `@>`) · 4) détails d'une commande (fonction) ·
5) faire avancer une commande (procédure) · 6) ajouter une évaluation ·
7) payer une commande (transaction COMMIT / ROLLBACK).

Avec `demo_employe`, les options 5, 6 et 7 sont refusées par la base
(`42501`, permission refusée) : c'est voulu.

## 6. Transactions et requêtes (à la main)

Dans pgAdmin, ouvrir le Query Tool sur `tp1_vincent_trudel` :

- `06_transactions.sql` : exécuter **bloc par bloc dans le même onglet**
  (voir les consignes dans le fichier). Le scénario 1 modifie la base.
- `07_requetes.sql` : sélectionner une requête à la fois, puis F5.

> pgAdmin ne peut pas ouvrir un fichier dont le chemin contient `%`
> (« URI malformed ») : copier le contenu dans le Query Tool.

## 7. Vue matérialisée

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY commerce.mv_ventes_produit_7j;
```

- **pgAgent** : job `refresh_mv_ventes_produits_7j` (base `postgres`, étape SQL
  locale sur `tp1_vincent_trudel`, tous les jours à 02:00).
- **cron** (alternative) :

```
0 2 * * * /Library/PostgreSQL/18/bin/psql -X -d tp1_vincent_trudel -c "REFRESH MATERIALIZED VIEW CONCURRENTLY commerce.mv_ventes_produit_7j;"
```

(mot de passe fourni par `~/.pgpass`, jamais dans la commande).

## 8. Export de la base de connaissances

Double-cliquer `export/lancer_export.command`, ou :

```bash
cd "chemin/vers/le/dossier/export"
psql -X -v ON_ERROR_STOP=1 -U postgres -d tp1_vincent_trudel -f export_connaissances.sql
```

Produit `export/base_connaissances.jsonl` (≥ 50 unités, clés `source_id`,
`content`, `metadata`). Voir `Doc/fiche_de_donnees_export.md`.

## 9. Remise

Archive `TP1_prenom_nom.zip` **sans** : mot de passe, `.env`, `.pgpass`,
`app/bin`, `app/obj`, `.DS_Store`, fichiers `~$*`.
