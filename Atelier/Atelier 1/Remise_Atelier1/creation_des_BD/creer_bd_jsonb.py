"""
Script pour créer la structure de la base JSONB : la table
'document' avec sa contrainte et ses index GIN.

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
# Commandes SQL de création
# ============================================================

CREER_TABLE = """
CREATE TABLE IF NOT EXISTS document (
    id              SERIAL PRIMARY KEY,
    type_document   VARCHAR(50) NOT NULL,
    donnees         JSONB NOT NULL
);
"""

CREER_CONTRAINTE = """
ALTER TABLE document
ADD CONSTRAINT donnees_est_objet CHECK (jsonb_typeof(donnees) = 'object');
"""

CREER_INDEX_DONNEES = """
CREATE INDEX IF NOT EXISTS idx_document_donnees
ON document USING GIN (donnees);
"""

CREER_INDEX_DONNEES_PATH = """
CREATE INDEX IF NOT EXISTS idx_document_donnees_path
ON document USING GIN (donnees jsonb_path_ops);
"""

CREER_INDEX_TYPE = """
CREATE INDEX IF NOT EXISTS idx_document_type
ON document (type_document);
"""


def creer_bd():
    conn = psycopg2.connect(**CONNEXION)
    cur = conn.cursor()

    cur.execute(CREER_TABLE)
    print("Table 'document' créée (ou déjà existante).")

    # La contrainte plante si elle existe déjà -- on l'ignore dans ce cas
    try:
        cur.execute(CREER_CONTRAINTE)
        print("Contrainte 'donnees_est_objet' ajoutée.")
    except psycopg2.errors.DuplicateObject:
        conn.rollback()
        print("Contrainte 'donnees_est_objet' déjà présente, ignorée.")

    cur.execute(CREER_INDEX_DONNEES)
    print("Index GIN 'idx_document_donnees' créé (ou déjà existant).")

    cur.execute(CREER_INDEX_DONNEES_PATH)
    print("Index GIN 'idx_document_donnees_path' créé (ou déjà existant).")

    cur.execute(CREER_INDEX_TYPE)
    print("Index 'idx_document_type' créé (ou déjà existant).")

    conn.commit()
    cur.close()
    conn.close()

    print("Structure de la base JSONB prête.")


if __name__ == "__main__":
    creer_bd()
