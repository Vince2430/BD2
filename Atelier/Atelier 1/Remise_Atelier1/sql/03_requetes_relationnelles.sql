-- ============================================================
-- 03_requetes_relationnelles.sql
-- Atelier 1 — Partie 1, point 5 : les cinq requêtes demandées
-- ============================================================
--
-- À exécuter sur atelier_bibliotheque_sql, APRÈS 01 et 02 :
--
--     psql -U postgres -d atelier_bibliotheque_sql -f 03_requetes_relationnelles.sql
--
-- Contenu :
--   1. Jointure       : emprunts + titre du livre + nom du membre
--   2. Agrégation     : nombre d'emprunts par membre
--   3. Requête filtrée et triée AVEC PARAMÈTRES
--   4. INSERT / UPDATE / DELETE sécuritaires
--   5. Transaction avec COMMIT et ROLLBACK
-- ============================================================



-- ############################################################
-- 1. JOINTURE : les emprunts, avec le titre du livre et le nom
--    du membre
-- ############################################################

SELECT
    e.id_emprunt,
    l.nom          AS titre_livre,
    m.nom          AS nom_membre,
    e.date_emprunt,
    e.date_retour
FROM emprunt e
JOIN livre  l ON l.id_livre  = e.id_livre
JOIN membre m ON m.id_membre = e.id_membre
ORDER BY e.date_emprunt DESC;

-- Explication : on part de "emprunt", la table qui porte les clés
-- étrangères, et on rejoint "livre" et "membre" pour remplacer les
-- id par des informations lisibles. C'est exactement l'information
-- que le modèle documentaire, lui, duplique déjà à l'intérieur de
-- chaque document (nom_membre dans le tableau "emprunts").



-- ############################################################
-- 2. AGRÉGATION : nombre d'emprunts par membre
-- ############################################################

SELECT
    m.id_membre,
    m.nom               AS nom_membre,
    COUNT(e.id_emprunt) AS nb_emprunts
FROM membre m
LEFT JOIN emprunt e ON e.id_membre = m.id_membre
GROUP BY m.id_membre, m.nom
ORDER BY nb_emprunts DESC, nom_membre;

-- LEFT JOIN (et non JOIN) : les membres qui n'ont fait AUCUN emprunt
-- apparaissent quand même, avec un compte de 0. Avec un JOIN normal
-- ils disparaîtraient du résultat.
--
-- Toute colonne du SELECT qui n'est pas dans une fonction d'agrégat
-- doit figurer dans le GROUP BY : c'est pourquoi id_membre ET nom
-- y sont tous les deux.


-- Variante : seulement les membres ayant plus de 2 emprunts.
-- HAVING filtre APRÈS le regroupement, contrairement à WHERE qui
-- filtre avant.

SELECT
    m.id_membre,
    m.nom               AS nom_membre,
    COUNT(e.id_emprunt) AS nb_emprunts
FROM membre m
JOIN emprunt e ON e.id_membre = m.id_membre
GROUP BY m.id_membre, m.nom
HAVING COUNT(e.id_emprunt) > 2
ORDER BY nb_emprunts DESC;



-- ############################################################
-- 3. REQUÊTE FILTRÉE ET TRIÉE, AVEC PARAMÈTRES
-- ############################################################
--
-- En SQL pur, l'équivalent du %s de psycopg (ou du @param de Npgsql)
-- s'appelle une requête PRÉPARÉE : la requête est définie une fois
-- avec des paramètres ($1, $2...), puis exécutée avec des valeurs
-- différentes. Le serveur reçoit la requête et les valeurs
-- séparément : une valeur ne peut donc jamais être interprétée
-- comme du code SQL.
--
-- Limite à connaître : un paramètre ne peut remplacer qu'une VALEUR,
-- jamais un nom de colonne ni un ASC/DESC. Le ORDER BY doit rester
-- fixe dans une requête préparée.

PREPARE recherche_emprunts (text, date) AS
    SELECT
        e.id_emprunt,
        l.nom  AS titre_livre,
        m.nom  AS nom_membre,
        e.date_emprunt,
        e.date_retour
    FROM emprunt e
    JOIN livre  l ON l.id_livre  = e.id_livre
    JOIN membre m ON m.id_membre = e.id_membre
    WHERE m.nom ILIKE $1
      AND e.date_emprunt >= $2
    ORDER BY e.date_emprunt DESC;

-- Membres dont le nom contient "ou", emprunts depuis le 1er janvier 2026
EXECUTE recherche_emprunts('%ou%', '2026-01-01');

-- Même requête préparée, autres valeurs : rien à réécrire
EXECUTE recherche_emprunts('%a%', '2026-06-01');

DEALLOCATE recherche_emprunts;


-- Variante triée différemment : comme ORDER BY ne peut pas être
-- paramétré, on prépare une seconde requête plutôt que de construire
-- le SQL par concaténation.

PREPARE recherche_emprunts_par_titre (text) AS
    SELECT
        e.id_emprunt,
        l.nom  AS titre_livre,
        m.nom  AS nom_membre,
        e.date_emprunt
    FROM emprunt e
    JOIN livre  l ON l.id_livre  = e.id_livre
    JOIN membre m ON m.id_membre = e.id_membre
    WHERE m.nom ILIKE $1
    ORDER BY l.nom ASC;

EXECUTE recherche_emprunts_par_titre('%ou%');

DEALLOCATE recherche_emprunts_par_titre;



