-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 2 : declencheurs
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel"
--   psql -U postgres -d tp1_vincent_trudel -f 02_declencheurs.sql
-- =============================================================

SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- 1. Maintien du stock reel (quantite_totale_produit)
--
-- quantite_totale_produit = stock reellement disponible en entrepot.
--
-- Ce declencheur gere le cote VENTE au niveau de la LIGNE : l'ajout
-- d'une ligne diminue le disponible, sa suppression ou la baisse de
-- sa quantite le restitue. L'annulation d'une commande entiere est
-- geree par trg_restituer_stock_annulation (section 7). Le cote
-- RECEPTION est gere par trg_maj_stock_reception (section 3).
--
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
    -- Si l'UPDATE a change de produit, c'est bien l'ancien produit
    -- qui est credite.
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

CREATE TRIGGER trg_maj_stock_produit
    AFTER INSERT OR UPDATE OR DELETE ON info_commande
    FOR EACH ROW
    EXECUTE FUNCTION maj_stock_produit();

-- -------------------------------------------------------------
-- 2. Regle metier : seul un client ayant achete le produit
--    peut l'evaluer.
--
-- Cette regle ne peut pas s'exprimer par une contrainte CHECK,
-- qui ne peut pas interroger d'autres tables. D'ou le declencheur.
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

CREATE TRIGGER trg_valider_achat_avant_evaluation
    BEFORE INSERT OR UPDATE ON evaluation
    FOR EACH ROW
    EXECUTE FUNCTION valider_achat_avant_evaluation();

-- -------------------------------------------------------------
-- 3. Reception : ajout au stock reel a la validation
--
-- Se declenche quand une reception passe de attendue
-- (est_complete = FALSE) a validee (est_complete = TRUE) : chaque
-- ligne de info_reception ajoute sa quantite au stock du produit.
-- Le declencheur de protection (section 4) empeche ensuite tout
-- retour en arriere, donc le stock n'est jamais ajoute deux fois.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION maj_stock_reception()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.est_complete = FALSE AND NEW.est_complete = TRUE THEN
        UPDATE produit p
           SET quantite_totale_produit = p.quantite_totale_produit + ir.quantite_recu
          FROM info_reception ir
         WHERE ir.id_reception = NEW.id_reception
           AND p.id_produit    = ir.id_produit;
    END IF;

    RETURN NULL;  -- declencheur AFTER : la valeur de retour est ignoree
END;
$$;

CREATE TRIGGER trg_maj_stock_reception
    AFTER UPDATE OF est_complete ON reception
    FOR EACH ROW
    EXECUTE FUNCTION maj_stock_reception();

-- -------------------------------------------------------------
-- 4. Protection des receptions validees
--
-- Une reception validee fait partie de l'historique et a deja
-- modifie le stock. Elle ne peut donc plus etre :
--   - supprimee (BEFORE DELETE);
--   - modifiee, y compris revenir a est_complete = FALSE (BEFORE UPDATE).
-- Une reception encore attendue reste modifiable et supprimable
-- (annulation, erreur de saisie).
-- Une reception doit aussi etre creee attendue (BEFORE INSERT) :
-- creee deja validee, elle n'aurait aucune ligne au moment de la
-- validation et le stock ne serait jamais mis a jour.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION proteger_reception()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.est_complete = TRUE THEN
            RAISE EXCEPTION
                'La reception % doit etre creee non completee, puis validee.',
                NEW.numero_reception
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    -- UPDATE ou DELETE
    IF OLD.est_complete = TRUE THEN
        RAISE EXCEPTION
            'La reception % est deja validee : % refuse(e).',
            OLD.numero_reception,
            CASE TG_OP WHEN 'DELETE' THEN 'suppression' ELSE 'modification' END
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;  -- BEFORE DELETE : retourner OLD laisse la suppression se faire
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_reception
    BEFORE INSERT OR UPDATE OR DELETE ON reception
    FOR EACH ROW
    EXECUTE FUNCTION proteger_reception();

