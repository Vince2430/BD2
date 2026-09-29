-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 6 : tests automatises (assertions SQL)
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel",
-- APRES creer_bd.command (scripts 00 a 05).
--
--   Recommande : double-cliquer lancer_tests.command (resultat de
--   chaque test + bilan).
--   psql -U postgres -v ON_ERROR_STOP=1 -d tp1_vincent_trudel -f 08_tests.sql
--
--   pgAdmin 4 : coller dans le Query Tool, F5. Resultats dans l'onglet
--   "Messages". En cas d'echec, executer ROLLBACK; avant de relancer.
--
-- Principe :
--   - Tout s'execute dans UNE transaction terminee par ROLLBACK :
--     les tests ne laissent aucune trace dans la base. Relancable
--     a volonte, sans relancer creer_bd.command.
--   - Chaque test est un bloc DO. Il affiche "OK Txx" s'il reussit,
--     sinon il leve une erreur ("ECHEC Txx" ou ASSERT).
--       * lancer_tests.command (ON_ERROR_ROLLBACK=on) : seul le test en
--         echec est annule, les suivants s'executent, bilan a la fin.
--       * psql avec ON_ERROR_STOP=1, ou pgAdmin : le script s'arrete au
--         premier echec et la transaction est annulee.
--   - Un refus attendu (contrainte, declencheur, privilege) est
--     verifie en attrapant le code d'erreur precis. Si l'operation
--     passe, le test echoue.
--   - Les tests creent leurs propres donnees (categorie, produits,
--     client, 4 commandes) : ils ne dependent pas du volume genere
--     par 03_donnees.sql. Les identifiants sont gardes dans des
--     parametres de session tst.* (lisibles aussi apres SET ROLE,
--     contrairement a une table temporaire).
--
-- Couverture (exigence de l'enonce -> tests) :
--   contraintes           : T01 a T04
--   declencheurs          : T05 a T11
--   routines              : T12 (details_commande), T13 (avancer_commande)
--   transaction           : T14
--   principaux resultats  : T15 (donnees, vues, vue materialisee)
--   roles et privileges   : T16, T17
-- =============================================================

SET search_path TO commerce, public;

BEGIN;

-- -------------------------------------------------------------
-- Donnees de test
-- Produits :
--   produit_vendu        : stock 20, present dans les commandes
--   produit_jamais_vendu : stock 5, dans aucune commande
--   produit_accessoire   : stock 5
-- Commandes (toutes creees "En attente", une par scenario) :
--   commande_cycle             : produit_vendu x2 + accessoire x1 = 125 $,
--                                paiement complete 125 $ -> parcours complet (T12, T13)
--   commande_a_annuler         : produit_vendu x3 = 150 $, aucun paiement
--                                -> refus du cycle de vie, audit, annulation (T08 a T11)
--   commande_paiement_partiel  : produit_vendu x1 = 50 $, autorisation 25 $
--                                non completee -> transaction (T05, T14)
--   commande_gestionnaire      : produit_vendu x1 = 50 $, paiement complete 50 $
--                                -> avancee par demo_gestionnaire (T17)
-- Les identifiants sont gardes dans les parametres de session tst.id_*
-- -------------------------------------------------------------
DO $$
DECLARE
    v_id_categorie                 INTEGER;
    v_id_produit_vendu             INTEGER;
    v_id_produit_jamais_vendu      INTEGER;
    v_id_produit_accessoire        INTEGER;
    v_id_client                    INTEGER;
    v_id_commande_cycle            INTEGER;
    v_id_commande_a_annuler        INTEGER;
    v_id_commande_paiement_partiel INTEGER;
    v_id_commande_gestionnaire     INTEGER;
    v_id_statut_en_attente         INTEGER := (SELECT id_statut FROM statut WHERE nom_statut = 'En attente');
BEGIN
    INSERT INTO categorie (nom_categorie) VALUES ('ZZ Test etape 6')
        RETURNING id_categorie INTO v_id_categorie;

    INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit,
                         quantite_totale_produit, id_categorie)
    VALUES ('Test produit vendu', 50, 30, 20, v_id_categorie) RETURNING id_produit INTO v_id_produit_vendu;
    INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit,
                         quantite_totale_produit, id_categorie)
    VALUES ('Test produit jamais vendu', 40, 20, 5, v_id_categorie) RETURNING id_produit INTO v_id_produit_jamais_vendu;
    INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit,
                         quantite_totale_produit, id_categorie)
    VALUES ('Test produit accessoire', 25, 10, 5, v_id_categorie) RETURNING id_produit INTO v_id_produit_accessoire;

    INSERT INTO client (nom_client, courriel_client, hash_mot_passe_client)
    VALUES ('Client Test', 'test.etape6@exemple.test', 'hash_factice')
        RETURNING id_client INTO v_id_client;

    INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
    VALUES ('1 rue du Test, Montreal', v_id_client, v_id_statut_en_attente) RETURNING id_commande INTO v_id_commande_cycle;
    INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
    VALUES ('1 rue du Test, Montreal', v_id_client, v_id_statut_en_attente) RETURNING id_commande INTO v_id_commande_a_annuler;
    INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
    VALUES ('1 rue du Test, Montreal', v_id_client, v_id_statut_en_attente) RETURNING id_commande INTO v_id_commande_paiement_partiel;
    INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
    VALUES ('1 rue du Test, Montreal', v_id_client, v_id_statut_en_attente) RETURNING id_commande INTO v_id_commande_gestionnaire;

    INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire) VALUES
        (v_id_commande_cycle,            v_id_produit_vendu,      2, 50),
        (v_id_commande_cycle,            v_id_produit_accessoire, 1, 25),
        (v_id_commande_a_annuler,        v_id_produit_vendu,      3, 50),
        (v_id_commande_paiement_partiel, v_id_produit_vendu,      1, 50),
        (v_id_commande_gestionnaire,     v_id_produit_vendu,      1, 50);

    INSERT INTO paiement (id_commande, mode_paiement, date_paiement,
                          montant_paiement, est_complete) VALUES
        (v_id_commande_cycle,            'Carte', LOCALTIMESTAMP, 125, TRUE),
        (v_id_commande_paiement_partiel, 'Carte', NULL,            25, FALSE),
        (v_id_commande_gestionnaire,     'Carte', LOCALTIMESTAMP,  50, TRUE);

    PERFORM set_config('tst.id_produit_vendu',             v_id_produit_vendu::TEXT,             TRUE);
    PERFORM set_config('tst.id_produit_jamais_vendu',      v_id_produit_jamais_vendu::TEXT,      TRUE);
    PERFORM set_config('tst.id_produit_accessoire',        v_id_produit_accessoire::TEXT,        TRUE);
    PERFORM set_config('tst.id_client',                    v_id_client::TEXT,                    TRUE);
    PERFORM set_config('tst.id_categorie',                 v_id_categorie::TEXT,                 TRUE);
    PERFORM set_config('tst.id_commande_cycle',            v_id_commande_cycle::TEXT,            TRUE);
    PERFORM set_config('tst.id_commande_a_annuler',        v_id_commande_a_annuler::TEXT,        TRUE);
    PERFORM set_config('tst.id_commande_paiement_partiel', v_id_commande_paiement_partiel::TEXT, TRUE);
    PERFORM set_config('tst.id_commande_gestionnaire',     v_id_commande_gestionnaire::TEXT,     TRUE);

    ASSERT (SELECT quantite_totale_produit FROM produit WHERE id_produit = v_id_produit_vendu) = 13,
        'Donnees de test : le stock de produit_vendu devrait etre 20 - 7 = 13';

    RAISE NOTICE '--- Donnees de test creees (commandes : cycle=%, a_annuler=%, paiement_partiel=%, gestionnaire=%) ---',
        v_id_commande_cycle, v_id_commande_a_annuler, v_id_commande_paiement_partiel, v_id_commande_gestionnaire;
