-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 4 : les 10 requetes
-- =============================================================
-- NE FAIT PAS PARTIE DE creer_bd.command : ce sont des lectures,
-- a executer a la main (Query Tool pgAdmin ou psql), une a la fois.
--
-- Chaque requete est numerotee, indique l'exigence qu'elle couvre
-- et la question metier a laquelle elle repond.
-- =============================================================

-- =============================================================
-- Tableau de correspondance exigence -> requete
-- =============================================================
-- Exigence                                          | Requete(s)
-- ---------------------------------------------------|-----------
-- 1. Jointure >= 3 tables                            | 1
-- 2. Agregation GROUP BY + HAVING                     | 2
-- 3. Sous-requete correlee ou EXISTS                  | 3
-- 4. CTE (WITH)                                       | 4
-- 5. Fonction de fenetre (OVER)                       | 5
-- 6. UNION / INTERSECT / EXCEPT                       | 6
-- 7. Appel a une vue / vue materialisee / routine      | 7
-- 8. Ecriture parametree (application, etape 5)       | 8
-- 9. JSONB : contenance @>                             | 9
-- 10. JSONB : manipulation structure imbriquee         | 10
-- 2 requetes ameliorables par index (EXPLAIN ANALYZE)  |
-- =============================================================

SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- 1. Jointure d'au moins 3 tables
-- Question : Pour chaque produit, quelles sont ses informations de
-- base, le nom de sa categorie et sa fiche de specifications (JSONB) ?
-- -------------------------------------------------------------
SELECT
    p.id_produit,
    p.nom_produit,
    p.prix_produit,
    p.cout_procuration_produit,
    p.quantite_totale_produit,
    c.nom_categorie,
    sp.specifications_produit
FROM commerce.produit p
JOIN commerce.categorie c
    ON c.id_categorie = p.id_categorie
JOIN commerce.specification_produit sp
    ON sp.id_produit = p.id_produit
ORDER BY p.nom_produit;


-- -------------------------------------------------------------
-- 2. Agregation GROUP BY + HAVING
-- Question : Quelles categories de produits generent un revenu total
-- (commandes non annulees) superieur a un certain seuil ?
-- -------------------------------------------------------------
SELECT
    cat.id_categorie,
    cat.nom_categorie,
    SUM(ic.quantite * ic.prix_unitaire) AS revenu_total
FROM commerce.categorie cat
JOIN commerce.produit p
    ON p.id_categorie = cat.id_categorie
JOIN commerce.info_commande ic
    ON ic.id_produit = p.id_produit
JOIN commerce.commande cmd
    ON cmd.id_commande = ic.id_commande
JOIN commerce.statut s
    ON s.id_statut = cmd.id_statut
WHERE s.nom_statut <> 'Annulée'
GROUP BY cat.id_categorie, cat.nom_categorie
HAVING SUM(ic.quantite * ic.prix_unitaire) > 1000 -- seuil a ajuster selon les donnees reelles
ORDER BY revenu_total DESC;


-- -------------------------------------------------------------
-- 3. Sous-requete correlee ou EXISTS
-- Question : Quel(s) client(s) ont depense le plus au total
-- (commandes non annulees) ? (technique : NOT EXISTS correle, sans
-- fonction de fenetre, celle-ci etant reservee au point 5)
-- -------------------------------------------------------------
SELECT d1.id_client, d1.nom_client, d1.total_depense
FROM (
    SELECT
        cl.id_client,
        cl.nom_client,
        SUM(ic.quantite * ic.prix_unitaire) AS total_depense
    FROM commerce.client cl
    JOIN commerce.commande cmd
        ON cmd.id_client = cl.id_client
    JOIN commerce.info_commande ic
        ON ic.id_commande = cmd.id_commande
    JOIN commerce.statut s
        ON s.id_statut = cmd.id_statut
    WHERE s.nom_statut <> 'Annulée'
    GROUP BY cl.id_client, cl.nom_client
) d1
WHERE NOT EXISTS (
    SELECT 1
    FROM (
        SELECT
            cl2.id_client,
            SUM(ic2.quantite * ic2.prix_unitaire) AS total_depense
        FROM commerce.client cl2
        JOIN commerce.commande cmd2
            ON cmd2.id_client = cl2.id_client
        JOIN commerce.info_commande ic2
            ON ic2.id_commande = cmd2.id_commande
        JOIN commerce.statut s2
            ON s2.id_statut = cmd2.id_statut
        WHERE s2.nom_statut <> 'Annulée'
        GROUP BY cl2.id_client
    ) d2
    WHERE d2.total_depense > d1.total_depense
);


