-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 2 : declencheurs (regles metier)
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel"
--   psql -U postgres -d tp1_vincent_trudel -f 02_declencheurs.sql
--
-- Toutes les regles metier refusees levent une erreur SQLSTATE 23514
-- (check_violation), comme une contrainte CHECK : l'application les
-- affiche comme « regle metier ou contrainte CHECK ».
--
-- Liste :
--   1. trg_maj_stock_produit              (info_commande)
--   2. trg_valider_achat_avant_evaluation (evaluation)
--   3. trg_maj_stock_reception            (reception)
--   4. trg_proteger_reception             (reception)
--      trg_proteger_info_reception        (info_reception)
--   5. trg_audit_statut_commande          (commande)
--   6. trg_valider_quantite_expediee      (info_expedition)
--      trg_proteger_quantite_commandee    (info_commande)
--   7. trg_proteger_commande              (commande : regles a a i)
--      trg_restituer_stock_annulation     (commande)
--      trg_proteger_lignes_commande_annulee (info_commande)
-- =============================================================

SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- 1. Maintien du stock reel (quantite_totale_produit)
--
-- Une ligne de commande diminue le disponible; une modification de la
-- ligne restitue l'ancienne quantite puis preleve la nouvelle.
-- Le stock est verifie AVANT d'etre decremente, ce qui permet un
-- message d'erreur explicite plutot que la violation du CHECK
-- quantite_totale_produit >= 0.
--
-- SELECT ... FOR UPDATE verrouille la ligne du produit le temps de
-- la transaction : deux commandes simultanees du dernier article
-- ne peuvent pas passer toutes les deux.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION maj_stock_produit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INTEGER;
BEGIN
    -- UPDATE ou DELETE : on restitue d'abord l'ancienne quantite.
    IF TG_OP <> 'INSERT' THEN
        UPDATE produit
           SET quantite_totale_produit = quantite_totale_produit + OLD.quantite
         WHERE id_produit = OLD.id_produit;
    END IF;

    -- INSERT ou UPDATE : on preleve la nouvelle quantite.
    IF TG_OP <> 'DELETE' THEN
        SELECT quantite_totale_produit
          INTO v_stock
          FROM produit
         WHERE id_produit = NEW.id_produit
           FOR UPDATE;

        IF v_stock < NEW.quantite THEN
            RAISE EXCEPTION
                'Stock insuffisant pour le produit % : % unite(s) disponible(s), % demandee(s).',
                NEW.id_produit, v_stock, NEW.quantite
                USING ERRCODE = 'check_violation';
        END IF;

        UPDATE produit
           SET quantite_totale_produit = v_stock - NEW.quantite
         WHERE id_produit = NEW.id_produit;
    END IF;

    RETURN NULL;  -- declencheur AFTER : la valeur de retour est ignoree
END;
$$;

DROP TRIGGER IF EXISTS trg_maj_stock_produit ON info_commande;
CREATE TRIGGER trg_maj_stock_produit
    AFTER INSERT OR UPDATE OF quantite, id_produit OR DELETE ON info_commande
    FOR EACH ROW
    EXECUTE FUNCTION maj_stock_produit();

-- -------------------------------------------------------------
-- 2. Seul un client ayant commande le produit peut l'evaluer.
--
-- Une contrainte CHECK ne peut pas interroger d'autres tables,
-- d'ou le declencheur. (Une commande annulee compte comme un achat :
-- question ouverte #8.)
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION valider_achat_avant_evaluation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM info_commande ic
        JOIN commande c ON c.id_commande = ic.id_commande
        WHERE ic.id_produit = NEW.id_produit
          AND c.id_client   = NEW.id_client
    ) THEN
        RAISE EXCEPTION
            'Le client % n''a jamais commande le produit % : evaluation refusee.',
            NEW.id_client, NEW.id_produit
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_valider_achat_avant_evaluation ON evaluation;
CREATE TRIGGER trg_valider_achat_avant_evaluation
    BEFORE INSERT OR UPDATE OF id_produit, id_client ON evaluation
    FOR EACH ROW
    EXECUTE FUNCTION valider_achat_avant_evaluation();

