-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Scenario : Commerce en ligne
-- Etape 1 : creation du schema, des tables, du JSONB et des index
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel"
-- (executer d'abord 00_create_database.sql)
--
--   pgAdmin 4 : selectionner la base dans l'arbre, Query Tool, F5.
--   psql      : psql -U postgres -d tp1_vincent_trudel -f 01_create_schema.sql
--
-- ATTENTION : DROP SCHEMA ... CASCADE supprime aussi les privileges.
-- Relancer 05_roles.sql apres ce script.
--
-- Nomenclature : snake_case, minuscules, sans accent.
-- Une cle etrangere porte le meme nom que la cle primaire qu'elle
-- reference (id_client partout), ce qui permet les jointures USING.
--
-- Aucune suppression en cascade : une commande n'est jamais
-- supprimee (elle est annulee, voir 02_declencheurs.sql).
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

-- Valeurs : En attente, Payee, En preparation, Expediee, Livree, Annulee
-- (inserees par 03_donnees.sql). Le cycle de vie est garde par
-- trg_proteger_commande (02_declencheurs.sql).
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
    adresse_client        TEXT,
    CONSTRAINT ck_client_courriel
        CHECK (courriel_client LIKE '_%@_%._%'),
    CONSTRAINT ck_client_nom_non_vide
        CHECK (btrim(nom_client) <> '')
);

-- -------------------------------------------------------------
-- Catalogue
--   quantite_totale_produit   = stock reellement disponible (maintenu
--                               par declencheurs : ventes, annulations,
--                               receptions validees)
--   quantite_entrante_produit = quantite attendue d'un fournisseur,
--                               pas encore recue (previsionnel)
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
-- Specifications techniques (JSONB)
-- Les caracteristiques varient d'une categorie a l'autre (un portable
-- a un processeur, un casque une autonomie...) et contiennent des
-- structures imbriquees (dimensions = objet, connectivite = tableau).
-- Une table 1-1 avec produit : la colonne JSONB reste separee des
-- donnees relationnelles stables (prix, stock, categorie).
--
-- Proprietes essentielles validees :
--   - le document est un objet;
--   - marque, modele et connectivite sont obligatoires;
--   - connectivite est un tableau;
--   - marque est une chaine;
--   - garantie_mois, si presente, est un nombre >= 0.
-- -------------------------------------------------------------

CREATE TABLE specification_produit (
    id_produit             INTEGER PRIMARY KEY REFERENCES produit (id_produit),
    specifications_produit JSONB   NOT NULL,
    CONSTRAINT ck_spec_est_objet
        CHECK (jsonb_typeof(specifications_produit) = 'object'),
    CONSTRAINT ck_spec_cles_obligatoires
        CHECK (specifications_produit ?& ARRAY['marque', 'modele', 'connectivite']),
    CONSTRAINT ck_spec_connectivite_tableau
        CHECK (COALESCE(jsonb_typeof(specifications_produit -> 'connectivite'), 'absent') = 'array'),
    CONSTRAINT ck_spec_marque_texte
        CHECK (COALESCE(jsonb_typeof(specifications_produit -> 'marque'), 'absent') = 'string'),
    CONSTRAINT ck_spec_garantie
        CHECK (NOT (specifications_produit ? 'garantie_mois')
               OR (jsonb_typeof(specifications_produit -> 'garantie_mois') = 'number'
                   AND (specifications_produit ->> 'garantie_mois')::NUMERIC >= 0))
);

-- -------------------------------------------------------------
-- Commandes
-- adresse_livraison_commande est figee au moment de la commande :
-- un changement d'adresse du client ne doit pas reecrire l'historique.
-- -------------------------------------------------------------

CREATE TABLE commande (
    id_commande                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_commande              TIMESTAMP NOT NULL DEFAULT LOCALTIMESTAMP,
    adresse_livraison_commande TEXT      NOT NULL,
    id_client                  INTEGER   NOT NULL REFERENCES client (id_client),
    id_statut                  INTEGER   NOT NULL REFERENCES statut (id_statut)
);