-- -------------------------------------------------------------
-- 4. Expression de table commune (WITH)
-- Question : Pour chaque client, combien de commandes a-t-il passees
-- (commandes non annulees), sur quelle periode, combien a-t-il
-- depense au total, et combien de produits differents met-il en
-- moyenne dans une meme commande ?
-- -------------------------------------------------------------
WITH commande_totaux AS (
    SELECT
        cmd.id_commande,
        cmd.id_client,
        cmd.date_commande,
        SUM(ic.quantite * ic.prix_unitaire) AS total_commande,
        COUNT(DISTINCT ic.id_produit) AS nb_produits_differents
    FROM commerce.commande cmd
    JOIN commerce.info_commande ic
        ON ic.id_commande = cmd.id_commande
    JOIN commerce.statut s
        ON s.id_statut = cmd.id_statut
    WHERE s.nom_statut <> 'Annulée'
    GROUP BY cmd.id_commande, cmd.id_client, cmd.date_commande
)
SELECT
    cl.id_client,
    cl.nom_client,
    COUNT(ct.id_commande) AS nombre_commandes,
    MIN(ct.date_commande) AS premiere_commande,
    MAX(ct.date_commande) AS derniere_commande,
    SUM(ct.total_commande) AS total_depense,
    ROUND(AVG(ct.nb_produits_differents), 2) AS moyenne_produits_par_commande
FROM commerce.client cl
JOIN commande_totaux ct
    ON ct.id_client = cl.id_client
GROUP BY cl.id_client, cl.nom_client
ORDER BY total_depense DESC;


-- -------------------------------------------------------------
-- 5. Fonction de fenetre (OVER)
-- Question : Quel est le classement complet des clients selon le
-- montant total depense (commandes non annulees) ? (reprend la
-- question de la requete 3, mais cette fois avec la technique
-- prevue pour ca : on voit TOUT le classement, pas seulement le
-- sommet)
-- -------------------------------------------------------------
SELECT
    cl.id_client,
    cl.nom_client,
    SUM(ic.quantite * ic.prix_unitaire) AS total_depense,
    RANK() OVER (ORDER BY SUM(ic.quantite * ic.prix_unitaire) DESC) AS rang_depense
FROM commerce.client cl
JOIN commerce.commande cmd
    ON cmd.id_client = cl.id_client
JOIN commerce.info_commande ic
    ON ic.id_commande = cmd.id_commande
JOIN commerce.statut s
    ON s.id_statut = cmd.id_statut
WHERE s.nom_statut <> 'Annulée'
GROUP BY cl.id_client, cl.nom_client
ORDER BY rang_depense;


-- -------------------------------------------------------------
-- 6. UNION, INTERSECT ou EXCEPT
-- Question : Quels clients sont "a risque", soit parce qu'ils ont au
-- moins une commande annulee, soit parce qu'une de leurs commandes
-- annulees a en plus laisse un paiement non complete derriere elle
-- (autorise mais jamais capture) ?
-- NOTE (24 sept, a revisiter) : le schema ne permet pas de
-- distinguer un paiement "echoue" d'un paiement simplement "pas
-- encore complete" (pas de colonne raison/statut sur paiement) --
-- voir Doc/justification_requetes_etape4.md. On limite donc le 2e
-- critere aux commandes DEJA annulees, seul cas ou "non complete"
-- est un vrai signal de risque plutot qu'un traitement normal en
-- cours.
-- -------------------------------------------------------------
SELECT DISTINCT
    cl.id_client,
    cl.nom_client,
    'Commande annulee' AS raison