-- -------------------------------------------------------------
-- 3. Reception validee : ajout au stock reel.
--
-- Quand une reception passe de est_complete = FALSE a TRUE, chaque
-- quantite attendue est ajoutee au stock reel et retiree de la
-- quantite entrante (previsionnel, jamais sous zero).
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION maj_stock_reception()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.est_complete AND NOT OLD.est_complete THEN
        UPDATE produit p
           SET quantite_totale_produit   = p.quantite_totale_produit + ir.quantite_attendue,
               quantite_entrante_produit = GREATEST(p.quantite_entrante_produit - ir.quantite_attendue, 0)
          FROM info_reception ir
         WHERE ir.id_reception = NEW.id_reception
           AND ir.id_produit   = p.id_produit;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_maj_stock_reception ON reception;
CREATE TRIGGER trg_maj_stock_reception
    AFTER UPDATE OF est_complete ON reception
    FOR EACH ROW
    EXECUTE FUNCTION maj_stock_reception();

-- -------------------------------------------------------------
-- 4. Une reception validee est figee (elle et ses lignes).
--    Sinon, on pourrait modifier une quantite deja ajoutee au stock
--    et le stock deviendrait faux.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION proteger_reception()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.est_complete THEN
        RAISE EXCEPTION
            'La reception % est validee : elle ne peut plus etre modifiee ni supprimee.',
            OLD.id_reception
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_reception ON reception;
CREATE TRIGGER trg_proteger_reception
    BEFORE UPDATE OR DELETE ON reception
    FOR EACH ROW
    EXECUTE FUNCTION proteger_reception();

CREATE OR REPLACE FUNCTION proteger_info_reception()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- UPDATE ou DELETE : la reception d'origine ne doit pas etre validee.
    IF TG_OP <> 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM reception r
                   WHERE r.id_reception = OLD.id_reception AND r.est_complete) THEN
            RAISE EXCEPTION
                'La reception % est validee : ses lignes sont figees.', OLD.id_reception
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- INSERT ou UPDATE : la reception de destination non plus.
    IF TG_OP <> 'DELETE' THEN
        IF EXISTS (SELECT 1 FROM reception r
                   WHERE r.id_reception = NEW.id_reception AND r.est_complete) THEN
            RAISE EXCEPTION
                'La reception % est validee : on ne peut plus y ajouter de ligne.', NEW.id_reception
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_info_reception ON info_reception;
CREATE TRIGGER trg_proteger_info_reception
    BEFORE INSERT OR UPDATE OR DELETE ON info_reception
    FOR EACH ROW
    EXECUTE FUNCTION proteger_info_reception();

-- -------------------------------------------------------------
-- 5. Audit des statuts de commande
--
-- Conserve l'operation, la date, l'ancien et le nouveau statut et
-- l'utilisateur PostgreSQL (current_user). Pas de SECURITY DEFINER :
-- l'utilisateur qui modifie la commande doit avoir INSERT sur la
-- table d'audit (voir 05_roles.sql).
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION audit_statut_commande()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ancien  VARCHAR(30);
    v_nouveau VARCHAR(30);
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.id_statut = NEW.id_statut THEN
            RETURN NULL;  -- le statut n'a pas change : rien a auditer
        END IF;
        SELECT nom_statut INTO v_ancien FROM statut WHERE id_statut = OLD.id_statut;
    END IF;

    SELECT nom_statut INTO v_nouveau FROM statut WHERE id_statut = NEW.id_statut;

    INSERT INTO audit_statut_commande
        (id_commande, operation, ancien_statut, nouveau_statut, date_operation, utilisateur)
    VALUES
        (NEW.id_commande, TG_OP, v_ancien, v_nouveau, LOCALTIMESTAMP, current_user);

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_statut_commande ON commande;
CREATE TRIGGER trg_audit_statut_commande
    AFTER INSERT OR UPDATE OF id_statut ON commande
    FOR EACH ROW
    EXECUTE FUNCTION audit_statut_commande();

