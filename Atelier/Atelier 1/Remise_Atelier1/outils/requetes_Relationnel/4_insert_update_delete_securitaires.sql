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
--
-- Les trois opérations ci-dessous travaillent toutes sur LE MÊME
-- membre de test : créé par l'INSERT, renommé par l'UPDATE, puis
-- retiré par le DELETE. Le script peut donc être relancé autant
-- de fois qu'on veut sans toucher aux vraies données et sans
-- laisser de trace.
--
-- Chaque opération se termine par RETURNING, ce qui rend son
-- résultat vérifiable immédiatement à l'écran.


-- ============================================================
-- INSERT sécuritaire
-- ============================================================

PREPARE inserer_membre (text) AS
    INSERT INTO membre (nom)
    VALUES ($1)
    RETURNING id_membre, nom;

EXECUTE inserer_membre('Test Sécuritaire');

DEALLOCATE inserer_membre;


-- ============================================================
-- UPDATE sécuritaire
-- ============================================================
-- On cible le membre par son nom de test, pas par un id écrit en
-- dur : un id en dur (ex: 1) viserait un VRAI membre du jeu de
-- données et le modifierait par erreur.

PREPARE modifier_nom_membre (text, text) AS
    UPDATE membre
    SET nom = $1
    WHERE nom = $2
    RETURNING id_membre, nom;

EXECUTE modifier_nom_membre('Test Sécuritaire (modifié)', 'Test Sécuritaire');

DEALLOCATE modifier_nom_membre;


-- ============================================================
-- DELETE sécuritaire
-- ============================================================

PREPARE supprimer_membre (text) AS
    DELETE FROM membre
    WHERE nom = $1
    RETURNING id_membre, nom;

EXECUTE supprimer_membre('Test Sécuritaire (modifié)');

DEALLOCATE supprimer_membre;


-- ============================================================
-- Vérification finale : le membre de test n'existe plus
-- ============================================================

SELECT COUNT(*) AS membres_de_test_restants
FROM membre
WHERE nom LIKE 'Test Sécuritaire%';
-- Doit afficher 0.


-- ============================================================
-- Pourquoi on ne supprime PAS un membre au hasard : la clé
-- étrangère protège les données
-- ============================================================
-- Si on essaie de supprimer un membre qui a déjà des emprunts,
-- PostgreSQL refuse, parce que emprunt.id_membre référence
-- membre.id_membre (contrainte fk_emprunt_membre) :
--
--   DELETE FROM membre WHERE id_membre = 1;
--
--   ERROR: update or delete on table "membre" violates foreign key
--   constraint "fk_emprunt_membre" on table "emprunt"
--
-- C'est exactement le rôle de la clé étrangère : empêcher de
-- laisser des emprunts orphelins. Pour vraiment supprimer un tel
-- membre, il faudrait d'abord supprimer (ou réaffecter) ses
-- emprunts, ou déclarer la clé étrangère en ON DELETE CASCADE --
-- ce qui n'est PAS souhaitable ici, car on perdrait l'historique
-- des emprunts.


-- ============================================================
-- Variante : récupérer l'id du membre qu'on vient d'insérer
-- ============================================================
-- currval() renvoie la dernière valeur générée par la séquence
-- dans la session courante -- pratique pour enchaîner sur l'id
-- réel plutôt que sur le nom :
--
-- PREPARE modifier_par_id (text, int) AS
--     UPDATE membre SET nom = $1 WHERE id_membre = $2 RETURNING id_membre, nom;
--
-- EXECUTE modifier_par_id('Autre nom', currval('membre_id_membre_seq')::int);
--
-- DEALLOCATE modifier_par_id;


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
