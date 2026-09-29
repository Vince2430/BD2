-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Demonstration des transactions : COMMIT et ROLLBACK
-- =============================================================
-- HORS DU LANCEUR : a executer A LA MAIN, BLOC PAR BLOC, dans le
-- MEME onglet du Query Tool de pgAdmin (la table temporaire tx_choix
-- n'existe que dans cette session).
--
-- Le scenario 1 MODIFIE la base (COMMIT). Pour rejouer la
-- demonstration depuis le debut : relancer creer_bd.command.
--
-- -------------------------------------------------------------
-- Regle metier protegee
-- -------------------------------------------------------------
-- Paiement par carte en deux temps :
--   1) autorisation : paiement.est_complete = FALSE (montant reserve);
--   2) capture      : est_complete = TRUE + date (montant encaisse).
-- Payer une commande = capturer le paiement ET passer la commande a
-- « Payée ». Ces deux changements doivent reussir ENSEMBLE ou pas du
-- tout :
--   - jamais de commande « Payée » sans paiement suffisant
--     (trg_proteger_commande, regle g);
--   - jamais de paiement capture « orphelin » (argent encaisse pour
--     une commande restee « En attente »).
--
-- Le processeur de paiement externe est SIMULE : sa reponse est
-- indiquee en commentaire. C'est l'application (option 7) qui decide
-- du COMMIT ou du ROLLBACK selon cette reponse.
-- =============================================================

SET search_path TO commerce, public;

-- =============================================================
-- BLOC 0 : choisir deux commandes « En attente » ayant une
--          autorisation non capturee couvrant leur total
-- =============================================================
DROP TABLE IF EXISTS pg_temp.tx_choix;
CREATE TEMP TABLE tx_choix AS
SELECT ROW_NUMBER() OVER (ORDER BY c.id_commande) AS scenario,
       c.id_commande
FROM commande c
JOIN statut s ON s.id_statut = c.id_statut
WHERE s.nom_statut = 'En attente'
  AND EXISTS (SELECT 1 FROM paiement p
              WHERE p.id_commande = c.id_commande AND NOT p.est_complete)
ORDER BY c.id_commande
LIMIT 2;

-- Etat de depart des deux commandes
SELECT t.scenario, c.id_commande, s.nom_statut,
       p.id_paiement, p.montant_paiement, p.est_complete, p.date_paiement,
       (SELECT SUM(quantite * prix_unitaire) FROM info_commande ic
        WHERE ic.id_commande = c.id_commande) AS total_commande
FROM tx_choix t
JOIN commande c ON c.id_commande = t.id_commande
JOIN statut s   ON s.id_statut   = c.id_statut
JOIN paiement p ON p.id_commande = c.id_commande
ORDER BY t.scenario;

-- =============================================================
-- SCENARIO 1 : capture approuvee -> COMMIT
-- (executer les blocs 1.1, 1.2 et 1.3 un apres l'autre)
-- =============================================================

-- 1.1 Debut de la transaction + capture du montant autorise
--     Reponse simulee du processeur : « APPROUVEE, montant complet »
BEGIN;

UPDATE paiement
   SET est_complete  = TRUE,
       date_paiement = LOCALTIMESTAMP
 WHERE id_commande = (SELECT id_commande FROM tx_choix WHERE scenario = 1)
   AND NOT est_complete;

-- 1.2 Passage a « Payée » : le declencheur verifie que les paiements
--     completes couvrent le total -> accepte.
UPDATE commande
   SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
 WHERE id_commande = (SELECT id_commande FROM tx_choix WHERE scenario = 1);

-- 1.3 Tout a reussi : on confirme.
COMMIT;

-- Verification : commande « Payée », paiement capture, ligne d'audit.
SELECT c.id_commande, s.nom_statut, p.est_complete, p.date_paiement, p.montant_paiement
FROM commande c
JOIN statut s   ON s.id_statut   = c.id_statut
JOIN paiement p ON p.id_commande = c.id_commande
WHERE c.id_commande = (SELECT id_commande FROM tx_choix WHERE scenario = 1);

SELECT * FROM audit_statut_commande
WHERE id_commande = (SELECT id_commande FROM tx_choix WHERE scenario = 1)
ORDER BY id_audit;

-- =============================================================
-- SCENARIO 2 : autorisation partielle -> refus -> ROLLBACK
-- Executer 2.1 + 2.2 ensemble, puis 2.3 SEUL, puis 2.4 SEUL.
-- (Dans pgAdmin, une erreur annule tout l'envoi en cours : c'est
--  pourquoi le ROLLBACK est execute a part.)
-- =============================================================

-- 2.1 Debut de la transaction
BEGIN;

-- 2.2 Capture partielle : le processeur n'accepte que la moitie.
--     Reponse simulee : « PARTIELLE, 50 % du montant »
UPDATE paiement
   SET est_complete     = TRUE,
       date_paiement    = LOCALTIMESTAMP,
       montant_paiement = ROUND(montant_paiement / 2, 2)
 WHERE id_commande = (SELECT id_commande FROM tx_choix WHERE scenario = 2)
   AND NOT est_complete;

-- 2.3 Passage a « Payée » : REFUSE par trg_proteger_commande (regle g)
--     ERREUR attendue : « paiements completes de X $ pour un total de Y $ »
--     La transaction est maintenant en echec.
UPDATE commande
   SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
 WHERE id_commande = (SELECT id_commande FROM tx_choix WHERE scenario = 2);

-- 2.4 On annule TOUT : la capture partielle disparait aussi.
ROLLBACK;

-- Verification : la commande est toujours « En attente », le paiement
-- est redevenu une autorisation du montant complet, aucun audit ajoute.
SELECT c.id_commande, s.nom_statut, p.est_complete, p.date_paiement, p.montant_paiement
FROM commande c
JOIN statut s   ON s.id_statut   = c.id_statut
JOIN paiement p ON p.id_commande = c.id_commande
WHERE c.id_commande = (SELECT id_commande FROM tx_choix WHERE scenario = 2);

SELECT * FROM audit_statut_commande
WHERE id_commande = (SELECT id_commande FROM tx_choix WHERE scenario = 2)
ORDER BY id_audit;
