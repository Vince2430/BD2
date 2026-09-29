-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 6 : tests automatises (17 tests, T01 a T17)
-- =============================================================
-- A EXECUTER APRES creer_bd.command (00 a 05), en superutilisateur.
--
--   Recommande : lancer_tests.command (double-clic) -> [OK]/[ECHEC]
--                pour chaque test + bilan.
--   psql       : psql -X -v ON_ERROR_STOP=1 -d tp1_vincent_trudel -f 08_tests.sql
--   pgAdmin    : coller le fichier dans le Query Tool, F5
--                (s'arrete au premier test en echec).
--
-- Fonctionnement
--   - Tout se passe dans UNE transaction terminee par ROLLBACK : la
--     base n'est jamais modifiee par les tests.
--   - Les tests creent leurs propres donnees (produits, clients et
--     4 commandes : cycle, a_annuler, paiement_partiel, gestionnaire).
--     Leurs id sont gardes dans des parametres de session tst.id_*
--     (set_config(..., TRUE) = local a la transaction), lisibles meme
--     apres SET ROLE, contrairement a une table temporaire.
--   - Chaque test est un bloc DO : il affiche « [OK] Txx » ou echoue
--     avec « [ECHEC] Txx : raison ».
--   - Un refus attendu est teste dans un bloc BEGIN ... EXCEPTION
--     (point de sauvegarde implicite) qui n'attrape QUE l'erreur
--     attendue (SQLSTATE).
--   - Les tests sont sequentiels : T05 ajoute une ligne a la commande
--     utilisee par T14; T10 et T13 font avancer la commande « cycle ».
--
-- Codes SQLSTATE : 23514 check_violation (CHECK et regles metier des
-- declencheurs), 23503 foreign_key_violation, 23505 unique_violation,
-- P0002 no_data_found, 42501 insufficient_privilege.
-- =============================================================

SET search_path TO commerce, public;
SET client_min_messages TO notice;

BEGIN;

-- -------------------------------------------------------------
-- Outils de test (temporaires, disparaissent avec la session)
-- -------------------------------------------------------------
SELECT set_config('tst.reussis', '0', TRUE);

CREATE FUNCTION pg_temp.ok(p_test TEXT, p_libelle TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('tst.reussis',
                       (current_setting('tst.reussis')::INTEGER + 1)::TEXT, TRUE);
    RAISE NOTICE '[OK] % : %', p_test, p_libelle;
END;
$$;

CREATE FUNCTION pg_temp.verifier(p_condition BOOLEAN, p_message TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_condition IS NOT TRUE THEN
        RAISE EXCEPTION '%', p_message;
    END IF;
END;
$$;

CREATE FUNCTION pg_temp.id(p_nom TEXT)
RETURNS INTEGER
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting('tst.id_' || p_nom)::INTEGER;
$$;

-- -------------------------------------------------------------
-- Donnees de test
--   Produit test A : 100 $, stock 10    Produit test B : 50 $, stock 5
--   4 commandes du client test, chacune : 1 x produit A (100 $) et
--   une autorisation de 100 $ (deja capturee pour « gestionnaire »).
--   Apres ce bloc : stock A = 6.
-- -------------------------------------------------------------
DO $$
DECLARE
    v_cat     INTEGER;
    v_attente INTEGER;
    v_prod_a  INTEGER;
    v_prod_b  INTEGER;
    v_client  INTEGER;
    v_client2 INTEGER;
    v_cmd     INTEGER;
    v_nom     TEXT;
BEGIN
    SELECT MIN(id_categorie) INTO v_cat FROM categorie;
    SELECT id_statut INTO v_attente FROM statut WHERE nom_statut = 'En attente';

    INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit,
                         quantite_totale_produit, id_categorie)
    VALUES ('Produit test A', 100.00, 60.00, 10, v_cat)
    RETURNING id_produit INTO v_prod_a;

    INSERT INTO specification_produit (id_produit, specifications_produit)
    VALUES (v_prod_a, '{"marque":"MarqueTest","modele":"A","connectivite":["USB-C"]}');

    INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit,
                         quantite_totale_produit, id_categorie)
    VALUES ('Produit test B', 50.00, 30.00, 5, v_cat)
    RETURNING id_produit INTO v_prod_b;

    INSERT INTO client (nom_client, courriel_client, hash_mot_passe_client, adresse_client)
    VALUES ('Client Test', 'client.test@exemple.test', 'sha256$test',
            '1 rue du Test, Joliette (QC) J6E 1A1')
    RETURNING id_client INTO v_client;

    INSERT INTO client (nom_client, courriel_client, hash_mot_passe_client)
    VALUES ('Client Sans Achat', 'sans.achat@exemple.test', 'sha256$test')
    RETURNING id_client INTO v_client2;

    FOREACH v_nom IN ARRAY ARRAY['cycle', 'a_annuler', 'paiement_partiel', 'gestionnaire']
    LOOP
        INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
        VALUES ('1 rue du Test, Joliette (QC) J6E 1A1', v_client, v_attente)
        RETURNING id_commande INTO v_cmd;

        INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire)
        VALUES (v_cmd, v_prod_a, 1, 100.00);

        INSERT INTO paiement (id_commande, mode_paiement, date_paiement,
                              montant_paiement, est_complete)
        VALUES (v_cmd, 'Carte de crédit', LOCALTIMESTAMP, 100.00, v_nom = 'gestionnaire');

        PERFORM set_config('tst.id_' || v_nom, v_cmd::TEXT, TRUE);
    END LOOP;

    PERFORM set_config('tst.id_produit_a',       v_prod_a::TEXT,  TRUE);
    PERFORM set_config('tst.id_produit_b',       v_prod_b::TEXT,  TRUE);
    PERFORM set_config('tst.id_client',          v_client::TEXT,  TRUE);
    PERFORM set_config('tst.id_client_sans_achat', v_client2::TEXT, TRUE);

    RAISE NOTICE 'Donnees de test pretes (commandes % a %).',
        pg_temp.id('cycle'), pg_temp.id('gestionnaire');
