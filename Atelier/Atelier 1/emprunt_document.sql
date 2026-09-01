-- ============================================================
-- Modèle "emprunt comme racine" : chaque emprunt est un document
-- autonome contenant un instantané (snapshot) du livre (avec son
-- auteur imbriqué) et du membre concernés.
-- ============================================================

-- On réutilise la table document générique déjà créée :
--
-- CREATE TABLE document (
--     id              SERIAL PRIMARY KEY,
--     type_document   VARCHAR(50) NOT NULL,
--     donnees         JSONB NOT NULL
-- );

-- ============================================================
-- Exemples d'insertion : documents de type 'emprunt'
-- ============================================================

INSERT INTO document (type_document, donnees) VALUES
('emprunt', '{
    "livre": {
        "id_livre": 5,
        "titre": "Le Petit Prince",
        "auteur": { "id_auteur": 3, "nom": "Antoine de Saint-Exupéry" }
    },
    "membre": { "id_membre": 12, "nom": "Julie Bouchard" },
    "date_emprunt": "2026-05-01",
    "date_retour": "2026-05-15"
}'),

('emprunt', '{
    "livre": {
        "id_livre": 5,
        "titre": "Le Petit Prince",
        "auteur": { "id_auteur": 3, "nom": "Antoine de Saint-Exupéry" }
    },
    "membre": { "id_membre": 7, "nom": "Marc Gagnon" },
    "date_emprunt": "2026-06-10",
    "date_retour": null
}'),

('emprunt', '{
    "livre": {
        "id_livre": 9,
        "titre": "1984",
        "auteur": { "id_auteur": 8, "nom": "George Orwell" }
    },
    "membre": { "id_membre": 12, "nom": "Julie Bouchard" },
    "date_emprunt": "2026-07-02",
    "date_retour": "2026-07-20"
}');


-- ============================================================
-- Requêtes utiles
-- ============================================================

-- Tous les documents de type 'emprunt'
SELECT * FROM document WHERE type_document = 'emprunt';

-- Le titre du livre et le nom du membre pour chaque emprunt
SELECT
    donnees -> 'livre' ->> 'titre'   AS titre_livre,
    donnees -> 'membre' ->> 'nom'    AS nom_membre,
    donnees ->> 'date_emprunt'       AS date_emprunt
FROM document
WHERE type_document = 'emprunt';

-- Tous les emprunts de Julie Bouchard
SELECT *
FROM document
WHERE type_document = 'emprunt'
  AND donnees -> 'membre' ->> 'nom' = 'Julie Bouchard';

-- Emprunts encore actifs (pas encore retournés)
SELECT *
FROM document
WHERE type_document = 'emprunt'
  AND donnees ->> 'date_retour' IS NULL;

-- Tous les emprunts d'un livre écrit par un auteur donné
SELECT *
FROM document
WHERE type_document = 'emprunt'
  AND donnees -> 'livre' -> 'auteur' ->> 'nom' = 'Antoine de Saint-Exupéry';