-- Les lignes d'une reception validee sont figees elles aussi :
-- sinon on pourrait vider ou gonfler le detail apres coup et le
-- stock ne concorderait plus avec l'historique.
-- Pour un UPDATE qui deplace une ligne, l'ancienne ET la nouvelle
-- reception sont verifiees.
CREATE OR REPLACE FUNCTION proteger_info_reception()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP <> 'INSERT' AND EXISTS (
        SELECT 1 FROM reception
         WHERE id_reception = OLD.id_reception
           AND est_complete = TRUE
    ) THEN
        RAISE EXCEPTION
            'La reception % est deja validee : ses lignes ne peuvent plus changer.',
            OLD.id_reception
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP <> 'DELETE' AND EXISTS (
        SELECT 1 FROM reception
         WHERE id_reception = NEW.id_reception
           AND est_complete = TRUE
    ) THEN
        RAISE EXCEPTION
            'La reception % est deja validee : ses lignes ne peuvent plus changer.',
            NEW.id_reception
            USING ERRCODE = 'check_violation';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_info_reception
    BEFORE INSERT OR UPDATE OR DELETE ON info_reception
    FOR EACH ROW
    EXECUTE FUNCTION proteger_info_reception();

-- -------------------------------------------------------------
-- 5. Audit des changements de statut d'une commande
--
-- Ecrit une ligne dans audit_statut_commande :
--   - a la creation d'une commande (statut initial);
--   - a chaque changement REEL de id_statut (UPDATE OF se declenche
--     aussi quand la colonne est dans le SET avec la meme valeur :
--     IS DISTINCT FROM filtre ces cas);
--   - a la suppression d'une commande (dernier statut connu).
-- Les noms des statuts sont copies depuis la table statut.
-- Si l'operation echoue ou est annulee (ROLLBACK), la ligne d'audit
-- est annulee avec elle : l'audit ne garde que ce qui a eu lieu.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION audit_statut_commande()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ancien  VARCHAR(30);
    v_nouveau VARCHAR(30);
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.id_statut IS NOT DISTINCT FROM NEW.id_statut THEN
        RETURN NULL;  -- statut inchange : rien a auditer
    END IF;

    IF TG_OP <> 'INSERT' THEN
        SELECT nom_statut INTO v_ancien FROM statut WHERE id_statut = OLD.id_statut;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        SELECT nom_statut INTO v_nouveau FROM statut WHERE id_statut = NEW.id_statut;
    END IF;

    INSERT INTO audit_statut_commande
        (id_commande, operation, ancien_statut, nouveau_statut, utilisateur)
    VALUES
        (CASE WHEN TG_OP = 'DELETE' THEN OLD.id_commande ELSE NEW.id_commande END,
         TG_OP, v_ancien, v_nouveau, current_user);

    RETURN NULL;  -- declencheur AFTER : la valeur de retour est ignoree
END;
$$;

CREATE TRIGGER trg_audit_statut_commande
    AFTER INSERT OR UPDATE OF id_statut OR DELETE ON commande
    FOR EACH ROW
    EXECUTE FUNCTION audit_statut_commande();

-- -------------------------------------------------------------
-- 6. Regle metier : on ne peut pas expedier plus d'unites qu'il
--    n'en a ete commande pour une ligne.
--
-- Une ligne de commande peut etre repartie sur plusieurs colis
-- (info_expedition.quantite_expediee). La somme expediee pour une
-- ligne ne doit jamais depasser info_commande.quantite.
-- Un CHECK ne peut pas faire cette somme (il ne voit qu'une ligne),
-- d'ou deux declencheurs :
--   a) sur info_expedition : refuse un envoi qui ferait depasser
--      la quantite commandee;
--   b) sur info_commande   : refuse de baisser la quantite commandee
--      sous ce qui est deja expedie.
-- Le SELECT ... FOR UPDATE sur la ligne de commande empeche deux
-- expeditions simultanees de depasser ensemble la quantite.
-- -------------------------------------------------------------

