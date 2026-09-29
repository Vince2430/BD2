# TP1 – Base de données II (420-B56) – Commerce en ligne

Vincent Trudel · PostgreSQL 18 · pgAdmin 4
Base : `tp1_vincent_trudel` · schéma : `commerce`

> README en cours de rédaction. Les sections marquées *(à compléter)*
> seront remplies aux étapes suivantes (application cliente, tests).

---

## 1. Prérequis

- PostgreSQL 18 (installateur EDB, `/Library/PostgreSQL/18`) et ses outils
  client (`psql`).
- pgAdmin 4.
- macOS pour le lanceur `creer_bd.command` (sinon, exécuter les scripts à la
  main, voir 3.2).
- Facultatif : pgAgent, pour le rafraîchissement automatique de la vue
  matérialisée (voir section 5).

## 2. Contenu des scripts SQL

Les scripts sont numérotés dans leur ordre d'exécution.

| Script | Base cible | Rôle |
|---|---|---|
| `00_create_database.sql` | `postgres` | Supprime puis recrée la base `tp1_vincent_trudel` |
| `01_create_schema.sql` | `tp1_vincent_trudel` | Schéma `commerce`, tables, contraintes, colonne JSONB, index |
| `02_declencheurs.sql` | `tp1_vincent_trudel` | Déclencheurs (stock, évaluation, réceptions, audit, expédition, annulation) |
| `03_donnees.sql` | `tp1_vincent_trudel` | Jeu de données fictives (≈ 5 000 lignes, 500 commandes) |
| `04_vues_fonctions.sql` | `tp1_vincent_trudel` | Vues `v_commandes` et `v_receptions_attendues`, fonction `details_commande`, vue matérialisée `mv_ventes_produit_7j`, procédure `avancer_commande` |
| `05_roles.sql` | `tp1_vincent_trudel` | Groupes `tp1_employe`, `tp1_gestionnaire`, `tp1_admin`, utilisateurs de démonstration, privilèges minimaux |
| `06_transactions.sql` | `tp1_vincent_trudel` | Démonstration COMMIT / ROLLBACK (paiement par carte). **Hors du lanceur**, à exécuter à la main |

`03_donnees.sql` a ses paramètres en haut du fichier (nombre de clients, de
commandes, graine aléatoire). Les dates des commandes sont calculées à partir
de la date d'exécution : recharger les données avant de tester la vue
matérialisée (ventes des 7 derniers jours).

## 3. Création de la base

**Attention : la création supprime la base `tp1_vincent_trudel` si elle
existe.** Fermer d'abord les onglets pgAdmin connectés à cette base.

### 3.1 Avec le lanceur (macOS)

1. Double-cliquer sur `creer_bd.command`.
2. Répondre aux questions : hôte (`localhost`), port (`5432`), utilisateur
   (`postgres`), mot de passe. Le mot de passe n'est pas affiché et n'est
   conservé que le temps de l'exécution.
3. Le lanceur exécute les scripts 00 à 05 et s'arrête à la première erreur.
   Il se termine par « Termine. Base tp1_vincent_trudel prete. »

Si macOS refuse de lancer le fichier : `chmod +x creer_bd.command` dans le
Terminal, ou clic droit → Ouvrir.

### 3.2 À la main

```
psql -U postgres -d postgres           -f 00_create_database.sql
psql -U postgres -d tp1_vincent_trudel -f 01_create_schema.sql
psql -U postgres -d tp1_vincent_trudel -f 02_declencheurs.sql
psql -U postgres -d tp1_vincent_trudel -f 03_donnees.sql
psql -U postgres -d tp1_vincent_trudel -f 04_vues_fonctions.sql
psql -U postgres -d tp1_vincent_trudel -f 05_roles.sql
```

`05_roles.sql` doit être relancé après toute ré-exécution de 01 ou 04
(recréer un objet efface les privilèges accordés dessus).

