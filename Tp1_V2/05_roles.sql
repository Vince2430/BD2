-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 5 (scripts) : roles et privileges
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel"
-- en tant que superutilisateur (postgres)
--   psql -U postgres -d tp1_vincent_trudel -f 05_roles.sql
--
-- A RELANCER apres 01 ou 04 (recreer un objet efface ses privileges).
--
-- Choix (option A) : le PERSONNEL est represente par des roles
-- PostgreSQL; les CLIENTS du site sont authentifies par l'application
-- (table client, hash_mot_passe_client), pas par PostgreSQL.
--
-- Groupes (NOLOGIN), emboites : chaque niveau herite du precedent.
--   tp1_employe      : LECTURE seulement
--   tp1_gestionnaire : + MODIFICATION (INSERT/UPDATE), avancer_commande
--   tp1_admin        : + MAINTAIN (VACUUM, ANALYZE, REINDEX, REFRESH)
-- Utilisateurs (LOGIN) : demo_employe, demo_gestionnaire, demo_admin.
--
-- Principe du moindre privilege :
--   - aucun DELETE ni TRUNCATE pour personne (une commande est annulee,
--     jamais supprimee; l'historique est conserve);
--   - hash_mot_passe_client illisible (privilege par colonne);
--   - PUBLIC perd ses droits par defaut (CONNECT, EXECUTE).
--
-- AUCUN MOT DE PASSE dans ce script. Apres chaque execution, les
-- definir a la main (pgAdmin ou psql) :
--   ALTER ROLE demo_gestionnaire WITH PASSWORD '...';
--   ALTER ROLE demo_employe      WITH PASSWORD '...';
-- =============================================================

SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- 1. Supprimer les roles existants (relance du script)
-- Les roles sont au niveau du SERVEUR : DROP OWNED BY retire leurs
-- privileges dans la base courante avant DROP ROLE.
-- -------------------------------------------------------------
DO $$
DECLARE
    v_role TEXT;
BEGIN
    FOREACH v_role IN ARRAY ARRAY['demo_admin', 'demo_gestionnaire', 'demo_employe',
                                  'tp1_admin', 'tp1_gestionnaire', 'tp1_employe']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            EXECUTE format('DROP OWNED BY %I', v_role);
            EXECUTE format('DROP ROLE %I', v_role);
        END IF;
    END LOOP;
END;
$$;

-- -------------------------------------------------------------
-- 2. Retirer les droits par defaut de PUBLIC
-- -------------------------------------------------------------
REVOKE ALL     ON DATABASE tp1_vincent_trudel FROM PUBLIC;
REVOKE ALL     ON SCHEMA commerce             FROM PUBLIC;
REVOKE ALL     ON ALL TABLES    IN SCHEMA commerce FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA commerce FROM PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA commerce FROM PUBLIC;

-- -------------------------------------------------------------
-- 3. Groupes
-- -------------------------------------------------------------
CREATE ROLE tp1_employe      NOLOGIN;
CREATE ROLE tp1_gestionnaire NOLOGIN;
CREATE ROLE tp1_admin        NOLOGIN;

GRANT tp1_employe      TO tp1_gestionnaire;
GRANT tp1_gestionnaire TO tp1_admin;

-- -------------------------------------------------------------
-- 4. tp1_employe : lecture
-- -------------------------------------------------------------
GRANT CONNECT ON DATABASE tp1_vincent_trudel TO tp1_employe;
GRANT USAGE   ON SCHEMA commerce             TO tp1_employe;

GRANT SELECT ON categorie, statut, produit, specification_produit,
                commande, info_commande, paiement, expedition,
                info_expedition, reception, info_reception, evaluation,
                audit_statut_commande
      TO tp1_employe;

-- client : toutes les colonnes SAUF hash_mot_passe_client
GRANT SELECT (id_client, nom_client, courriel_client, telephone_client, adresse_client)
      ON client TO tp1_employe;

GRANT SELECT ON v_commandes, v_receptions_attendues, mv_ventes_produit_7j
      TO tp1_employe;

GRANT EXECUTE ON FUNCTION details_commande(INTEGER) TO tp1_employe;

-- -------------------------------------------------------------
-- 5. tp1_gestionnaire : modification (herite de la lecture)
-- -------------------------------------------------------------
-- Tables d'operation
GRANT INSERT, UPDATE ON commande, info_commande, paiement, expedition,
                        info_expedition, reception, info_reception, evaluation
      TO tp1_gestionnaire;

-- Catalogue et clients (UPDATE sur produit aussi necessaire aux
-- declencheurs de stock, qui s'executent avec les droits de l'appelant)
GRANT INSERT, UPDATE ON categorie, produit, specification_produit, client
      TO tp1_gestionnaire;

-- Audit : le declencheur n'est pas SECURITY DEFINER, il ecrit avec les
-- droits de l'utilisateur qui modifie la commande.
-- Limite connue : un gestionnaire pourrait inserer une fausse ligne
-- d'audit a la main.
GRANT INSERT ON audit_statut_commande TO tp1_gestionnaire;

-- La table statut reste en lecture seule (le cycle de vie en depend).

GRANT EXECUTE ON PROCEDURE avancer_commande(INTEGER, VARCHAR) TO tp1_gestionnaire;

-- -------------------------------------------------------------
-- 6. tp1_admin : maintenance (PostgreSQL 17+)
-- MAINTAIN permet VACUUM, ANALYZE, REINDEX, CLUSTER, LOCK TABLE et
-- REFRESH MATERIALIZED VIEW, sans donner DELETE ni TRUNCATE.
-- -------------------------------------------------------------
GRANT MAINTAIN ON ALL TABLES IN SCHEMA commerce TO tp1_admin;
GRANT MAINTAIN ON mv_ventes_produit_7j          TO tp1_admin;

-- -------------------------------------------------------------
-- 7. Utilisateurs de demonstration (sans mot de passe ici)
-- -------------------------------------------------------------
CREATE ROLE demo_employe      LOGIN IN ROLE tp1_employe;
CREATE ROLE demo_gestionnaire LOGIN IN ROLE tp1_gestionnaire;

-- demo_admin peut creer des utilisateurs et leur donner les groupes
-- employe et gestionnaire (ADMIN OPTION), mais pas le groupe admin.
CREATE ROLE demo_admin LOGIN CREATEROLE IN ROLE tp1_admin;
GRANT tp1_employe, tp1_gestionnaire TO demo_admin WITH ADMIN OPTION;

-- -------------------------------------------------------------
-- Verification
-- -------------------------------------------------------------
SELECT grantee, table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'commerce'
  AND grantee LIKE 'tp1_%'
GROUP BY grantee, table_name
ORDER BY grantee, table_name;

SELECT r.rolname AS membre, g.rolname AS groupe, m.admin_option
FROM pg_auth_members m
JOIN pg_roles r ON r.oid = m.member
JOIN pg_roles g ON g.oid = m.roleid
WHERE g.rolname LIKE 'tp1_%'
ORDER BY groupe, membre;