END $$;

-- =============================================================
-- CONTRAINTES
-- =============================================================

-- T01 : CHECK prix_produit > 0
DO $$
BEGIN
    BEGIN
        INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit, id_categorie)
        VALUES ('Prix nul', 0, 0, current_setting('tst.id_categorie')::INT);
        RAISE EXCEPTION 'ECHEC T01 : un produit a 0 $ a ete accepte';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    RAISE NOTICE 'OK  T01 - CHECK : prix de produit nul refuse';
END $$;

-- T02 : cle etrangere (commande d'un client inexistant)
DO $$
BEGIN
    BEGIN
        INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
        VALUES ('Nulle part', -1,
                (SELECT id_statut FROM statut WHERE nom_statut = 'En attente'));
        RAISE EXCEPTION 'ECHEC T02 : commande d''un client inexistant acceptee';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    RAISE NOTICE 'OK  T02 - FK : commande pour un client inexistant refusee';
END $$;

-- T03 : UNIQUE courriel_client
DO $$
BEGIN
    BEGIN
        INSERT INTO client (nom_client, courriel_client, hash_mot_passe_client)
        VALUES ('Doublon', 'test.etape6@exemple.test', 'x');
        RAISE EXCEPTION 'ECHEC T03 : courriel en double accepte';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    RAISE NOTICE 'OK  T03 - UNIQUE : courriel client en double refuse';
END $$;

-- T04 : contraintes JSONB de specification_produit
--       (un document valide passe; chaque document invalide est refuse
--        par LA contrainte attendue)
DO $$
DECLARE
    v_spec_valide JSONB := '{"marque": "MarqueTest", "modele": "T-1", "garantie_mois": 12,
                    "dimensions": {"largeur": 10, "hauteur": 5},
                    "connectivite": ["USB-C"]}';
    v_contrainte TEXT;
