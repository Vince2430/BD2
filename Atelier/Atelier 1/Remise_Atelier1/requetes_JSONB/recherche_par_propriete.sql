-- ============================================================
-- Recherche par propriété dans du JSONB : ->, ->>, #>>
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


-- ============================================================
-- -> : retourne du JSONB (garde le type JSON, utile pour
-- continuer à naviguer plus profondément)
-- ============================================================

-- Récupérer l'objet "livre" au complet (encore en JSONB)
SELECT donnees -> 'livre'
FROM document
WHERE type_document = 'emprunt';


-- ============================================================
-- ->> : retourne du TEXTE (utile pour la valeur finale,
-- comparaisons, affichage)
-- ============================================================

-- Le titre du livre pour chaque emprunt (on chaîne -> puis ->>)
SELECT donnees -> 'livre' ->> 'titre' AS titre_livre
FROM document
WHERE type_document = 'emprunt';

-- Filtrer : tous les emprunts du livre "Le Petit Prince"
SELECT *
FROM document
WHERE type_document = 'emprunt'
  AND donnees -> 'livre' ->> 'titre' = 'Le Petit Prince';

-- Filtrer sur une propriété imbriquée plus profondément (l'auteur)
SELECT *
FROM document
WHERE type_document = 'emprunt'
  AND donnees -> 'livre' -> 'auteur' ->> 'nom' = 'Antoine de Saint-Exupéry';

-- Emprunts encore actifs (date_retour absente/null)
SELECT *
FROM document
WHERE type_document = 'emprunt'
  AND donnees ->> 'date_retour' IS NULL;


-- ============================================================
-- #>> : équivalent à chaîner -> plusieurs fois, mais en donnant
-- directement le CHEMIN COMPLET sous forme de tableau de texte.
-- Retourne du texte (comme ->>). Il existe aussi #> (sans les
-- deux chevrons finaux) qui retourne du JSONB, comme ->.
-- ============================================================

-- Équivalent de : donnees -> 'livre' ->> 'titre'
SELECT donnees #>> '{livre,titre}' AS titre_livre
FROM document
WHERE type_document = 'emprunt';

-- Équivalent de : donnees -> 'livre' -> 'auteur' ->> 'nom'
SELECT donnees #>> '{livre,auteur,nom}' AS nom_auteur
FROM document
WHERE type_document = 'emprunt';

-- Même filtre qu'avant, mais écrit avec #>>
SELECT *
FROM document
WHERE type_document = 'emprunt'
  AND donnees #>> '{livre,auteur,nom}' = 'Antoine de Saint-Exupéry';

-- Filtrer par nom de membre, avec #>>
SELECT *
FROM document
WHERE type_document = 'emprunt'
  AND donnees #>> '{membre,nom}' = 'Julie Bouchard';
