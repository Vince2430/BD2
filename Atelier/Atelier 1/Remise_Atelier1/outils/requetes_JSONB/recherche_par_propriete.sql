-- ============================================================
-- Recherche par propriété dans du JSONB : ->, ->>, #>>
-- ============================================================
--
-- Rappel de la structure des documents (modèle "livre ou membre") :
--
-- type_document = 'livre' :
-- {
--     "titre": "Le Petit Prince",
--     "auteur": { "id_auteur": 3, "nom": "Antoine de Saint-Exupéry" },
--     "emprunts": [
--         { "id_membre": 12, "nom_membre": "Julie Bouchard", "date_emprunt": "2026-05-01", "date_retour": "2026-05-15" },
--         { "id_membre": 7,  "nom_membre": "Marc Gagnon",    "date_emprunt": "2026-06-10", "date_retour": null }
--     ]
-- }
--
-- type_document = 'membre' :
-- {
--     "nom": "Julie Bouchard",
--     "emprunts_actifs": [
--         { "titre_livre": "Le Petit Prince", "date_emprunt": "2026-05-01" }
--     ]
-- }


-- ============================================================
-- -> : retourne du JSONB (garde le type JSON, utile pour
-- continuer à naviguer plus profondément)
-- ============================================================

-- Récupérer l'objet "auteur" au complet (encore en JSONB) de chaque livre
SELECT donnees -> 'auteur'
FROM document
WHERE type_document = 'livre';

-- Récupérer le tableau "emprunts_actifs" au complet de chaque membre
SELECT donnees -> 'emprunts_actifs'
FROM document
WHERE type_document = 'membre';


-- ============================================================
-- ->> : retourne du TEXTE (utile pour la valeur finale,
-- comparaisons, affichage)
-- ============================================================

-- Le nom de l'auteur pour chaque livre (on chaîne -> puis ->>)
SELECT donnees ->> 'titre'          AS titre,
       donnees -> 'auteur' ->> 'nom' AS nom_auteur
FROM document
WHERE type_document = 'livre';

-- Filtrer : le livre "Le Petit Prince"
SELECT *
FROM document
WHERE type_document = 'livre'
  AND donnees ->> 'titre' = 'Le Petit Prince';

-- Filtrer sur une propriété imbriquée plus profondément (l'auteur)
SELECT *
FROM document
WHERE type_document = 'livre'
  AND donnees -> 'auteur' ->> 'nom' = 'Antoine de Saint-Exupéry';

-- Le nom de chaque membre
SELECT donnees ->> 'nom' AS nom_membre
FROM document
WHERE type_document = 'membre';


-- ============================================================
-- #>> : équivalent à chaîner -> plusieurs fois, mais en donnant
-- directement le CHEMIN COMPLET sous forme de tableau de texte.
-- Retourne du texte (comme ->>). Il existe aussi #> (sans les
-- deux chevrons finaux) qui retourne du JSONB, comme ->.
-- ============================================================

-- Équivalent de : donnees -> 'auteur' ->> 'nom'
SELECT donnees #>> '{auteur,nom}' AS nom_auteur
FROM document
WHERE type_document = 'livre';

-- Même filtre qu'avant, mais écrit avec #>>
SELECT *
FROM document
WHERE type_document = 'livre'
  AND donnees #>> '{auteur,nom}' = 'Antoine de Saint-Exupéry';

-- Filtrer par nom de membre, avec #>>
SELECT *
FROM document
WHERE type_document = 'membre'
  AND donnees #>> '{nom}' = 'Julie Bouchard';