BEGIN
    INSERT INTO specification_produit (id_produit, specifications_produit)
    VALUES (current_setting('tst.id_produit_jamais_vendu')::INT, v_spec_valide);

    -- connectivite fournie mais vide
    BEGIN
        INSERT INTO specification_produit (id_produit, specifications_produit)
        VALUES (current_setting('tst.id_produit_accessoire')::INT,
                jsonb_set(v_spec_valide, '{connectivite}', '[]'));
        RAISE EXCEPTION 'ECHEC T04 : connectivite vide acceptee';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_contrainte = CONSTRAINT_NAME;
        ASSERT v_contrainte = 'ck_spec_connectivite_non_vide',
            'T04 : mauvaise contrainte declenchee : ' || v_contrainte;
    END;

    -- garantie negative
    BEGIN
        INSERT INTO specification_produit (id_produit, specifications_produit)
        VALUES (current_setting('tst.id_produit_accessoire')::INT,
                jsonb_set(v_spec_valide, '{garantie_mois}', '-1'));
        RAISE EXCEPTION 'ECHEC T04 : garantie negative acceptee';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_contrainte = CONSTRAINT_NAME;
        ASSERT v_contrainte = 'ck_spec_garantie',
            'T04 : mauvaise contrainte declenchee : ' || v_contrainte;
    END;

    -- dimensions qui n'est pas un objet
    BEGIN
        INSERT INTO specification_produit (id_produit, specifications_produit)
        VALUES (current_setting('tst.id_produit_accessoire')::INT,
                jsonb_set(v_spec_valide, '{dimensions}', '"10x5"'));
        RAISE EXCEPTION 'ECHEC T04 : dimensions non-objet acceptees';
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS v_contrainte = CONSTRAINT_NAME;
        ASSERT v_contrainte = 'ck_spec_types',
            'T04 : mauvaise contrainte declenchee : ' || v_contrainte;
    END;

    RAISE NOTICE 'OK  T04 - JSONB : document valide accepte, 3 documents invalides refuses';
END $$;

-- =============================================================
-- DECLENCHEURS
-- =============================================================

-- T05 : trg_maj_stock_produit (vente = stock diminue; stock insuffisant refuse)
DO $$
DECLARE
    v_id_produit_accessoire INTEGER := current_setting('tst.id_produit_accessoire')::INT;
    v_stock_avant INTEGER;
    v_stock_apres INTEGER;
