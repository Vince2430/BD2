-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Scenario : Commerce en ligne
-- Etape 1 : creation du schema et des tables
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel"
-- (executer d'abord 00_create_database.sql)
--
--   pgAdmin 4 : selectionner la base dans l'arbre, Query Tool, F5.
--   psql      : psql -U postgres -d tp1_vincent_trudel -f 01_create_schema.sql
--
-- Nomenclature : snake_case, minuscules, sans accent.
-- Une cle etrangere porte le meme nom que la cle primaire qu'elle
-- reference (id_client partout), ce qui permet les jointures USING.
-- =============================================================

DROP SCHEMA IF EXISTS commerce CASCADE;
CREATE SCHEMA commerce;

SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- Tables de reference
-- -------------------------------------------------------------

CREATE TABLE categorie (
    id_categorie  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_categorie VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE statut (
    id_statut  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_statut VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE client (
    id_client             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_client            VARCHAR(100) NOT NULL,
    courriel_client       VARCHAR(255) NOT NULL UNIQUE,
    telephone_client      VARCHAR(20),
    hash_mot_passe_client VARCHAR(255) NOT NULL,
    adresse_client        TEXT
);

-- -------------------------------------------------------------
-- Catalogue
-- quantite_totale_produit est un cache : elle vaut
-- quantite_entrante_produit moins la somme des quantites vendues.
-- Elle sera maintenue par un declencheur sur info_commande.
-- -------------------------------------------------------------

CREATE TABLE produit (
    id_produit                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_produit               VARCHAR(100)  NOT NULL,
    prix_produit              NUMERIC(10,2) NOT NULL CHECK (prix_produit > 0),
    cout_procuration_produit  NUMERIC(10,2) NOT NULL CHECK (cout_procuration_produit >= 0),
    quantite_totale_produit   INTEGER       NOT NULL DEFAULT 0 CHECK (quantite_totale_produit >= 0),
    quantite_entrante_produit INTEGER       NOT NULL DEFAULT 0 CHECK (quantite_entrante_produit >= 0),
    id_categorie              INTEGER       NOT NULL REFERENCES categorie (id_categorie)
);

-- -------------------------------------------------------------
-- Commandes
-- adresse_livraison_commande est figee au moment de la commande :
-- un changement d'adresse du client ne doit pas reecrire l'historique.
-- -------------------------------------------------------------

CREATE TABLE commande (
    id_commande                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_commande              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    adresse_livraison_commande TEXT      NOT NULL,
    id_client                  INTEGER   NOT NULL REFERENCES client (id_client),
    id_statut                  INTEGER   NOT NULL REFERENCES statut (id_statut)
);

-- Resout le N-N entre produit et commande.
-- prix_unitaire est fige au moment de la commande, pour la meme raison
-- que l'adresse de livraison.
CREATE TABLE info_commande (
    id_info_commande INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_commande      INTEGER       NOT NULL REFERENCES commande (id_commande) ON DELETE CASCADE,
    id_produit       INTEGER       NOT NULL REFERENCES produit (id_produit),
    quantite         INTEGER       NOT NULL CHECK (quantite > 0),
    prix_unitaire    NUMERIC(10,2) NOT NULL CHECK (prix_unitaire >= 0),
    CONSTRAINT uq_info_commande_produit UNIQUE (id_commande, id_produit)
);

CREATE TABLE paiement (
    id_paiement      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_commande      INTEGER       NOT NULL REFERENCES commande (id_commande),
    mode_paiement    VARCHAR(30)   NOT NULL,
    date_paiement    TIMESTAMP,
    montant_paiement NUMERIC(10,2) NOT NULL CHECK (montant_paiement > 0),
    est_complete     BOOLEAN       NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_paiement_coherence
        CHECK (est_complete = FALSE OR date_paiement IS NOT NULL)
);

-- -------------------------------------------------------------
-- Expeditions
-- Une commande peut partir en plusieurs colis (livraison partielle)
-- et un colis peut regrouper plusieurs commandes : le lien se fait
-- au grain de la LIGNE de commande, pas de la commande entiere.
-- Regle metier : une ligne voyage entierement dans un seul colis.
-- -------------------------------------------------------------

CREATE TABLE expedition (
    id_expedition           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_prevue_expedition  DATE        NOT NULL,
    date_complete_expedition TIMESTAMP,
    est_complete            BOOLEAN     NOT NULL DEFAULT FALSE,
    camion_expedition       VARCHAR(50),
    CONSTRAINT ck_expedition_coherence
        CHECK (est_complete = FALSE OR date_complete_expedition IS NOT NULL)
);

CREATE TABLE info_expedition (
    id_info_expedition INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_info_commande   INTEGER NOT NULL REFERENCES info_commande (id_info_commande) ON DELETE CASCADE,
    id_expedition      INTEGER NOT NULL REFERENCES expedition (id_expedition),
    CONSTRAINT uq_info_expedition UNIQUE (id_info_commande, id_expedition)
);

-- -------------------------------------------------------------
-- Evaluations
-- -------------------------------------------------------------

CREATE TABLE evaluation (
    id_evaluation          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_produit             INTEGER  NOT NULL REFERENCES produit (id_produit),
    id_client              INTEGER  NOT NULL REFERENCES client (id_client),
    note_evaluation        SMALLINT NOT NULL CHECK (note_evaluation BETWEEN 1 AND 5),
    commentaire_evaluation TEXT,
    date_evaluation        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_evaluation_client_produit UNIQUE (id_produit, id_client)
);

-- -------------------------------------------------------------
-- Rendre le schema visible par defaut pour les prochaines sessions
-- -------------------------------------------------------------
ALTER DATABASE tp1_vincent_trudel SET search_path TO commerce, public;

-- Verification
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'commerce'
ORDER BY table_name;
