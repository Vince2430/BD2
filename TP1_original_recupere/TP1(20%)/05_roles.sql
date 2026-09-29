-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 3 : roles, groupes et privileges minimaux
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel",
-- APRES 04_vues_fonctions.sql (les objets doivent exister), avec un
-- utilisateur qui peut creer des roles (postgres).
--   psql -U postgres -d tp1_vincent_trudel -f 05_roles.sql
--
-- A RELANCER apres toute re-execution de 01 ou 04 : recreer une
-- table, une vue ou une routine efface les privileges accordes dessus.
--
-- Qui se connecte a la base ?
--   - le PERSONNEL (employe, gestionnaire, admin) : des roles
--     PostgreSQL, authentifies par PostgreSQL;
--   - les CLIENTS : jamais directement. Ils sont authentifies par
--     l'application (client.hash_mot_passe_client).
--
-- Groupes (NOLOGIN), emboites : chaque groupe herite du precedent et
-- ne recoit que ce qu'il AJOUTE.
--   tp1_employe      : lecture seule (+ details_commande)
--   tp1_gestionnaire : + INSERT / UPDATE, + avancer_commande
--   tp1_admin        : + MAINTAIN (refresh, VACUUM, ANALYZE, REINDEX)
--                      + creation d'utilisateurs (voir demo_admin)
-- Personne n'a DELETE ni TRUNCATE : une commande ne se supprime pas,
-- et TRUNCATE contournerait les declencheurs.
--
-- Les roles existent au niveau du SERVEUR (pas de la base) : ils
-- sont prefixes tp1_ / demo_ pour ne jamais toucher un role d'un
-- autre projet, et supprimes puis recrees a chaque execution.
--
-- Utilisateurs de demonstration (LOGIN), SANS mot de passe ici :
-- le definir a la main apres l'execution, par exemple dans psql
--   \password demo_employe
-- ou dans pgAdmin (Login/Group Roles > Properties > Definition).
-- =============================================================

SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- 1. Nettoyage (relancable)
-- DROP OWNED BY retire les privileges du role dans CETTE base;
-- le role peut ensuite etre supprime.
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
-- 2. Groupes et hierarchie
-- -------------------------------------------------------------
CREATE ROLE tp1_employe      NOLOGIN;
CREATE ROLE tp1_gestionnaire NOLOGIN;
CREATE ROLE tp1_admin        NOLOGIN;

GRANT tp1_employe      TO tp1_gestionnaire;   -- gestionnaire herite d'employe
GRANT tp1_gestionnaire TO tp1_admin;          -- admin herite de gestionnaire

-- -------------------------------------------------------------
-- 3. Retirer les droits donnes par defaut a PUBLIC (tout le monde)
-- -------------------------------------------------------------
REVOKE ALL ON DATABASE tp1_vincent_trudel FROM PUBLIC;       -- CONNECT, TEMPORARY
REVOKE ALL ON SCHEMA commerce FROM PUBLIC;
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA commerce FROM PUBLIC;

-- -------------------------------------------------------------
-- 4. tp1_employe : lecture seule
-- -------------------------------------------------------------
GRANT CONNECT ON DATABASE tp1_vincent_trudel TO tp1_employe;
GRANT USAGE   ON SCHEMA commerce             TO tp1_employe;

-- Toutes les tables, vues et la vue materialisee
GRANT SELECT ON ALL TABLES IN SCHEMA commerce TO tp1_employe;

-- Sauf le hachage du mot de passe des clients : seul l'application
-- d'authentification des clients en a besoin. Privilege par colonne.
REVOKE SELECT ON client FROM tp1_employe;
GRANT  SELECT (id_client, nom_client, courriel_client, telephone_client, adresse_client)
    ON client TO tp1_employe;

GRANT EXECUTE ON FUNCTION details_commande(INTEGER) TO tp1_employe;

-- -------------------------------------------------------------
-- 5. tp1_gestionnaire : + INSERT / UPDATE
-- -------------------------------------------------------------
-- Tables d'operation et catalogue. statut reste en lecture seule
-- (les regles metier reposent sur ses noms).
GRANT INSERT, UPDATE ON
    commande, info_commande, paiement,
    expedition, info_expedition,
    reception, info_reception,
    client, evaluation,
    produit, categorie, specification_produit
TO tp1_gestionnaire;

-- Audit : INSERT seulement, et UNIQUEMENT parce que le declencheur
-- trg_audit_statut_commande s'execute avec les droits de
-- l'utilisateur qui modifie la commande. Pas d'UPDATE : une ligne
-- d'audit ecrite ne peut pas etre modifiee.
-- Limite : un gestionnaire pourrait inserer une fausse ligne d'audit
-- a la main (SECURITY DEFINER sur la fonction l'eviterait).
GRANT INSERT ON audit_statut_commande TO tp1_gestionnaire;

-- Le stock (produit.quantite_totale_produit) est modifie par les
-- declencheurs : couvert par UPDATE sur produit ci-dessus.

GRANT EXECUTE ON PROCEDURE avancer_commande(INTEGER, VARCHAR) TO tp1_gestionnaire;

-- -------------------------------------------------------------
-- 6. tp1_admin : + MAINTAIN (PostgreSQL 17+)
-- REFRESH MATERIALIZED VIEW, VACUUM, ANALYZE, REINDEX, CLUSTER
-- -------------------------------------------------------------
GRANT MAINTAIN ON
    categorie, statut, client, produit, specification_produit,
    reception, info_reception, commande, info_commande, paiement,
    expedition, info_expedition, evaluation, audit_statut_commande,
    mv_ventes_produit_7j
TO tp1_admin;

-- -------------------------------------------------------------
-- 7. Utilisateurs de demonstration (sans mot de passe)
-- -------------------------------------------------------------
CREATE ROLE demo_employe      LOGIN IN ROLE tp1_employe;
CREATE ROLE demo_gestionnaire LOGIN IN ROLE tp1_gestionnaire;

-- L'admin cree des utilisateurs :
--   - CREATEROLE est un ATTRIBUT : il ne s'herite pas d'un groupe,
--     il doit etre donne a l'utilisateur lui-meme;
--   - depuis PostgreSQL 16, il faut aussi l'ADMIN OPTION sur un
--     groupe pour pouvoir y ajouter des membres.
CREATE ROLE demo_admin LOGIN CREATEROLE IN ROLE tp1_admin;
GRANT tp1_employe, tp1_gestionnaire TO demo_admin WITH ADMIN OPTION;
