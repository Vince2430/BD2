-- ============================================================
-- Démonstration : l'index GIN change le plan d'exécution
-- ============================================================
--
-- Astuce importante : sur une TOUTE PETITE table (quelques
-- lignes), PostgreSQL choisit souvent un "Seq Scan" même s'il y a
-- un index, parce que lire directement les quelques lignes est
-- plus rapide que de consulter l'index. Pour voir clairement la
-- différence, insère d'abord un grand nombre de documents (par
-- exemple avec le script Python generer_emprunts.py, en mettant
-- NB_A_INSERER = 2000 ou plus) avant de faire ce test.


-- ============================================================
-- Étape 1 : la requête qu'on va observer
-- (utilise @>, l'opérateur que l'index GIN sait accélérer)
-- ============================================================

-- On la garde de côté, on va l'exécuter deux fois : sans index,
-- puis avec index.


-- ============================================================
-- Étape 2 : AVANT -- sans index (on le supprime s'il existe)
-- ============================================================

DROP INDEX IF EXISTS idx_document_donnees;

EXPLAIN ANALYZE
SELECT *
FROM document
WHERE donnees @> '{"membre": {"nom": "Julie Bouchard"}}';

-- Résultat attendu : "Seq Scan on document" -- PostgreSQL doit
-- lire et décortiquer CHAQUE ligne une par une pour vérifier
-- la condition.


-- ============================================================
-- Étape 3 : APRÈS -- on recrée l'index
-- ============================================================

CREATE INDEX idx_document_donnees ON document USING GIN (donnees);

EXPLAIN ANALYZE
SELECT *
FROM document
WHERE donnees @> '{"membre": {"nom": "Julie Bouchard"}}';

-- Résultat attendu : "Bitmap Heap Scan on document" avec, en
-- dessous, "Bitmap Index Scan on idx_document_donnees" -- signe
-- que PostgreSQL a utilisé l'index au lieu de tout balayer.


-- ============================================================
-- Étape 4 (optionnelle) : forcer l'utilisation de l'index
-- même sur une petite table, pour la démonstration
-- ============================================================

SET enable_seqscan = off;

EXPLAIN ANALYZE
SELECT *
FROM document
WHERE donnees @> '{"membre": {"nom": "Julie Bouchard"}}';

SET enable_seqscan = on;  -- remettre le comportement normal après le test


-- ============================================================
-- Comment lire le résultat de EXPLAIN ANALYZE
-- ============================================================
-- - "Seq Scan"           : lit toute la table, ligne par ligne
-- - "Bitmap Index Scan"  : consulte l'index pour trouver les
--                          lignes candidates, sans lire toute la table
-- - "Bitmap Heap Scan"   : va ensuite chercher les lignes trouvées
--                          par le Bitmap Index Scan
-- - "cost="               : estimation du coût (avant exécution)
-- - "actual time="        : temps réellement mesuré (avec ANALYZE)
-- - "rows="                : nombre de lignes trouvées/estimées
