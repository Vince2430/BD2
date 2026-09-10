

-- ############################################################
-- ############################################################
--
--   REQUÊTES JSONB DEMANDÉES (partie 2, point 4)
--
--   1. Recherche par propriété      ->  ->>  #>>
--   2. Recherche par contenance     @>
--   3. Recherche dans un tableau JSON
--   4. Mise à jour ciblée           jsonb_set
--   5. Requête démontrant l'index, avec EXPLAIN
--
-- ############################################################
-- ############################################################



-- ############################################################
-- 1. RECHERCHE PAR PROPRIÉTÉ : ->, ->> et #>>
-- ############################################################
--
--   ->   retourne du JSONB  (on garde le type JSON pour continuer
--                            à descendre dans le document)
--   ->>  retourne du TEXTE  (valeur finale : comparaison, affichage)
--   #>>  retourne du TEXTE  en donnant le CHEMIN COMPLET d'un coup
--        (#> existe aussi et retourne du JSONB, comme ->)


-- -> : l'objet "auteur" au complet, encore en JSONB
SELECT id, donnees -> 'auteur' AS auteur_json
FROM document
WHERE type_document = 'livre'
ORDER BY id
LIMIT 5;


-- -> puis ->> : descendre d'un niveau, puis lire le texte
SELECT donnees ->> 'titre'           AS titre,
       donnees -> 'auteur' ->> 'nom' AS nom_auteur
FROM document
WHERE type_document = 'livre'
ORDER BY titre;


-- ->> en filtre : un livre précis
SELECT id, donnees ->> 'titre' AS titre
FROM document
WHERE type_document = 'livre'
  AND donnees ->> 'titre' = 'Le Petit Prince';


-- #>> : exactement équivalent à donnees -> 'auteur' ->> 'nom',
-- mais en une seule écriture du chemin
SELECT donnees ->> 'titre'        AS titre,
       donnees #>> '{auteur,nom}' AS nom_auteur
FROM document
WHERE type_document = 'livre'
  AND donnees #>> '{auteur,nom}' = 'Albert Camus';


-- Les livres jamais empruntés : tableau "emprunts" de longueur 0.
-- Impossible à représenter dans le modèle « un document = un emprunt »,
-- d'où l'abandon de ce premier modèle.
SELECT donnees ->> 'titre' AS jamais_emprunte
FROM document
WHERE type_document = 'livre'
  AND jsonb_array_length(donnees -> 'emprunts') = 0
ORDER BY 1;



-- ############################################################
-- 2. RECHERCHE PAR CONTENANCE : @>
-- ############################################################
--
-- @> se lit « le JSONB de gauche CONTIENT le JSONB de droite ».
-- On fournit un petit gabarit ; le document peut avoir autant
-- d'autres clés qu'il veut en plus.
--
-- Différence importante avec ->> : @> compare des valeurs EXACTES
-- (pas de ILIKE, pas de %), mais c'est la seule des deux formes que
-- l'index GIN sait accélérer.


-- Contenance simple, propriété de premier niveau
SELECT id, donnees ->> 'titre' AS titre
FROM document
WHERE type_document = 'livre'
  AND donnees @> '{"titre": "Le Petit Prince"}';


-- Contenance sur une propriété IMBRIQUÉE
SELECT id, donnees ->> 'titre' AS titre
FROM document
WHERE type_document = 'livre'
  AND donnees @> '{"auteur": {"nom": "Victor Hugo"}}'
ORDER BY titre;


-- Contenance COMBINÉE : plusieurs critères d'un coup
SELECT id, donnees ->> 'titre' AS titre
FROM document
WHERE type_document = 'livre'
  AND donnees @> '{"titre": "La Peste", "auteur": {"nom": "Albert Camus"}}';



-- ############################################################
-- 3. RECHERCHE DANS UN TABLEAU JSON
-- ############################################################
--
-- Trois façons de fouiller le tableau "emprunts" d'un livre ou le
-- tableau "emprunts_actifs" d'un membre.


-- --- a) jsonb_array_elements : « dérouler » le tableau en lignes ---
-- Chaque élément devient une ligne, ce qui permet de le traiter
-- comme une vraie table.

SELECT
    d.donnees ->> 'titre'                AS titre_livre,
    emprunt ->> 'nom_membre'             AS nom_membre,
    emprunt ->> 'date_emprunt'           AS date_emprunt,
    emprunt ->> 'date_retour'            AS date_retour
