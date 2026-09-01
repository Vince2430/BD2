-- ============================================================
-- INSERT, UPDATE, DELETE exécutés de façon SÉCURITAIRE -- SQL pur
-- ============================================================
--
-- En SQL statique (écrit à la main dans un fichier comme celui-ci),
-- il n'y a pas de risque d'injection -- le risque apparaît
-- seulement quand une requête est CONSTRUITE dynamiquement à
-- partir d'une valeur externe (ex: dans une fonction PL/pgSQL
-- avec EXECUTE, ou depuis du code applicatif). La façon
-- "sécuritaire" de le faire en SQL est donc d'utiliser des
-- requêtes préparées (PREPARE/EXECUTE) plutôt que de construire
-- la requête en concaténant du texte.


-- ============================================================
-- INSERT sécuritaire
-- ============================================================

PREPARE inserer_membre (text) AS
    INSERT INTO membre (nom)
    VALUES ($1)
    RETURNING id_membre;

EXECUTE inserer_membre('Test Sécuritaire');

DEALLOCATE inserer_membre;


-- ============================================================
-- UPDATE sécuritaire
-- ============================================================

PREPARE modifier_nom_membre (text, int) AS
    UPDATE membre
    SET nom = $1
    WHERE id_membre = $2;

EXECUTE modifier_nom_membre('Test Sécuritaire (modifié)', 1);

DEALLOCATE modifier_nom_membre;


-- ============================================================
-- DELETE sécuritaire
-- ============================================================

PREPARE supprimer_membre (int) AS
    DELETE FROM membre
    WHERE id_membre = $1;

EXECUTE supprimer_membre(1);

DEALLOCATE supprimer_membre;


-- ============================================================
-- Pourquoi c'est important : exemple de ce qui serait DANGEREUX
-- si on construisait la requête dynamiquement (ex: dans une
-- fonction PL/pgSQL) en collant le texte au lieu d'utiliser un
-- paramètre -- NE JAMAIS FAIRE ÇA :
-- ============================================================

-- DO $$
-- DECLARE
--     nom_recu text := 'Julie''; DROP TABLE membre; --';
-- BEGIN
--     -- MAUVAIS : concaténation directe, vulnérable à l'injection
--     EXECUTE 'INSERT INTO membre (nom) VALUES (''' || nom_recu || ''')';
-- END $$;

-- La bonne façon, si on doit vraiment construire du SQL
-- dynamique dans une fonction, est d'utiliser format() avec %L
-- (litéral, échappé automatiquement) plutôt que de concaténer :

-- DO $$
-- DECLARE
--     nom_recu text := 'Julie''; DROP TABLE membre; --';
-- BEGIN
--     -- BON : %L échappe correctement la valeur, même si elle
--     -- contient des apostrophes ou du SQL malicieux
--     EXECUTE format('INSERT INTO membre (nom) VALUES (%L)', nom_recu);
-- END $$;