CREATE OR REPLACE FUNCTION valider_quantite_expediee()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_commandee INTEGER;
    v_deja      INTEGER;
BEGIN
    SELECT quantite
      INTO v_commandee
      FROM info_commande
     WHERE id_info_commande = NEW.id_info_commande
       FOR UPDATE;

    -- Total deja expedie pour cette ligne, sans compter la ligne
    -- d'expedition en cours (utile pour un UPDATE). Pour un INSERT,
    -- l'identifiant est deja genere quand le declencheur BEFORE s'execute.
    SELECT COALESCE(SUM(quantite_expediee), 0)
      INTO v_deja
      FROM info_expedition
     WHERE id_info_commande   = NEW.id_info_commande
       AND id_info_expedition <> NEW.id_info_expedition;

    IF v_deja + NEW.quantite_expediee > v_commandee THEN
        RAISE EXCEPTION
            'Ligne de commande % : % unite(s) commandee(s), % deja expediee(s), % demandee(s) : depassement refuse.',
            NEW.id_info_commande, v_commandee, v_deja, NEW.quantite_expediee
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_valider_quantite_expediee
    BEFORE INSERT OR UPDATE ON info_expedition
    FOR EACH ROW
    EXECUTE FUNCTION valider_quantite_expediee();

CREATE OR REPLACE FUNCTION proteger_quantite_commandee()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_expediee INTEGER;
BEGIN
    SELECT COALESCE(SUM(quantite_expediee), 0)
      INTO v_expediee
      FROM info_expedition
     WHERE id_info_commande = NEW.id_info_commande;

    IF NEW.quantite < v_expediee THEN
        RAISE EXCEPTION
            'Ligne de commande % : % unite(s) deja expediee(s), la quantite ne peut pas descendre a %.',
            NEW.id_info_commande, v_expediee, NEW.quantite
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_quantite_commandee
    BEFORE UPDATE OF quantite ON info_commande
    FOR EACH ROW
    EXECUTE FUNCTION proteger_quantite_commandee();

-- -------------------------------------------------------------
-- 7. Annulation d'une commande
--
-- Regles metier :
--   a) Une commande n'est jamais supprimee : on l'annule, pour
--      conserver l'historique des commandes annulees.
--   b) Une commande ne peut etre annulee que tant qu'elle n'est pas
--      en expedition (statut En attente, Payée ou En préparation).
--   c) Une commande annulee est figee : ni son statut (pas de
--      reactivation : le client passe une nouvelle commande), ni ses
--      autres champs, ni ses lignes ne peuvent changer.
--   d) A l'annulation, la quantite de chaque ligne est rendue au stock.
--
-- Cycle de vie (ajoute le 22 sept.) : TOUT changement de statut est
-- valide ici, quelle que soit sa source (procedure avancer_commande,
-- application ou UPDATE direct) :
--   e) une nouvelle commande nait toujours "En attente";
--   f) seules ces transitions sont permises :
--        En attente -> Payée -> En préparation -> Expédiée -> Livrée
--        (+ l'annulation de la regle b);
--   g) "Payée" exige au moins une ligne et des paiements completes
--      (est_complete) couvrant le total de la commande. On ne peut donc
--      pas preparer une commande qui n'est pas payee;
--   h) "Expédiée" exige que chaque ligne soit entierement prevue dans
--      une ou plusieurs expeditions (info_expedition);
--   i) "Livrée" exige que toutes ces expeditions soient completees.
--
-- Les statuts sont reperes par leur NOM (nom_statut) et non par leur
-- id, qui depend de l'ordre d'insertion.
-- Le TRUNCATE du script de donnees n'est pas bloque : TRUNCATE ne
-- declenche pas les declencheurs FOR EACH ROW.
-- -------------------------------------------------------------