END;
$$;

-- =============================================================
-- CONTRAINTES
-- =============================================================

-- T01 CHECK : un prix doit etre positif
DO $$
BEGIN
    BEGIN
        INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit, id_categorie)
        VALUES ('Prix invalide', 0, 0, (SELECT MIN(id_categorie) FROM categorie));
        RAISE EXCEPTION 'un prix de 0 $ a ete accepte';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    PERFORM pg_temp.ok('T01', 'CHECK prix_produit > 0 refuse un prix de 0 $');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T01 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T02 FK : une commande doit viser un client existant
DO $$
BEGIN
    BEGIN
        INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
        VALUES ('Nulle part', -1, (SELECT id_statut FROM statut WHERE nom_statut = 'En attente'));
        RAISE EXCEPTION 'une commande pour le client -1 a ete acceptee';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    PERFORM pg_temp.ok('T02', 'FK commande.id_client refuse un client inexistant');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T02 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T03 UNIQUE : deux clients ne partagent pas un courriel
DO $$
BEGIN
    BEGIN
        INSERT INTO client (nom_client, courriel_client, hash_mot_passe_client)
        VALUES ('Doublon', 'client.test@exemple.test', 'x');
        RAISE EXCEPTION 'un courriel en double a ete accepte';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    PERFORM pg_temp.ok('T03', 'UNIQUE courriel_client refuse un doublon');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T03 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T04 JSONB : proprietes essentielles des specifications
--   a) sans « connectivite » (viole 2 contraintes) -> la contrainte
--      signalee est ck_spec_cles_obligatoires (la premiere par ordre
--      alphabetique);
--   b) « connectivite » qui n'est pas un tableau -> ck_spec_connectivite_tableau.
DO $$
DECLARE
    v_contrainte TEXT;