BEGIN
    SELECT quantite_totale_produit INTO v_stock_avant FROM produit WHERE id_produit = v_id_produit_accessoire;

    INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire)
    VALUES (current_setting('tst.id_commande_paiement_partiel')::INT, v_id_produit_accessoire, 2, 25);

    SELECT quantite_totale_produit INTO v_stock_apres FROM produit WHERE id_produit = v_id_produit_accessoire;
    ASSERT v_stock_apres = v_stock_avant - 2, 'T05 : le stock aurait du baisser de 2';

    BEGIN
        UPDATE info_commande SET quantite = 1000
         WHERE id_commande = current_setting('tst.id_commande_paiement_partiel')::INT AND id_produit = v_id_produit_accessoire;
        RAISE EXCEPTION 'ECHEC T05 : quantite superieure au stock acceptee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    ASSERT (SELECT quantite_totale_produit FROM produit WHERE id_produit = v_id_produit_accessoire) = v_stock_apres,
        'T05 : le stock a change malgre le refus';

    RAISE NOTICE 'OK  T05 - Stock : vente deduite du stock, stock insuffisant refuse';
END $$;

-- T06 : trg_valider_achat_avant_evaluation
DO $$
BEGIN
    -- le client a achete produit_vendu (commande_cycle) : evaluation acceptee
    INSERT INTO evaluation (id_produit, id_client, note_evaluation)
    VALUES (current_setting('tst.id_produit_vendu')::INT, current_setting('tst.id_client')::INT, 5);

    -- il n'a jamais achete produit_jamais_vendu : evaluation refusee
    BEGIN
        INSERT INTO evaluation (id_produit, id_client, note_evaluation)
        VALUES (current_setting('tst.id_produit_jamais_vendu')::INT, current_setting('tst.id_client')::INT, 1);
        RAISE EXCEPTION 'ECHEC T06 : evaluation d''un produit non achete acceptee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    RAISE NOTICE 'OK  T06 - Evaluation : acceptee si achete, refusee sinon';
END $$;

-- T07 : receptions (ajout au stock a la validation, reception validee figee)
DO $$
DECLARE
    v_id_produit_jamais_vendu INTEGER := current_setting('tst.id_produit_jamais_vendu')::INT;
    v_id_reception INTEGER;
    v_stock_avant INTEGER;
BEGIN
    SELECT quantite_totale_produit INTO v_stock_avant FROM produit WHERE id_produit = v_id_produit_jamais_vendu;

    INSERT INTO reception (numero_reception, date_prevue_reception)
    VALUES ('TEST-REC-E6', CURRENT_DATE) RETURNING id_reception INTO v_id_reception;
    INSERT INTO info_reception (id_reception, id_produit, quantite_recu)
    VALUES (v_id_reception, v_id_produit_jamais_vendu, 5);

    ASSERT EXISTS (SELECT 1 FROM v_receptions_attendues
                    WHERE id_reception = v_id_reception AND total_unites_attendues = 5),
        'T07 : la reception attendue devrait apparaitre dans v_receptions_attendues';
    ASSERT (SELECT quantite_totale_produit FROM produit WHERE id_produit = v_id_produit_jamais_vendu) = v_stock_avant,
        'T07 : une reception attendue ne doit pas encore toucher au stock';

    UPDATE reception SET est_complete = TRUE, date_complete_reception = LOCALTIMESTAMP
     WHERE id_reception = v_id_reception;

    ASSERT (SELECT quantite_totale_produit FROM produit WHERE id_produit = v_id_produit_jamais_vendu) = v_stock_avant + 5,
        'T07 : la validation aurait du ajouter 5 unites au stock';
    ASSERT NOT EXISTS (SELECT 1 FROM v_receptions_attendues WHERE id_reception = v_id_reception),
        'T07 : une reception validee ne doit plus etre attendue';

    BEGIN
        UPDATE reception SET est_complete = FALSE WHERE id_reception = v_id_reception;
        RAISE EXCEPTION 'ECHEC T07 : modification d''une reception validee acceptee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        DELETE FROM reception WHERE id_reception = v_id_reception;
        RAISE EXCEPTION 'ECHEC T07 : suppression d''une reception validee acceptee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        UPDATE info_reception SET quantite_recu = 50 WHERE id_reception = v_id_reception;
        RAISE EXCEPTION 'ECHEC T07 : modification d''une ligne de reception validee acceptee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    RAISE NOTICE 'OK  T07 - Reception : stock ajoute a la validation, reception validee figee';
END $$;

