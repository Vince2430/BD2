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
-- Semantique des deux quantites :
--   quantite_totale_produit    = stock reellement disponible en entrepot
--   quantite_entrante_produit  = quantite attendue d'un fournisseur,
--                                pas encore recue (previsionnel)
--
-- Le declencheur ne touche QUE le stock reel : une commande client
-- diminue le disponible, une annulation le restitue. La quantite
-- entrante releve du reapprovisionnement et n'est pas geree ici.
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