-- 7a. Protection de la commande (regles a, b, c, e, f, g, h et i)
CREATE OR REPLACE FUNCTION proteger_commande()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_ancien  VARCHAR(30);
    v_nouveau VARCHAR(30);
    v_total   NUMERIC(12,2);
    v_paye    NUMERIC(12,2);
BEGIN
    -- Regle a
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION
            'La commande % ne peut pas etre supprimee : il faut l''annuler.',
            OLD.id_commande
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT nom_statut INTO v_nouveau FROM statut WHERE id_statut = NEW.id_statut;

    -- Regle e : creation
    IF TG_OP = 'INSERT' THEN
        IF v_nouveau IS DISTINCT FROM 'En attente' THEN
            RAISE EXCEPTION
                'Une nouvelle commande doit avoir le statut "En attente" (statut demande : "%").',
                v_nouveau
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    SELECT nom_statut INTO v_ancien FROM statut WHERE id_statut = OLD.id_statut;

    -- Regle c
    IF v_ancien = 'Annulée' THEN
        RAISE EXCEPTION
            'La commande % est annulee : aucune modification permise. Le client doit passer une nouvelle commande.',
            OLD.id_commande
            USING ERRCODE = 'check_violation';
    END IF;

    -- Statut inchange (modification d'un autre champ) : rien a verifier
    IF NEW.id_statut = OLD.id_statut THEN
        RETURN NEW;
    END IF;

    -- Regle b
    -- Liste des statuts AUTORISES plutot que des statuts interdits :
    -- un statut ajoute plus tard sera refuse par defaut.
    IF v_nouveau = 'Annulée' THEN
        IF v_ancien NOT IN ('En attente', 'Payée', 'En préparation') THEN
            RAISE EXCEPTION
                'La commande % a le statut "%" : elle est en expedition, annulation refusee.',
                OLD.id_commande, v_ancien
                USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
    END IF;

    -- Regle f : transitions permises (liste blanche)
    IF NOT (   (v_ancien = 'En attente'     AND v_nouveau = 'Payée')
            OR (v_ancien = 'Payée'          AND v_nouveau = 'En préparation')
            OR (v_ancien = 'En préparation' AND v_nouveau = 'Expédiée')
            OR (v_ancien = 'Expédiée'       AND v_nouveau = 'Livrée')) THEN
        RAISE EXCEPTION
            'Commande % : passage de "%" a "%" interdit. Ordre permis : En attente -> Payée -> En préparation -> Expédiée -> Livrée.',
            OLD.id_commande, v_ancien, v_nouveau
            USING ERRCODE = 'check_violation';
    END IF;

    -- Regle g : payee = au moins une ligne + paiements completes >= total
    IF v_nouveau = 'Payée' THEN
        SELECT COALESCE(SUM(quantite * prix_unitaire), 0)
          INTO v_total
          FROM info_commande
         WHERE id_commande = NEW.id_commande;

        IF v_total = 0 THEN
            RAISE EXCEPTION
                'Commande % : aucune ligne, elle ne peut pas etre payee.',
                NEW.id_commande
                USING ERRCODE = 'check_violation';
        END IF;

        SELECT COALESCE(SUM(montant_paiement), 0)
          INTO v_paye
          FROM paiement
         WHERE id_commande = NEW.id_commande
           AND est_complete;

        IF v_paye < v_total THEN
            RAISE EXCEPTION
                'Commande % : paiements completes de % pour un total de %, passage a "Payée" refuse.',
                NEW.id_commande, v_paye, v_total
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    -- Regle h : chaque ligne entierement prevue dans une expedition
    IF v_nouveau = 'Expédiée' AND EXISTS (
        SELECT 1
          FROM info_commande ic
         WHERE ic.id_commande = NEW.id_commande
           AND ic.quantite > (SELECT COALESCE(SUM(ie.quantite_expediee), 0)
                                FROM info_expedition ie
                               WHERE ie.id_info_commande = ic.id_info_commande)
    ) THEN
        RAISE EXCEPTION
            'Commande % : certaines quantites ne sont prevues dans aucune expedition, passage a "Expédiée" refuse.',
            NEW.id_commande
            USING ERRCODE = 'check_violation';
    END IF;

    -- Regle i : toutes les expeditions de la commande completees
    IF v_nouveau = 'Livrée' AND EXISTS (
        SELECT 1
          FROM info_commande ic
          JOIN info_expedition ie ON ie.id_info_commande = ic.id_info_commande
          JOIN expedition e       ON e.id_expedition     = ie.id_expedition
         WHERE ic.id_commande = NEW.id_commande
           AND NOT e.est_complete
    ) THEN
        RAISE EXCEPTION
            'Commande % : au moins une expedition n''est pas completee, passage a "Livrée" refuse.',
            NEW.id_commande
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_commande
    BEFORE INSERT OR UPDATE OR DELETE ON commande
    FOR EACH ROW
    EXECUTE FUNCTION proteger_commande();

-- 7b. Remise en stock a l'annulation (regle d)
-- Ne s'execute qu'une fois par commande : 7a empeche toute
-- modification d'une commande deja annulee.
-- UNIQUE (id_commande, id_produit) garantit qu'un produit n'apparait
-- qu'une fois dans la commande, donc l'UPDATE ... FROM est sans doublon.
CREATE OR REPLACE FUNCTION restituer_stock_annulation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF  (SELECT nom_statut FROM statut WHERE id_statut = NEW.id_statut) =  'Annulée'
    AND (SELECT nom_statut FROM statut WHERE id_statut = OLD.id_statut) <> 'Annulée' THEN
        UPDATE produit p
           SET quantite_totale_produit = p.quantite_totale_produit + ic.quantite
          FROM info_commande ic
         WHERE ic.id_commande = NEW.id_commande
           AND p.id_produit   = ic.id_produit;
    END IF;

    RETURN NULL;  -- declencheur AFTER : la valeur de retour est ignoree
END;
$$;

CREATE TRIGGER trg_restituer_stock_annulation
    AFTER UPDATE OF id_statut ON commande
    FOR EACH ROW
    EXECUTE FUNCTION restituer_stock_annulation();

-- 7c. Lignes d'une commande annulee figees (regle c)
-- Sans cette protection, supprimer une ligne d'une commande annulee
-- ferait rendre son stock une deuxieme fois par trg_maj_stock_produit.
-- Pour un UPDATE qui deplace une ligne, l'ancienne ET la nouvelle
-- commande sont verifiees.
-- FOR SHARE verrouille la commande le temps de la transaction : une
-- annulation simultanee attend donc la fin de l'ajout de la ligne,
-- puis rend aussi son stock (sinon cette ligne serait oubliee).
CREATE OR REPLACE FUNCTION proteger_lignes_commande_annulee()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_statut VARCHAR(30);
BEGIN
    IF TG_OP <> 'INSERT' THEN
        SELECT s.nom_statut INTO v_statut
          FROM commande c
          JOIN statut s ON s.id_statut = c.id_statut
         WHERE c.id_commande = OLD.id_commande
           FOR SHARE OF c;

        IF v_statut = 'Annulée' THEN
            RAISE EXCEPTION
                'La commande % est annulee : ses lignes ne peuvent plus changer.',
                OLD.id_commande
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF TG_OP <> 'DELETE' THEN
        SELECT s.nom_statut INTO v_statut
          FROM commande c
          JOIN statut s ON s.id_statut = c.id_statut
         WHERE c.id_commande = NEW.id_commande
           FOR SHARE OF c;

        IF v_statut = 'Annulée' THEN
            RAISE EXCEPTION
                'La commande % est annulee : ses lignes ne peuvent plus changer.',
                NEW.id_commande
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_proteger_lignes_commande_annulee
    BEFORE INSERT OR UPDATE OR DELETE ON info_commande
    FOR EACH ROW
    EXECUTE FUNCTION proteger_lignes_commande_annulee();
