"""
exporter_donnees.py — génère les deux fichiers de données de la remise
à partir du CONTENU RÉEL de tes deux bases :

    ../sql/02_donnees_relationnelles.sql
    ../sql/05_donnees_et_requetes_jsonb.sql

Pourquoi un script plutôt que des INSERT écrits à la main : les données
relationnelles sont générées aléatoirement par Faker, donc elles
changent à chaque exécution de script_insertion_donnee_SQL.py. Ce
script fige l'état actuel des bases dans des fichiers SQL rejouables.

Le fichier 05 est composé de deux morceaux :
    1. les INSERT des documents, extraits de la base ;
    2. le bloc de requêtes JSONB, repris tel quel de
       modele_05_requetes.sql (à côté de ce script).

Aucun mot de passe ici : la connexion passe par config_bd (.env).

Usage :
    cd Remise_Atelier1/outils
    python exporter_donnees.py
"""

import json
import sys
from datetime import date, datetime
from pathlib import Path

import config_bd

# ------------------------------------------------------------
# Le pilote : psycopg2 (utilisé par les autres scripts) ou
# psycopg 3 (utilisé par l'application de la partie 4).
# ------------------------------------------------------------
try:
    import psycopg2 as pilote

    VERSION_PILOTE = 2
except ImportError:
    try:
        import psycopg as pilote

        VERSION_PILOTE = 3
    except ImportError:
        sys.exit(
            "Aucun pilote PostgreSQL trouve.\n"
            "Installe l'un des deux :\n"
            "    pip install psycopg2-binary\n"
            "    pip install 'psycopg[binary]'"
        )


DOSSIER = Path(__file__).resolve().parent
DOSSIER_SQL = DOSSIER.parent / "sql"
MODELE_REQUETES = DOSSIER / "modele_05_requetes.sql"

LIGNES_PAR_INSERT = 50   # nombre de tuples par instruction INSERT


# ============================================================
# Échappement des valeurs
# ============================================================
# On n'écrit JAMAIS les valeurs à la main dans le SQL : on demande au
# pilote de les échapper, exactement comme il le ferait pour une
# requête paramétrée. C'est la même règle que dans les applications.

def fabriquer_echappeur(conn):
    """Retourne une fonction (valeurs, gabarit) -> '(v1, v2, ...)'.

    mogrify() applique exactement le même échappement que pour une
    requête paramétrée, puis nous rend le texte SQL obtenu.
    """
    if VERSION_PILOTE == 2:
        curseur = conn.cursor()

        def echapper(valeurs, gabarit):
            return curseur.mogrify(gabarit, valeurs).decode("utf-8")

    else:  # psycopg 3
        curseur = pilote.ClientCursor(conn)

        def echapper(valeurs, gabarit):
            return curseur.mogrify(gabarit, valeurs)

    return echapper


def bloc_insert(nom_table, colonnes, lignes, echapper, casts=None):
    """Construit une suite d'INSERT ... VALUES (...), (...);

    `casts` permet de forcer un type sur certaines colonnes,
    par exemple ['', '', '::jsonb'].
    """
    if not lignes:
        return f"-- (aucune ligne dans {nom_table})\n\n"

    if casts is None:
        casts = [""] * len(colonnes)
    gabarit = "(" + ", ".join(f"%s{c}" for c in casts) + ")"

    morceaux = []
    entete = f"INSERT INTO {nom_table} ({', '.join(colonnes)}) VALUES\n"

    for depart in range(0, len(lignes), LIGNES_PAR_INSERT):
        paquet = lignes[depart:depart + LIGNES_PAR_INSERT]
        valeurs = [echapper(ligne, gabarit) for ligne in paquet]
        morceaux.append(entete + ",\n".join(valeurs) + ";\n")

    return "\n".join(morceaux) + "\n"


def normaliser(valeur):
    """date/datetime -> str ISO ; le reste inchangé."""
    if isinstance(valeur, (date, datetime)):
        return valeur.isoformat()
    return valeur


# ============================================================
# 02 — données relationnelles
# ============================================================

