-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 4 : les 10 requetes + analyse des plans d'execution
-- =============================================================
-- HORS DU LANCEUR : a executer A LA MAIN, une requete a la fois
-- (selectionner la requete dans le Query Tool, puis F5).
-- Les requetes 8 et 10 MODIFIENT la base : elles sont entourees de
-- BEGIN ... ROLLBACK pour la demonstration.
--
-- Choix communs (voir Doc/justification_requetes_etape4.md) :
--   - les revenus / depenses excluent les commandes « Annulée »;
--   - ils utilisent le prix FIGE (info_commande.prix_unitaire) et non
--     le prix actuel du catalogue, pour rester fideles aux ventes reelles.
--
-- Tableau de correspondance exigence -> requete
-- ---------------------------------------------------------------
--  Notion exigee                                   | Requete
-- -------------------------------------------------+-------------
--  jointure d'au moins trois tables                | 1 (aussi 2, 4)
--  agregation GROUP BY + HAVING                    | 2
--  sous-requete correlee / EXISTS                  | 3 (NOT EXISTS)
--  expression de table commune WITH                | 4
--  fonction de fenetre OVER                        | 5
--  operation ensembliste UNION/INTERSECT/EXCEPT    | 6 (UNION)
--  appel vue / vue materialisee / fonction         | 7 (mv) (+ 7b fonction)
--  ecriture parametree executee par l'application  | 8 (INSERT evaluation, app option 6)
--  JSONB : recherche par contenance @>             | 9 (index GIN)
--  JSONB : manipulation de structure imbriquee     | 10 (jsonb_set)
--  EXPLAIN ANALYZE avant / apres index             | 11 et 12
-- ---------------------------------------------------------------
-- =============================================================

SET search_path TO commerce, public;

-- =============================================================
-- Requete 1 - Jointure de trois tables
-- Question : quel est le catalogue complet, avec la categorie et les
-- specifications techniques de chaque produit?
-- =============================================================
SELECT p.id_produit,
       p.nom_produit,
       c.nom_categorie,
       p.prix_produit,
       p.quantite_totale_produit,
       sp.specifications_produit
FROM produit p
INNER JOIN categorie c              ON c.id_categorie = p.id_categorie
INNER JOIN specification_produit sp ON sp.id_produit  = p.id_produit
ORDER BY p.nom_produit;

-- =============================================================
-- Requete 2 - Agregation GROUP BY + HAVING
-- Question : quelles categories ont genere plus de 1000 $ de revenus
-- (commandes non annulees)?
-- Le seuil est a ajuster selon les donnees observees.
-- =============================================================
SELECT cat.nom_categorie,
       COUNT(DISTINCT c.id_commande)              AS nb_commandes,
       SUM(ic.quantite)                           AS unites_vendues,
       SUM(ic.quantite * ic.prix_unitaire)        AS revenu_total
FROM info_commande ic
JOIN commande c    ON c.id_commande    = ic.id_commande
JOIN statut s      ON s.id_statut      = c.id_statut
JOIN produit p     ON p.id_produit     = ic.id_produit
JOIN categorie cat ON cat.id_categorie = p.id_categorie
WHERE s.nom_statut <> 'Annulée'
GROUP BY cat.nom_categorie
HAVING SUM(ic.quantite * ic.prix_unitaire) > 1000
ORDER BY revenu_total DESC;

-- =============================================================
-- Requete 3 - Sous-requete correlee (NOT EXISTS)
-- Question : quel client (ou quels clients a egalite) a depense le
-- plus au total?
-- Un client est retenu s'il N'EXISTE PAS d'autre client ayant depense
-- plus que lui. (Meme question que la requete 5, autre technique;
-- sans fenetre, reservee a la requete 5, ni WITH, reserve a la 4.)
-- =============================================================
SELECT t.id_client,
       cl.nom_client,
       t.total_depense