-- T08 : quantite expediee <= quantite commandee (commande_a_annuler : produit_vendu x3)
DO $$
DECLARE
    v_id_info_commande     INTEGER;
    v_id_expedition_colis1 INTEGER;
    v_id_expedition_colis2 INTEGER;
BEGIN
    SELECT id_info_commande INTO v_id_info_commande FROM info_commande
     WHERE id_commande = current_setting('tst.id_commande_a_annuler')::INT;

    INSERT INTO expedition (date_prevue_expedition) VALUES (CURRENT_DATE)
        RETURNING id_expedition INTO v_id_expedition_colis1;
    INSERT INTO expedition (date_prevue_expedition) VALUES (CURRENT_DATE)
        RETURNING id_expedition INTO v_id_expedition_colis2;

    -- colis 1 : 2 unites sur 3, accepte
    INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
    VALUES (v_id_info_commande, v_id_expedition_colis1, 2);

    -- colis 2 : 2 unites de plus (total 4 > 3), refuse
    BEGIN
        INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
        VALUES (v_id_info_commande, v_id_expedition_colis2, 2);
        RAISE EXCEPTION 'ECHEC T08 : expedition de 4 unites sur 3 acceptee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- baisser la quantite commandee sous ce qui est deja expedie : refuse
    BEGIN
        UPDATE info_commande SET quantite = 1 WHERE id_info_commande = v_id_info_commande;
        RAISE EXCEPTION 'ECHEC T08 : quantite commandee baissee sous le total expedie';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    RAISE NOTICE 'OK  T08 - Expedition : depassement refuse (2 colis), baisse sous l''expedie refusee';
END $$;

-- T09 : cycle de vie d'une commande (trg_proteger_commande, regles a, e, f, g)
DO $$
DECLARE
    v_id_commande_a_annuler INTEGER := current_setting('tst.id_commande_a_annuler')::INT;
BEGIN
    -- regle e : une nouvelle commande nait "En attente"
    BEGIN
        INSERT INTO commande (adresse_livraison_commande, id_client, id_statut)
        VALUES ('x', current_setting('tst.id_client')::INT,
                (SELECT id_statut FROM statut WHERE nom_statut = 'Payée'));
        RAISE EXCEPTION 'ECHEC T09 : commande creee directement "Payée"';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- regle f : saut de statut
    BEGIN
        UPDATE commande
           SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Expédiée')
         WHERE id_commande = v_id_commande_a_annuler;
        RAISE EXCEPTION 'ECHEC T09 : saut "En attente" -> "Expédiée" accepte';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- regle g : "Payée" sans paiement complete
    BEGIN
        UPDATE commande
           SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
         WHERE id_commande = v_id_commande_a_annuler;
        RAISE EXCEPTION 'ECHEC T09 : commande sans paiement passee a "Payée"';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- regle a : jamais de suppression
    BEGIN
        DELETE FROM commande WHERE id_commande = v_id_commande_a_annuler;
        RAISE EXCEPTION 'ECHEC T09 : suppression d''une commande acceptee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    RAISE NOTICE 'OK  T09 - Cycle de vie : creation hors "En attente", saut, "Payée" sans paiement et DELETE refuses';
END $$;

-- T10 : audit (trg_audit_statut_commande)
DO $$
DECLARE
    v_id_commande_a_annuler INTEGER := current_setting('tst.id_commande_a_annuler')::INT;
BEGIN
    ASSERT (SELECT COUNT(*) FROM audit_statut_commande WHERE id_commande = v_id_commande_a_annuler) = 1,
        'T10 : la creation de la commande aurait du etre journalisee une fois';
    ASSERT EXISTS (SELECT 1 FROM audit_statut_commande
                    WHERE id_commande = v_id_commande_a_annuler AND operation = 'INSERT'
                      AND ancien_statut IS NULL AND nouveau_statut = 'En attente'),
        'T10 : ligne d''audit de creation incorrecte';

    -- meme statut reecrit : aucune nouvelle ligne
    UPDATE commande SET id_statut = id_statut WHERE id_commande = v_id_commande_a_annuler;
    ASSERT (SELECT COUNT(*) FROM audit_statut_commande WHERE id_commande = v_id_commande_a_annuler) = 1,
        'T10 : un statut inchange ne doit pas etre journalise';

    RAISE NOTICE 'OK  T10 - Audit : creation journalisee, statut inchange ignore';
