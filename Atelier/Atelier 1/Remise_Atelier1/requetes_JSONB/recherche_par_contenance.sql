-- ============================================================
-- Recherche par contenance dans du JSONB : @>
-- ============================================================
--
-- Rappel de la structure d'un document 'emprunt' :
--
-- {
--     "livre": {
--         "id_livre": 5,
--         "titre": "Le Petit Prince",
--         "auteur": { "id_auteur": 3, "nom": "Antoine de Saint-Exupéry" }
--     },
--     "membre": { "id_membre": 12, "nom": "Julie Bouchard" },
--     "date_emprunt": "2026-05-01",
--     "date_retour": "2026-05-15"
-- }
--
-- @> se lit : "le JSONB de gauche CONTIENT le JSONB de droite".
-- Le document peut avoir d'autres clés en plus de celles données
-- à droite -- on donne juste le petit "gabarit" qui doit matcher
-- quelque part dans le document.


-- ============================================================
-- Contenance simple (propriété au premier niveau)
-- ============================================================

-- Tous les emprunts encore actifs (date_retour est null)
SELECT *
FROM document
WHERE donnees @> '{"date_retour": null}';

-- Tous les documents de type 'emprunt' (contenance sur type_document
-- si ce champ était stocké dans le JSONB plutôt qu'en colonne à part)
-- SELECT * FROM document WHERE donnees @> '{"type_document": "emprunt"}';


-- ============================================================
-- Contenance sur une propriété imbriquée à un niveau
-- ============================================================

-- Recherche par titre de livre
SELECT *
FROM document
WHERE donnees @> '{"livre": {"titre": "Le Petit Prince"}}';

-- Recherche par nom de membre
SELECT *
FROM document
WHERE donnees @> '{"membre": {"nom": "Julie Bouchard"}}';


-- ============================================================
-- Contenance sur une propriété imbriquée à deux niveaux
-- ============================================================

-- Recherche par nom d'auteur (imbriqué dans livre)
SELECT *
FROM document
WHERE donnees @> '{"livre": {"auteur": {"nom": "Antoine de Saint-Exupéry"}}}';


-- ============================================================
-- Contenance combinée : plusieurs critères en même temps
-- ============================================================

-- Livre ET membre en même temps
SELECT *
FROM document
WHERE donnees @> '{
    "livre": {"titre": "Le Petit Prince"},
    "membre": {"nom": "Julie Bouchard"}
}';


-- ============================================================
-- Vérifier que l'index GIN est bien utilisé
-- ============================================================

EXPLAIN ANALYZE
SELECT *
FROM document
WHERE donnees @> '{"membre": {"nom": "Julie Bouchard"}}';

-- On devrait voir "Bitmap Index Scan" sur idx_document_donnees
-- dans le plan d'exécution, plutôt qu'un "Seq Scan".