FROM (SELECT c.id_client, SUM(ic.quantite * ic.prix_unitaire) AS total_depense
      FROM commande c
      JOIN info_commande ic ON ic.id_commande = c.id_commande
      JOIN statut s         ON s.id_statut    = c.id_statut
      WHERE s.nom_statut <> 'Annulée'
      GROUP BY c.id_client) t
JOIN client cl ON cl.id_client = t.id_client
WHERE NOT EXISTS (
    SELECT 1
    FROM (SELECT c2.id_client, SUM(ic2.quantite * ic2.prix_unitaire) AS total_depense
          FROM commande c2
          JOIN info_commande ic2 ON ic2.id_commande = c2.id_commande
          JOIN statut s2         ON s2.id_statut    = c2.id_statut
          WHERE s2.nom_statut <> 'Annulée'
          GROUP BY c2.id_client) t2
    WHERE t2.total_depense > t.total_depense   -- correlation avec t
);

-- =============================================================
-- Requete 4 - Expression de table commune (WITH)
-- Question : pour chaque client, combien de commandes, quelle premiere
-- et derniere date, combien depense au total et combien de produits
-- differents par commande en moyenne?
-- La CTE calcule d'abord un resume PAR COMMANDE; la requete principale
-- le regroupe ensuite PAR CLIENT.
-- =============================================================
WITH commande_totaux AS (
    SELECT c.id_commande,
           c.id_client,
           c.date_commande,
           SUM(ic.quantite * ic.prix_unitaire) AS total_commande,
           COUNT(ic.id_produit)                AS nb_produits_differents
    FROM commande c
    JOIN info_commande ic ON ic.id_commande = c.id_commande
    JOIN statut s         ON s.id_statut    = c.id_statut
    WHERE s.nom_statut <> 'Annulée'
    GROUP BY c.id_commande, c.id_client, c.date_commande
)
SELECT cl.id_client,
       cl.nom_client,
       COUNT(*)                                   AS nb_commandes,
       MIN(ct.date_commande)::DATE                AS premiere_commande,
       MAX(ct.date_commande)::DATE                AS derniere_commande,
       SUM(ct.total_commande)                     AS total_depense,
       ROUND(AVG(ct.nb_produits_differents), 2)   AS moy_produits_par_commande
FROM commande_totaux ct
JOIN client cl ON cl.id_client = ct.id_client
GROUP BY cl.id_client, cl.nom_client
ORDER BY total_depense DESC
LIMIT 20;

-- =============================================================
-- Requete 5 - Fonction de fenetre (OVER)
-- Question : quel est le classement des clients selon le montant
-- depense? (Le rang 1 correspond au resultat de la requete 3.)
-- RANK() est applique directement sur l'agregat groupe : les ex aequo
-- ont le meme rang et le rang suivant est saute.
-- =============================================================
SELECT RANK() OVER (ORDER BY SUM(ic.quantite * ic.prix_unitaire) DESC) AS rang,
       cl.id_client,
       cl.nom_client,
       SUM(ic.quantite * ic.prix_unitaire)                            AS total_depense
FROM commande c
JOIN info_commande ic ON ic.id_commande = c.id_commande
JOIN statut s         ON s.id_statut    = c.id_statut
JOIN client cl        ON cl.id_client   = c.id_client
WHERE s.nom_statut <> 'Annulée'
GROUP BY cl.id_client, cl.nom_client
ORDER BY rang
LIMIT 25;