END $$;

-- T11 : annulation (stock rendu, audit, commande et lignes figees)
DO $$
DECLARE
    v_id_commande_a_annuler INTEGER := current_setting('tst.id_commande_a_annuler')::INT;
    v_id_produit_vendu INTEGER := current_setting('tst.id_produit_vendu')::INT;
    v_stock_avant INTEGER;
BEGIN
    SELECT quantite_totale_produit INTO v_stock_avant FROM produit WHERE id_produit = v_id_produit_vendu;

    UPDATE commande
       SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Annulée')
     WHERE id_commande = v_id_commande_a_annuler;

    ASSERT (SELECT quantite_totale_produit FROM produit WHERE id_produit = v_id_produit_vendu) = v_stock_avant + 3,
        'T11 : l''annulation aurait du rendre 3 unites au stock';
    ASSERT EXISTS (SELECT 1 FROM audit_statut_commande
                    WHERE id_commande = v_id_commande_a_annuler AND operation = 'UPDATE'
                      AND ancien_statut = 'En attente' AND nouveau_statut = 'Annulée'),
        'T11 : l''annulation aurait du etre journalisee';

    -- commande annulee figee : pas de reactivation
    BEGIN
        UPDATE commande
           SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'En attente')
         WHERE id_commande = v_id_commande_a_annuler;
        RAISE EXCEPTION 'ECHEC T11 : commande annulee reactivee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- ni aucun autre champ
    BEGIN
        UPDATE commande SET adresse_livraison_commande = 'Ailleurs' WHERE id_commande = v_id_commande_a_annuler;
        RAISE EXCEPTION 'ECHEC T11 : adresse d''une commande annulee modifiee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- ni ses lignes
    BEGIN
        INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire)
        VALUES (v_id_commande_a_annuler, current_setting('tst.id_produit_accessoire')::INT, 1, 25);
        RAISE EXCEPTION 'ECHEC T11 : ligne ajoutee a une commande annulee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    RAISE NOTICE 'OK  T11 - Annulation : stock rendu, journalisee, commande et lignes figees';
END $$;

-- =============================================================
-- ROUTINES
-- =============================================================

-- T12 : details_commande (commande_cycle : produit_vendu x2 a 50 $ + accessoire x1 a 25 $)
DO $$
DECLARE
    v_nb_lignes INTEGER;
    v_total     NUMERIC;
BEGIN
    SELECT COUNT(*), SUM(sous_total) INTO v_nb_lignes, v_total
      FROM details_commande(current_setting('tst.id_commande_cycle')::INT);
    ASSERT v_nb_lignes = 2,  'T12 : 2 lignes attendues, obtenu ' || v_nb_lignes;
    ASSERT v_total = 125.00, 'T12 : total de 125.00 attendu, obtenu ' || v_total;

    BEGIN
        PERFORM * FROM details_commande(-1);
        RAISE EXCEPTION 'ECHEC T12 : aucune erreur pour une commande inexistante';
    EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;
    END;

    RAISE NOTICE 'OK  T12 - details_commande : sous-totaux corrects, commande inexistante -> P0002';
END $$;

-- T13 : avancer_commande, parcours complet de commande_cycle
DO $$
DECLARE
    v_id_commande_cycle INTEGER := current_setting('tst.id_commande_cycle')::INT;
    v_statut VARCHAR(30);
    v_statut_attendu TEXT;
