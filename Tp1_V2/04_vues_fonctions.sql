-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 4 (scripts) : vues, vue materialisee, fonction, procedure
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel"
--   psql -U postgres -d tp1_vincent_trudel -f 04_vues_fonctions.sql
--
-- Les objets sont supprimes puis recrees : relancer 05_roles.sql
-- apres ce script (les privileges disparaissent avec l'objet).
-- =============================================================

SET search_path TO commerce, public;

DROP VIEW              IF EXISTS v_commandes;
DROP VIEW              IF EXISTS v_receptions_attendues;
DROP MATERIALIZED VIEW IF EXISTS mv_ventes_produit_7j;
DROP FUNCTION          IF EXISTS details_commande(INTEGER);
DROP PROCEDURE         IF EXISTS avancer_commande(INTEGER, VARCHAR);

-- -------------------------------------------------------------
-- Vue 1 : v_commandes
-- Liste de toutes les commandes avec le nom du client et le statut
-- lisible, les plus recentes d'abord. Utilisee par l'application
-- (option 1) : elle cache les deux jointures.
-- -------------------------------------------------------------
CREATE VIEW v_commandes AS
SELECT c.id_commande,
       cl.nom_client,
       c.date_commande,
       s.nom_statut
FROM commande c
JOIN client cl ON cl.id_client = c.id_client
JOIN statut s  ON s.id_statut  = c.id_statut
ORDER BY c.date_commande DESC;

-- -------------------------------------------------------------
-- Vue 2 : v_receptions_attendues
-- Receptions fournisseur pas encore validees : une ligne par
-- reception, avec le nombre de produits et le total d'unites attendues.
-- -------------------------------------------------------------
CREATE VIEW v_receptions_attendues AS
SELECT r.id_reception,
       r.fournisseur_reception,
       r.date_prevue_reception,
       COUNT(ir.id_info_reception)             AS nb_produits,
       COALESCE(SUM(ir.quantite_attendue), 0)  AS total_unites_attendues
FROM reception r
LEFT JOIN info_reception ir ON ir.id_reception = r.id_reception
WHERE r.est_complete = FALSE
GROUP BY r.id_reception, r.fournisseur_reception, r.date_prevue_reception
ORDER BY r.date_prevue_reception;

-- -------------------------------------------------------------
-- Vue materialisee : mv_ventes_produit_7j
-- Une ligne par produit (y compris ceux sans vente) : quantite vendue
-- dans les 7 jours precedant le dernier rafraichissement, commandes
-- annulees exclues. La date du calcul est conservee.
--
-- L'index UNIQUE permet REFRESH ... CONCURRENTLY (les lecteurs ne
-- sont pas bloques pendant le rafraichissement).
--
-- Commande de rafraichissement :
--   REFRESH MATERIALIZED VIEW CONCURRENTLY commerce.mv_ventes_produit_7j;
-- Planification : job pgAgent « refresh_mv_ventes_produits_7j »
-- (base postgres, etape SQL locale, tous les jours a 02:00), ou cron
-- (voir README.md).
-- -------------------------------------------------------------
CREATE MATERIALIZED VIEW mv_ventes_produit_7j AS
SELECT p.id_produit,
       p.nom_produit,
       cat.nom_categorie,
       p.prix_produit,
       COALESCE(v.quantite_vendue, 0)::INTEGER AS quantite_vendue_7j,
       LOCALTIMESTAMP(0)                       AS date_rafraichissement
FROM produit p
JOIN categorie cat ON cat.id_categorie = p.id_categorie
LEFT JOIN (
    SELECT ic.id_produit, SUM(ic.quantite) AS quantite_vendue
    FROM info_commande ic
    JOIN commande c ON c.id_commande = ic.id_commande
    JOIN statut s   ON s.id_statut   = c.id_statut
    WHERE c.date_commande >= LOCALTIMESTAMP - INTERVAL '7 days'
      AND s.nom_statut <> 'Annulée'
    GROUP BY ic.id_produit
) v ON v.id_produit = p.id_produit;

CREATE UNIQUE INDEX ux_mv_ventes_produit_7j ON mv_ventes_produit_7j (id_produit);

-- -------------------------------------------------------------
-- Fonction : details_commande(p_id_commande)
-- Retourne les lignes d'une commande : produit, quantite, prix
-- unitaire FIGE au moment de la commande, sous-total.
-- STABLE : ne modifie rien et donne le meme resultat dans une meme
-- requete. Commande inexistante -> erreur P0002 (no_data_found),
-- pour la distinguer d'une commande existante sans ligne.
-- -------------------------------------------------------------
CREATE FUNCTION details_commande(p_id_commande INTEGER)
RETURNS TABLE (
    produit            VARCHAR,
    quantite_commandee INTEGER,
    prix_unitaire_fige NUMERIC,
    sous_total         NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM commande c WHERE c.id_commande = p_id_commande) THEN
        RAISE EXCEPTION 'La commande % n''existe pas.', p_id_commande
            USING ERRCODE = 'no_data_found';
    END IF;

    RETURN QUERY
    SELECT p.nom_produit::VARCHAR,
           ic.quantite,
           ic.prix_unitaire::NUMERIC,
           (ic.quantite * ic.prix_unitaire)::NUMERIC
    FROM info_commande ic
    JOIN produit p ON p.id_produit = ic.id_produit
    WHERE ic.id_commande = p_id_commande
    ORDER BY p.nom_produit;
