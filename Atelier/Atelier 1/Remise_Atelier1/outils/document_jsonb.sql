-- ============================================================
-- Table "document" : structure générique pour stocker des
-- documents JSON de la bibliothèque.
--
-- Chaque document est SOIT un "livre" SOIT un "membre" :
--   - un "livre" contient son auteur imbriqué et le tableau de
--     ses emprunts (vide si le livre n'a jamais été emprunté) ;
--   - un "membre" contient son tableau d'emprunts actifs (vide
--     si le membre n'a rien emprunté en ce moment).
--
-- Contrairement à la version précédente, TOUS les livres et
-- TOUS les membres doivent avoir leur propre document, même
-- ceux qui n'ont aucun emprunt. On ne stocke plus des
-- documents de type "emprunt" séparés : l'emprunt vit
-- uniquement à l'intérieur du livre/membre concerné.
-- ============================================================

-- Supprime la table si elle existe déjà, pour pouvoir relancer
-- ce script proprement (utile en développement)
DROP TABLE IF EXISTS document CASCADE;

CREATE TABLE document (
    id              SERIAL PRIMARY KEY,
    type_document   VARCHAR(50) NOT NULL,   -- 'livre' ou 'membre' uniquement
    donnees         JSONB NOT NULL,
    cree_le         TIMESTAMP NOT NULL DEFAULT now()   -- date/heure de création du document (champ oublié)
);

-- Contrainte : force "donnees" à être un objet JSON,
-- pas juste un nombre ou une chaîne de texte
ALTER TABLE document
ADD CONSTRAINT donnees_est_objet CHECK (jsonb_typeof(donnees) = 'object');

-- Contrainte : un document ne peut être qu'un "livre" ou un "membre"
ALTER TABLE document
ADD CONSTRAINT type_document_valide CHECK (type_document IN ('livre', 'membre'));

-- Index GIN : accélère les recherches à l'intérieur de la colonne JSONB
CREATE INDEX idx_document_donnees ON document USING GIN (donnees);

-- Index classique sur type_document, pratique pour filtrer par type
CREATE INDEX idx_document_type ON document (type_document);


-- ============================================================
-- Exemple d'insertion : document de type "livre", déjà emprunté
-- (auteur en objet imbriqué, emprunts en tableau)
-- ============================================================

INSERT INTO document (type_document, donnees) VALUES
('livre', '{
    "titre": "Le Petit Prince",
    "auteur": {
        "id_auteur": 3,
        "nom": "Antoine de Saint-Exupéry"
    },
    "emprunts": [
        {
            "id_membre": 12,
            "nom_membre": "Julie Bouchard",
            "date_emprunt": "2026-05-01",
            "date_retour": "2026-05-15"
        },
        {
            "id_membre": 7,
            "nom_membre": "Marc Gagnon",
            "date_emprunt": "2026-06-10",
            "date_retour": null
        }
    ]
}');


-- ============================================================
-- Exemple d'insertion : document de type "livre", JAMAIS emprunté
-- (le livre existe quand même comme document, avec un tableau
-- "emprunts" vide -- c'est ce qui manquait avant)
-- ============================================================

INSERT INTO document (type_document, donnees) VALUES
('livre', '{
    "titre": "Fahrenheit 451",
    "auteur": {
        "id_auteur": 14,
        "nom": "Ray Bradbury"
    },
    "emprunts": []
}');


-- ============================================================
-- Exemple d'insertion : document de type "membre"
-- (emprunts actifs en tableau)
-- ============================================================

INSERT INTO document (type_document, donnees) VALUES
('membre', '{
    "nom": "Julie Bouchard",
    "emprunts_actifs": [
        {
            "titre_livre": "Le Petit Prince",
            "date_emprunt": "2026-05-01"
        }
    ]
}');


-- ============================================================
-- Exemple d'insertion : document de type "membre" sans emprunt actif
-- ============================================================

INSERT INTO document (type_document, donnees) VALUES
('membre', '{
    "nom": "Marc Gagnon",
    "emprunts_actifs": []
}');


-- ============================================================
-- Quelques requêtes utiles pour tester
-- ============================================================

-- Tous les documents de type "livre"
-- SELECT * FROM document WHERE type_document = 'livre';

-- Le titre de chaque livre
-- SELECT donnees ->> 'titre' AS titre FROM document WHERE type_document = 'livre';

-- Les livres dont l'auteur est "Antoine de Saint-Exupéry"
-- SELECT * FROM document WHERE donnees -> 'auteur' ->> 'nom' = 'Antoine de Saint-Exupéry';

-- Les livres jamais empruntés (tableau "emprunts" vide)
-- SELECT donnees ->> 'titre' FROM document WHERE type_document = 'livre' AND jsonb_array_length(donnees -> 'emprunts') = 0;

-- Les documents créés le plus récemment
-- SELECT * FROM document ORDER BY cree_le DESC;