BEGIN
    FOREACH v_statut_attendu IN ARRAY ARRAY['Payée', 'En préparation', 'Expédiée', 'Livrée'] LOOP
        CALL avancer_commande(v_id_commande_cycle, 'CAM-TEST');
        SELECT nom_statut INTO v_statut FROM v_commandes WHERE id_commande = v_id_commande_cycle;
        ASSERT v_statut = v_statut_attendu,
            format('T13 : statut "%s" attendu, obtenu "%s"', v_statut_attendu, v_statut);

        IF v_statut_attendu = 'Expédiée' THEN
            ASSERT (SELECT SUM(ie.quantite_expediee)
                      FROM info_expedition ie
                      JOIN info_commande ic ON ic.id_info_commande = ie.id_info_commande
                     WHERE ic.id_commande = v_id_commande_cycle) = 3,
                'T13 : les 3 unites de la commande devraient etre expediees';
        END IF;
    END LOOP;

    ASSERT NOT EXISTS (SELECT 1
                         FROM info_expedition ie
                         JOIN info_commande ic ON ic.id_info_commande = ie.id_info_commande
                         JOIN expedition e     ON e.id_expedition     = ie.id_expedition
                        WHERE ic.id_commande = v_id_commande_cycle AND NOT e.est_complete),
        'T13 : les expeditions d''une commande livree devraient etre completees';

    ASSERT (SELECT COUNT(*) FROM audit_statut_commande WHERE id_commande = v_id_commande_cycle) = 5,
        'T13 : 5 lignes d''audit attendues (creation + 4 changements)';

    -- une commande livree ne peut plus avancer...
    BEGIN
        CALL avancer_commande(v_id_commande_cycle);
        RAISE EXCEPTION 'ECHEC T13 : une commande livree a avance';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    -- ...ni etre annulee (regle b)
    BEGIN
        UPDATE commande
           SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Annulée')
         WHERE id_commande = v_id_commande_cycle;
        RAISE EXCEPTION 'ECHEC T13 : une commande livree a ete annulee';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    RAISE NOTICE 'OK  T13 - avancer_commande : parcours complet, expedition, audit, fin de cycle';
END $$;

-- =============================================================
-- TRANSACTION
-- =============================================================

-- T14 : tout ou rien (meme scenario que 06_transactions.sql, scenario 2)
--   commande_paiement_partiel : total 100 $ (produit_vendu 50 $ + accessoire
--   2 x 25 $ ajoute en T05), autorisation de 25 $. Capture, puis passage a "Payée" refuse :
--   la capture doit etre annulee avec lui.
DO $$
DECLARE
    v_id_commande_paiement_partiel INTEGER := current_setting('tst.id_commande_paiement_partiel')::INT;
BEGIN
    BEGIN
        UPDATE paiement SET est_complete = TRUE, date_paiement = LOCALTIMESTAMP
         WHERE id_commande = v_id_commande_paiement_partiel;
        UPDATE commande
           SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
         WHERE id_commande = v_id_commande_paiement_partiel;
        RAISE EXCEPTION 'ECHEC T14 : paiement partiel accepte comme "Payée"';
    EXCEPTION WHEN check_violation THEN NULL;  -- equivalent d'un ROLLBACK du bloc
    END;

    ASSERT (SELECT NOT est_complete FROM paiement WHERE id_commande = v_id_commande_paiement_partiel),
        'T14 : la capture aurait du etre annulee avec l''echec';
    ASSERT (SELECT nom_statut FROM v_commandes WHERE id_commande = v_id_commande_paiement_partiel) = 'En attente',
        'T14 : la commande devrait rester "En attente"';

    RAISE NOTICE 'OK  T14 - Transaction : echec du passage a "Payée" = capture annulee aussi';
END $$;

-- =============================================================
-- PRINCIPAUX RESULTATS
-- =============================================================

-- Photo a jour pour la vue materialisee (annulee avec le ROLLBACK final)
REFRESH MATERIALIZED VIEW mv_ventes_produit_7j;