FROM commerce.client cl
JOIN commerce.commande cmd
    ON cmd.id_client = cl.id_client
JOIN commerce.statut s
    ON s.id_statut = cmd.id_statut
WHERE s.nom_statut = 'Annulée'

UNION

SELECT DISTINCT
    cl.id_client,
    cl.nom_client,
    'Commande annulee avec paiement non complete' AS raison
FROM commerce.client cl
JOIN commerce.commande cmd
    ON cmd.id_client = cl.id_client
JOIN commerce.statut s
    ON s.id_statut = cmd.id_statut
JOIN commerce.paiement p
    ON p.id_commande = cmd.id_commande
WHERE s.nom_statut = 'Annulée'
  AND p.est_complete = FALSE

ORDER BY id_client, raison;


-- -------------------------------------------------------------
-- 7. Appel a une vue, a la vue materialisee ou a une routine
-- Question : Quels sont les produits les plus vendus dans les 7
-- derniers jours, selon le dernier rafraichissement de la vue
-- materialisee mv_ventes_produit_7j ?
-- -------------------------------------------------------------
SELECT
    id_produit,
    nom_produit,
    nom_categorie,
    quantite_vendue_7j,
    date_rafraichissement
FROM commerce.mv_ventes_produit_7j
WHERE quantite_vendue_7j > 0
ORDER BY quantite_vendue_7j DESC
LIMIT 10;


-- -------------------------------------------------------------
-- 8. Ecriture parametree executee par l'application (etape 5)
-- Question : Recherche de commandes selon 2 criteres (client +
-- statut) -- gabarit de la requete que l'application (Python/psycopg
-- ou C#/Npgsql) executera avec de vrais parametres. Les %s sont le
-- style psycopg2 (position) ; ajuster en @nom_parametre pour Npgsql.
-- Pour tester manuellement dans pgAdmin, remplacer chaque %s par une
-- valeur litterale (ex. 12 et 'Payée').
-- -------------------------------------------------------------
SELECT
    cmd.id_commande,
    cmd.date_commande,
    cl.nom_client,
    s.nom_statut,
    cmd.adresse_livraison_commande
FROM commerce.commande cmd
JOIN commerce.client cl
    ON cl.id_client = cmd.id_client
JOIN commerce.statut s
    ON s.id_statut = cmd.id_statut
WHERE cmd.id_client = %s
  AND s.nom_statut = %s
ORDER BY cmd.date_commande DESC;


-- -------------------------------------------------------------
-- 9. JSONB : recherche par contenance @>
-- Question : Quels produits ont la marque recherchee par
-- l'utilisateur ? Version generique/parametree : jsonb_build_object
-- construit le fragment JSON a comparer a partir du parametre %s, au
-- lieu d'ecrire un litteral JSON en dur -- l'application (etape 5)
-- pourra passer n'importe quelle marque en parametre. Beneficie de
-- l'index GIN jsonb_path_ops (idx_specification_produit_gin, voir
-- 01_create_schema.sql) qui accelere justement @>.
-- Pour tester dans pgAdmin, remplacer %s par une valeur litterale
-- (ex. 'Samsung').
-- La cle marque est facultative (01_create_schema.sql) : un produit
-- sans cle marque n'est jamais retourne. Un parametre NULL donne
-- {"marque": null} et retourne les produits a marque inconnue
-- (ex. prototypes).
-- -------------------------------------------------------------
SELECT
    p.id_produit,
    p.nom_produit,
    sp.specifications_produit
FROM commerce.produit p
JOIN commerce.specification_produit sp
    ON sp.id_produit = p.id_produit
WHERE sp.specifications_produit @> jsonb_build_object('marque', %s)
ORDER BY p.nom_produit;