BEGIN
    BEGIN
        INSERT INTO specification_produit (id_produit, specifications_produit)
        VALUES (pg_temp.id('produit_b'), '{"marque":"MarqueTest","modele":"B"}');
        RAISE EXCEPTION 'un document sans connectivite a ete accepte';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_contrainte = CONSTRAINT_NAME;
    END;
    PERFORM pg_temp.verifier(v_contrainte = 'ck_spec_cles_obligatoires',
        format('contrainte signalee : %s', v_contrainte));

    BEGIN
        INSERT INTO specification_produit (id_produit, specifications_produit)
        VALUES (pg_temp.id('produit_b'),
                '{"marque":"MarqueTest","modele":"B","connectivite":"USB-C"}');
        RAISE EXCEPTION 'une connectivite qui n''est pas un tableau a ete acceptee';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_contrainte = CONSTRAINT_NAME;
    END;
    PERFORM pg_temp.verifier(v_contrainte = 'ck_spec_connectivite_tableau',
        format('contrainte signalee : %s', v_contrainte));

    PERFORM pg_temp.ok('T04', 'contraintes JSONB (cles obligatoires, tableau)');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T04 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- =============================================================
-- DECLENCHEURS
-- =============================================================

-- T05 Stock : une ligne de commande diminue le stock; une quantite
--     superieure au stock est refusee avec un message clair.
--     (Ajoute 2 x produit B a la commande « paiement_partiel » : total 200 $.)
DO $$
DECLARE
    v_stock INTEGER;
    v_msg   TEXT;
BEGIN
    SELECT quantite_totale_produit INTO v_stock FROM produit WHERE id_produit = pg_temp.id('produit_a');
    PERFORM pg_temp.verifier(v_stock = 6, format('stock A attendu 6, obtenu %s', v_stock));

    INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire)
    VALUES (pg_temp.id('paiement_partiel'), pg_temp.id('produit_b'), 2, 50.00);

    SELECT quantite_totale_produit INTO v_stock FROM produit WHERE id_produit = pg_temp.id('produit_b');
    PERFORM pg_temp.verifier(v_stock = 3, format('stock B attendu 3, obtenu %s', v_stock));

    BEGIN
        INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire)
        VALUES (pg_temp.id('cycle'), pg_temp.id('produit_b'), 99, 50.00);
        RAISE EXCEPTION '99 unites acceptees pour un stock de 3';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    END;
    PERFORM pg_temp.verifier(v_msg LIKE 'Stock insuffisant%', format('message : %s', v_msg));

    PERFORM pg_temp.ok('T05', 'stock decremente, survente refusee');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T05 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T06 Evaluation : reservee aux acheteurs, une seule par client et produit
DO $$
BEGIN
    BEGIN
        INSERT INTO evaluation (id_produit, id_client, note_evaluation)
        VALUES (pg_temp.id('produit_a'), pg_temp.id('client_sans_achat'), 5);
        RAISE EXCEPTION 'un client sans achat a pu evaluer';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    INSERT INTO evaluation (id_produit, id_client, note_evaluation, commentaire_evaluation)
    VALUES (pg_temp.id('produit_a'), pg_temp.id('client'), 4, 'Test');

    BEGIN
        INSERT INTO evaluation (id_produit, id_client, note_evaluation)
        VALUES (pg_temp.id('produit_a'), pg_temp.id('client'), 3);
        RAISE EXCEPTION 'une deuxieme evaluation du meme produit a ete acceptee';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    PERFORM pg_temp.ok('T06', 'evaluation : achat obligatoire + une seule par produit');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T06 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T07 Reception : la validation ajoute au stock, puis la reception est figee
DO $$
DECLARE
    v_rec   INTEGER;
    v_stock INTEGER;
