-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 3 : transactions (COMMIT et ROLLBACK)
-- =============================================================
-- NE FAIT PAS PARTIE DE creer_bd.command : ce script modifie les
-- donnees et son 2e scenario echoue VOLONTAIREMENT (le lanceur
-- s'arrete a la premiere erreur).
--
-- A EXECUTER A LA MAIN, BLOC PAR BLOC, dans un Query Tool pgAdmin
-- connecte a "tp1_vincent_trudel", ET TOUJOURS DANS LE MEME ONGLET :
-- la table temporaire tx_choix vit le temps de la session.
--
-- Regle metier protegee : une commande ne peut passer a "Payée" que
-- si des paiements completes couvrent son total
-- (trg_proteger_commande, regle g). La transaction garantit en plus
-- le TOUT OU RIEN : on ne garde jamais un paiement capture sans que
-- la commande soit payee.
--
-- Modele du paiement par carte (reel, simule ici) :
--   1. AUTORISATION : la banque reserve le montant sur la carte.
--      -> paiement.est_complete = FALSE, date_paiement NULL
--   2. CAPTURE      : le commerçant confirme, le client est debite.
--      -> paiement.est_complete = TRUE + date_paiement
-- Le processeur de paiement (Stripe, Moneris...) est un service
-- EXTERNE : la base ne l'appelle pas. C'est l'application (etape 5)
-- qui l'interroge, puis qui fait COMMIT ou ROLLBACK selon sa reponse.
-- Ici, sa reponse est ecrite en commentaire avant chaque scenario.
-- Rappel : un ROLLBACK dans la base n'annule pas un debit sur la
-- carte; un vrai systeme capture apres le COMMIT, ou rembourse.
-- =============================================================

SET search_path TO commerce, public;

-- Memorise les commandes choisies (table temporaire : disparait
-- a la fin de la session, ne touche pas au schema).
CREATE TEMP TABLE IF NOT EXISTS tx_choix (
    etape       TEXT PRIMARY KEY,
    id_commande INTEGER,
    id_paiement INTEGER,
    total       NUMERIC(12,2)
);

-- =============================================================
-- SCENARIO 1 -- COMMIT : le processeur APPROUVE la capture
-- =============================================================

-- 1.1 Choisir une commande "En attente" qui a des lignes et un
--     paiement autorise (non complete) couvrant son total.
DELETE FROM tx_choix WHERE etape = 'succes';

INSERT INTO tx_choix (etape, id_commande, id_paiement, total)
SELECT 'succes', c.id_commande, p.id_paiement, t.total
  FROM commande c
  JOIN statut   s ON s.id_statut = c.id_statut AND s.nom_statut = 'En attente'
  JOIN paiement p ON p.id_commande = c.id_commande AND p.est_complete = FALSE
  JOIN LATERAL (SELECT SUM(ic.quantite * ic.prix_unitaire) AS total
                  FROM info_commande ic
                 WHERE ic.id_commande = c.id_commande) t ON t.total IS NOT NULL
 WHERE p.montant_paiement >= t.total
 ORDER BY c.id_commande
 LIMIT 1;

SELECT * FROM tx_choix WHERE etape = 'succes';

-- 1.2 Etat AVANT
SELECT c.id_commande, s.nom_statut, p.id_paiement, p.montant_paiement,
       p.est_complete, p.date_paiement
  FROM tx_choix x
  JOIN commande c ON c.id_commande = x.id_commande
  JOIN statut   s ON s.id_statut   = c.id_statut
  JOIN paiement p ON p.id_paiement = x.id_paiement
 WHERE x.etape = 'succes';

-- 1.3 La transaction
--     Reponse du processeur : APPROUVE (capture du montant reserve).
BEGIN;

UPDATE paiement
   SET est_complete  = TRUE,
       date_paiement = LOCALTIMESTAMP
 WHERE id_paiement = (SELECT id_paiement FROM tx_choix WHERE etape = 'succes');

UPDATE commande
   SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
 WHERE id_commande = (SELECT id_commande FROM tx_choix WHERE etape = 'succes');

COMMIT;

-- 1.4 Etat APRES : statut "Payée", paiement capture, ligne d'audit
SELECT c.id_commande, s.nom_statut, p.est_complete, p.date_paiement
  FROM tx_choix x
  JOIN commande c ON c.id_commande = x.id_commande
  JOIN statut   s ON s.id_statut   = c.id_statut
  JOIN paiement p ON p.id_paiement = x.id_paiement
 WHERE x.etape = 'succes';

SELECT a.operation, a.ancien_statut, a.nouveau_statut, a.utilisateur
  FROM audit_statut_commande a
  JOIN tx_choix x ON x.id_commande = a.id_commande
 WHERE x.etape = 'succes'
 ORDER BY a.id_audit_statut_commande;

-- =============================================================
-- SCENARIO 2 -- ROLLBACK : autorisation PARTIELLE
-- La banque n'a reserve qu'une partie du montant (carte au plafond).
-- L'application tente quand meme la capture : le declencheur refuse
-- le passage a "Payée", et le ROLLBACK annule AUSSI la capture.
-- =============================================================

-- 2.1 Choisir une AUTRE commande "En attente" avec un paiement autorise
DELETE FROM tx_choix WHERE etape = 'echec';

INSERT INTO tx_choix (etape, id_commande, id_paiement, total)
SELECT 'echec', c.id_commande, p.id_paiement, t.total
  FROM commande c
  JOIN statut   s ON s.id_statut = c.id_statut AND s.nom_statut = 'En attente'
  JOIN paiement p ON p.id_commande = c.id_commande AND p.est_complete = FALSE
  JOIN LATERAL (SELECT SUM(ic.quantite * ic.prix_unitaire) AS total
                  FROM info_commande ic
                 WHERE ic.id_commande = c.id_commande) t ON t.total IS NOT NULL
 WHERE c.id_commande NOT IN (SELECT id_commande FROM tx_choix WHERE etape = 'succes')
 ORDER BY c.id_commande
 LIMIT 1;

SELECT * FROM tx_choix WHERE etape = 'echec';

-- 2.2 Etat AVANT
SELECT c.id_commande, s.nom_statut, p.montant_paiement, x.total,
       p.est_complete, p.date_paiement
  FROM tx_choix x
  JOIN commande c ON c.id_commande = x.id_commande
  JOIN statut   s ON s.id_statut   = c.id_statut
  JOIN paiement p ON p.id_paiement = x.id_paiement
 WHERE x.etape = 'echec';

-- 2.3 La transaction : le 2e UPDATE doit LEVER UNE ERREUR
BEGIN;

-- Capture de la seule moitie autorisee
UPDATE paiement
   SET est_complete     = TRUE,
       date_paiement    = LOCALTIMESTAMP,
       montant_paiement = ROUND((SELECT total / 2 FROM tx_choix WHERE etape = 'echec'), 2)
 WHERE id_paiement = (SELECT id_paiement FROM tx_choix WHERE etape = 'echec');

-- Refus attendu : paiements completes < total de la commande
UPDATE commande
   SET id_statut = (SELECT id_statut FROM statut WHERE nom_statut = 'Payée')
 WHERE id_commande = (SELECT id_commande FROM tx_choix WHERE etape = 'echec');

-- (apres l'erreur, la transaction est "avortee" : PostgreSQL refuse
--  toute autre commande jusqu'au ROLLBACK)
ROLLBACK;

-- 2.4 Etat APRES : tout est revenu comme avant.
--     Le paiement est toujours EN AUTORISATION (est_complete = FALSE,
--     montant d'origine, aucune date) et la commande "En attente".
SELECT c.id_commande, s.nom_statut, p.montant_paiement, x.total,
       p.est_complete, p.date_paiement
  FROM tx_choix x
  JOIN commande c ON c.id_commande = x.id_commande
  JOIN statut   s ON s.id_statut   = c.id_statut
  JOIN paiement p ON p.id_paiement = x.id_paiement
 WHERE x.etape = 'echec';

-- Aucune ligne d'audit "UPDATE" pour cette commande : le changement
-- de statut n'a jamais eu lieu (une ligne INSERT, du chargement, reste).
SELECT a.operation, a.ancien_statut, a.nouveau_statut
  FROM audit_statut_commande a
  JOIN tx_choix x ON x.id_commande = a.id_commande
 WHERE x.etape = 'echec'
 ORDER BY a.id_audit_statut_commande;

-- Pour rejouer les deux scenarios a neuf : relancer creer_bd.command
-- (le scenario 1 a reellement modifie la base).
