# Dossier `outils/` — hors structure de remise

Ce dossier contient les scripts et fichiers de travail qui ont servi à
construire la remise, mais qui **ne font pas partie** de la structure
exigée par l'énoncé (`sql/`, `csharp/`, `python/`, `README.md`, `IA.md`).

Il peut rester dans l'archive comme trace de démarche, ou en être retiré.

## Configuration

`config_bd.py` — paramètres de connexion partagés par tous les scripts
Python de ce dossier. **Aucun mot de passe n'y est écrit** : les valeurs
sont lues dans les variables d'environnement, ou dans le fichier
`Remise_Atelier1/.env` (copié depuis `.env.example`, jamais remis).

C'est ce module qui a remplacé les dictionnaires `CONNEXION = {... "password": ...}`
qui se trouvaient auparavant en clair dans les quatre scripts ci-dessous.

## Générer `sql/02` et `sql/05`

Les données relationnelles sont produites aléatoirement par Faker : elles
changent à chaque exécution. `exporter_donnees.py` fige l'état actuel des
deux bases dans les deux fichiers de la remise.

```bash
cd Remise_Atelier1/outils
python exporter_donnees.py
```

Il écrit :

- `sql/02_donnees_relationnelles.sql` — les INSERT des 4 tables, dans
  l'ordre des dépendances, avec remise à niveau des séquences ;
- `sql/05_donnees_et_requetes_jsonb.sql` — les INSERT des documents,
  suivis du bloc de requêtes repris de `modele_05_requetes.sql`.

**À relancer** chaque fois que le contenu des bases change (par exemple
après avoir rejoué `script_insertion_donnee_SQL.py`).

Pour modifier les requêtes JSONB de la remise, éditer
`modele_05_requetes.sql` puis relancer l'export — ne pas éditer
`sql/05_...` directement, il serait écrasé.

## Scripts de génération de données

| Fichier | Rôle |
|---|---|
| `creer_bd_relationnelle.py` | crée les 4 tables (équivalent de `sql/01`) |
| `creer_bd_jsonb.py` | crée la table `document`, ses contraintes et ses index (équivalent de `sql/04`) |
| `script_insertion_donnee_SQL.py` | remplit la base relationnelle avec Faker |
| `script_insertion_donnee_JSONB.py` | construit les documents JSONB |
| `exporter_donnees.py` | exporte le contenu des bases vers `sql/02` et `sql/05` |
| `modele_05_requetes.sql` | bloc de requêtes JSONB inséré dans `sql/05` |

## Fichiers de travail conservés pour référence

| Fichier / dossier | Devenu |
|---|---|
| `requetes_Relationnel/` (5 fichiers) | fusionnés dans `sql/03_requetes_relationnelles.sql` |
| `requetes_JSONB/` (4 fichiers) | fusionnés dans `modele_05_requetes.sql` → `sql/05` |
| `demo_index_explain.sql` | intégré à la section 5 de `modele_05_requetes.sql` |
| `document_jsonb.sql` | première version de `sql/04_creation_jsonb.sql` |
| `_creation_des_BD_vide/` | ancien dossier, ne contient plus qu'un `__pycache__` à supprimer |

Ces copies sont redondantes avec les fichiers de `sql/` : elles peuvent
être supprimées sans rien casser.