BEGIN
    INSERT INTO reception (fournisseur_reception, date_prevue_reception)
    VALUES ('Fournisseur test', CURRENT_DATE)
    RETURNING id_reception INTO v_rec;

    INSERT INTO info_reception (id_reception, id_produit, quantite_attendue)
    VALUES (v_rec, pg_temp.id('produit_b'), 20);

    SELECT quantite_totale_produit INTO v_stock FROM produit WHERE id_produit = pg_temp.id('produit_b');
    PERFORM pg_temp.verifier(v_stock = 3, format('stock B avant validation : %s (attendu 3)', v_stock));

    UPDATE reception SET est_complete = TRUE, date_complete_reception = LOCALTIMESTAMP
     WHERE id_reception = v_rec;

    SELECT quantite_totale_produit INTO v_stock FROM produit WHERE id_produit = pg_temp.id('produit_b');
    PERFORM pg_temp.verifier(v_stock = 23, format('stock B apres validation : %s (attendu 23)', v_stock));

    BEGIN
        UPDATE reception SET fournisseur_reception = 'Autre' WHERE id_reception = v_rec;
        RAISE EXCEPTION 'une reception validee a ete modifiee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO info_reception (id_reception, id_produit, quantite_attendue)
        VALUES (v_rec, pg_temp.id('produit_a'), 5);
        RAISE EXCEPTION 'une ligne a ete ajoutee a une reception validee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    PERFORM pg_temp.ok('T07', 'reception validee : stock ajoute, reception figee');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T07 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T08 Expedition : on n'expedie pas plus que la quantite commandee
DO $$
DECLARE
    v_exp INTEGER;
BEGIN
    INSERT INTO expedition (date_prevue_expedition) VALUES (CURRENT_DATE)
    RETURNING id_expedition INTO v_exp;

    BEGIN
        INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
        SELECT id_info_commande, v_exp, 2
        FROM info_commande WHERE id_commande = pg_temp.id('cycle');
        RAISE EXCEPTION '2 unites expediees pour 1 commandee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    PERFORM pg_temp.ok('T08', 'quantite expediee <= quantite commandee');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T08 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T09 Cycle de vie (trg_proteger_commande) : regles a, b, f et g
DO $$
BEGIN
    -- f) pas de saut d'etape
    BEGIN
        UPDATE commande SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Expédiée')
         WHERE id_commande = pg_temp.id('cycle');
        RAISE EXCEPTION 'passage direct En attente -> Expediee accepte';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- g) pas de « Payee » sans paiement complete
    BEGIN
        UPDATE commande SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
         WHERE id_commande = pg_temp.id('cycle');
        RAISE EXCEPTION 'commande payee sans paiement complete';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- a) jamais de suppression
    BEGIN
        DELETE FROM commande WHERE id_commande = pg_temp.id('cycle');
        RAISE EXCEPTION 'une commande a ete supprimee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- b) une nouvelle commande commence « En attente »
    BEGIN
        INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
        VALUES ('x', pg_temp.id('client'), (SELECT id_statut FROM statut WHERE nom_statut = 'Livrée'));
        RAISE EXCEPTION 'une commande a ete creee directement « Livree »';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    PERFORM pg_temp.ok('T09', 'cycle de vie : saut, paiement manquant, DELETE et INSERT refuses');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T09 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T10 Audit : la creation et chaque changement de statut sont conserves
--     (capture du paiement de « cycle », puis passage a « Payee »)
DO $$
DECLARE
    v_audit audit_statut_commande%ROWTYPE;
    v_nb    INTEGER;
BEGIN
    UPDATE paiement SET est_complete = TRUE, date_paiement = LOCALTIMESTAMP
     WHERE id_commande = pg_temp.id('cycle');

    UPDATE commande SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
     WHERE id_commande = pg_temp.id('cycle');

    SELECT COUNT(*) INTO v_nb FROM audit_statut_commande
     WHERE id_commande = pg_temp.id('cycle');
    PERFORM pg_temp.verifier(v_nb = 2, format('%s ligne(s) d''audit, 2 attendues', v_nb));

    SELECT * INTO v_audit FROM audit_statut_commande
     WHERE id_commande = pg_temp.id('cycle')
     ORDER BY id_audit DESC LIMIT 1;

    PERFORM pg_temp.verifier(
        v_audit.operation = 'UPDATE'
        AND v_audit.ancien_statut = 'En attente'
        AND v_audit.nouveau_statut = 'Payée'
        AND v_audit.utilisateur = current_user
        AND v_audit.date_operation IS NOT NULL,
        format('ligne d''audit inattendue : %s', row_to_json(v_audit)));

    PERFORM pg_temp.ok('T10', 'audit : operation, ancien/nouveau statut, date, utilisateur');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T10 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T11 Annulation : le stock est rendu, puis la commande est figee
