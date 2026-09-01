-- ============================================================
-- Recherche dans un tableau JSON (JSONB)
-- ============================================================
--
-- On réutilise ici le modèle "livre comme racine", où le
-- tableau "emprunts" contient plusieurs objets imbriqués :
--
-- {
--     "titre": "Le Petit Prince",
--     "auteur": { "id_auteur": 3, "nom": "Antoine de Saint-Exupéry" },
--     "emprunts": [
--         { "id_membre": 12, "nom_membre": "Julie Bouchard", "date_emprunt": "2026-05-01", "date_retour": "2026-05-15" },
--         { "id_membre": 7,  "nom_membre": "Marc Gagnon",    "date_emprunt": "2026-06-10", "date_retour": null }
--     ]
-- }

-- Au cas où tu ne l'as pas déjà en base, exemple d'insertion :
INSERT INTO document (type_document, donnees) VALUES
('livre', '{
    "titre": "Le Petit Prince",
    "auteur": {"id_auteur": 3, "nom": "Antoine de Saint-Exupéry"},
    "emprunts": [
        {"id_membre": 12, "nom_membre": "Julie Bouchard", "date_emprunt": "2026-05-01", "date_retour": "2026-05-15"},
        {"id_membre": 7,  "nom_membre": "Marc Gagnon",    "date_emprunt": "2026-06-10", "date_retour": null}
    ]
}');


-- ============================================================
-- 1. jsonb_array_elements() : "dérouler" le tableau en lignes
-- ============================================================
-- Chaque élément du tableau devient une ligne séparée, ce qui
-- permet de le traiter comme une vraie table pour filtrer/joindre.

SELECT
    donnees ->> 'titre'              AS titre_livre,
    emprunt_element ->> 'nom_membre' AS nom_membre,
    emprunt_element ->> 'date_emprunt' AS date_emprunt
FROM document,
     jsonb_array_elements(donnees -> 'emprunts') AS emprunt_element
WHERE type_document = 'livre';


-- ============================================================
-- 2. Filtrer sur une propriété à l'intérieur des éléments du tableau
-- ============================================================
-- Trouver tous les livres empruntés par "Julie Bouchard"

SELECT DISTINCT donnees ->> 'titre' AS titre_livre
FROM document,
     jsonb_array_elements(donnees -> 'emprunts') AS emprunt_element
WHERE type_document = 'livre'
  AND emprunt_element ->> 'nom_membre' = 'Julie Bouchard';


-- ============================================================
-- 3. EXISTS : même résultat, mais sans dérouler tout le tableau
-- ni risquer de dupliquer les lignes de "document"
-- ============================================================

SELECT donnees ->> 'titre' AS titre_livre
FROM document
WHERE type_document = 'livre'
  AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(donnees -> 'emprunts') AS e
      WHERE e ->> 'nom_membre' = 'Julie Bouchard'
  );


-- ============================================================
-- 4. @> sur un tableau : contenance directe, si tu connais
-- la sous-structure exacte que tu cherches
-- ============================================================

SELECT *
FROM document
WHERE type_document = 'livre'
  AND donnees -> 'emprunts' @> '[{"nom_membre": "Julie Bouchard"}]';


-- ============================================================
-- 5. jsonb_array_length() : compter les éléments du tableau
-- ============================================================
-- Combien de fois chaque livre a été emprunté

SELECT
    donnees ->> 'titre' AS titre_livre,
    jsonb_array_length(donnees -> 'emprunts') AS nb_emprunts
FROM document
WHERE type_document = 'livre';