-- -------------------------------------------------------------
-- 6. Expeditions : on n'expedie jamais plus que la quantite commandee.
--
-- a) info_expedition : total expedie de la ligne (toutes expeditions
--    confondues) <= quantite commandee. La ligne de commande est
--    verrouillee (FOR UPDATE) pour eviter deux expeditions simultanees.
-- b) info_commande : on ne peut pas baisser la quantite commandee
--    sous ce qui est deja expedie.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION valider_quantite_expediee()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_commandee INTEGER;
    v_deja      INTEGER;
BEGIN
    SELECT quantite INTO v_commandee
      FROM info_commande
     WHERE id_info_commande = NEW.id_info_commande
       FOR UPDATE;

    SELECT COALESCE(SUM(quantite_expediee), 0) INTO v_deja
      FROM info_expedition
     WHERE id_info_commande = NEW.id_info_commande
       AND id_info_expedition IS DISTINCT FROM NEW.id_info_expedition;

    IF v_deja + NEW.quantite_expediee > v_commandee THEN
        RAISE EXCEPTION
            'Ligne de commande % : % commandee(s), % deja expediee(s), % de plus refusee(s).',
            NEW.id_info_commande, v_commandee, v_deja, NEW.quantite_expediee
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_valider_quantite_expediee ON info_expedition;
CREATE TRIGGER trg_valider_quantite_expediee
    BEFORE INSERT OR UPDATE OF quantite_expediee, id_info_commande ON info_expedition
    FOR EACH ROW
    EXECUTE FUNCTION valider_quantite_expediee();

CREATE OR REPLACE FUNCTION proteger_quantite_commandee()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_deja INTEGER;
BEGIN
    SELECT COALESCE(SUM(quantite_expediee), 0) INTO v_deja
      FROM info_expedition
     WHERE id_info_commande = OLD.id_info_commande;

    IF NEW.quantite < v_deja THEN
        RAISE EXCEPTION
            'Ligne de commande % : impossible de passer a % unite(s), % deja expediee(s).',
            OLD.id_info_commande, NEW.quantite, v_deja
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_quantite_commandee ON info_commande;
CREATE TRIGGER trg_proteger_quantite_commandee
    BEFORE UPDATE OF quantite ON info_commande
    FOR EACH ROW
    EXECUTE FUNCTION proteger_quantite_commandee();

-- -------------------------------------------------------------
-- 7. Cycle de vie d'une commande
--
-- Le declencheur est le GARDIEN (il refuse ce qui est interdit, peu
-- importe qui modifie la table); la procedure avancer_commande
-- (04_vues_fonctions.sql) est l'OPERATION METIER (elle fait le travail
-- de chaque etape puis change le statut).
--
-- Cycle normal :
--   En attente -> Payee -> En preparation -> Expediee -> Livree
-- Annulation possible depuis En attente, Payee ou En preparation.
--
-- Regles de trg_proteger_commande :
--   a) une commande n'est jamais supprimee (on l'annule);
--   b) une nouvelle commande commence toujours « En attente »;
--   c) une commande Livree ou Annulee est figee (aucune modification);
--   d) le client et la date d'une commande ne changent jamais;
--   e) l'adresse de livraison ne change que « En attente »;
--   f) le statut n'avance que d'une etape a la fois, ou passe a
--      « Annulee » avant l'expedition (pas de retour en arriere);
--   g) « Payee » exige au moins une ligne et des paiements COMPLETES
--      couvrant le total de la commande;
--   h) « Expediee » exige que toutes les quantites soient en expedition;
--   i) « Livree » exige que toutes ses expeditions soient completees.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION proteger_commande()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ancien  VARCHAR(30);
    v_nouveau VARCHAR(30);
    v_total   NUMERIC(12,2);
    v_paye    NUMERIC(12,2);
    v_nb      INTEGER;
