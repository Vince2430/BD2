-- ============================================================
-- Transaction avec COMMIT / ROLLBACK -- SQL pur
-- ============================================================
--
-- BEGIN démarre une transaction. Toutes les commandes qui
-- suivent ne sont PAS définitives tant qu'on n'a pas fait
-- COMMIT -- et si quelque chose se passe mal, ROLLBACK annule
-- tout ce qui a été fait depuis le BEGIN.


-- ============================================================
-- Cas 1 : transaction réussie -- se termine par COMMIT
-- ============================================================

BEGIN;

INSERT INTO emprunt (id_livre, id_membre, date_emprunt)
VALUES (1, 1, CURRENT_DATE);

-- On pourrait ajouter d'autres commandes ici qui doivent
-- réussir ensemble avec l'INSERT ci-dessus

COMMIT;
-- L'emprunt est maintenant définitivement enregistré.


-- ============================================================
-- Cas 2 : transaction annulée volontairement -- ROLLBACK
-- ============================================================

BEGIN;

INSERT INTO emprunt (id_livre, id_membre, date_emprunt)
VALUES (2, 1, CURRENT_DATE);

-- On change d'avis, ou on détecte un problème logique
-- (par exemple après avoir vérifié autre chose) :

ROLLBACK;
-- L'INSERT ci-dessus n'a jamais été appliqué à la base.


-- ============================================================
-- Cas 3 : transaction annulée automatiquement à cause d'une
-- erreur (ex: violation de clé étrangère)
-- ============================================================

BEGIN;

INSERT INTO emprunt (id_livre, id_membre, date_emprunt)
VALUES (999999, 1, CURRENT_DATE);
-- ERREUR : id_livre 999999 n'existe pas -> viole fk_emprunt_livre
-- PostgreSQL met automatiquement la transaction en état "aborted" :
-- toute commande suivante sera refusée tant qu'on n'a pas fait
-- ROLLBACK explicitement (COMMIT tout seul ne suffit pas à s'en sortir).

ROLLBACK;
-- Nécessaire ici pour "libérer" la session et repartir sur une
-- transaction propre.


-- ============================================================
-- Variante avec gestion conditionnelle (comme un try/except) :
-- un bloc DO avec EXCEPTION annule automatiquement SES PROPRES
-- changements si une erreur survient, sans faire échouer toute
-- la session
-- ============================================================

DO $$
BEGIN
    INSERT INTO emprunt (id_livre, id_membre, date_emprunt)
    VALUES (999999, 1, CURRENT_DATE);  -- id_livre invalide, volontairement

    RAISE NOTICE 'Emprunt inséré avec succès.';
EXCEPTION
    WHEN foreign_key_violation THEN
        RAISE NOTICE 'Erreur : livre ou membre inexistant, opération annulée.';
END $$;
-- Ici, le bloc DO intercepte l'erreur lui-même : la session reste
-- utilisable normalement après, contrairement au Cas 3 ci-dessus.
