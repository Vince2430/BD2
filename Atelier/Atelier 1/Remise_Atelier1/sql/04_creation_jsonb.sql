-- ============================================================
-- 04_creation_jsonb.sql
-- Atelier 1 — Partie 2 : structure de la base documentaire
-- ============================================================
--
-- PRÉALABLE : créer la base (une seule fois), depuis psql ou pgAdmin,
-- en étant connecté à une AUTRE base (par exemple 'postgres') :
--
--     CREATE DATABASE atelier1_bibliotheque_jsonb
--         ENCODING 'UTF8'
--         TEMPLATE template0;
--
-- Puis exécuter ce fichier EN ÉTANT CONNECTÉ à cette base :
--
--     psql -U postgres -d atelier1_bibliotheque_jsonb -f 04_creation_jsonb.sql
--
-- Ce script est ré-exécutable (DROP TABLE en tête).
-- ============================================================
--
-- MODÈLE RETENU : un document est SOIT un livre, SOIT un membre.
--
--   type_document = 'livre'
--   {
--       "titre":  "Le Petit Prince",
--       "auteur": { "id_auteur": 1, "nom": "Antoine de Saint-Exupéry" },
--       "emprunts": [
--           { "id_membre": 12, "nom_membre": "Julie Bouchard",
--             "date_emprunt": "2026-05-01", "date_retour": "2026-05-15" }
--       ]
--   }
--
--   type_document = 'membre'
--   {
--       "nom": "Julie Bouchard",
--       "emprunts_actifs": [
--           { "titre_livre": "Le Petit Prince", "date_emprunt": "2026-05-01" }
--       ]
--   }
--
-- Un premier modèle « un document = un emprunt » a été essayé puis
-- abandonné : un livre jamais emprunté et un auteur sans emprunt
-- n'existaient alors nulle part dans la base. Ici, tous les livres et
-- tous les membres ont leur document, avec un tableau vide au besoin.
-- ============================================================


DROP TABLE IF EXISTS document CASCADE;

CREATE TABLE document (
    id              SERIAL PRIMARY KEY,
    type_document   VARCHAR(50)  NOT NULL,        -- 'livre' ou 'membre'
    donnees         JSONB        NOT NULL,        -- le document lui-même
    cree_le         TIMESTAMP    NOT NULL DEFAULT now()
);


-- ============================================================
-- Contraintes de validation
-- ============================================================

-- 1. La colonne JSONB doit contenir un OBJET, pas un nombre, une
--    chaîne ou un tableau : '"bonjour"'::jsonb et '42'::jsonb sont
--    du JSONB parfaitement valide, mais n'ont aucun sens ici.
ALTER TABLE document
    ADD CONSTRAINT donnees_est_objet
    CHECK (jsonb_typeof(donnees) = 'object');

-- 2. Le type de document est limité aux deux seuls types du modèle.
ALTER TABLE document
    ADD CONSTRAINT type_document_valide
    CHECK (type_document IN ('livre', 'membre'));

-- 3. (PROPOSITION — non activée, à décider par l'étudiant)
--    L'énoncé demande « au moins une contrainte vérifiant une
--    propriété JSON essentielle ». Les deux contraintes ci-dessus
--    valident le TYPE de la colonne et la colonne type_document,
--    mais aucune ne vérifie qu'une propriété NOMMÉE est présente.
--    La contrainte suivante comblerait ce point. L'opérateur ?
--    teste la présence d'une clé dans l'objet JSONB ; c'est
--    l'équivalent documentaire du NOT NULL relationnel, sauf qu'ici
--    c'est à nous de l'écrire — rien n'est imposé par défaut.
--    Vérifiée compatible avec le jeu de données actuel.
--
-- ALTER TABLE document
--     ADD CONSTRAINT donnees_proprietes_essentielles
--     CHECK (
--         (type_document = 'livre'  AND donnees ? 'titre' AND donnees ? 'auteur')
--         OR
--         (type_document = 'membre' AND donnees ? 'nom')
--     );


-- ============================================================
-- Index
-- ============================================================

-- Index GIN par défaut (classe jsonb_ops) : supporte @>, ?, ?& et ?|.
CREATE INDEX idx_document_donnees
    ON document USING GIN (donnees);

-- Index GIN jsonb_path_ops : plus petit et plus rapide, mais ne
-- supporte QUE @>. C'est celui que le planificateur choisit en
-- pratique pour nos recherches par contenance.
CREATE INDEX idx_document_donnees_path
    ON document USING GIN (donnees jsonb_path_ops);

-- Index B-tree classique pour filtrer rapidement par type.
CREATE INDEX idx_document_type
    ON document (type_document);


-- ============================================================
-- Vérification : contraintes et index en place
-- ============================================================

SELECT conname AS contrainte, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'document'::regclass
ORDER BY conname;

SELECT indexname AS index_cree
FROM pg_indexes
WHERE tablename = 'document'
ORDER BY indexname;
