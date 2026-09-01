"""
Script pour créer la base relationnelle (auteur, livre, membre, emprunt)
à partir de ton schéma SQL original.

Installation requise :
    pip install psycopg2-binary
"""

import psycopg2

# ============================================================
# Paramètres de connexion — à adapter selon ta base
# ============================================================
CONNEXION = {
    "host": "localhost",
    "dbname": "atelier1_bibliotheque_jsonb",
    "user": "postgres",
    "password": "Gu3pard1",
    "port": 5432,
}

# ============================================================
# Commandes SQL de création (dans l'ordre à cause des clés étrangères :
# auteur et membre d'abord, puis livre, puis emprunt)
# ============================================================

CREER_AUTEUR = """
CREATE TABLE IF NOT EXISTS auteur (
    id_auteur   SERIAL PRIMARY KEY,
    nom         VARCHAR(100) NOT NULL DEFAULT 'anonyme'  -- un auteur ne peut pas exister sans avoir de nom
);
"""

CREER_LIVRE = """
CREATE TABLE IF NOT EXISTS livre (
    id_livre    SERIAL PRIMARY KEY,
    nom         VARCHAR(150) NOT NULL,   -- titre du livre
    id_auteur   INTEGER NOT NULL,        -- un livre doit obligatoirement avoir un auteur
    CONSTRAINT fk_livre_auteur
        FOREIGN KEY (id_auteur)
        REFERENCES auteur (id_auteur)
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
        REFERENCES membre (id_membre)
);
"""


def creer_bd_relationnelle():
    conn = psycopg2.connect(**CONNEXION)
    cur = conn.cursor()

    cur.execute(CREER_AUTEUR)
    print("Table 'auteur' créée (ou déjà existante).")

    cur.execute(CREER_MEMBRE)
    print("Table 'membre' créée (ou déjà existante).")

    cur.execute(CREER_LIVRE)
    print("Table 'livre' créée (ou déjà existante).")

    cur.execute(CREER_EMPRUNT)
    print("Table 'emprunt' créée (ou déjà existante).")

    conn.commit()
    cur.close()
    conn.close()

    print("Base relationnelle prête.")


if __name__ == "__main__":
    creer_bd_relationnelle()