END;
$$;

-- -------------------------------------------------------------
-- Procedure : avancer_commande(p_id_commande, p_camion)
-- Operation metier en plusieurs etapes : fait passer la commande au
-- statut suivant en faisant le travail de l'etape.
--   En attente     -> Payee          : le declencheur verifie les paiements (regle g)
--   Payee          -> En preparation : changement de statut seulement
--   En preparation -> Expediee       : cree UNE expedition (camion facultatif)
--                                      pour toutes les quantites restantes
--   Expediee       -> Livree         : complete les expeditions de la commande
-- La commande est verrouillee (FOR UPDATE) : deux appels simultanes ne
-- peuvent pas la faire avancer deux fois. Tout est atomique : si une
-- etape echoue, rien n'est conserve (l'appel CALL est une seule
-- instruction).
-- -------------------------------------------------------------
CREATE PROCEDURE avancer_commande(p_id_commande INTEGER,
                                  p_camion      VARCHAR DEFAULT NULL)
LANGUAGE plpgsql
AS $$
DECLARE
    v_statut   VARCHAR(30);
    v_suivant  VARCHAR(30);
    v_id_exp   INTEGER;
    v_restant  INTEGER;
    v_nb       INTEGER;
BEGIN
    SELECT s.nom_statut
      INTO v_statut
      FROM commande c
      JOIN statut s ON s.id_statut = c.id_statut
     WHERE c.id_commande = p_id_commande
       FOR UPDATE OF c;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'La commande % n''existe pas.', p_id_commande
            USING ERRCODE = 'no_data_found';
    END IF;

    v_suivant := CASE v_statut
                     WHEN 'En attente'     THEN 'Payée'
                     WHEN 'Payée'          THEN 'En préparation'
                     WHEN 'En préparation' THEN 'Expédiée'
                     WHEN 'Expédiée'       THEN 'Livrée'
                 END;

    IF v_suivant IS NULL THEN
        RAISE EXCEPTION 'La commande % est « % » : elle ne peut plus avancer.',
            p_id_commande, v_statut
            USING ERRCODE = 'check_violation';
    END IF;

    IF v_suivant = 'Expédiée' THEN
        -- Unites qui restent a expedier
        SELECT COALESCE(SUM(ic.quantite - COALESCE(e.deja, 0)), 0)
          INTO v_restant
          FROM info_commande ic
          LEFT JOIN (SELECT id_info_commande, SUM(quantite_expediee) AS deja
                     FROM info_expedition
                     GROUP BY id_info_commande) e
                 ON e.id_info_commande = ic.id_info_commande
         WHERE ic.id_commande = p_id_commande;

        IF v_restant > 0 THEN
            INSERT INTO expedition (date_prevue_expedition, camion_expedition)
            VALUES (CURRENT_DATE, NULLIF(btrim(p_camion), ''))
            RETURNING id_expedition INTO v_id_exp;

            INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
            SELECT ic.id_info_commande,
                   v_id_exp,
                   ic.quantite - COALESCE(e.deja, 0)
              FROM info_commande ic
              LEFT JOIN (SELECT id_info_commande, SUM(quantite_expediee) AS deja
                         FROM info_expedition
                         GROUP BY id_info_commande) e
                     ON e.id_info_commande = ic.id_info_commande
             WHERE ic.id_commande = p_id_commande
               AND ic.quantite - COALESCE(e.deja, 0) > 0;

            GET DIAGNOSTICS v_nb = ROW_COUNT;
            RAISE NOTICE 'Expedition % creee : % ligne(s), % unite(s).',
                v_id_exp, v_nb, v_restant;
        END IF;

    ELSIF v_suivant = 'Livrée' THEN
        UPDATE expedition e
           SET est_complete = TRUE,
               date_complete_expedition = LOCALTIMESTAMP
         WHERE NOT e.est_complete
           AND e.id_expedition IN (SELECT ie.id_expedition
                                   FROM info_expedition ie
                                   JOIN info_commande ic
                                     ON ic.id_info_commande = ie.id_info_commande
                                   WHERE ic.id_commande = p_id_commande);

        GET DIAGNOSTICS v_nb = ROW_COUNT;
        RAISE NOTICE '% expedition(s) marquee(s) comme completee(s).', v_nb;
    END IF;

    -- Le declencheur trg_proteger_commande verifie la transition.
    UPDATE commande
       SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = v_suivant)
     WHERE id_commande = p_id_commande;

    RAISE NOTICE 'Commande % : « % » -> « % ».', p_id_commande, v_statut, v_suivant;
END;
$$;

-- -------------------------------------------------------------
-- Verification rapide
-- -------------------------------------------------------------
SELECT * FROM v_commandes LIMIT 5;
SELECT * FROM v_receptions_attendues;
SELECT * FROM mv_ventes_produit_7j ORDER BY quantite_vendue_7j DESC LIMIT 5;
SELECT * FROM details_commande((SELECT MIN(id_commande) FROM commande));