Ou dans pgAdmin : sélectionner la base indiquée dans le tableau de la
section 2, ouvrir le script dans le Query Tool et l'exécuter (F5).

## 4. Utilisation des objets de l'étape 3

```sql
SET search_path TO commerce, public;

SELECT * FROM v_commandes WHERE nom_statut = 'Payée';
SELECT * FROM v_receptions_attendues;
SELECT * FROM details_commande(1);          -- erreur P0002 si la commande n'existe pas
SELECT * FROM mv_ventes_produit_7j;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventes_produit_7j;

CALL avancer_commande(42);             -- statut suivant de la commande 42
CALL avancer_commande(42, 'CAM-02');   -- idem, avec un camion (étape Expédiée)
```

**Cycle de vie d'une commande.** Le déclencheur `trg_proteger_commande`
valide tout changement de statut, quelle qu'en soit la source :

```
En attente -> Payée -> En préparation -> Expédiée -> Livrée
     \___________\______________\____________-> Annulée
```

- une nouvelle commande est toujours « En attente »;
- « Payée » exige au moins une ligne et des paiements complétés couvrant
  le total;
- « Expédiée » exige que toutes les quantités soient prévues dans des
  expéditions;
- « Livrée » exige que ces expéditions soient complétées;
- une commande annulée est figée; une commande n'est jamais supprimée.

