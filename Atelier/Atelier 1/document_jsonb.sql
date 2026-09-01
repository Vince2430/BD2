-- ============================================================
-- Table "document" : structure générique pour stocker des
-- documents JSON de différents types (livre, membre, etc.)
-- ============================================================

CREATE TABLE document (
    id              SERIAL PRIMARY KEY,
    type_document   VARCHAR(50) NOT NULL,   -- ex: 'livre', 'membre'
    donnees         JSONB NOT NULL
);

-- Contrainte optionnelle : force "donnees" à être un objet JSON,
-- pas juste un nombre ou une chaîne de texte
ALTER TABLE document
ADD CONSTRAINT donnees_est_objet CHECK (jsonb_typeof(donnees) = 'object');

-- Index GIN : accélère les recherches à l'intérieur de la colonne JSONB
CREATE INDEX idx_document_donnees ON document USING GIN (donnees);

-- Index classique sur type_document, pratique pour filtrer par type
CREATE INDEX idx_document_type ON document (type_document);


-- ============================================================
-- Exemple d'insertion : document de type "livre"
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
-- Quelques requêtes utiles pour tester
-- ============================================================

-- Tous les documents de type "livre"
-- SELECT * FROM document WHERE type_document = 'livre';

-- Le titre de chaque livre
-- SELECT donnees ->> 'titre' AS titre FROM document WHERE type_document = 'livre';

-- Les livres dont l'auteur est "Antoine de Saint-Exupéry"
-- SELECT * FROM document WHERE donnees -> 'auteur' ->> 'nom' = 'Antoine de Saint-Exupéry';
