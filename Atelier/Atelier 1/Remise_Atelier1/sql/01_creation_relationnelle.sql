-- ============================================================
-- 01_creation_relationnelle.sql
-- Atelier 1 — Partie 1 : schéma de la base relationnelle
-- ============================================================
--
-- PRÉALABLE : créer la base (une seule fois), depuis psql ou pgAdmin,
-- en étant connecté à une AUTRE base (par exemple 'postgres') :
--
--     CREATE DATABASE atelier_bibliotheque_sql
--         ENCODING 'UTF8'
--         TEMPLATE template0;
--
-- Puis exécuter ce fichier EN ÉTANT CONNECTÉ à atelier_bibliotheque_sql :
--
--     psql -U postgres -d atelier_bibliotheque_sql -f 01_creation_relationnelle.sql
--
-- Ce script est ré-exécutable : il supprime les tables existantes avant
-- de les recréer, donc il fonctionne aussi bien sur une base vide que
-- sur une base déjà remplie.
-- ============================================================


-- ============================================================
-- Suppression dans l'ordre inverse des dépendances
-- (emprunt référence livre et membre ; livre référence auteur)
-- ============================================================

DROP TABLE IF EXISTS emprunt CASCADE;
DROP TABLE IF EXISTS livre   CASCADE;
DROP TABLE IF EXISTS membre  CASCADE;
DROP TABLE IF EXISTS auteur  CASCADE;


-- ============================================================
-- auteur
-- ============================================================

CREATE TABLE auteur (
    id_auteur   SERIAL PRIMARY KEY,

    -- NOT NULL : un auteur ne peut pas exister sans nom.
    -- DEFAULT  : si aucun nom n'est fourni, on inscrit 'anonyme'
    --            plutôt que de refuser la ligne.
    nom         VARCHAR(100) NOT NULL DEFAULT 'anonyme',

    -- CHECK : NOT NULL n'empêche PAS une chaîne vide ('') ni une
    -- chaîne faite uniquement d'espaces. btrim(nom) <> '' comble ce trou.
    CONSTRAINT chk_auteur_nom_non_vide CHECK (btrim(nom) <> '')
);


-- ============================================================
-- membre
-- ============================================================

CREATE TABLE membre (
    id_membre   SERIAL PRIMARY KEY,
    nom         VARCHAR(100) NOT NULL   -- un membre doit avoir un nom
);


-- ============================================================
-- livre  (dépend de auteur)
-- ============================================================

CREATE TABLE livre (
    id_livre    SERIAL PRIMARY KEY,
    nom         VARCHAR(150) NOT NULL,  -- titre du livre
    id_auteur   INTEGER      NOT NULL,  -- un livre a obligatoirement un auteur

    CONSTRAINT fk_livre_auteur
        FOREIGN KEY (id_auteur) REFERENCES auteur (id_auteur),

    -- UNIQUE sur le COUPLE (titre, auteur) : deux auteurs différents
    -- peuvent avoir écrit un livre du même titre, mais le même auteur
    -- ne peut pas avoir deux fois le même titre dans le catalogue.
    CONSTRAINT uq_livre_titre_auteur UNIQUE (nom, id_auteur)
);


-- ============================================================
-- emprunt  (dépend de livre et de membre)
-- ============================================================

CREATE TABLE emprunt (
    id_emprunt      SERIAL PRIMARY KEY,
    id_livre        INTEGER NOT NULL,   -- un emprunt sans livre n'a pas de sens
    id_membre       INTEGER NOT NULL,   -- ni un emprunt sans emprunteur

    -- DEFAULT : un emprunt enregistré sans date est daté d'aujourd'hui.
    date_emprunt    DATE NOT NULL DEFAULT CURRENT_DATE,

    -- Volontairement NULLABLE : date_retour IS NULL = emprunt encore actif.
    date_retour     DATE,

    CONSTRAINT fk_emprunt_livre
        FOREIGN KEY (id_livre)  REFERENCES livre (id_livre),
    CONSTRAINT fk_emprunt_membre
        FOREIGN KEY (id_membre) REFERENCES membre (id_membre),

    -- CHECK : on ne peut pas retourner un livre avant de l'avoir emprunté.
    -- Le "date_retour IS NULL OR" est indispensable : sans lui, un emprunt
    -- encore actif (date_retour NULL) serait évalué à NULL et... accepté,
    -- mais toute mise à jour deviendrait confuse. On rend la règle explicite.
    CONSTRAINT chk_emprunt_dates
        CHECK (date_retour IS NULL OR date_retour >= date_emprunt)
);


-- ============================================================
-- Vérification rapide du schéma créé
-- ============================================================

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;