FROM document AS d,
     jsonb_array_elements(d.donnees -> 'emprunts') AS emprunt
WHERE d.type_document = 'livre'
  AND d.donnees ->> 'titre' = 'Le Petit Prince';


-- --- b) EXISTS : filtrer sans dupliquer les lignes de document ---
-- Les livres actuellement empruntés (au moins un emprunt sans
-- date_retour). Chaque livre apparaît une seule fois.

SELECT d.donnees ->> 'titre' AS livre_actuellement_emprunte
FROM document d
WHERE d.type_document = 'livre'
  AND EXISTS (
      SELECT 1
      FROM jsonb_array_elements(d.donnees -> 'emprunts') AS e
      WHERE e ->> 'date_retour' IS NULL
  )
ORDER BY 1;


-- --- c) @> sur un tableau : contenance directe ---
-- Il suffit qu'UN élément du tableau contienne le gabarit donné.
-- C'est la forme la plus rapide (elle peut passer par l'index GIN),
-- mais elle exige de connaître la valeur exacte.

-- Les membres ayant "Le Petit Prince" parmi leurs emprunts actifs
SELECT donnees ->> 'nom' AS nom_membre
FROM document
WHERE type_document = 'membre'
  AND donnees @> '{"emprunts_actifs": [{"titre_livre": "Le Petit Prince"}]}'
ORDER BY 1;


-- --- d) jsonb_array_length : compter les éléments du tableau ---
-- Le « nombre d'emprunts par livre », équivalent documentaire de
-- l'agrégation GROUP BY du fichier 03. Ici, aucun regroupement :
-- l'information est déjà rassemblée dans le document.

SELECT
    donnees ->> 'titre'                     AS titre,
    jsonb_array_length(donnees -> 'emprunts') AS nb_emprunts
FROM document
WHERE type_document = 'livre'
ORDER BY nb_emprunts DESC, titre
LIMIT 10;



-- ############################################################
-- 4. MISE À JOUR CIBLÉE : jsonb_set
-- ############################################################
--
-- jsonb_set(document, chemin, nouvelle_valeur, creer_si_absent)
--
--   chemin           : tableau de texte, ex. '{titre}' ou '{auteur,nom}'
--   nouvelle_valeur  : doit être du JSONB — une chaîne s'écrit avec
--                      ses guillemets : '"Julie"', pas 'Julie'.
--                      to_jsonb(...) évite d'avoir à les écrire.
--   creer_si_absent  : true par défaut ; false = ne rien faire si la
--                      clé n'existe pas déjà.


-- --- a) Propriété de premier niveau ---
-- On modifie, on vérifie, puis on remet la valeur d'origine pour
-- que le script reste rejouable.

UPDATE document
SET donnees = jsonb_set(donnees, '{titre}', '"La Peste (édition annotée)"')
WHERE type_document = 'livre'
  AND donnees ->> 'titre' = 'La Peste'
RETURNING id, donnees ->> 'titre' AS nouveau_titre;

UPDATE document
SET donnees = jsonb_set(donnees, '{titre}', '"La Peste"')
WHERE type_document = 'livre'
  AND donnees ->> 'titre' = 'La Peste (édition annotée)'
RETURNING id, donnees ->> 'titre' AS titre_restaure;


-- --- b) Propriété IMBRIQUÉE (un niveau plus profond) ---

UPDATE document
SET donnees = jsonb_set(donnees, '{auteur,nom}', '"A. de Saint-Exupéry"')
WHERE type_document = 'livre'
  AND donnees #>> '{auteur,nom}' = 'Antoine de Saint-Exupéry'
RETURNING id, donnees #>> '{auteur,nom}' AS nouveau_nom;

UPDATE document
SET donnees = jsonb_set(donnees, '{auteur,nom}', '"Antoine de Saint-Exupéry"')
WHERE type_document = 'livre'
  AND donnees #>> '{auteur,nom}' = 'A. de Saint-Exupéry'
RETURNING id, donnees #>> '{auteur,nom}' AS nom_restaure;


-- --- c) creer_si_absent = false ---
-- Sans ce false, jsonb_set CRÉERAIT la clé "isbn". Avec false, il ne
-- fait rien si elle n'existe pas déjà : 0 ligne visible ci-dessous.

UPDATE document
SET donnees = jsonb_set(donnees, '{isbn}', '"978-2-07-040850-4"', false)
WHERE type_document = 'livre'
  AND donnees ->> 'titre' = 'La Peste'
