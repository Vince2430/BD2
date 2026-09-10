"""
Script pour créer la structure de la base JSONB : la table
'document' avec ses contraintes et ses index GIN.

Chaque document est SOIT un "livre" SOIT un "membre" (contrainte
type_document_valide) :
    - un "livre" : auteur imbriqué + tableau "emprunts" (vide si
      le livre n'a jamais été emprunté) ;
    - un "membre" : tableau "emprunts_actifs" (vide si le membre
      n'a rien emprunté en ce moment).

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

CONNEXION = config_bd.PARAMS_JSONB

# ============================================================
# Commandes SQL de création
# ============================================================

SUPPRIMER_TABLE = """
DROP TABLE IF EXISTS document CASCADE;
"""

CREER_TABLE = """
CREATE TABLE IF NOT EXISTS document (
    id              SERIAL PRIMARY KEY,
    type_document   VARCHAR(50) NOT NULL,
    donnees         JSONB NOT NULL,
    cree_le         TIMESTAMP NOT NULL DEFAULT now()
);
"""

CREER_CONTRAINTE = """
ALTER TABLE document
ADD CONSTRAINT donnees_est_objet CHECK (jsonb_typeof(donnees) = 'object');
"""

CREER_CONTRAINTE_TYPE = """
ALTER TABLE document
ADD CONSTRAINT type_document_valide CHECK (type_document IN ('livre', 'membre'));
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

    cur.execute(SUPPRIMER_TABLE)
    print("Table 'document' supprimée si elle existait.")

    cur.execute(CREER_TABLE)
    print("Table 'document' créée (ou déjà existante).")

    # Les contraintes plantent si elles existent déjà -- on les ignore dans ce cas
    try:
        cur.execute(CREER_CONTRAINTE)
        print("Contrainte 'donnees_est_objet' ajoutée.")
    except psycopg2.errors.DuplicateObject:
        conn.rollback()
        print("Contrainte 'donnees_est_objet' déjà présente, ignorée.")

    try:
        cur.execute(CREER_CONTRAINTE_TYPE)
        print("Contrainte 'type_document_valide' ajoutée.")
    except psycopg2.errors.DuplicateObject:
        conn.rollback()
        print("Contrainte 'type_document_valide' déjà présente, ignorée.")

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