BEGIN
    -- a) jamais de suppression
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION
            'Une commande n''est jamais supprimee (commande %) : annulez-la plutot.',
            OLD.id_commande
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT nom_statut INTO v_nouveau FROM statut WHERE id_statut = NEW.id_statut;

    -- b) une commande commence « En attente »
    IF TG_OP = 'INSERT' THEN
        IF v_nouveau IS DISTINCT FROM 'En attente' THEN
            RAISE EXCEPTION
                'Une nouvelle commande doit etre « En attente » (recu : « % »).', v_nouveau
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE
    SELECT nom_statut INTO v_ancien FROM statut WHERE id_statut = OLD.id_statut;

    -- c) Livree et Annulee sont des etats finaux
    IF v_ancien IN ('Livrée', 'Annulée') THEN
        RAISE EXCEPTION
            'La commande % est « % » : elle ne peut plus etre modifiee.',
            OLD.id_commande, v_ancien
            USING ERRCODE = 'check_violation';
    END IF;

    -- d) client et date immuables
    IF NEW.id_client <> OLD.id_client OR NEW.date_commande <> OLD.date_commande THEN
        RAISE EXCEPTION
            'Commande % : le client et la date d''une commande ne changent jamais.',
            OLD.id_commande
            USING ERRCODE = 'check_violation';
    END IF;

    -- e) adresse modifiable seulement « En attente »
    IF NEW.adresse_livraison_commande <> OLD.adresse_livraison_commande
       AND v_ancien <> 'En attente' THEN
        RAISE EXCEPTION
            'Commande % : l''adresse de livraison ne change plus apres « En attente ».',
            OLD.id_commande
            USING ERRCODE = 'check_violation';
    END IF;

    IF NEW.id_statut = OLD.id_statut THEN
        RETURN NEW;  -- pas de changement de statut : rien d'autre a verifier
    END IF;

    -- f) transitions permises
    IF NOT (
           (v_ancien = 'En attente'     AND v_nouveau IN ('Payée', 'Annulée'))
        OR (v_ancien = 'Payée'          AND v_nouveau IN ('En préparation', 'Annulée'))
        OR (v_ancien = 'En préparation' AND v_nouveau IN ('Expédiée', 'Annulée'))
        OR (v_ancien = 'Expédiée'       AND v_nouveau = 'Livrée')
    ) THEN
        RAISE EXCEPTION
            'Commande % : passage de « % » a « % » interdit.',
            OLD.id_commande, v_ancien, v_nouveau
            USING ERRCODE = 'check_violation';
    END IF;

    -- g) Payee : paiements completes >= total
    IF v_nouveau = 'Payée' THEN
        SELECT COUNT(*), COALESCE(SUM(quantite * prix_unitaire), 0)
          INTO v_nb, v_total
          FROM info_commande
         WHERE id_commande = NEW.id_commande;

        SELECT COALESCE(SUM(montant_paiement), 0)
          INTO v_paye
          FROM paiement
         WHERE id_commande = NEW.id_commande
           AND est_complete;

        IF v_nb = 0 THEN
            RAISE EXCEPTION
                'Commande % : une commande sans ligne ne peut pas etre payee.',
                NEW.id_commande
                USING ERRCODE = 'check_violation';
        END IF;

        IF v_paye < v_total THEN
            RAISE EXCEPTION
                'Commande % : paiements completes de % $ pour un total de % $.',
                NEW.id_commande, v_paye, v_total
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- h) Expediee : tout est en expedition
    IF v_nouveau = 'Expédiée' THEN
        SELECT COUNT(*) INTO v_nb
          FROM info_commande ic
         WHERE ic.id_commande = NEW.id_commande
           AND ic.quantite > (SELECT COALESCE(SUM(ie.quantite_expediee), 0)
                              FROM info_expedition ie
                              WHERE ie.id_info_commande = ic.id_info_commande);
        IF v_nb > 0 THEN
            RAISE EXCEPTION
                'Commande % : % ligne(s) pas entierement en expedition.',
                NEW.id_commande, v_nb
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- i) Livree : toutes les expeditions sont completees
    IF v_nouveau = 'Livrée' THEN
        SELECT COUNT(*) INTO v_nb
          FROM info_expedition ie
          JOIN info_commande ic ON ic.id_info_commande = ie.id_info_commande
          JOIN expedition e     ON e.id_expedition     = ie.id_expedition
         WHERE ic.id_commande = NEW.id_commande
           AND NOT e.est_complete;
        IF v_nb > 0 THEN
            RAISE EXCEPTION
                'Commande % : % ligne(s) d''expedition pas encore completee(s).',
                NEW.id_commande, v_nb
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_commande ON commande;
CREATE TRIGGER trg_proteger_commande
    BEFORE INSERT OR UPDATE OR DELETE ON commande
    FOR EACH ROW
    EXECUTE FUNCTION proteger_commande();