-- ############################################################
-- 4. INSERT, UPDATE et DELETE SÉCURITAIRES
-- ############################################################
--
-- "Sécuritaire" = la valeur passe par un paramètre ($1), jamais par
-- une concaténation de texte. En SQL écrit à la main il n'y a pas de
-- risque d'injection ; le risque apparaît dès qu'une requête est
-- CONSTRUITE à partir d'une valeur extérieure (code applicatif, ou
-- EXECUTE dans une fonction PL/pgSQL).
--
-- Les trois opérations travaillent sur LE MÊME membre de test :
-- créé par l'INSERT, renommé par l'UPDATE, retiré par le DELETE.
-- Le script est donc rejouable et ne touche jamais aux vraies données.
-- Chaque opération se termine par RETURNING : le résultat est
-- vérifiable immédiatement à l'écran.


-- --- INSERT ---
PREPARE inserer_membre (text) AS
    INSERT INTO membre (nom) VALUES ($1)
    RETURNING id_membre, nom;

EXECUTE inserer_membre('Test Sécuritaire');
DEALLOCATE inserer_membre;


-- --- UPDATE ---
-- On cible le membre par son nom de test, pas par un id écrit en dur :
-- un id en dur (ex: 1) viserait un VRAI membre du jeu de données.
PREPARE modifier_nom_membre (text, text) AS
    UPDATE membre SET nom = $1 WHERE nom = $2
    RETURNING id_membre, nom;

EXECUTE modifier_nom_membre('Test Sécuritaire (modifié)', 'Test Sécuritaire');
DEALLOCATE modifier_nom_membre;


-- --- DELETE ---
PREPARE supprimer_membre (text) AS
    DELETE FROM membre WHERE nom = $1
    RETURNING id_membre, nom;

EXECUTE supprimer_membre('Test Sécuritaire (modifié)');
DEALLOCATE supprimer_membre;


-- Vérification : plus aucun membre de test (doit afficher 0)
SELECT COUNT(*) AS membres_de_test_restants
FROM membre
WHERE nom LIKE 'Test Sécuritaire%';


-- Pourquoi on ne supprime pas un membre au hasard : la clé étrangère
-- fk_emprunt_membre refuse de laisser des emprunts orphelins.
--
--   DELETE FROM membre WHERE id_membre = 1;
--   ERROR: update or delete on table "membre" violates foreign key
--          constraint "fk_emprunt_membre" on table "emprunt"
--
-- C'est exactement le rôle de la clé étrangère. La contourner avec
-- ON DELETE CASCADE serait une mauvaise idée ici : on perdrait
-- l'historique des emprunts.


-- Ce qu'il ne faut JAMAIS faire (laissé en commentaire) : construire
-- la requête en collant la valeur reçue.
--
--   DO $$
--   DECLARE nom_recu text := 'Julie''; DROP TABLE membre; --';
--   BEGIN
--       EXECUTE 'INSERT INTO membre (nom) VALUES (''' || nom_recu || ''')';
--   END $$;
--
-- Si du SQL dynamique est vraiment nécessaire, format() avec %L
-- échappe correctement la valeur :
--
--   EXECUTE format('INSERT INTO membre (nom) VALUES (%L)', nom_recu);



-- ############################################################
-- 5. TRANSACTION AVEC COMMIT ET ROLLBACK
-- ############################################################
--
-- BEGIN démarre une transaction : rien n'est définitif tant qu'il
-- n'y a pas de COMMIT, et ROLLBACK annule tout depuis le BEGIN.


-- --- Cas 1 : transaction réussie, terminée par COMMIT ---

BEGIN;

INSERT INTO emprunt (id_livre, id_membre, date_emprunt)
VALUES (
    (SELECT MIN(id_livre)  FROM livre),
    (SELECT MIN(id_membre) FROM membre),
    CURRENT_DATE
);

COMMIT;
-- L'emprunt est maintenant définitivement enregistré.


-- --- Cas 2 : transaction annulée volontairement, ROLLBACK ---

BEGIN;

INSERT INTO emprunt (id_livre, id_membre, date_emprunt)
VALUES (
    (SELECT MIN(id_livre)  FROM livre),
    (SELECT MIN(id_membre) FROM membre),
    CURRENT_DATE
);

ROLLBACK;
-- L'INSERT ci-dessus n'a jamais été appliqué.


-- --- Cas 3 : transaction annulée automatiquement par une erreur ---

BEGIN;

INSERT INTO emprunt (id_livre, id_membre, date_emprunt)
VALUES (999999, 1, CURRENT_DATE);
-- ERREUR volontaire : le livre 999999 n'existe pas -> viole
-- fk_emprunt_livre. PostgreSQL met la transaction en état "aborted" :
-- toute commande suivante est refusée tant qu'on n'a pas fait
-- ROLLBACK (un COMMIT seul ne suffit pas à s'en sortir).

ROLLBACK;


-- --- Variante : gérer l'erreur soi-même, comme un try/except ---
-- Un bloc DO avec EXCEPTION annule uniquement SES PROPRES
-- changements ; la session reste utilisable après, contrairement
-- au cas 3.

DO $$
BEGIN
    INSERT INTO emprunt (id_livre, id_membre, date_emprunt)
    VALUES (999999, 1, CURRENT_DATE);   -- id_livre invalide, volontairement

    RAISE NOTICE 'Emprunt inséré avec succès.';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'Erreur : livre ou membre inexistant, opération annulée.';
END $$;