def exporter_relationnel():
    conn = pilote.connect(**config_bd.PARAMS_SQL)
    try:
        echapper = fabriquer_echappeur(conn)
        cur = conn.cursor()

        def lire(requete):
            cur.execute(requete)
            return [tuple(normaliser(v) for v in ligne) for ligne in cur.fetchall()]

        auteurs = lire("SELECT id_auteur, nom FROM auteur ORDER BY id_auteur;")
        membres = lire("SELECT id_membre, nom FROM membre ORDER BY id_membre;")
        livres = lire("SELECT id_livre, nom, id_auteur FROM livre ORDER BY id_livre;")
        emprunts = lire(
            "SELECT id_emprunt, id_livre, id_membre, date_emprunt, date_retour "
            "FROM emprunt ORDER BY id_emprunt;"
        )
    finally:
        conn.close()

    texte = f"""-- ============================================================
-- 02_donnees_relationnelles.sql
-- Atelier 1 — Partie 1, point 4 : jeu de données
-- ============================================================
--
-- Fichier GÉNÉRÉ par outils/exporter_donnees.py à partir du contenu
-- réel de la base. Les noms d'auteurs, de livres et de membres ont
-- été produits par Faker (voir outils/script_insertion_donnee_SQL.py) ;
-- ce fichier les fige pour que la remise soit reproductible.
--
-- À exécuter APRÈS 01_creation_relationnelle.sql :
--
--     psql -U postgres -d atelier_bibliotheque_sql -f 02_donnees_relationnelles.sql
--
-- Volumes (minimums exigés par l'énoncé entre parenthèses) :
--     {len(auteurs):>4} auteurs   (5)
--     {len(livres):>4} livres    (10)
--     {len(membres):>4} membres   (5)
--     {len(emprunts):>4} emprunts  (8), dont certains actifs et d'autres terminés
-- ============================================================


-- Repartir d'une base vide, sans supprimer les tables :
-- RESTART IDENTITY remet les séquences à 1, CASCADE vide aussi
-- les tables qui dépendent de celles-ci.
TRUNCATE emprunt, livre, membre, auteur RESTART IDENTITY CASCADE;


-- ============================================================
-- auteur
-- ============================================================

{bloc_insert("auteur", ["id_auteur", "nom"], auteurs, echapper)}
-- ============================================================
-- membre
-- ============================================================

{bloc_insert("membre", ["id_membre", "nom"], membres, echapper)}
-- ============================================================
-- livre  (référence auteur)
-- ============================================================

{bloc_insert("livre", ["id_livre", "nom", "id_auteur"], livres, echapper)}
-- ============================================================
-- emprunt  (référence livre et membre)
-- date_retour NULL = emprunt encore actif
-- ============================================================

{bloc_insert("emprunt", ["id_emprunt", "id_livre", "id_membre", "date_emprunt", "date_retour"], emprunts, echapper)}
-- ============================================================
-- Remise à niveau des séquences
-- ============================================================
-- Les id ont été insérés explicitement : sans cela, le prochain
-- INSERT sans id repartirait de 1 et violerait la clé primaire.

SELECT setval(pg_get_serial_sequence('auteur',  'id_auteur'),  COALESCE((SELECT MAX(id_auteur)  FROM auteur),  1));
SELECT setval(pg_get_serial_sequence('membre',  'id_membre'),  COALESCE((SELECT MAX(id_membre)  FROM membre),  1));
SELECT setval(pg_get_serial_sequence('livre',   'id_livre'),   COALESCE((SELECT MAX(id_livre)   FROM livre),   1));
SELECT setval(pg_get_serial_sequence('emprunt', 'id_emprunt'), COALESCE((SELECT MAX(id_emprunt) FROM emprunt), 1));


-- ============================================================
-- Vérification
-- ============================================================

SELECT 'auteur' AS table_, count(*) FROM auteur
UNION ALL SELECT 'livre',   count(*) FROM livre
UNION ALL SELECT 'membre',  count(*) FROM membre
UNION ALL SELECT 'emprunt', count(*) FROM emprunt
UNION ALL SELECT 'emprunts actifs', count(*) FROM emprunt WHERE date_retour IS NULL;
"""

    chemin = DOSSIER_SQL / "02_donnees_relationnelles.sql"
    chemin.write_text(texte, encoding="utf-8")
    print(f"  {chemin.name} : {len(auteurs)} auteurs, {len(livres)} livres, "
          f"{len(membres)} membres, {len(emprunts)} emprunts")
    return chemin


