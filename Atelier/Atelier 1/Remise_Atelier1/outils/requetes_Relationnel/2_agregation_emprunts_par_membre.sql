-- ============================================================
-- Agrégation : nombre d'emprunts par membre
-- ============================================================

SELECT
    m.id_membre,
    m.nom              AS nom_membre,
    COUNT(e.id_emprunt) AS nb_emprunts
FROM membre m
LEFT JOIN emprunt e ON e.id_membre = m.id_membre
GROUP BY m.id_membre, m.nom
ORDER BY nb_emprunts DESC;

-- Explication :
-- On utilise LEFT JOIN (et non JOIN) pour que les membres qui
-- n'ont fait AUCUN emprunt apparaissent quand même dans le
-- résultat, avec un compte de 0 -- avec un JOIN normal, ils
-- disparaîtraient complètement du résultat.
--
-- Toute colonne du SELECT qui n'est pas dans une fonction
-- d'agrégat (ici COUNT) doit apparaître dans le GROUP BY --
-- c'est pour ça que id_membre ET nom sont tous les deux listés.


-- Variante : seulement les membres qui ont au moins 1 emprunt
SELECT
    m.id_membre,
    m.nom               AS nom_membre,
    COUNT(e.id_emprunt)  AS nb_emprunts
FROM membre m
JOIN emprunt e ON e.id_membre = m.id_membre
GROUP BY m.id_membre, m.nom
HAVING COUNT(e.id_emprunt) > 0
ORDER BY nb_emprunts DESC;

-- HAVING sert à filtrer APRÈS le regroupement (contrairement à
-- WHERE, qui filtre avant). Ici c'est redondant avec le JOIN
-- normal, mais HAVING devient utile si tu veux par exemple
-- "seulement les membres avec plus de 3 emprunts".