-- -------------------------------------------------------------
-- 10. JSONB : manipulation d'une structure imbriquee
-- Question : Corriger la largeur (dimensions.largeur) d'un produit
-- precis dans ses specifications, sans toucher au reste du JSON.
-- UPDATE normal (WHERE id_produit cible une seule ligne), sauf que
-- la nouvelle valeur de la colonne est calculee par jsonb_set() sur
-- une cle imbriquee plutot qu'ecrite directement.
-- Remplacer 7 par un id_produit qui a bien une cle "dimensions"
-- dans ses specifications (tous les produits n'en ont pas).
-- create_missing = false : ne cree PAS la cle si le chemin n'existe
-- pas deja, pour eviter d'ajouter "dimensions" par erreur a un
-- produit qui n'en a pas dans sa categorie.
-- -------------------------------------------------------------
UPDATE commerce.specification_produit
SET specifications_produit = jsonb_set(
    specifications_produit,
    '{dimensions,largeur}',
    '35'::jsonb,
    false
)
WHERE id_produit = 7;


-- ===============================================================
-- Analyse des plans d'execution (2 requetes ameliorables par un index)
-- ===============================================================

-- -------------------------------------------------------------
-- 11. Candidat A : filtre sur commande.id_statut (via jointure statut)
-- Question : Quelles commandes ont le statut 'Annulee' ?
-- Colonne ciblee par l'index : commande(id_statut).
-- Utilisee (via jointure a statut) dans les requetes 2,3,4,5,6,7.
-- Jeu de donnees pour ce test : 50 000 commandes, 1500 clients (graine 0.75)
-- genere via 03_donnees.sql, pour avoir un volume assez grand pour observer
-- un vrai changement de plan.
--
-- AVANT index : Seq Scan sur commande (50 000 lignes lues) + Hash Join avec
-- statut. cost=8.18..3530.19, 3996 lignes retournees, Execution Time = 21.423 ms.
--
-- Index cree : CREATE INDEX idx_commande_id_statut ON commerce.commande(id_statut);
--
-- APRES index : le plan change reellement -> Bitmap Index Scan sur
-- idx_commande_id_statut + Bitmap Heap Scan, dans un Nested Loop.
-- cost=97.02..3182.53, memes 3996 lignes, Execution Time = 10.855 ms.
--
-- Conclusion : avec un jeu de donnees assez grand, l'index est rentable et
-- le planificateur change effectivement de strategie. Le cout estime baisse
-- legerement (3530 -> 3183) et le temps reel est quasiment divise par 2
-- (21.4 ms -> 10.9 ms).
-- -------------------------------------------------------------
EXPLAIN ANALYZE
SELECT c.id_commande, c.date_commande, c.id_client
FROM commerce.commande c
JOIN commerce.statut s ON s.id_statut = c.id_statut
WHERE s.nom_statut = 'Annulée';


-- -------------------------------------------------------------
-- 12. Candidat B : filtre sur paiement.est_complete
-- Question : Quels paiements sont restes non completes ?
-- Colonne ciblee par l'index : paiement(est_complete) (index partiel
-- possible, WHERE est_complete = FALSE, car c'est la seule valeur
-- recherchee dans ce contexte).
-- Jeu de donnees pour ce test : 50 000 commandes, 1500 clients (graine 0.75).
--
-- AVANT index : Seq Scan sur paiement, filtre elimine 45 412 lignes sur
-- ~47 710 pour n'en garder que 2298. Execution Time = 8.722 ms.
--
-- Index cree : CREATE INDEX idx_paiement_incomplet
--              ON commerce.paiement(id_commande) WHERE est_complete = FALSE;
--
-- APRES index : Index Scan using idx_paiement_incomplet. Le cout estime
-- chute radicalement (885.10 -> 92.91) mais le gain en temps reel est plus
-- modeste : Execution Time = 6.283 ms (vs 8.722 ms).
--
-- Conclusion : le plan change bien (Seq Scan -> Index Scan) et le cout
-- estime baisse fortement, mais le gain de temps reel est plus discret
-- car les donnees etaient deja largement en cache (buffers "shared hit"
-- eleves des deux cotes) -- le Seq Scan n'etait donc pas si couteux en
-- pratique ici. L'avantage de l'index serait plus marque sur une table
-- qui ne tiendrait pas entierement en memoire.
-- -------------------------------------------------------------
EXPLAIN ANALYZE
SELECT p.id_paiement, p.id_commande, p.mode_paiement, p.montant_paiement
FROM commerce.paiement p
WHERE p.est_complete = FALSE;