-- T15 : donnees chargees, vues et vue materialisee
DO $$
BEGIN
    ASSERT (SELECT COUNT(*) FROM statut) = 6, 'T15 : 6 statuts attendus';
    ASSERT (SELECT COUNT(*) FROM commande) >= 250,
        'T15 : au moins 250 commandes attendues (03_donnees.sql)';

    -- v_commandes : toutes les commandes, annulees comprises
    ASSERT (SELECT COUNT(*) FROM v_commandes) = (SELECT COUNT(*) FROM commande),
        'T15 : v_commandes doit contenir toutes les commandes';
    ASSERT (SELECT nom_statut FROM v_commandes
             WHERE id_commande = current_setting('tst.id_commande_a_annuler')::INT) = 'Annulée',
        'T15 : la commande annulee doit apparaitre dans v_commandes';

    -- v_receptions_attendues : une ligne par reception non completee
    ASSERT (SELECT COUNT(*) FROM v_receptions_attendues)
         = (SELECT COUNT(*) FROM reception WHERE NOT est_complete),
        'T15 : v_receptions_attendues doit lister les receptions non completees';

    -- vue materialisee : une ligne par produit; ventes de produit_vendu
    -- sur 7 jours = cycle (2) + paiement_partiel (1) + gestionnaire (1);
    -- commande_a_annuler est annulee donc exclue
    ASSERT (SELECT COUNT(*) FROM mv_ventes_produit_7j) = (SELECT COUNT(*) FROM produit),
        'T15 : une ligne par produit attendue dans mv_ventes_produit_7j';
    ASSERT (SELECT quantite_vendue_7j FROM mv_ventes_produit_7j
             WHERE id_produit = current_setting('tst.id_produit_vendu')::INT) = 4,
        'T15 : 4 unites de produit_vendu attendues (commande annulee exclue)';
    ASSERT (SELECT quantite_vendue_7j FROM mv_ventes_produit_7j
             WHERE id_produit = current_setting('tst.id_produit_jamais_vendu')::INT) = 0,
        'T15 : un produit jamais vendu doit apparaitre avec 0';

    RAISE NOTICE 'OK  T15 - Resultats : donnees, v_commandes, v_receptions_attendues, mv_ventes_produit_7j';
END $$;

-- =============================================================
-- ROLES ET PRIVILEGES
-- =============================================================

-- T16 : employe (lecture seulement, sans le hachage du mot de passe)
SET ROLE demo_employe;
DO $$
BEGIN
    PERFORM nom_client, courriel_client FROM client LIMIT 1;  -- colonnes permises

    BEGIN
        PERFORM hash_mot_passe_client FROM client LIMIT 1;
        RAISE EXCEPTION 'ECHEC T16 : l''employe lit hash_mot_passe_client';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        UPDATE commande SET adresse_livraison_commande = 'x'
         WHERE id_commande = current_setting('tst.id_commande_gestionnaire')::INT;
        RAISE EXCEPTION 'ECHEC T16 : l''employe modifie une commande';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        CALL avancer_commande(current_setting('tst.id_commande_gestionnaire')::INT);
        RAISE EXCEPTION 'ECHEC T16 : l''employe appelle avancer_commande';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    PERFORM * FROM details_commande(current_setting('tst.id_commande_gestionnaire')::INT);  -- permis

    RAISE NOTICE 'OK  T16 - Role employe : lecture permise, hachage/ecriture/procedure refuses';
END $$;
RESET ROLE;

-- T17 : gestionnaire (fait avancer une commande, ne supprime rien)
SET ROLE demo_gestionnaire;
DO $$
DECLARE
    v_id_commande_gestionnaire INTEGER := current_setting('tst.id_commande_gestionnaire')::INT;
BEGIN
    CALL avancer_commande(v_id_commande_gestionnaire);   -- En attente -> Payée (paiement complete)

    ASSERT (SELECT utilisateur FROM audit_statut_commande
             WHERE id_commande = v_id_commande_gestionnaire AND operation = 'UPDATE') = 'demo_gestionnaire',
        'T17 : l''audit devrait nommer demo_gestionnaire';

    BEGIN
        DELETE FROM commande WHERE id_commande = v_id_commande_gestionnaire;
        RAISE EXCEPTION 'ECHEC T17 : le gestionnaire supprime une commande';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        UPDATE statut SET nom_statut = nom_statut WHERE FALSE;
        RAISE EXCEPTION 'ECHEC T17 : le gestionnaire modifie la table statut';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    BEGIN
        EXECUTE 'REFRESH MATERIALIZED VIEW mv_ventes_produit_7j';
        RAISE EXCEPTION 'ECHEC T17 : le gestionnaire rafraichit la vue materialisee';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    RAISE NOTICE 'OK  T17 - Role gestionnaire : avance une commande (audit a son nom), DELETE/statut/REFRESH refuses';
END $$;
RESET ROLE;

-- =============================================================
-- Fin : tout a reussi. On annule les donnees de test.
-- =============================================================
DO $$ BEGIN RAISE NOTICE '=== Fin des tests. ROLLBACK : la base est inchangee. ==='; END $$;

ROLLBACK;
