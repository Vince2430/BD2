-- ============================================================
-- Mise à jour ciblée d'une propriété avec jsonb_set()
-- ============================================================
--
-- Syntaxe : jsonb_set(donnees_originales, chemin, nouvelle_valeur, creer_si_absent)
--
-- - chemin : un tableau de texte donnant le chemin vers la clé
--            à modifier, ex: '{auteur,nom}'
-- - nouvelle_valeur : doit être du JSONB valide -- une chaîne de
--   texte doit être écrite entre guillemets doubles à l'intérieur
--   des guillemets simples : '"Julie"', pas juste 'Julie'
-- - creer_si_absent (optionnel, true par défaut) : si false, ne
--   fait rien quand la clé n'existe pas déjà
--
-- Rappel de structure : un livre a un tableau "emprunts" (chaque
-- élément a son propre id_membre/nom_membre/date_emprunt/date_retour),
-- un membre a un tableau "emprunts_actifs".


-- ============================================================
-- 1. Modifier une propriété au premier niveau
-- ============================================================
-- Ex : corriger le titre d'un livre

UPDATE document
SET donnees = jsonb_set(donnees, '{titre}', '"Le Petit Prince (édition spéciale)"')
WHERE type_document = 'livre' AND id = 1;


-- ============================================================
-- 2. Modifier une propriété imbriquée (un niveau plus profond)
-- ============================================================
-- Ex : corriger le nom de l'auteur, imbriqué dans "auteur"

UPDATE document
SET donnees = jsonb_set(donnees, '{auteur,nom}', '"A. de Saint-Exupéry"')
WHERE type_document = 'livre' AND id = 1;


-- ============================================================
-- 3. Modifier un élément DANS UN TABLEAU (par index)
-- ============================================================
-- Le chemin inclut l'index de l'élément (commence à 0). Ex :
-- marquer comme retourné le PREMIER emprunt (index 0) du tableau
-- "emprunts" d'un livre, avec to_jsonb() pour insérer une date
-- sans avoir à écrire les guillemets à la main.

UPDATE document
SET donnees = jsonb_set(donnees, '{emprunts,0,date_retour}', to_jsonb(CURRENT_DATE))
WHERE type_document = 'livre' AND id = 2;


-- ============================================================
-- 4. Exemple réaliste : marquer l'emprunt actif d'un membre
-- donné comme retourné, en le retrouvant par contenance plutôt
-- que par un index de tableau connu à l'avance
-- ============================================================
-- On doit d'abord retrouver l'INDEX de l'élément à modifier dans
-- le tableau "emprunts" (jsonb_set a besoin d'un index numérique
-- dans le chemin, pas d'un filtre) -- WITH ORDINALITY nous donne
-- cette position.

WITH cible AS (
    SELECT d.id AS doc_id, (elem.pos - 1) AS idx
    FROM document AS d,
         jsonb_array_elements(d.donnees -> 'emprunts') WITH ORDINALITY AS elem(valeur, pos)
    WHERE d.type_document = 'livre'
      AND elem.valeur ->> 'nom_membre' = 'Marc Gagnon'
      AND elem.valeur ->> 'date_retour' IS NULL
)
UPDATE document
SET donnees = jsonb_set(
    document.donnees,
    ARRAY['emprunts', cible.idx::text, 'date_retour'],
    to_jsonb(CURRENT_DATE)
)
FROM cible
WHERE document.id = cible.doc_id
RETURNING document.id, document.donnees;

-- Il faudrait aussi mettre à jour le document 'membre' correspondant
-- (retirer cet emprunt de son tableau "emprunts_actifs") -- laissé
-- volontairement de côté ici pour garder l'exemple simple, mais
-- c'est le genre de synchronisation manuelle que le modèle
-- documentaire impose (contrairement au relationnel, où une seule
-- ligne "emprunt" suffit).


-- ============================================================
-- 5. creer_si_absent = false : ne rien faire si la clé n'existe
-- pas déjà (évite de créer accidentellement une nouvelle clé)
-- ============================================================

UPDATE document
SET donnees = jsonb_set(donnees, '{isbn}', '"978-2-07-040850-4"', false)
WHERE type_document = 'livre' AND id = 1;
-- Ici, si "isbn" n'existe pas déjà dans le document, rien ne
-- change (contrairement au comportement par défaut).
