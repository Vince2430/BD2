-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 3 : vues, fonction, vue materialisee et procedure
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel"
-- (apres 01_create_schema.sql)
--   psql -U postgres -d tp1_vincent_trudel -f 04_vues_fonctions.sql
--
-- Relancable : chaque objet est supprime puis recree.
-- =============================================================

SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- 1. Vue v_commandes
--
-- Liste de TOUTES les commandes (annulees comprises) avec le nom
-- du client, la date et le libelle du statut.
-- id_commande est conserve : nom_client n'est pas UNIQUE et c'est
-- la valeur a passer a la fonction details_commande().
-- Le filtrage (statut, client, periode) se fait dans la requete
-- qui interroge la vue.
-- -------------------------------------------------------------

DROP VIEW IF EXISTS v_commandes;

CREATE VIEW v_commandes AS
SELECT
    c.id_commande,
    cl.nom_client,
    c.date_commande,
    s.nom_statut
FROM commande c
JOIN client   cl ON cl.id_client = c.id_client
JOIN statut   s  ON s.id_statut  = c.id_statut
ORDER BY c.date_commande DESC;

-- -------------------------------------------------------------
-- 2. Vue v_receptions_attendues
--
-- Receptions NON completees (est_complete = FALSE), une ligne par
-- reception, avec le total d'unites attendues.
-- LEFT JOIN + COALESCE : une reception encore sans ligne apparait
-- quand meme, avec un total de 0.
-- Le detail d'une reception se consulte dans l'application par une
-- requete parametree sur info_reception (filtre id_reception).
-- -------------------------------------------------------------

DROP VIEW IF EXISTS v_receptions_attendues;

CREATE VIEW v_receptions_attendues AS
SELECT
    r.id_reception,
    r.numero_reception,
    r.date_prevue_reception,
    COALESCE(SUM(ir.quantite_recu), 0) AS total_unites_attendues
FROM reception r
LEFT JOIN info_reception ir ON ir.id_reception = r.id_reception
WHERE r.est_complete = FALSE
GROUP BY r.id_reception, r.numero_reception, r.date_prevue_reception
ORDER BY r.date_prevue_reception;

-- -------------------------------------------------------------
-- 3. Fonction details_commande(p_id_commande)
--
-- Retourne une ligne par produit de la commande : nom du produit,
-- quantite commandee, prix unitaire fige au moment de la commande et
-- sous-total (quantite x prix unitaire).
-- Le total de la commande est calcule par l'application (somme des
-- sous-totaux).
--
-- Commande inexistante : exception avec SQLSTATE P0002
-- (no_data_found), que l'application pourra reconnaitre.
-- Commande existante sans ligne : resultat vide (pas d'erreur).
--
-- Les colonnes retournees ne portent pas le nom d'une colonne de
-- table (produit, quantite_commandee, prix_unitaire_fige, sous_total)
-- pour eviter toute ambiguite entre variable PL/pgSQL et colonne.
-- STABLE : la fonction ne modifie rien.
-- -------------------------------------------------------------

DROP FUNCTION IF EXISTS details_commande(INTEGER);

CREATE FUNCTION details_commande(p_id_commande INTEGER)
RETURNS TABLE (
    produit            VARCHAR(100),
    quantite_commandee INTEGER,
    prix_unitaire_fige NUMERIC(10,2),
    sous_total         NUMERIC(12,2)
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM commande c WHERE c.id_commande = p_id_commande) THEN
        RAISE EXCEPTION 'La commande % n''existe pas.', p_id_commande
            USING ERRCODE = 'P0002';
    END IF;

    RETURN QUERY
    SELECT
        p.nom_produit,
        ic.quantite,
        ic.prix_unitaire,
        (ic.quantite * ic.prix_unitaire)::NUMERIC(12,2)
    FROM info_commande ic
    JOIN produit p ON p.id_produit = ic.id_produit
    WHERE ic.id_commande = p_id_commande
    ORDER BY p.nom_produit;
END;
$$;

-- -------------------------------------------------------------
-- 4. Vue materialisee mv_ventes_produit_7j
--
-- Une ligne par produit : toutes ses informations (sauf les
-- specifications JSONB) et la quantite vendue dans les 7 derniers
-- jours, commandes annulees exclues.
-- Les 7 jours sont comptes a partir du moment du REFRESH (photo);
-- date_rafraichissement indique de quand datent les chiffres.
-- LEFT JOIN + COALESCE : un produit sans vente apparait avec 0.
-- L'index UNIQUE permet REFRESH ... CONCURRENTLY (lecture non
-- bloquee pendant le rafraichissement).
-- -------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_ventes_produit_7j;

CREATE MATERIALIZED VIEW mv_ventes_produit_7j AS
SELECT
    p.id_produit,
    p.nom_produit,
    cat.nom_categorie,
    p.prix_produit,
    p.cout_procuration_produit,
    p.quantite_totale_produit,
    COALESCE(v.quantite_vendue, 0) AS quantite_vendue_7j,
    LOCALTIMESTAMP                 AS date_rafraichissement
FROM produit p
JOIN categorie cat ON cat.id_categorie = p.id_categorie
LEFT JOIN (
    SELECT
        ic.id_produit,
        SUM(ic.quantite) AS quantite_vendue
    FROM info_commande ic
    JOIN commande c ON c.id_commande = ic.id_commande
    JOIN statut   s ON s.id_statut   = c.id_statut
    WHERE c.date_commande >= LOCALTIMESTAMP - INTERVAL '7 days'
      AND s.nom_statut <> 'Annulée'
    GROUP BY ic.id_produit
) v ON v.id_produit = p.id_produit;

