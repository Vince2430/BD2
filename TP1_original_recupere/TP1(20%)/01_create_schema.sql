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
-- quantite_totale_produit = stock REEL disponible en entrepot.
--   Diminue a la vente et est restitue a l'annulation
--   (trg_maj_stock_produit sur info_commande); augmente a la
--   validation d'une reception (trg_maj_stock_reception).
-- La quantite ENTRANTE (attendue, pas encore recue) n'est pas
-- stockee : elle se calcule a partir des receptions non completees
-- (vue prevue a l'etape 3). La stocker ici serait une donnee derivee.
-- -------------------------------------------------------------

CREATE TABLE produit (
    id_produit                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom_produit               VARCHAR(100)  NOT NULL,
    prix_produit              NUMERIC(10,2) NOT NULL CHECK (prix_produit > 0),
    cout_procuration_produit  NUMERIC(10,2) NOT NULL CHECK (cout_procuration_produit >= 0),
    quantite_totale_produit   INTEGER       NOT NULL DEFAULT 0 CHECK (quantite_totale_produit >= 0),
    id_categorie              INTEGER       NOT NULL REFERENCES categorie (id_categorie)
);

-- Specifications du produit (JSONB)
-- Relation 1 a 1 avec produit : un seul document par produit
-- (UNIQUE sur id_produit). Le document contient autant d'attributs
-- que necessaire; ils varient selon la categorie du produit.
-- Forme du document :
--   cles communes : marque (texte), modele (texte),
--     garantie_mois (nombre >= 0), dimensions (objet imbrique),
--     connectivite (tableau non vide), ecran (objet), materiel (objet);
--   puis toute autre cle propre a la categorie (batterie_wh,
--     batterie_mah, ...), sans contrainte.
-- Aucune cle n'est obligatoire. Prevu d'avance pour de futurs objets
-- de collection ou prototypes, dont la marque ou la garantie ne sont
-- pas toujours connues (le catalogue actuel renseigne toutes les cles
-- communes). Chaque cle commune est donc :
--   absente     -> attribut sans objet pour ce produit;
--   null (JSON) -> attribut qui existe mais dont la valeur est inconnue;
--   sinon       -> du bon type, et valide (garantie >= 0, liste non vide).
-- Une contrainte par regle : le message d'erreur nomme la regle violee.
-- Le "NOT ? 'cle' OR ..." rend explicite l'acceptation d'une cle
-- absente (sans lui, jsonb_typeof() retournerait NULL et le CHECK
-- passerait seulement par effet de bord).
-- Les CASE evitent une erreur de conversion (::NUMERIC) ou d'appel
-- (jsonb_array_length) quand la valeur n'a pas le bon type; le type
-- lui-meme est verifie par ck_spec_types.
CREATE TABLE specification_produit (
    id_specification_produit INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_produit               INTEGER NOT NULL REFERENCES produit (id_produit) ON DELETE CASCADE,
    specifications_produit   JSONB   NOT NULL,
    CONSTRAINT uq_specification_produit UNIQUE (id_produit),

    -- Le document est un objet JSON
    CONSTRAINT ck_spec_objet
        CHECK (jsonb_typeof(specifications_produit) = 'object'),

    -- Chaque cle commune est absente, null ou du bon type
    CONSTRAINT ck_spec_types
        CHECK (    (NOT specifications_produit ? 'marque'
                    OR jsonb_typeof(specifications_produit -> 'marque')        IN ('string', 'null'))
               AND (NOT specifications_produit ? 'modele'
                    OR jsonb_typeof(specifications_produit -> 'modele')        IN ('string', 'null'))
               AND (NOT specifications_produit ? 'garantie_mois'
                    OR jsonb_typeof(specifications_produit -> 'garantie_mois') IN ('number', 'null'))
               AND (NOT specifications_produit ? 'dimensions'
                    OR jsonb_typeof(specifications_produit -> 'dimensions')    IN ('object', 'null'))
               AND (NOT specifications_produit ? 'connectivite'
                    OR jsonb_typeof(specifications_produit -> 'connectivite')  IN ('array', 'null'))
               AND (NOT specifications_produit ? 'ecran'
                    OR jsonb_typeof(specifications_produit -> 'ecran')         IN ('object', 'null'))
               AND (NOT specifications_produit ? 'materiel'
                    OR jsonb_typeof(specifications_produit -> 'materiel')      IN ('object', 'null'))),

    -- La garantie, si elle est connue, est un nombre positif ou nul
    CONSTRAINT ck_spec_garantie
        CHECK (CASE WHEN jsonb_typeof(specifications_produit -> 'garantie_mois') = 'number'
                    THEN (specifications_produit ->> 'garantie_mois')::NUMERIC >= 0
                    ELSE TRUE END),

    -- La liste de connectivite, si elle est fournie, n'est pas vide
    CONSTRAINT ck_spec_connectivite_non_vide
        CHECK (CASE WHEN jsonb_typeof(specifications_produit -> 'connectivite') = 'array'
                    THEN jsonb_array_length(specifications_produit -> 'connectivite') > 0
                    ELSE TRUE END)
);

-- Index GIN pour les recherches par contenance (@>).
-- jsonb_path_ops : plus petit et plus rapide pour @>, mais ne sert
-- pas aux operateurs ? / ?& dans les requetes (les CHECK n'utilisent
-- de toute facon pas d'index).
CREATE INDEX idx_specification_produit_gin
    ON specification_produit
    USING GIN (specifications_produit jsonb_path_ops);

-- -------------------------------------------------------------
-- Receptions de marchandise (approvisionnement)
-- Une reception est creee ATTENDUE (est_complete = FALSE), puis
-- validee a l'arrivee (est_complete = TRUE + date_complete_reception).
-- La validation ajoute les quantites au stock reel (declencheur).
-- Une reception validee est figee : ni modification, ni suppression,
-- ni changement de ses lignes (declencheurs de protection).
-- -------------------------------------------------------------

CREATE TABLE reception (
    id_reception            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero_reception        VARCHAR(30) NOT NULL UNIQUE,
    date_prevue_reception   DATE        NOT NULL,
    date_complete_reception TIMESTAMP,
    est_complete            BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT ck_reception_coherence
        CHECK (est_complete = FALSE OR date_complete_reception IS NOT NULL)
);

-- Resout le N-N entre reception et produit.
CREATE TABLE info_reception (
    id_info_reception INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reception      INTEGER NOT NULL REFERENCES reception (id_reception) ON DELETE CASCADE,
    id_produit        INTEGER NOT NULL REFERENCES produit (id_produit),
    quantite_recu     INTEGER NOT NULL CHECK (quantite_recu > 0),
    CONSTRAINT uq_info_reception_produit UNIQUE (id_reception, id_produit)
);

-- -------------------------------------------------------------
-- Commandes
-- adresse_livraison_commande est figee au moment de la commande :
-- un changement d'adresse du client ne doit pas reecrire l'historique.
-- Une commande n'est jamais supprimee : on l'annule (voir
-- trg_proteger_commande dans 02_declencheurs.sql). D'ou l'absence de
-- ON DELETE CASCADE entre info_commande et commande.
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
    id_commande      INTEGER       NOT NULL REFERENCES commande (id_commande),
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
-- Une ligne peut etre repartie sur plusieurs colis (ex. 3 laptops :
-- 2 maintenant, 1 plus tard) : info_expedition porte la quantite
-- expediee dans chaque colis. Une ligne apparait une seule fois par
-- colis (UNIQUE).
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
    quantite_expediee  INTEGER NOT NULL CHECK (quantite_expediee > 0),
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
-- Audit : historique des changements de statut des commandes
-- Alimentee uniquement par le declencheur trg_audit_statut_commande.
--   INSERT : statut initial (ancien_statut NULL)
--   UPDATE : changement de statut (ancien et nouveau)
--   DELETE : suppression de la commande (dernier statut connu)
--            N'arrive plus en pratique : trg_proteger_commande refuse
--            toute suppression. Conserve comme filet de securite.
-- Pas de cle etrangere vers commande, volontairement : l'historique
-- doit survivre a la suppression d'une commande. Les NOMS des statuts
-- sont stockes (et non leurs id) pour que l'historique reste lisible
-- meme si un statut est renomme ou supprime plus tard.
-- utilisateur = role PostgreSQL connecte (current_user), pas le client.
-- -------------------------------------------------------------

CREATE TABLE audit_statut_commande (
    id_audit_statut_commande INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_commande              INTEGER     NOT NULL,
    operation                VARCHAR(6)  NOT NULL
        CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    ancien_statut            VARCHAR(30),
    nouveau_statut           VARCHAR(30),
    date_changement          TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    utilisateur              VARCHAR(63) NOT NULL DEFAULT CURRENT_USER,
    CONSTRAINT ck_audit_statut_coherence CHECK (
           (operation = 'INSERT' AND ancien_statut IS NULL     AND nouveau_statut IS NOT NULL)
        OR (operation = 'UPDATE' AND ancien_statut IS NOT NULL AND nouveau_statut IS NOT NULL)
        OR (operation = 'DELETE' AND ancien_statut IS NOT NULL AND nouveau_statut IS NULL)
    )
);

-- -------------------------------------------------------------
-- Index de performance (hors cles primaires et contraintes UNIQUE,
-- qui ont deja leur index automatique).
-- Rappel : un index sur (a, b) sert aussi aux recherches sur a seul.
-- Donc info_commande(id_commande) et info_reception(id_reception)
-- sont deja couverts par leurs contraintes UNIQUE.
-- -------------------------------------------------------------

-- Historique des achats d'un client (besoin utilisateur) :
-- WHERE commande.id_client = ?
CREATE INDEX idx_commande_client
    ON commande (id_client);

-- Commandes sur une periode (rapports, ventes du mois) :
-- WHERE date_commande BETWEEN ? AND ?
CREATE INDEX idx_commande_date
    ON commande (date_commande);

-- Ventes par produit, et verification du declencheur
-- trg_valider_achat_avant_evaluation (le client a-t-il commande
-- ce produit ?) : WHERE info_commande.id_produit = ?
-- Non couvert par UNIQUE (id_commande, id_produit) : id_produit
-- n'y est que la deuxieme colonne.
CREATE INDEX idx_info_commande_produit
    ON info_commande (id_produit);

-- Historique des statuts d'une commande, en ordre chronologique :
-- WHERE id_commande = ? ORDER BY date_changement
-- (aucune FK ni UNIQUE sur cette table, donc aucun index existant)
CREATE INDEX idx_audit_statut_commande
    ON audit_statut_commande (id_commande, date_changement);

-- -------------------------------------------------------------
-- Rendre le schema visible par defaut pour les prochaines sessions
-- -------------------------------------------------------------
ALTER DATABASE tp1_vincent_trudel SET search_path TO commerce, public;

-- Verification
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'commerce'
ORDER BY table_name;
