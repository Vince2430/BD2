-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Scenario : Commerce en ligne
-- Etape 0 : creation de la base de donnees
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A LA BASE "postgres"
--
--   pgAdmin 4 : selectionner la base "postgres" dans l'arbre de gauche,
--               ouvrir le Query Tool, coller ce fichier, executer (F5).
--   psql      : psql -U postgres -d postgres -f 00_create_database.sql
--
-- Ces deux commandes ne peuvent pas s'executer dans une transaction,
-- ni depuis une session connectee a tp1_vincent_trudel.
-- =============================================================

DROP DATABASE IF EXISTS tp1_vincent_trudel;

CREATE DATABASE tp1_vincent_trudel
    WITH ENCODING  = 'UTF8'
         TEMPLATE  = template0;