-- =============================================================
-- Requete 6 - Operation ensembliste (UNION)
-- Question : quels clients sont « a risque », et pour quelle raison?
--   raison 1 : au moins une commande annulee;
--   raison 2 : une commande annulee a laisse derriere elle un paiement
--              non complete (autorisation jamais capturee).
-- UNION elimine les doublons A L'INTERIEUR de chaque raison (un client
-- avec plusieurs commandes annulees n'apparait qu'une fois par raison).
-- Limite : le schema ne distingue pas un paiement « echoue » d'un
-- paiement simplement pas encore complete (question ouverte #3).
-- =============================================================
SELECT cl.id_client, cl.nom_client, 'Commande annulée' AS raison
FROM client cl
JOIN commande c ON c.id_client = cl.id_client
JOIN statut s   ON s.id_statut = c.id_statut
WHERE s.nom_statut = 'Annulée'

UNION

SELECT cl.id_client, cl.nom_client, 'Paiement non complété sur une commande annulée'
FROM client cl
JOIN commande c ON c.id_client   = cl.id_client
JOIN statut s   ON s.id_statut   = c.id_statut
JOIN paiement p ON p.id_commande = c.id_commande
WHERE s.nom_statut = 'Annulée'
  AND p.est_complete = FALSE

ORDER BY nom_client, raison;

-- =============================================================
-- Requete 7 - Appel de la vue materialisee
-- Question : quels sont les 10 produits les plus vendus dans les 7
-- derniers jours (au moment du dernier rafraichissement)?
-- =============================================================
-- (facultatif) REFRESH MATERIALIZED VIEW CONCURRENTLY mv_ventes_produit_7j;
SELECT id_produit,
       nom_produit,
       nom_categorie,
       quantite_vendue_7j,
       date_rafraichissement
FROM mv_ventes_produit_7j
WHERE quantite_vendue_7j > 0
ORDER BY quantite_vendue_7j DESC, nom_produit
LIMIT 10;

-- 7b (complement) : appel de la fonction details_commande
SELECT * FROM details_commande((SELECT MAX(id_commande) FROM commande));

-- =============================================================
-- Requete 8 - Ecriture parametree executee par l'application
-- Question / operation : un client ajoute l'evaluation d'un produit
-- qu'il a achete.
-- C'est l'INSERT de l'option 6 de l'application (Actions.cs), ou les
-- valeurs sont passees en parametres Npgsql (@id_produit, @id_client,
-- @note, @commentaire), jamais concatenees dans le SQL.
-- Ici, meme requete avec PREPARE/EXECUTE ($1..$4 = parametres).
-- Le declencheur (achat obligatoire), le CHECK (note 1 a 5) et le
-- UNIQUE (une evaluation par client et produit) s'appliquent.
-- =============================================================
BEGIN;

PREPARE ajouter_evaluation (INTEGER, INTEGER, SMALLINT, TEXT) AS
INSERT INTO evaluation (id_produit, id_client, note_evaluation, commentaire_evaluation)
VALUES ($1, $2, $3, $4)
RETURNING id_evaluation, date_evaluation;

-- Un couple client-produit achete mais pas encore evalue
SELECT ic.id_produit, c.id_client
FROM info_commande ic
JOIN commande c ON c.id_commande = ic.id_commande
WHERE NOT EXISTS (SELECT 1 FROM evaluation e
                  WHERE e.id_produit = ic.id_produit AND e.id_client = c.id_client)
ORDER BY c.id_client, ic.id_produit
LIMIT 1;

-- Remplacer 1 et 1 par les valeurs obtenues ci-dessus
EXECUTE ajouter_evaluation(1, 1, 5::SMALLINT, 'Test de la requête 8');

DEALLOCATE ajouter_evaluation;
ROLLBACK;

-- 8b (complement) : recherche selon deux criteres, telle que codee
-- dans l'application (option 2) : nom du client (partiel, ILIKE) +
-- statut. Lecture parametree, pas une ecriture.
PREPARE rechercher_commandes (TEXT, TEXT) AS
SELECT cmd.id_commande, cmd.date_commande, cl.id_client, cl.nom_client,
       s.nom_statut, cmd.adresse_livraison_commande
FROM commande cmd
JOIN client cl ON cl.id_client = cmd.id_client
JOIN statut s  ON s.id_statut  = cmd.id_statut
WHERE cl.nom_client ILIKE '%' || $1 || '%'
  AND s.nom_statut  = $2
ORDER BY cl.nom_client, cmd.date_commande DESC;

EXECUTE rechercher_commandes('Tremblay', 'Livrée');
DEALLOCATE rechercher_commandes;

-- =============================================================
-- Requete 9 - JSONB : recherche par contenance (@>)
-- Question : quels produits sont d'une marque donnee?
-- Le document recherche est construit par jsonb_build_object a partir
-- d'un parametre (pas de litteral JSON en dur) : l'application
-- (option 3) y passe n'importe quelle marque.
-- Profite de l'index GIN idx_specification_produit_gin (jsonb_path_ops).
-- Marques des donnees : Aurore, Kappa, Nordik, Pixelis, Sonance, Voltra.
-- =============================================================
PREPARE produits_par_marque (TEXT) AS
SELECT p.id_produit,
       p.nom_produit,
       sp.specifications_produit ->> 'modele'        AS modele,
       sp.specifications_produit ->> 'garantie_mois' AS garantie_mois
FROM produit p
JOIN specification_produit sp ON sp.id_produit = p.id_produit
WHERE sp.specifications_produit @> jsonb_build_object('marque', $1::TEXT)
ORDER BY p.nom_produit;

EXECUTE produits_par_marque('Pixelis');
DEALLOCATE produits_par_marque;

-- =============================================================
-- Requete 10 - JSONB : manipulation d'une structure imbriquee
-- Operation : corriger UNE cle imbriquee (dimensions.largeur) d'un
-- produit sans toucher au reste du document.
-- create_missing = false : si le produit n'a pas d'objet
-- « dimensions » (ex. certains accessoires), rien n'est cree.
-- =============================================================
BEGIN;

SELECT id_produit, specifications_produit -> 'dimensions' AS avant
FROM specification_produit WHERE id_produit = 1;

UPDATE specification_produit
   SET specifications_produit = jsonb_set(specifications_produit,
                                          '{dimensions,largeur}',
                                          to_jsonb(39.8),
                                          false)
 WHERE id_produit = 1
RETURNING id_produit, specifications_produit -> 'dimensions' AS apres;

ROLLBACK;

-- =============================================================
-- 11. Analyse de plan - Candidat A : commande.id_statut
-- Requete : commandes annulees (colonne filtree dans les requetes
-- 2 a 7). Executer les blocs dans l'ordre et copier les plans.
-- =============================================================
-- 11.1 AVANT : sans index
DROP INDEX IF EXISTS idx_commande_id_statut;
ANALYZE commande;

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_commande, c.date_commande, c.id_client
FROM commande c
JOIN statut s ON s.id_statut = c.id_statut
WHERE s.nom_statut = 'Annulée';

-- 11.2 APRES : avec index
CREATE INDEX idx_commande_id_statut ON commande (id_statut);
ANALYZE commande;

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.id_commande, c.date_commande, c.id_client
FROM commande c
JOIN statut s ON s.id_statut = c.id_statut
WHERE s.nom_statut = 'Annulée';

-- =============================================================
-- 12. Analyse de plan - Candidat B : paiements non completes
-- Index PARTIEL : seules les lignes est_complete = FALSE (une petite
-- minorite) sont indexees -> index minuscule, inutile de maintenir
-- les paiements deja captures.
-- =============================================================
-- 12.1 AVANT
DROP INDEX IF EXISTS idx_paiement_incomplet;
ANALYZE paiement;

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id_paiement, p.id_commande, p.montant_paiement, p.date_paiement
FROM paiement p
WHERE p.est_complete = FALSE;

-- 12.2 APRES
CREATE INDEX idx_paiement_incomplet ON paiement (id_commande)
    WHERE est_complete = FALSE;
ANALYZE paiement;

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id_paiement, p.id_commande, p.montant_paiement, p.date_paiement
FROM paiement p
WHERE p.est_complete = FALSE;

-- Remarque : lancer chaque EXPLAIN ANALYZE deux ou trois fois et
-- garder une mesure representative (le premier passage peut lire le
-- disque; les suivants lisent le cache : « shared hit »).