-- Annulation : le stock des lignes est rendu.
CREATE OR REPLACE FUNCTION restituer_stock_annulation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF (SELECT nom_statut FROM statut WHERE id_statut = NEW.id_statut) = 'Annulée' THEN
        UPDATE produit p
           SET quantite_totale_produit = p.quantite_totale_produit + ic.quantite
          FROM info_commande ic
         WHERE ic.id_commande = NEW.id_commande
           AND ic.id_produit  = p.id_produit;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_restituer_stock_annulation ON commande;
CREATE TRIGGER trg_restituer_stock_annulation
    AFTER UPDATE OF id_statut ON commande
    FOR EACH ROW
    WHEN (OLD.id_statut IS DISTINCT FROM NEW.id_statut)
    EXECUTE FUNCTION restituer_stock_annulation();

-- Les lignes d'une commande annulee sont figees (sinon le stock deja
-- rendu serait rendu ou preleve une deuxieme fois).
CREATE OR REPLACE FUNCTION proteger_lignes_commande_annulee()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- UPDATE ou DELETE : la commande d'origine ne doit pas etre annulee.
    IF TG_OP <> 'INSERT' THEN
        IF EXISTS (SELECT 1
                   FROM commande c
                   JOIN statut s ON s.id_statut = c.id_statut
                   WHERE c.id_commande = OLD.id_commande
                     AND s.nom_statut = 'Annulée') THEN
            RAISE EXCEPTION
                'La commande % est annulee : ses lignes sont figees.', OLD.id_commande
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- INSERT ou UPDATE : la commande de destination non plus.
    IF TG_OP <> 'DELETE' THEN
        IF EXISTS (SELECT 1
                   FROM commande c
                   JOIN statut s ON s.id_statut = c.id_statut
                   WHERE c.id_commande = NEW.id_commande
                     AND s.nom_statut = 'Annulée') THEN
            RAISE EXCEPTION
                'La commande % est annulee : ses lignes sont figees.', NEW.id_commande
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_lignes_commande_annulee ON info_commande;
CREATE TRIGGER trg_proteger_lignes_commande_annulee
    BEFORE INSERT OR UPDATE OR DELETE ON info_commande
    FOR EACH ROW
    EXECUTE FUNCTION proteger_lignes_commande_annulee();

-- Verification
SELECT event_object_table AS table_cible, trigger_name, action_timing,
       string_agg(event_manipulation, ', ' ORDER BY event_manipulation) AS evenements
FROM information_schema.triggers
WHERE trigger_schema = 'commerce'
GROUP BY event_object_table, trigger_name, action_timing
ORDER BY event_object_table, trigger_name;