RETURNING id, donnees ? 'isbn' AS isbn_present;


-- --- d) Cas réaliste : marquer un emprunt du tableau comme retourné ---
--
-- jsonb_set a besoin d'un INDEX NUMÉRIQUE dans le chemin
-- ('{emprunts,0,date_retour}'), pas d'un filtre. Il faut donc
-- d'abord retrouver la position de l'élément à modifier :
-- WITH ORDINALITY donne cette position (elle commence à 1, d'où le -1).
--
-- Exécuté dans une transaction annulée : on voit le résultat sans
-- altérer le jeu de données.

BEGIN;

WITH cible AS (
    SELECT d.id AS doc_id,
           (elem.pos - 1) AS idx
    FROM document AS d,
         jsonb_array_elements(d.donnees -> 'emprunts')
             WITH ORDINALITY AS elem(valeur, pos)
    WHERE d.type_document = 'livre'
      AND elem.valeur ->> 'date_retour' IS NULL
    ORDER BY d.id, elem.pos
    LIMIT 1
)
UPDATE document
SET donnees = jsonb_set(
        document.donnees,
        ARRAY['emprunts', cible.idx::text, 'date_retour'],
        to_jsonb(CURRENT_DATE))
FROM cible
WHERE document.id = cible.doc_id
RETURNING document.id,
          document.donnees ->> 'titre' AS titre,
          document.donnees -> 'emprunts' AS emprunts_apres;

ROLLBACK;

-- LIMITE DU MODÈLE DOCUMENTAIRE, à noter pour la comparaison :
-- il faudrait AUSSI retirer cet emprunt du tableau "emprunts_actifs"
-- du document 'membre' correspondant. Deux écritures à synchroniser
-- à la main, sans aucune garantie de la base. Dans le modèle
-- relationnel, un seul UPDATE sur une seule ligne emprunt suffit,
-- et les clés étrangères garantissent la cohérence.



-- ############################################################
-- 5. UTILISATION DE L'INDEX, AVEC EXPLAIN
-- ############################################################
--
-- Rappel : ILIKE et ->> ne peuvent PAS utiliser l'index GIN.
-- Seul @> le peut. C'est le compromis du modèle documentaire :
-- recherche exacte rapide, recherche approximative lente.


-- --- a) Plan choisi spontanément par le planificateur ---

EXPLAIN ANALYZE
SELECT *
FROM document
WHERE donnees @> '{"auteur": {"nom": "Albert Camus"}}';

-- Sur ce volume (quelques dizaines de documents), PostgreSQL affiche
-- souvent « Seq Scan » : lire les quelques pages de la table coûte
-- moins cher que de consulter l'index. Ce n'est PAS un bug, c'est le
-- planificateur qui fait son travail.


-- --- b) On force l'usage de l'index pour la démonstration ---

SET enable_seqscan = off;

EXPLAIN ANALYZE
SELECT *
FROM document
WHERE donnees @> '{"auteur": {"nom": "Albert Camus"}}';

SET enable_seqscan = on;   -- remettre le comportement normal

-- On voit alors « Bitmap Heap Scan on document » et, en dessous,
-- « Bitmap Index Scan on idx_document_donnees_path ».
--
-- Pourquoi idx_document_donnees_path et non idx_document_donnees ?
-- Les deux sont des index GIN sur la même colonne, mais
-- jsonb_path_ops ne supporte QUE @> : il est plus petit et moins
-- coûteux, donc le planificateur le préfère pour cette requête.


-- --- c) Comparaison : la même recherche SANS index possible ---

EXPLAIN ANALYZE
SELECT *
FROM document
WHERE donnees #>> '{auteur,nom}' = 'Albert Camus';

-- Toujours un Seq Scan, même avec les index en place : l'extraction
-- #>> est calculée ligne par ligne, l'index GIN ne peut rien y faire.
-- Il faudrait un index d'expression dédié :
--     CREATE INDEX ON document ((donnees #>> '{auteur,nom}'));


-- ============================================================
-- Comment lire un plan d'exécution
-- ============================================================
--   Seq Scan          : lit toute la table, ligne par ligne
--   Bitmap Index Scan : consulte l'index pour repérer les lignes candidates
--   Bitmap Heap Scan  : va ensuite chercher ces lignes dans la table
--   cost=             : estimation AVANT exécution
--   actual time=      : temps réellement mesuré (grâce à ANALYZE)
--   rows=             : lignes estimées / réellement trouvées