DO $$
DECLARE
    v_avant INTEGER;
    v_apres INTEGER;
BEGIN
    SELECT quantite_totale_produit INTO v_avant FROM produit WHERE id_produit = pg_temp.id('produit_a');

    UPDATE commande SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Annulée')
     WHERE id_commande = pg_temp.id('a_annuler');

    SELECT quantite_totale_produit INTO v_apres FROM produit WHERE id_produit = pg_temp.id('produit_a');
    PERFORM pg_temp.verifier(v_apres = v_avant + 1,
        format('stock A : %s avant, %s apres (attendu +1)', v_avant, v_apres));

    BEGIN
        UPDATE commande SET adresse_livraison_commande = 'Autre adresse'
         WHERE id_commande = pg_temp.id('a_annuler');
        RAISE EXCEPTION 'une commande annulee a ete modifiee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire)
        VALUES (pg_temp.id('a_annuler'), pg_temp.id('produit_b'), 1, 50.00);
        RAISE EXCEPTION 'une ligne a ete ajoutee a une commande annulee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    PERFORM pg_temp.ok('T11', 'annulation : stock rendu, commande et lignes figees');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T11 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- =============================================================
-- ROUTINES
-- =============================================================

-- T12 Fonction details_commande : lignes, prix fige, sous-totaux; P0002
DO $$
DECLARE
    v_nb    INTEGER;
    v_total NUMERIC;
BEGIN
    SELECT COUNT(*), SUM(sous_total) INTO v_nb, v_total
    FROM details_commande(pg_temp.id('paiement_partiel'));
    PERFORM pg_temp.verifier(v_nb = 2 AND v_total = 200.00,
        format('%s ligne(s), total %s (attendu 2 lignes, 200.00)', v_nb, v_total));

    BEGIN
        PERFORM * FROM details_commande(-1);
        RAISE EXCEPTION 'aucune erreur pour une commande inexistante';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    PERFORM pg_temp.ok('T12', 'details_commande : 2 lignes, 200 $; inexistante -> P0002');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T12 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T13 Procedure avancer_commande : « cycle » (Payee) -> En preparation
--     -> Expediee (expedition creee) -> Livree (expedition completee);
--     une commande livree ne peut plus avancer.
DO $$
DECLARE
    v_statut  VARCHAR;
    v_expedie INTEGER;
    v_nb_inc  INTEGER;
BEGIN
    CALL avancer_commande(pg_temp.id('cycle'));
    CALL avancer_commande(pg_temp.id('cycle'), 'Camion-Test');

    SELECT COALESCE(SUM(ie.quantite_expediee), 0) INTO v_expedie
    FROM info_expedition ie
    JOIN info_commande ic ON ic.id_info_commande = ie.id_info_commande
    WHERE ic.id_commande = pg_temp.id('cycle');
    PERFORM pg_temp.verifier(v_expedie = 1, format('%s unite(s) en expedition (attendu 1)', v_expedie));

    CALL avancer_commande(pg_temp.id('cycle'));

    SELECT s.nom_statut INTO v_statut
    FROM commande c JOIN statut s ON s.id_statut = c.id_statut
    WHERE c.id_commande = pg_temp.id('cycle');
    PERFORM pg_temp.verifier(v_statut = 'Livrée', format('statut final : %s', v_statut));

    SELECT COUNT(*) INTO v_nb_inc
    FROM info_expedition ie
    JOIN info_commande ic ON ic.id_info_commande = ie.id_info_commande
    JOIN expedition e     ON e.id_expedition     = ie.id_expedition
    WHERE ic.id_commande = pg_temp.id('cycle') AND NOT e.est_complete;
    PERFORM pg_temp.verifier(v_nb_inc = 0, 'expedition non completee apres livraison');

    BEGIN
        CALL avancer_commande(pg_temp.id('cycle'));
        RAISE EXCEPTION 'une commande livree a encore avance';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        CALL avancer_commande(-1);
        RAISE EXCEPTION 'aucune erreur pour une commande inexistante';
    EXCEPTION WHEN no_data_found THEN NULL;
    END;

    PERFORM pg_temp.ok('T13', 'avancer_commande : cycle complet jusqu''a Livree');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T13 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- =============================================================
