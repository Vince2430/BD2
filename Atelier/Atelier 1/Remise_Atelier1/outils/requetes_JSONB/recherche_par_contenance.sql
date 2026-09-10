-- ============================================================
-- Recherche par contenance dans du JSONB : @>
-- ============================================================
--
-- Rappel de la structure des documents (modèle "livre ou membre") :
--
-- type_document = 'livre' :
-- {
--     "titre": "Le Petit Prince",
--     "auteur": { "id_auteur": 3, "nom": "Antoine de Saint-Exupéry" },
--     "emprunts": [ { "id_membre": 12, "nom_membre": "Julie Bouchard", ... } ]
-- }
--
-- type_document = 'membre' :
-- {
--     "nom": "Julie Bouchard",
--     "emprunts_actifs": [ { "titre_livre": "Le Petit Prince", "date_emprunt": "2026-05-01" } ]
-- }
--
-- @> se lit : "le JSONB de gauche CONTIENT le JSONB de droite".
-- Le document peut avoir d'autres clés en plus de celles données
-- à droite -- on donne juste le petit "gabarit" qui doit matcher
-- quelque part dans le document.


-- ============================================================
-- Contenance simple (propriété au premier niveau)
-- ============================================================

-- Le livre "Le Petit Prince"
SELECT *
FROM document
WHERE type_document = 'livre'
  AND donnees @> '{"titre": "Le Petit Prince"}';

-- Le membre "Julie Bouchard"
SELECT *
FROM document
WHERE type_document = 'membre'
  AND donnees @> '{"nom": "Julie Bouchard"}';


-- ============================================================
-- Contenance sur une propriété imbriquée à un niveau
-- ============================================================

-- Les livres écrits par "Antoine de Saint-Exupéry"
SELECT *
FROM document
WHERE type_document = 'livre'
  AND donnees @> '{"auteur": {"nom": "Antoine de Saint-Exupéry"}}';


-- ============================================================
-- Contenance sur un élément de tableau
-- ============================================================
-- @> fonctionne aussi à l'intérieur d'un tableau : il suffit que
-- l'un des éléments du tableau contienne le gabarit donné.

-- Les membres qui ont un emprunt actif pour "Le Petit Prince"
SELECT donnees ->> 'nom' AS nom_membre
FROM document
WHERE type_document = 'membre'
  AND donnees @> '{"emprunts_actifs": [{"titre_livre": "Le Petit Prince"}]}';

-- Les livres actuellement empruntés par "Marc Gagnon" (emprunt sans date_retour)
SELECT donnees ->> 'titre' AS titre
FROM document
WHERE type_document = 'livre'
  AND donnees @> '{"emprunts": [{"nom_membre": "Marc Gagnon", "date_retour": null}]}';


-- ============================================================
-- Contenance combinée : plusieurs critères en même temps
-- ============================================================

-- Livre avec ce titre ET écrit par cet auteur
SELECT *
FROM document
WHERE type_document = 'livre'
  AND donnees @> '{
      "titre": "Le Petit Prince",
      "auteur": {"nom": "Antoine de Saint-Exupéry"}
  }';


-- ============================================================
-- Vérifier que l'index GIN est bien utilisé
-- ============================================================

EXPLAIN ANALYZE
SELECT *
FROM document
WHERE donnees @> '{"auteur": {"nom": "Antoine de Saint-Exupéry"}}';

-- On devrait voir "Bitmap Index Scan" sur idx_document_donnees
-- dans le plan d'exécution, plutôt qu'un "Seq Scan" -- à condition
-- d'avoir assez de documents en base (voir demo_index_explain.sql).
