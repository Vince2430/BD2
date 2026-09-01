-- ============================================================
-- Mise à jour ciblée d'une propriété avec jsonb_set()
-- ============================================================
--
-- Syntaxe : jsonb_set(donnees_originales, chemin, nouvelle_valeur, creer_si_absent)
--
-- - chemin : un tableau de texte donnant le chemin vers la clé
--            à modifier, ex: '{membre,nom}'
-- - nouvelle_valeur : doit être du JSONB valide -- une chaîne de
--   texte doit être écrite entre guillemets doubles à l'intérieur
--   des guillemets simples : '"Julie"', pas juste 'Julie'
-- - creer_si_absent (optionnel, true par défaut) : si false, ne
--   fait rien quand la clé n'existe pas déjà


-- ============================================================
-- 1. Modifier une propriété au premier niveau
-- ============================================================
-- Ex : marquer un emprunt comme retourné

UPDATE document
SET donnees = jsonb_set(donnees, '{date_retour}', '"2026-08-01"')
WHERE id = 1;


-- ============================================================
-- 2. Modifier une propriété imbriquée (un niveau plus profond)
-- ============================================================
-- Ex : corriger le nom d'un membre

UPDATE document
SET donnees = jsonb_set(donnees, '{membre,nom}', '"Julie Tremblay"')
WHERE id = 1;


-- ============================================================
-- 3. Modifier une propriété imbriquée à deux niveaux
-- ============================================================
-- Ex : corriger le nom de l'auteur, imbriqué dans livre

UPDATE document
SET donnees = jsonb_set(donnees, '{livre,auteur,nom}', '"A. de Saint-Exupéry"')
WHERE id = 1;


-- ============================================================
-- 4. Utiliser to_jsonb() pour insérer une valeur non-textuelle
-- (date, nombre) sans avoir à écrire les guillemets à la main
-- ============================================================

UPDATE document
SET donnees = jsonb_set(donnees, '{date_retour}', to_jsonb(CURRENT_DATE))
WHERE id = 1;


-- ============================================================
-- 5. Exemple réaliste : marquer un emprunt actif comme retourné,
-- en ciblant la ligne avec @> plutôt qu'un id connu à l'avance
-- ============================================================

UPDATE document
SET donnees = jsonb_set(donnees, '{date_retour}', to_jsonb(CURRENT_DATE))
WHERE type_document = 'emprunt'
  AND donnees @> '{"membre": {"nom": "Marc Gagnon"}, "livre": {"titre": "Le Petit Prince"}}'
  AND donnees ->> 'date_retour' IS NULL
RETURNING id, donnees;


-- ============================================================
-- 6. creer_si_absent = false : ne rien faire si la clé n'existe
-- pas déjà (évite de créer accidentellement une nouvelle clé)
-- ============================================================

UPDATE document
SET donnees = jsonb_set(donnees, '{date_prolongation}', '"2026-09-01"', false)
WHERE id = 1;
-- Ici, si "date_prolongation" n'existe pas déjà dans le document,
-- rien ne change (contrairement au comportement par défaut).


-- ============================================================
-- 7. Modifier un élément DANS UN TABLEAU (par index)
-- ============================================================
-- Pour le modèle "livre comme racine", avec le tableau "emprunts" :
-- le chemin inclut l'index de l'élément (commence à 0)

UPDATE document
SET donnees = jsonb_set(donnees, '{emprunts,0,date_retour}', to_jsonb(CURRENT_DATE))
WHERE type_document = 'livre'
  AND id = 2;
-- Met à jour "date_retour" du PREMIER élément (index 0) du tableau emprunts