La procédure `avancer_commande` fait le travail de chaque étape (création de
l'expédition et de ses lignes, complétion des expéditions à la livraison)
puis change le statut; le déclencheur valide la transition.

## 5. Rafraîchissement nocturne de la vue matérialisée

`mv_ventes_produit_7j` est une photo des ventes des 7 derniers jours, prise
au moment du `REFRESH`. La colonne `date_rafraichissement` indique de quand
datent les chiffres. PostgreSQL ne planifie rien lui-même : il faut un outil
externe. Deux options.

### 5.1 pgAgent (option utilisée)

1. Installer pgAgent avec Stack Builder (Add-ons, tools and utilities →
   pgAgent). Il s'installe comme service sous l'utilisateur macOS `postgres`.
2. Dans la base **`postgres`** : `CREATE EXTENSION IF NOT EXISTS pgagent;`
3. pgAdmin → clic droit sur *pgAgent Jobs* → *Create > pgAgent Job* :
   - General : nom `refresh_mv_ventes_produits_7j`, activé;
   - Steps : type **SQL**, connexion **Local**, base `tp1_vincent_trudel`,
     code :
     `REFRESH MATERIALIZED VIEW CONCURRENTLY commerce.mv_ventes_produit_7j;`
   - Schedules : aucune date de fin; Repeat : Hours = 02, Minutes = 00.
4. Tester : clic droit sur la tâche → *Run now*, puis vérifier
   `date_rafraichissement`.

**Mot de passe.** Le step se connecte à `tp1_vincent_trudel` avec
l'utilisateur de pgAgent, sans mot de passe dans la tâche. Le mot de passe est
lu dans le fichier `.pgpass` de l'utilisateur macOS `postgres`
(`/Library/PostgreSQL/18/.pgpass`, permissions `600`). Le fichier créé par
l'installateur ne vise que la base `postgres`; le champ base doit valoir `*` :

```
localhost:5432:*:postgres:<mot de passe>
```

Sinon, la tâche échoue avec « Couldn't get a connection to DataBase! ».
Le `.pgpass` contient un mot de passe : il ne fait pas partie de la remise.

La tâche est enregistrée dans la base `postgres` : elle survit à la
recréation de `tp1_vincent_trudel`. Elle ne s'exécute que si l'ordinateur est
allumé et que le service pgAgent tourne.

### 5.2 Alternative : cron

Sans pgAgent, le planificateur du système peut lancer `psql` chaque nuit à
2 h. `crontab -e`, puis :

```
0 2 * * * /Library/PostgreSQL/18/bin/psql -h localhost -U postgres -d tp1_vincent_trudel -c "REFRESH MATERIALIZED VIEW CONCURRENTLY commerce.mv_ventes_produit_7j;"
```

Le mot de passe est lu dans le `~/.pgpass` de l'utilisateur qui possède la
crontab (même format, permissions `600`).

## 6. Rôles et privilèges

Le **personnel** se connecte à PostgreSQL avec des rôles; les **clients** ne
se connectent jamais à la base (ils sont authentifiés par l'application avec
`client.hash_mot_passe_client`).

| Groupe | Hérite de | Ajoute |
|---|---|---|
| `tp1_employe` | — | `CONNECT`, `USAGE` sur `commerce`, `SELECT` sur tables et vues (sauf `client.hash_mot_passe_client`), `EXECUTE details_commande` |
| `tp1_gestionnaire` | `tp1_employe` | `INSERT`, `UPDATE` (tables d'opération et catalogue; `statut` et l'audit exclus, sauf `INSERT` sur l'audit requis par son déclencheur), `EXECUTE avancer_commande` |
| `tp1_admin` | `tp1_gestionnaire` | `MAINTAIN` (refresh de la vue matérialisée, VACUUM, ANALYZE, REINDEX) |

Personne n'a `DELETE` ni `TRUNCATE`. Les droits par défaut de `PUBLIC`
(connexion à la base, exécution des routines) sont retirés.

Utilisateurs de démonstration : `demo_employe`, `demo_gestionnaire`,
`demo_admin` (`CREATEROLE` + `ADMIN OPTION` sur `tp1_employe` et
`tp1_gestionnaire` : peut créer des utilisateurs et les placer dans ces
groupes). **Aucun mot de passe n'est dans les scripts** : les définir après
la création, par exemple :

```
psql -U postgres -d tp1_vincent_trudel
\password demo_employe
```

ou dans pgAdmin : *Login/Group Roles* → clic droit → *Properties* →
*Definition*.

Les rôles existent au niveau du serveur; ils sont préfixés `tp1_` / `demo_`
et `05_roles.sql` les supprime puis les recrée à chaque exécution.

## 7. Transactions (démonstration)

`06_transactions.sql` ne fait pas partie du lanceur : il modifie les données
et son deuxième scénario échoue volontairement. Il s'exécute **bloc par bloc**
dans un Query Tool pgAdmin, **toujours dans le même onglet** (il utilise une
table temporaire liée à la session).

Il simule le parcours réel d'un paiement par carte :

1. **autorisation** — la banque réserve le montant (`paiement.est_complete =
   FALSE`, sans date);
2. **capture** — le commerçant confirme et le client est débité
   (`est_complete = TRUE` + date), puis la commande passe à « Payée ».

Le processeur de paiement est un service externe : la base ne l'appelle pas.
Sa réponse est écrite en commentaire dans le script, et c'est l'application
(étape 5) qui, en vrai, décide du `COMMIT` ou du `ROLLBACK`.

- **Scénario 1 (COMMIT)** : capture approuvée → paiement complété + commande
  « Payée », le tout validé.
- **Scénario 2 (ROLLBACK)** : autorisation partielle (la moitié du total). La
  capture passe, mais le déclencheur refuse le passage à « Payée » (règle :
  paiements complétés ≥ total). Le `ROLLBACK` annule aussi la capture : le
  paiement reste en autorisation et la commande « En attente ».

La règle protégée est donc double : pas de commande payée sans paiement
suffisant, et jamais un paiement capturé sans la commande correspondante.
À noter : un `ROLLBACK` dans la base n'annule pas un débit sur la carte; un
vrai système capture après le `COMMIT`, ou rembourse.

Le scénario 1 modifie réellement la base : relancer `creer_bd.command` pour
rejouer la démonstration à neuf.

## 8. Variables d'environnement *(à compléter — application cliente)*

## 9. Tests *(à compléter — étape 6)*

## 10. Lancement de l'application cliente *(à compléter — étape 5)*
