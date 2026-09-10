# Parties 3 et 4 — applications console C# et Python

> Ce fichier couvre uniquement les parties 3 et 4. Son contenu est à fusionner
> dans le `README.md` final de la remise (qui doit aussi contenir l'installation
> des bases, la comparaison des deux modèles en 150-250 mots et la justification
> d'au moins deux contraintes).

Les deux applications font exactement les mêmes opérations, pour permettre la
comparaison des deux langages :

| # | Opération | Base utilisée |
|---|---|---|
| 1 | Afficher la liste des livres | relationnelle |
| 2 | Rechercher un livre ou un auteur (saisie utilisateur) | relationnelle |
| 3 | Afficher l'information équivalente (`->`, `->>`, `#>>`, `@>`, tableau JSON) | JSONB |
| 4 | Ajouter un livre / modifier un titre (`INSERT`, `UPDATE`, `jsonb_set`) | les deux |
| 0 | Quitter (fermeture propre des connexions) | — |

---

## 1. Configuration (à faire une seule fois)

Aucun mot de passe n'est écrit dans le code. Les deux applications lisent les
mêmes variables d'environnement, avec un fichier `.env` comme valeur par défaut.

```bash
cd Remise_Atelier1
cp .env.example .env
```

Puis ouvrir `.env` et remplir `PGPASSWORD` (et au besoin `PGUSER`, `PGHOST`,
`PGPORT`). Le fichier `.env` **n'est pas remis** : il est listé dans
`.gitignore` et doit être retiré de l'archive `Atelier1.zip`.

Variables lues :

| Variable | Valeur par défaut | Rôle |
|---|---|---|
| `PGHOST` | `localhost` | serveur PostgreSQL |
| `PGPORT` | `5432` | port |
| `PGUSER` | `postgres` | utilisateur |
| `PGPASSWORD` | *(aucune — obligatoire)* | mot de passe |
| `PGDATABASE_SQL` | `atelier_bibliotheque_sql` | base de la partie 1 |
| `PGDATABASE_JSONB` | `atelier1_bibliotheque_jsonb` | base de la partie 2 |

Une variable réellement définie dans le terminal a toujours priorité sur le
`.env`. On peut donc aussi lancer les applications sans `.env` :

```bash
export PGPASSWORD='...'
```

**Prérequis** : les deux bases doivent déjà exister et contenir des données
(scripts de création et d'insertion des parties 1 et 2).

---

## 2. Partie 4 — application Python

```bash
cd Remise_Atelier1/python
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

Fichiers :

| Fichier | Contenu |
|---|---|
| `config.py` | recherche du `.env`, lecture des variables, paramètres de connexion |
| `bibliotheque.py` | **toutes** les requêtes SQL, une fonction par opération |
| `app.py` | menu, saisies, affichage, gestion des erreurs |
| `requirements.txt` | `psycopg[binary]` (pilote v3) et `python-dotenv` |

Points demandés par l'énoncé :

- la connexion et les requêtes sont isolées dans des fonctions
  (`ouvrir_connexion_sql`, `lister_livres`, `rechercher_livre_ou_auteur`, …) ;
- **aucune concaténation** : toute saisie passe par un paramètre `%s`. Les `%`
  du `ILIKE` sont ajoutés à la *valeur* en Python, pas au texte de la requête ;
- les paramètres de connexion viennent des variables d'environnement / `.env` ;
- messages d'erreur distincts pour une variable manquante
  (`RuntimeError`), une connexion impossible (`psycopg.OperationalError`) et une
  requête refusée (`psycopg.Error`, avec un cas explicite pour `UniqueViolation`
  et `CheckViolation`) ;
- `try / finally` : les deux connexions sont fermées même après une erreur ou
  un `Ctrl+C`.

---

## 3. Partie 3 — application C#

```bash
cd Remise_Atelier1/csharp
dotnet restore        # récupère Npgsql depuis NuGet
dotnet run
```

Fichiers :

| Fichier | Contenu |
|---|---|
| `Bibliotheque.csproj` | cible `net10.0`, dépendance `Npgsql` |
| `Program.cs` | configuration, connexions, les 4 opérations, menu |

Si `dotnet restore` échoue sur la version du paquet, forcer la dernière :

```bash
dotnet add package Npgsql
```

Points demandés par l'énoncé :

- connexion **aux deux bases** (`NpgsqlConnectionStringBuilder`, qui échappe
  correctement un mot de passe contenant `;` ou `=`) ;
- toutes les valeurs saisies passent par `commande.Parameters.AddWithValue(...)`
  et un paramètre nommé `@motif`, `@titre`, `@id`… ;
- l'ajout d'un livre se fait dans une **transaction** : si l'`INSERT` du livre
  viole `uq_livre_titre_auteur`, le `Rollback` annule aussi l'auteur créé juste
  avant ;
- les erreurs PostgreSQL sont interceptées par `SqlState` :
  `23505` (UNIQUE), `23514` (CHECK), `23503` (clé étrangère), et un cas général ;
- `try / finally` avec `Dispose()` sur les deux connexions.

---

## 4. Ce qui a été vérifié

Toutes les requêtes SQL utilisées par les deux applications ont été exécutées
contre un vrai serveur PostgreSQL (16) sur les deux schémas réels de l'atelier :

- les 2 requêtes relationnelles (jointure + agrégation `FILTER`) retournent des lignes ;
- les 3 requêtes JSONB (`->>` / `#>>`, `@>` sur objet imbriqué, `@>` sur tableau)
  retournent des lignes ;
- `EXPLAIN` confirme que la requête `@>` utilise bien l'index GIN
  (`Bitmap Index Scan on idx_document_donnees_path`) ;
- l'ajout d'un livre en double déclenche bien `SQLSTATE 23505`
  (`uq_livre_titre_auteur`) et un nom d'auteur vide `SQLSTATE 23514`
  (`chk_auteur_nom_non_vide`) — ce sont les deux codes traités dans les apps ;
- `jsonb_set` met bien à jour le titre du document sans réécrire le reste.

Le code C# n'a **pas** pu être compilé pendant la rédaction (pas de SDK .NET
disponible dans l'environnement de travail) : il faut le lancer une fois avec
`dotnet run` avant la remise.

---

## 5. Attention avant de zipper

- `atelier1_bibliotheque_jsonb` (nom réel des scripts) ≠
  `atelier_bibliotheque_jsonb` (nom demandé dans l'énoncé). Uniformiser, ou
  assumer le nom et le documenter.
- Les scripts de création/insertion des parties 1 et 2 contiennent encore le
  **mot de passe en clair** (`CONNEXION = {... "password": ...}`). L'énoncé
  l'interdit explicitement : les faire lire le `.env` comme ici.
- Retirer `.env`, `__pycache__/`, `bin/`, `obj/` et `.DS_Store` de l'archive.
