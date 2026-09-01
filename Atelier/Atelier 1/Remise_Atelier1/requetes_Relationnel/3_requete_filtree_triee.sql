-- ============================================================
-- Requête filtrée et triée AVEC PARAMÈTRES -- version SQL pur
-- ============================================================
--
-- En SQL, l'équivalent d'une requête paramétrée (comme %s en
-- Python) s'appelle une requête PRÉPARÉE : on définit la requête
-- une fois avec des paramètres ($1, $2, ...), puis on l'exécute
-- plusieurs fois avec des valeurs différentes.
--
-- Important : comme en Python, un paramètre ($1) ne peut
-- remplacer qu'une VALEUR, jamais un nom de colonne ou un
-- ASC/DESC -- ORDER BY doit rester fixe dans une requête préparée.

-- ============================================================
-- Préparer la requête (une seule fois)
-- ============================================================

PREPARE recherche_emprunts (text, date) AS
    SELECT
        e.id_emprunt,
        l.nom AS titre_livre,
        m.nom AS nom_membre,
        e.date_emprunt,
        e.date_retour
    FROM emprunt e
    JOIN livre  l ON l.id_livre  = e.id_livre
    JOIN membre m ON m.id_membre = e.id_membre
    WHERE m.nom ILIKE $1
      AND e.date_emprunt >= $2
    ORDER BY e.date_emprunt DESC;

-- ============================================================
-- Exécuter la requête préparée avec différents paramètres
-- ============================================================

-- Recherche : membres dont le nom contient "ou", emprunts depuis 2026-01-01
EXECUTE recherche_emprunts('%ou%', '2026-01-01');

-- Même requête préparée, mais avec d'autres valeurs -- pas besoin
-- de la réécrire, seulement de changer les paramètres
EXECUTE recherche_emprunts('%gagnon%', '2026-06-01');

-- ============================================================
-- Nettoyage (libère la requête préparée de la session)
-- ============================================================

DEALLOCATE recherche_emprunts;


-- ============================================================
-- Si tu veux vraiment un tri dynamique (choisi au moment de
-- l'exécution), il faut soit écrire une requête préparée
-- distincte par option de tri, soit passer par une fonction
-- PL/pgSQL avec EXECUTE + format(), en validant la colonne
-- avec une liste blanche (comme on l'a fait côté Python)
-- ============================================================

PREPARE recherche_emprunts_par_titre (text) AS
    SELECT
        e.id_emprunt,
        l.nom AS titre_livre,
        m.nom AS nom_membre,
        e.date_emprunt
    FROM emprunt e
    JOIN livre  l ON l.id_livre  = e.id_livre
    JOIN membre m ON m.id_membre = e.id_membre
    WHERE m.nom ILIKE $1
    ORDER BY l.nom ASC;

EXECUTE recherche_emprunts_par_titre('%ou%');

DEALLOCATE recherche_emprunts_par_titre;