-- TRANSACTION
-- =============================================================

-- T14 Paiement partiel -> refus -> ROLLBACK (meme scenario que
--     06_transactions.sql et l'option 7 de l'application).
--     Le bloc interne est un point de sauvegarde : l'erreur annule la
--     capture ET le changement de statut.
DO $$
DECLARE
    v_complete BOOLEAN;
    v_montant  NUMERIC;
    v_statut   VARCHAR;
BEGIN
    BEGIN
        UPDATE paiement
           SET est_complete = TRUE, date_paiement = LOCALTIMESTAMP,
               montant_paiement = ROUND(montant_paiement / 2, 2)
         WHERE id_commande = pg_temp.id('paiement_partiel') AND NOT est_complete;

        UPDATE commande SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
         WHERE id_commande = pg_temp.id('paiement_partiel');

        RAISE EXCEPTION 'commande payee avec un paiement partiel';
    EXCEPTION WHEN check_violation THEN NULL;   -- ROLLBACK du point de sauvegarde
    END;

    SELECT est_complete, montant_paiement INTO v_complete, v_montant
    FROM paiement WHERE id_commande = pg_temp.id('paiement_partiel');

    SELECT s.nom_statut INTO v_statut
    FROM commande c JOIN statut s ON s.id_statut = c.id_statut
    WHERE c.id_commande = pg_temp.id('paiement_partiel');

    PERFORM pg_temp.verifier(NOT v_complete AND v_montant = 100.00 AND v_statut = 'En attente',
        format('apres ROLLBACK : complete=%s, montant=%s, statut=%s', v_complete, v_montant, v_statut));

    PERFORM pg_temp.ok('T14', 'transaction : paiement partiel refuse, tout est annule');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T14 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- =============================================================
-- PRINCIPAUX RESULTATS
-- =============================================================

-- T15 Vues et vue materialisee
--   v_commandes : toutes les commandes (>= 250);
--   mv_ventes_produit_7j : apres REFRESH, produit A = 3 (cycle,
--   paiement_partiel, gestionnaire; la commande annulee est exclue),
--   produit B = 2;
--   v_receptions_attendues : la reception validee de T07 n'y est pas.
DO $$
DECLARE
    v_nb_vue  INTEGER;
    v_nb_tab  INTEGER;
    v_qte_a   INTEGER;
    v_qte_b   INTEGER;
    v_nb_rec  INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_nb_vue FROM v_commandes;
    SELECT COUNT(*) INTO v_nb_tab FROM commande;
    PERFORM pg_temp.verifier(v_nb_vue = v_nb_tab AND v_nb_vue >= 250,
        format('v_commandes : %s ligne(s), commande : %s', v_nb_vue, v_nb_tab));

    REFRESH MATERIALIZED VIEW mv_ventes_produit_7j;

    SELECT quantite_vendue_7j INTO v_qte_a FROM mv_ventes_produit_7j WHERE id_produit = pg_temp.id('produit_a');
    SELECT quantite_vendue_7j INTO v_qte_b FROM mv_ventes_produit_7j WHERE id_produit = pg_temp.id('produit_b');
    PERFORM pg_temp.verifier(v_qte_a = 3 AND v_qte_b = 2,
        format('ventes 7 jours : A=%s (attendu 3), B=%s (attendu 2)', v_qte_a, v_qte_b));

    SELECT COUNT(*) INTO v_nb_rec FROM v_receptions_attendues WHERE fournisseur_reception = 'Fournisseur test';
    PERFORM pg_temp.verifier(v_nb_rec = 0, 'reception validee presente dans v_receptions_attendues');

    PERFORM pg_temp.ok('T15', 'v_commandes, mv_ventes_produit_7j, v_receptions_attendues');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T15 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- =============================================================