-- Resout le N-N entre produit et commande.
-- prix_unitaire est fige au moment de la commande, pour la meme raison
-- que l'adresse de livraison.
CREATE TABLE info_commande (
    id_info_commande INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_commande      INTEGER       NOT NULL REFERENCES commande (id_commande),
    id_produit       INTEGER       NOT NULL REFERENCES produit (id_produit),
    quantite         INTEGER       NOT NULL CHECK (quantite > 0),
    prix_unitaire    NUMERIC(10,2) NOT NULL CHECK (prix_unitaire >= 0),
    CONSTRAINT uq_info_commande_produit UNIQUE (id_commande, id_produit)
);

-- Paiement par carte en deux temps :
--   est_complete = FALSE : autorisation (montant reserve)
--   est_complete = TRUE  : capture (montant reellement encaisse)
-- Le paiement reference la commande et non le client (3FN : le client
-- se deduit de la commande).
CREATE TABLE paiement (
    id_paiement      INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_commande      INTEGER       NOT NULL REFERENCES commande (id_commande),
    mode_paiement    VARCHAR(30)   NOT NULL,
    date_paiement    TIMESTAMP,
    montant_paiement NUMERIC(10,2) NOT NULL CHECK (montant_paiement > 0),
    est_complete     BOOLEAN       NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_paiement_mode
        CHECK (mode_paiement IN ('Carte de crédit', 'Carte de débit', 'PayPal')),
    CONSTRAINT ck_paiement_coherence
        CHECK (est_complete = FALSE OR date_paiement IS NOT NULL)
);

-- -------------------------------------------------------------
-- Expeditions
-- Une commande peut partir en plusieurs colis (livraison partielle)
-- et un colis peut regrouper plusieurs commandes : le lien se fait
-- au grain de la LIGNE de commande, avec la quantite expediee.
-- Regle : total expedie d'une ligne <= quantite commandee (declencheur).
-- -------------------------------------------------------------

CREATE TABLE expedition (
    id_expedition            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_prevue_expedition   DATE        NOT NULL DEFAULT CURRENT_DATE,
    date_complete_expedition TIMESTAMP,
    est_complete             BOOLEAN     NOT NULL DEFAULT FALSE,
    camion_expedition        VARCHAR(50),
    CONSTRAINT ck_expedition_coherence
        CHECK (est_complete = FALSE OR date_complete_expedition IS NOT NULL)
);

CREATE TABLE info_expedition (
    id_info_expedition INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_info_commande   INTEGER NOT NULL REFERENCES info_commande (id_info_commande),
    id_expedition      INTEGER NOT NULL REFERENCES expedition (id_expedition),
    quantite_expediee  INTEGER NOT NULL CHECK (quantite_expediee > 0),
    CONSTRAINT uq_info_expedition UNIQUE (id_info_commande, id_expedition)
);

-- -------------------------------------------------------------
-- Receptions (reapprovisionnement fournisseur)
-- Une reception validee (est_complete = TRUE) ajoute ses quantites au
-- stock reel, puis devient figee (declencheurs).
-- -------------------------------------------------------------

CREATE TABLE reception (
    id_reception            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fournisseur_reception   VARCHAR(100) NOT NULL,
    date_prevue_reception   DATE         NOT NULL,
    date_complete_reception TIMESTAMP,
    est_complete            BOOLEAN      NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_reception_coherence
        CHECK (est_complete = FALSE OR date_complete_reception IS NOT NULL)
);

CREATE TABLE info_reception (
    id_info_reception INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reception      INTEGER NOT NULL REFERENCES reception (id_reception),
    id_produit        INTEGER NOT NULL REFERENCES produit (id_produit),
    quantite_attendue INTEGER NOT NULL CHECK (quantite_attendue > 0),
    CONSTRAINT uq_info_reception_produit UNIQUE (id_reception, id_produit)
);

