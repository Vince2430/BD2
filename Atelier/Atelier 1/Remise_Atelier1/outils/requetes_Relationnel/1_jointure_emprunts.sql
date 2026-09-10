-- ============================================================
-- Jointure : afficher les emprunts avec le titre du livre
-- et le nom du membre
-- ============================================================

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

-- Explication :
-- On part de la table "emprunt" (celle qui contient les clés
-- étrangères) et on rejoint "livre" et "membre" pour remplacer
-- les id par des informations lisibles (titre, nom). C'est le
-- JOIN classique en relationnel -- l'équivalent de ce qu'on
-- "aplatit" manuellement dans un document JSONB imbriqué.