CREATE UNIQUE INDEX uq_mv_ventes_produit_7j
    ON mv_ventes_produit_7j (id_produit);

-- Rafraichissement, planifie chaque nuit (pgAgent ou cron, voir README) :
-- REFRESH MATERIALIZED VIEW CONCURRENTLY commerce.mv_ventes_produit_7j;

-- -------------------------------------------------------------
-- 5. Procedure avancer_commande(p_id_commande, p_camion)
--
-- Fait passer une commande au statut SUIVANT de son cycle de vie,
-- en effectuant le travail propre a chaque etape :
--   En attente     -> Payée          : changement de statut seulement
--   Payée          -> En préparation : changement de statut seulement
--   En préparation -> Expédiée       : cree une expedition (date prevue
--                                      = aujourd'hui, camion facultatif)
--                                      et une ligne info_expedition par
--                                      produit pour la quantite restante
--   Expédiée       -> Livrée         : complete les expeditions de la
--                                      commande (est_complete + date)
--
-- Les regles (ordre des statuts, paiement complete pour "Payée",
-- quantites couvertes pour "Expédiée", expeditions completees pour
-- "Livrée") sont GARANTIES par trg_proteger_commande : la procedure
-- fait l'operation, le declencheur la valide.
--
-- Tout est atomique : si une etape echoue (exception de la procedure
-- ou d'un declencheur), toutes ses modifications sont annulees.
-- FOR UPDATE verrouille la commande : deux appels simultanes sur la
-- meme commande s'executent l'un apres l'autre.
--
-- Limite : une expedition peut regrouper plusieurs commandes (meme
-- camion, meme date, comme dans le jeu de donnees). La completer a la
-- livraison d'une commande la complete aussi pour les autres.
--
-- Appel : CALL avancer_commande(42);
--         CALL avancer_commande(42, 'CAM-02');
-- -------------------------------------------------------------

DROP PROCEDURE IF EXISTS avancer_commande(INTEGER, VARCHAR);

CREATE PROCEDURE avancer_commande(
    p_id_commande INTEGER,
    p_camion      VARCHAR(50) DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_actuel        VARCHAR(30);
    v_suivant       VARCHAR(30);
    v_id_expedition INTEGER;
BEGIN
    -- Etape 1 : la commande existe; statut actuel (commande verrouillee)
    SELECT s.nom_statut
      INTO v_actuel
      FROM commande c
      JOIN statut   s ON s.id_statut = c.id_statut
     WHERE c.id_commande = p_id_commande
       FOR UPDATE OF c;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La commande % n''existe pas.', p_id_commande
            USING ERRCODE = 'P0002';
    END IF;

    -- Etape 2 : statut suivant
    v_suivant := CASE v_actuel
                     WHEN 'En attente'     THEN 'Payée'
                     WHEN 'Payée'          THEN 'En préparation'
                     WHEN 'En préparation' THEN 'Expédiée'
                     WHEN 'Expédiée'       THEN 'Livrée'
                 END;

    IF v_suivant IS NULL THEN
        RAISE EXCEPTION 'La commande % a le statut "%" : elle ne peut plus avancer.',
            p_id_commande, v_actuel
            USING ERRCODE = 'check_violation';
    END IF;

    -- Etape 3 : travail propre a la transition
    IF v_suivant = 'Expédiée' THEN
        -- Expedition creee seulement s'il reste quelque chose a envoyer
        IF EXISTS (
            SELECT 1
              FROM info_commande ic
             WHERE ic.id_commande = p_id_commande
               AND ic.quantite > (SELECT COALESCE(SUM(ie.quantite_expediee), 0)
                                    FROM info_expedition ie
                                   WHERE ie.id_info_commande = ic.id_info_commande)
        ) THEN
            INSERT INTO expedition (date_prevue_expedition, camion_expedition)
            VALUES (CURRENT_DATE, p_camion)
            RETURNING id_expedition INTO v_id_expedition;

            INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
            SELECT ic.id_info_commande,
                   v_id_expedition,
                   ic.quantite - COALESCE(SUM(ie.quantite_expediee), 0)
              FROM info_commande ic
              LEFT JOIN info_expedition ie ON ie.id_info_commande = ic.id_info_commande
             WHERE ic.id_commande = p_id_commande
             GROUP BY ic.id_info_commande, ic.quantite
            HAVING ic.quantite - COALESCE(SUM(ie.quantite_expediee), 0) > 0;
        END IF;

    ELSIF v_suivant = 'Livrée' THEN
        UPDATE expedition e
           SET est_complete             = TRUE,
               date_complete_expedition = LOCALTIMESTAMP
         WHERE NOT e.est_complete
           AND e.id_expedition IN (SELECT ie.id_expedition
                                     FROM info_expedition ie
                                     JOIN info_commande  ic ON ic.id_info_commande = ie.id_info_commande
                                    WHERE ic.id_commande = p_id_commande);
    END IF;

    -- Etape 4 : changement de statut (valide par trg_proteger_commande,
    -- journalise par trg_audit_statut_commande)
    UPDATE commande
       SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = v_suivant)
     WHERE id_commande = p_id_commande;

    RAISE NOTICE 'Commande % : "%" -> "%".', p_id_commande, v_actuel, v_suivant;
END;
$$;