-- ROLES
-- =============================================================

-- T16 demo_employe : lecture seulement, jamais le hash du mot de passe
DO $$
DECLARE
    v_nom TEXT;
    v_nb  INTEGER;
    v_err TEXT := NULL;
BEGIN
    SET LOCAL ROLE demo_employe;

    SELECT nom_client INTO v_nom FROM client WHERE id_client = pg_temp.id('client');
    SELECT COUNT(*) INTO v_nb FROM details_commande(pg_temp.id('paiement_partiel'));

    BEGIN
        PERFORM hash_mot_passe_client FROM client LIMIT 1;
        v_err := 'hash_mot_passe_client lisible';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    IF v_err IS NULL THEN
        BEGIN
            INSERT INTO evaluation (id_produit, id_client, note_evaluation)
            VALUES (pg_temp.id('produit_b'), pg_temp.id('client'), 5);
            v_err := 'INSERT accepte pour l''employe';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;
    END IF;

    IF v_err IS NULL THEN
        BEGIN
            CALL avancer_commande(pg_temp.id('gestionnaire'));
            v_err := 'avancer_commande accepte pour l''employe';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;
    END IF;

    RESET ROLE;

    PERFORM pg_temp.verifier(v_err IS NULL, v_err);
    PERFORM pg_temp.verifier(v_nom = 'Client Test' AND v_nb = 2, 'lecture impossible pour l''employe');

    PERFORM pg_temp.ok('T16', 'demo_employe : lecture OK; hash, INSERT et procedure refuses (42501)');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T16 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- T17 demo_gestionnaire : fait avancer une commande (audit a son nom),
--     mais ne peut ni supprimer ni modifier la table statut
DO $$
DECLARE
    v_statut      VARCHAR;
    v_utilisateur VARCHAR;
    v_err         TEXT := NULL;
BEGIN
    SET LOCAL ROLE demo_gestionnaire;

    CALL avancer_commande(pg_temp.id('gestionnaire'));

    SELECT s.nom_statut INTO v_statut
    FROM commande c JOIN statut s ON s.id_statut = c.id_statut
    WHERE c.id_commande = pg_temp.id('gestionnaire');

    SELECT utilisateur INTO v_utilisateur FROM audit_statut_commande
     WHERE id_commande = pg_temp.id('gestionnaire')
     ORDER BY id_audit DESC LIMIT 1;

    BEGIN
        DELETE FROM evaluation WHERE id_client = pg_temp.id('client');
        v_err := 'DELETE accepte pour le gestionnaire';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    IF v_err IS NULL THEN
        BEGIN
            UPDATE statut SET nom_statut = nom_statut WHERE FALSE;
            v_err := 'UPDATE sur statut accepte pour le gestionnaire';
        EXCEPTION WHEN insufficient_privilege THEN NULL;
        END;
    END IF;

    RESET ROLE;

    PERFORM pg_temp.verifier(v_err IS NULL, v_err);
    PERFORM pg_temp.verifier(v_statut = 'Payée' AND v_utilisateur = 'demo_gestionnaire',
        format('statut=%s, audit par %s', v_statut, v_utilisateur));

    PERFORM pg_temp.ok('T17', 'demo_gestionnaire : procedure + audit a son nom; DELETE et statut refuses');
EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION '[ECHEC] T17 : % (SQLSTATE %)', SQLERRM, SQLSTATE;
END;
$$;

-- -------------------------------------------------------------
-- Bilan (nombre de tests reussis; le total est compte par le lanceur)
-- -------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE 'BILAN : % test(s) reussi(s)', current_setting('tst.reussis');
END;
$$;

ROLLBACK;