-- -------------------------------------------------------------
-- Evaluations
-- Regle : seul un client ayant commande le produit peut l'evaluer
-- (declencheur), une seule evaluation par client et par produit (UNIQUE).
-- -------------------------------------------------------------

CREATE TABLE evaluation (
    id_evaluation          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_produit             INTEGER   NOT NULL REFERENCES produit (id_produit),
    id_client              INTEGER   NOT NULL REFERENCES client (id_client),
    note_evaluation        SMALLINT  NOT NULL CHECK (note_evaluation BETWEEN 1 AND 5),
    commentaire_evaluation TEXT,
    date_evaluation        TIMESTAMP NOT NULL DEFAULT LOCALTIMESTAMP,
    CONSTRAINT uq_evaluation_client_produit UNIQUE (id_produit, id_client)
);

-- -------------------------------------------------------------
-- Audit des changements de statut d'une commande
-- Rempli uniquement par trg_audit_statut_commande.
-- On conserve les NOMS de statut (valeurs lisibles telles qu'elles
-- etaient au moment de l'operation) et l'utilisateur PostgreSQL.
-- -------------------------------------------------------------

CREATE TABLE audit_statut_commande (
    id_audit       INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_commande    INTEGER     NOT NULL REFERENCES commande (id_commande),
    operation      VARCHAR(10) NOT NULL CHECK (operation IN ('INSERT', 'UPDATE')),
    ancien_statut  VARCHAR(30),
    nouveau_statut VARCHAR(30) NOT NULL,
    date_operation TIMESTAMP   NOT NULL DEFAULT LOCALTIMESTAMP,
    utilisateur    VARCHAR(63) NOT NULL DEFAULT current_user
);

-- -------------------------------------------------------------
-- Index (les index des PK et des UNIQUE sont crees automatiquement
-- et ne comptent pas). Justification detaillee :
-- Doc/justification_requetes_etape4.md
-- -------------------------------------------------------------

-- Recherche des commandes d'un client (app option 2, requetes 3-6,
-- verification d'achat du declencheur d'evaluation).
CREATE INDEX idx_commande_id_client ON commande (id_client);

-- Tri par date (v_commandes, app option 1) et fenetre de 7 jours
-- (mv_ventes_produit_7j, requete 7).
CREATE INDEX idx_commande_date_commande ON commande (date_commande);

-- Ventes par produit (vue materialisee, requete 2) et verification
-- d'achat avant evaluation. (id_commande est deja couvert par
-- l'index de uq_info_commande_produit.)
CREATE INDEX idx_info_commande_id_produit ON info_commande (id_produit);

-- Lignes expediees d'une ligne de commande (declencheurs d'expedition,
-- procedure avancer_commande).
CREATE INDEX idx_info_expedition_id_expedition ON info_expedition (id_expedition);

-- Index GIN pour la recherche par contenance @> (requete 9, app option 3).
-- jsonb_path_ops : plus petit et plus rapide que l'operateur par defaut,
-- mais ne supporte que @> (suffisant ici).
CREATE INDEX idx_specification_produit_gin
    ON specification_produit USING GIN (specifications_produit jsonb_path_ops);

-- Ajoutes a l'etape 4 apres EXPLAIN ANALYZE avant/apres
-- (07_requetes.sql, sections 11 et 12).
CREATE INDEX idx_commande_id_statut ON commande (id_statut);

CREATE INDEX idx_paiement_incomplet ON paiement (id_commande)
    WHERE est_complete = FALSE;

-- -------------------------------------------------------------
-- Rendre le schema visible par defaut pour les prochaines sessions
-- -------------------------------------------------------------
ALTER DATABASE tp1_vincent_trudel SET search_path TO commerce, public;

-- Verification
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'commerce'
ORDER BY table_name;
