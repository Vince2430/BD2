"""
Script pour créer la base relationnelle (auteur, livre, membre, emprunt)
à partir de ton schéma SQL original.

Respecte les exigences de l'atelier : clés primaires/étrangères, et au
moins une contrainte de chaque type (NOT NULL, UNIQUE, CHECK, valeur
par défaut).

Installation requise :
    pip install psycopg2-binary
"""

import psycopg2

# ============================================================
# Paramètres de connexion
# ============================================================
# Aucun mot de passe dans ce fichier : les valeurs viennent des
# variables d'environnement ou de Remise_Atelier1/.env
# (voir config_bd.py et .env.example).
import config_bd

CONNEXION = config_bd.PARAMS_SQL

# ============================================================
# Suppression (pour pouvoir relancer le script à partir d'une
# base vide -- CASCADE supprime aussi les contraintes/index
# dépendants sans erreur). Ordre inverse des dépendances.
# ============================================================

SUPPRIMER_TABLES = """
DROP TABLE IF EXISTS emprunt CASCADE;
DROP TABLE IF EXISTS livre CASCADE;
DROP TABLE IF EXISTS membre CASCADE;
DROP TABLE IF EXISTS auteur CASCADE;
"""

# ============================================================
# Commandes SQL de création (dans l'ordre à cause des clés étrangères :
# auteur et membre d'abord, puis livre, puis emprunt)
# ============================================================

CREER_AUTEUR = """
CREATE TABLE IF NOT EXISTS auteur (
    id_auteur   SERIAL PRIMARY KEY,
    nom         VARCHAR(100) NOT NULL DEFAULT 'anonyme',  -- un auteur ne peut pas exister sans avoir de nom
    CONSTRAINT chk_auteur_nom_non_vide CHECK (btrim(nom) <> '')  -- NOT NULL n'empêche pas une chaîne vide, ce CHECK le fait
);
"""

CREER_LIVRE = """
CREATE TABLE IF NOT EXISTS livre (
    id_livre    SERIAL PRIMARY KEY,
    nom         VARCHAR(150) NOT NULL,   -- titre du livre
    id_auteur   INTEGER NOT NULL,        -- un livre doit obligatoirement avoir un auteur
    CONSTRAINT fk_livre_auteur
        FOREIGN KEY (id_auteur)
        REFERENCES auteur (id_auteur),
    CONSTRAINT uq_livre_titre_auteur
        UNIQUE (nom, id_auteur)  -- empêche d'insérer deux fois le même titre pour le même auteur
);
"""

CREER_MEMBRE = """
CREATE TABLE IF NOT EXISTS membre (
    id_membre   SERIAL PRIMARY KEY,
    nom         VARCHAR(100) NOT NULL  -- un membre doit obligatoirement avoir un nom pour exister
);
"""

CREER_EMPRUNT = """
CREATE TABLE IF NOT EXISTS emprunt (
    id_emprunt      SERIAL PRIMARY KEY,
    id_livre        INTEGER NOT NULL,   -- un emprunt ne peut pas exister sans livre
    id_membre       INTEGER NOT NULL,   -- un emprunt ne peut pas exister sans membre
    date_emprunt    DATE NOT NULL DEFAULT CURRENT_DATE,
    date_retour     DATE,
    CONSTRAINT fk_emprunt_livre
        FOREIGN KEY (id_livre)
        REFERENCES livre (id_livre),
    CONSTRAINT fk_emprunt_membre
        FOREIGN KEY (id_membre)
        REFERENCES membre (id_membre),
    CONSTRAINT chk_emprunt_dates
        CHECK (date_retour IS NULL OR date_retour >= date_emprunt)  -- un retour ne peut pas précéder l'emprunt
);
"""


def creer_bd_relationnelle():
    conn = psycopg2.connect(**CONNEXION)
    cur = conn.cursor()

    cur.execute(SUPPRIMER_TABLES)
    print("Tables existantes supprimées (si elles existaient).")

    cur.execute(CREER_AUTEUR)
    print("Table 'auteur' créée.")

    cur.execute(CREER_MEMBRE)
    print("Table 'membre' créée.")

    cur.execute(CREER_LIVRE)
    print("Table 'livre' créée.")

    cur.execute(CREER_EMPRUNT)
    print("Table 'emprunt' créée.")

    conn.commit()
    cur.close()
    conn.close()

    print("Base relationnelle prête.")


if __name__ == "__main__":
    creer_bd_relationnelle()