# ============================================================
# 05 — données JSONB + requêtes
# ============================================================

def exporter_jsonb():
    conn = pilote.connect(**config_bd.PARAMS_JSONB)
    try:
        echapper = fabriquer_echappeur(conn)
        cur = conn.cursor()
        cur.execute(
            "SELECT id, type_document, donnees FROM document ORDER BY id;"
        )
        documents = [
            (id_, type_doc, json.dumps(donnees, ensure_ascii=False))
            for id_, type_doc, donnees in cur.fetchall()
        ]
    finally:
        conn.close()

    nb_livres = sum(1 for d in documents if d[1] == "livre")
    nb_membres = sum(1 for d in documents if d[1] == "membre")

    if not MODELE_REQUETES.is_file():
        sys.exit(f"Fichier introuvable : {MODELE_REQUETES}")
    requetes = MODELE_REQUETES.read_text(encoding="utf-8")

    # ::jsonb : le document est passé comme du TEXTE échappé par le
    # pilote, puis converti côté serveur. Aucun JSON collé à la main.
    inserts = bloc_insert(
        "document",
        ["id", "type_document", "donnees"],
        documents,
        echapper,
        casts=["", "", "::jsonb"],
    )

    texte = f"""-- ============================================================
-- 05_donnees_et_requetes_jsonb.sql
-- Atelier 1 — Partie 2 : données documentaires + requêtes JSONB
-- ============================================================
--
-- La première moitié (les INSERT) est GÉNÉRÉE par
-- outils/exporter_donnees.py à partir du contenu réel de la base.
-- La seconde moitié (les requêtes) vient de outils/modele_05_requetes.sql.
--
-- À exécuter APRÈS 04_creation_jsonb.sql :
--
--     psql -U postgres -d atelier1_bibliotheque_jsonb -f 05_donnees_et_requetes_jsonb.sql
--
-- Contenu : {nb_livres} documents 'livre' et {nb_membres} documents 'membre'.
-- Chaque document contient au moins un objet imbriqué (auteur) ou un
-- tableau (emprunts / emprunts_actifs), conformément à l'énoncé.
-- ============================================================


TRUNCATE document RESTART IDENTITY;


-- ############################################################
-- DONNÉES
-- ############################################################

{inserts}
SELECT setval(pg_get_serial_sequence('document', 'id'),
              COALESCE((SELECT MAX(id) FROM document), 1));


-- Vérification du chargement
SELECT type_document, count(*) AS nb_documents
FROM document
GROUP BY type_document
ORDER BY type_document;

{requetes}"""

    chemin = DOSSIER_SQL / "05_donnees_et_requetes_jsonb.sql"
    chemin.write_text(texte, encoding="utf-8")
    print(f"  {chemin.name} : {nb_livres} documents 'livre', "
          f"{nb_membres} documents 'membre'")
    return chemin


# ============================================================

def main() -> int:
    print(config_bd.source())
    DOSSIER_SQL.mkdir(exist_ok=True)

    try:
        exporter_relationnel()
        exporter_jsonb()
    except pilote.OperationalError as erreur:
        print("\nERREUR DE CONNEXION a PostgreSQL.")
        print("Verifie que le serveur est demarre et les variables")
        print("PGHOST / PGPORT / PGUSER / PGPASSWORD / PGDATABASE_*.")
        print(f"Detail : {str(erreur).strip()}")
        return 1
    except pilote.Error as erreur:
        print(f"\nERREUR SQL : {str(erreur).strip()}")
        return 1

    print("\nFichiers 02 et 05 regeneres dans sql/.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
