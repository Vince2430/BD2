-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 7 : export de la base de connaissances (JSONL)
-- =============================================================
-- Regenere export/base_connaissances.jsonl a partir de PostgreSQL :
-- une ligne = une unite documentaire autoportante
--   { "source_id": ..., "content": ..., "metadata": { ... } }
--
-- A EXECUTER AVEC psql (pas pgAdmin : \o et \pset sont des commandes
-- de psql), DEPUIS LE DOSSIER export/ :
--   Recommande : double-cliquer lancer_export.command
--   psql -X -v ON_ERROR_STOP=1 -d tp1_vincent_trudel -f export_connaissances.sql
-- Prealable : base creee par creer_bd.command (scripts 00 a 05).
-- Lecture seule : le script ne modifie aucune table (seule une table
-- TEMPORAIRE est creee, detruite a la fin de la session).
--
-- Composition de la tranche (regles deterministes : memes unites et
-- memes source_id a chaque export, tant que la base est recreee avec
-- la meme graine dans 03_donnees.sql) :
--   produit     : les 2 plus petits id_produit de chaque categorie (12)
--   categorie   : toutes (6)
--   commande    : les 2 premieres (id_commande) de chaque statut, parmi
--                 celles qui contiennent au moins un produit choisi (12)
--   client      : les clients de ces commandes, pseudonymises (1 a 12)
--   evaluation  : les 24 premieres de la table (id_evaluation), liees
--                 ou non aux produits choisis (24)
--   Total attendu : 55 a 66 unites (minimum exige : 50).
--
-- Donnees semi-structurees et non structurees :
--   produit.metadata.specifications    = document JSONB brut
--   evaluation.metadata.commentaire    = texte libre complet
--                                        ("aucun commentaire" si NULL)
--
-- Renseignements personnels : aucun nom, courriel, telephone, adresse
-- complete ni hash n'est exporte. Client = pseudonyme client-NNNN;
-- livraison = ville seulement. La colonne utilisateur de l'audit
-- (roles PostgreSQL) n'est pas exportee. Verifie a l'etape 3.
--
-- Montants : 1234,56 $ (sans separateur de milliers). Dates : ISO
-- AAAA-MM-JJ (independant de la langue du serveur).
-- Revenus et ventes : commandes au statut « Annulée » exclues, prix
-- figes dans info_commande (meme convention que l'etape 4).
-- =============================================================

\set ON_ERROR_STOP on
\encoding UTF8
SET search_path TO commerce, public;

-- Montant en format canadien-francais : 1234,56 $
CREATE OR REPLACE FUNCTION pg_temp.montant(p NUMERIC)
RETURNS TEXT LANGUAGE sql STABLE AS $f$
    SELECT replace(to_char(p, 'FM9999999990.00'), '.', ',') || ' $'
$f$;

-- -------------------------------------------------------------
-- 1. Construction des unites (table temporaire)
-- -------------------------------------------------------------
CREATE TEMP TABLE export_unites AS
WITH
-- ---- Selection de la tranche --------------------------------
produits_choisis AS (
    SELECT id_produit
    FROM (SELECT p.id_produit,
                 ROW_NUMBER() OVER (PARTITION BY p.id_categorie
                                    ORDER BY p.id_produit) AS rang
          FROM produit p) x
    WHERE rang <= 2
),
commandes_choisies AS (
    SELECT id_commande
    FROM (SELECT c.id_commande,
                 ROW_NUMBER() OVER (PARTITION BY c.id_statut
                                    ORDER BY c.id_commande) AS rang
          FROM commande c
          WHERE EXISTS (SELECT 1
                        FROM info_commande ic
                        JOIN produits_choisis pc USING (id_produit)
                        WHERE ic.id_commande = c.id_commande)) x
    WHERE rang <= 2
),
clients_choisis AS (
    SELECT DISTINCT c.id_client
    FROM commande c
    JOIN commandes_choisies cc USING (id_commande)
),
evaluations_choisies AS (
    SELECT id_evaluation
    FROM evaluation
    ORDER BY id_evaluation
    LIMIT 24
),
-- ---- Statistiques reutilisees ---------------------------------
ventes_produit AS (
    SELECT ic.id_produit,
           COUNT(DISTINCT ic.id_commande)        AS nb_commandes,
           SUM(ic.quantite)                      AS unites,
           SUM(ic.quantite * ic.prix_unitaire)   AS revenu
    FROM info_commande ic
    JOIN commande c USING (id_commande)
    JOIN statut s   USING (id_statut)
    WHERE s.nom_statut <> 'Annulée'
    GROUP BY ic.id_produit
),
notes_produit AS (
    SELECT id_produit,
           COUNT(*)                        AS nb_evaluations,
           ROUND(AVG(note_evaluation), 1)  AS note_moyenne
    FROM evaluation
    GROUP BY id_produit
),

-- ---- Unites : produit ------------------------------------------
u_produit AS (
    SELECT 1 AS ordre, p.id_produit AS cle,
           'produit-' || p.id_produit AS source_id,
           format('%s, de la catégorie %s, vendu %s. Commandé dans %s commandes non annulées, pour %s unités vendues. %s',
                  p.nom_produit, cat.nom_categorie, pg_temp.montant(p.prix_produit),
                  COALESCE(v.nb_commandes, 0), COALESCE(v.unites, 0),
                  CASE WHEN n.nb_evaluations IS NULL THEN 'Aucune évaluation.'
                       ELSE format('%s évaluations, note moyenne de %s/5.',
                                   n.nb_evaluations, replace(n.note_moyenne::TEXT, '.', ','))
                  END) AS content,
           json_build_object(
               'type',           'produit',
               'source',         'tp1_vincent_trudel.commerce.produit + specification_produit',
               'categorie',      cat.nom_categorie,
               'categorie_ref',  'categorie-' || cat.id_categorie,
               'prix',           p.prix_produit,
               'date_export',    to_char(CURRENT_DATE, 'YYYY-MM-DD'),
               'specifications', sp.specifications_produit) AS metadata
    FROM produits_choisis pc
    JOIN produit p        USING (id_produit)
    JOIN categorie cat    USING (id_categorie)
    LEFT JOIN specification_produit sp USING (id_produit)
    LEFT JOIN ventes_produit v         USING (id_produit)
    LEFT JOIN notes_produit n          USING (id_produit)
),

-- ---- Unites : categorie ----------------------------------------
u_categorie AS (
    SELECT 2 AS ordre, cat.id_categorie AS cle,
           'categorie-' || cat.id_categorie AS source_id,
           CASE WHEN st.nb_produits = 0
                THEN format('Catégorie %s : aucun produit au catalogue.', cat.nom_categorie)
                ELSE format('Catégorie %s : %s produits au catalogue, de %s à %s. Revenu total de %s sur les commandes non annulées. Produit le plus vendu (en unités) : %s.',
                            cat.nom_categorie, st.nb_produits,
                            pg_temp.montant(st.prix_min), pg_temp.montant(st.prix_max),
                            pg_temp.montant(COALESCE(rv.revenu, 0)),
                            COALESCE(top.nom_produit, 'aucune vente'))
           END AS content,
           json_build_object(
               'type',         'categorie',
               'source',       'tp1_vincent_trudel.commerce.categorie + produit + info_commande',
               'nb_produits',  st.nb_produits,
               'produits_ref', COALESCE(refs.produits_ref, '[]'::JSON),
               'date_export',  to_char(CURRENT_DATE, 'YYYY-MM-DD')) AS metadata
    FROM categorie cat
    CROSS JOIN LATERAL (
        SELECT COUNT(*) AS nb_produits, MIN(p.prix_produit) AS prix_min,
               MAX(p.prix_produit) AS prix_max
        FROM produit p
        WHERE p.id_categorie = cat.id_categorie) st
    CROSS JOIN LATERAL (
        SELECT SUM(v.revenu) AS revenu
        FROM produit p
        JOIN ventes_produit v USING (id_produit)
        WHERE p.id_categorie = cat.id_categorie) rv
    LEFT JOIN LATERAL (
        SELECT p.nom_produit
        FROM produit p
        JOIN ventes_produit v USING (id_produit)
        WHERE p.id_categorie = cat.id_categorie
        ORDER BY v.unites DESC, p.id_produit
        LIMIT 1) top ON TRUE
    CROSS JOIN LATERAL (
        -- liens vers les unites produit presentes dans l'export
        SELECT json_agg('produit-' || p.id_produit ORDER BY p.id_produit) AS produits_ref
        FROM produit p
        JOIN produits_choisis pc USING (id_produit)
        WHERE p.id_categorie = cat.id_categorie) refs
),

-- ---- Unites : commande -----------------------------------------
u_commande AS (
    SELECT 3 AS ordre, c.id_commande AS cle,
           'commande-' || c.id_commande AS source_id,
           format('Commande passée le %s par le client %s, livraison à %s. Statut actuel : %s. Contenu : %s. Total : %s. Paiement : %s. Expédition : %s. Historique du statut : %s.',
                  to_char(c.date_commande, 'YYYY-MM-DD'),
                  'client-' || lpad(c.id_client::TEXT, 4, '0'),
                  COALESCE(substring(c.adresse_livraison_commande FROM ', ([^,]+) \(QC\)'),
                           'ville non précisée'),
                  s.nom_statut,
                  li.lignes, pg_temp.montant(li.total),
                  COALESCE(pa.paiements, 'aucun paiement enregistré'),
                  COALESCE(ex.expeditions, 'aucune expédition'),
                  COALESCE(hi.historique, 'non disponible')) AS content,
           json_build_object(
               'type',         'commande',
               'source',       'tp1_vincent_trudel.commerce.commande + info_commande + paiement + expedition + audit_statut_commande',
               'statut',       s.nom_statut,
               'date',         to_char(c.date_commande, 'YYYY-MM-DD'),
               'total',        li.total,
               'ville',        substring(c.adresse_livraison_commande FROM ', ([^,]+) \(QC\)'),
               'client_ref',   'client-' || lpad(c.id_client::TEXT, 4, '0'),
               'produits_ref', li.produits_ref,
               'date_export',  to_char(CURRENT_DATE, 'YYYY-MM-DD')) AS metadata
    FROM commandes_choisies cc
    JOIN commande c USING (id_commande)
    JOIN statut s   USING (id_statut)
    -- lignes de la commande (tous les produits, meme hors tranche)
    CROSS JOIN LATERAL (
        SELECT string_agg(format('%s × %s à %s', p.nom_produit, ic.quantite,
                                 pg_temp.montant(ic.prix_unitaire)),
                          ', ' ORDER BY ic.id_info_commande)           AS lignes,
               SUM(ic.quantite * ic.prix_unitaire)                    AS total,
               json_agg('produit-' || ic.id_produit ORDER BY ic.id_info_commande) AS produits_ref
        FROM info_commande ic
        JOIN produit p USING (id_produit)
        WHERE ic.id_commande = c.id_commande) li
    -- paiements (autorisation = non complete, capture = complete)
    CROSS JOIN LATERAL (
        SELECT string_agg(format('%s de %s, %s', pm.mode_paiement,
                                 pg_temp.montant(pm.montant_paiement),
                                 CASE WHEN pm.est_complete
                                      THEN 'capturé le ' || to_char(pm.date_paiement, 'YYYY-MM-DD')
                                      ELSE 'non complété' END),
                          '; ' ORDER BY pm.id_paiement) AS paiements
        FROM paiement pm
        WHERE pm.id_commande = c.id_commande) pa
    -- colis (une commande peut partir en plusieurs colis)
    CROSS JOIN LATERAL (
        SELECT string_agg(format('colis du camion %s prévu le %s, %s unité(s), %s',
                                 COALESCE(e.camion_expedition, 'non assigné'),
                                 to_char(e.date_prevue_expedition, 'YYYY-MM-DD'),
                                 e.unites,
                                 CASE WHEN e.est_complete
                                      THEN 'livré le ' || to_char(e.date_complete_expedition, 'YYYY-MM-DD')
                                      ELSE 'en route' END),
                          '; ' ORDER BY e.id_expedition) AS expeditions
        FROM (SELECT x.id_expedition, x.camion_expedition, x.date_prevue_expedition,
                     x.est_complete, x.date_complete_expedition,
                     SUM(ie.quantite_expediee) AS unites
              FROM info_expedition ie
              JOIN info_commande ic USING (id_info_commande)
              JOIN expedition x     USING (id_expedition)
              WHERE ic.id_commande = c.id_commande
              GROUP BY x.id_expedition) e) ex
    -- historique tire de la table d'audit (sans la colonne utilisateur)
    CROSS JOIN LATERAL (
        SELECT string_agg(a.nouveau_statut || ' (' || to_char(a.date_changement, 'YYYY-MM-DD') || ')',
                          ' → ' ORDER BY a.date_changement, a.id_audit_statut_commande) AS historique
        FROM audit_statut_commande a
        WHERE a.id_commande = c.id_commande
          AND a.operation IN ('INSERT', 'UPDATE')) hi
),

-- ---- Unites : client (pseudonymise) ----------------------------
u_client AS (
    SELECT 4 AS ordre, cl.id_client AS cle,
           'client-' || lpad(cl.id_client::TEXT, 4, '0') AS source_id,
           format('Client %s (pseudonyme) : %s commandes entre le %s et le %s, dont %s annulées. Total dépensé sur les commandes non annulées : %s. Catégories les plus achetées : %s. %s',
                  'client-' || lpad(cl.id_client::TEXT, 4, '0'),
                  co.nb_commandes,
                  to_char(co.premiere, 'YYYY-MM-DD'), to_char(co.derniere, 'YYYY-MM-DD'),
                  co.nb_annulees,
                  pg_temp.montant(COALESCE(de.total, 0)),
                  COALESCE(ca.categories, 'aucune'),
                  CASE WHEN ev.nb_evaluations = 0 THEN 'Aucune évaluation laissée.'
                       ELSE format('%s évaluations laissées, note moyenne de %s/5.',
                                   ev.nb_evaluations, replace(ev.note_moyenne::TEXT, '.', ','))
                  END) AS content,
           json_build_object(
               'type',          'client',
               'source',        'tp1_vincent_trudel.commerce.client (pseudonymisé) + commande + info_commande + evaluation',
               'nb_commandes',  co.nb_commandes,
               'total_depense', COALESCE(de.total, 0),
               'commandes_ref', cr.commandes_ref,
               'date_export',   to_char(CURRENT_DATE, 'YYYY-MM-DD')) AS metadata
    FROM clients_choisis cl
    CROSS JOIN LATERAL (
        SELECT COUNT(*) AS nb_commandes,
               COUNT(*) FILTER (WHERE s.nom_statut = 'Annulée') AS nb_annulees,
               MIN(c.date_commande) AS premiere,
               MAX(c.date_commande) AS derniere
        FROM commande c
        JOIN statut s USING (id_statut)
        WHERE c.id_client = cl.id_client) co
    CROSS JOIN LATERAL (
        SELECT SUM(ic.quantite * ic.prix_unitaire) AS total
        FROM commande c
        JOIN statut s         USING (id_statut)
        JOIN info_commande ic USING (id_commande)
        WHERE c.id_client = cl.id_client
          AND s.nom_statut <> 'Annulée') de
    CROSS JOIN LATERAL (
        -- les 2 categories ou le client a achete le plus d'unites
        SELECT string_agg(t.nom_categorie, ', ' ORDER BY t.unites DESC, t.nom_categorie) AS categories
        FROM (SELECT cat.nom_categorie, SUM(ic.quantite) AS unites
              FROM commande c
              JOIN statut s         USING (id_statut)
              JOIN info_commande ic USING (id_commande)
              JOIN produit p        USING (id_produit)
              JOIN categorie cat    USING (id_categorie)
              WHERE c.id_client = cl.id_client
                AND s.nom_statut <> 'Annulée'
              GROUP BY cat.nom_categorie
              ORDER BY unites DESC, cat.nom_categorie
              LIMIT 2) t) ca
    CROSS JOIN LATERAL (
        SELECT COUNT(*) AS nb_evaluations,
               ROUND(AVG(e.note_evaluation), 1) AS note_moyenne
        FROM evaluation e
        WHERE e.id_client = cl.id_client) ev
    CROSS JOIN LATERAL (
        -- liens vers les unites commande presentes dans l'export
        SELECT json_agg('commande-' || c.id_commande ORDER BY c.id_commande) AS commandes_ref
        FROM commande c
        JOIN commandes_choisies cc USING (id_commande)
        WHERE c.id_client = cl.id_client) cr
),

-- ---- Unites : evaluation ---------------------------------------
u_evaluation AS (
    SELECT 5 AS ordre, e.id_evaluation AS cle,
           'evaluation-' || e.id_evaluation AS source_id,
           format('Évaluation de %s/5 du produit %s (catégorie %s) par le client %s, le %s.',
                  e.note_evaluation, p.nom_produit, cat.nom_categorie,
                  'client-' || lpad(e.id_client::TEXT, 4, '0'),
                  to_char(e.date_evaluation, 'YYYY-MM-DD')) AS content,
           json_build_object(
               'type',        'evaluation',
               'source',      'tp1_vincent_trudel.commerce.evaluation + produit + categorie',
               'note',        e.note_evaluation,
               'date',        to_char(e.date_evaluation, 'YYYY-MM-DD'),
               'produit_ref', 'produit-' || e.id_produit,
               'client_ref',  'client-' || lpad(e.id_client::TEXT, 4, '0'),
               'commentaire', COALESCE(e.commentaire_evaluation, 'aucun commentaire'),
               'date_export', to_char(CURRENT_DATE, 'YYYY-MM-DD')) AS metadata
    FROM evaluations_choisies ec
    JOIN evaluation e  USING (id_evaluation)
    JOIN produit p     USING (id_produit)
    JOIN categorie cat USING (id_categorie)
)
SELECT * FROM u_produit
UNION ALL SELECT * FROM u_categorie
UNION ALL SELECT * FROM u_commande
UNION ALL SELECT * FROM u_client
UNION ALL SELECT * FROM u_evaluation;

-- -------------------------------------------------------------
-- 2. Verifications AVANT d'ecrire le fichier
--    Erreur = arret (ON_ERROR_STOP) et aucun fichier regenere.
--    Avertissement = le fichier est ecrit, mais a verifier.
-- -------------------------------------------------------------
DO $$
DECLARE
    v_total      INTEGER;
    v_doublons   INTEGER;
    v_statut     RECORD;
    v_nb         INTEGER;
BEGIN
    -- Minimum exige par l'enonce
    SELECT COUNT(*) INTO v_total FROM export_unites;
    IF v_total < 50 THEN
        RAISE EXCEPTION 'Export refuse : % unites seulement (minimum 50).', v_total;
    END IF;

    -- source_id unique (identifiant stable = cle de l'unite)
    SELECT COUNT(*) - COUNT(DISTINCT source_id) INTO v_doublons FROM export_unites;
    IF v_doublons > 0 THEN
        RAISE EXCEPTION 'Export refuse : % source_id en double.', v_doublons;
    END IF;

    -- Aucun renseignement personnel : ni courriel, ni nom de client
    IF EXISTS (SELECT 1 FROM export_unites
               WHERE content LIKE '%@%' OR metadata::TEXT LIKE '%@%') THEN
        RAISE EXCEPTION 'Export refuse : un courriel semble present.';
    END IF;
    IF EXISTS (SELECT 1
               FROM export_unites u
               JOIN client cl
                 ON u.content LIKE '%' || cl.nom_client || '%'
                 OR u.metadata::TEXT LIKE '%' || cl.nom_client || '%') THEN
        RAISE EXCEPTION 'Export refuse : un nom de client semble present.';
    END IF;

    -- 2 commandes par statut (un statut rare peut en avoir moins)
    FOR v_statut IN SELECT nom_statut FROM statut ORDER BY id_statut LOOP
        SELECT COUNT(*) INTO v_nb
        FROM export_unites
        WHERE metadata->>'type' = 'commande'
          AND metadata->>'statut' = v_statut.nom_statut;
        IF v_nb < 2 THEN
            RAISE WARNING 'Statut « % » : % commande(s) seulement dans l''export.',
                          v_statut.nom_statut, v_nb;
        END IF;
    END LOOP;

    RAISE NOTICE 'Verifications reussies : % unites.', v_total;
END $$;

-- -------------------------------------------------------------
-- 3. Ecriture du fichier JSONL (une ligne par unite, ordre stable)
--    json_build_object (et non jsonb) : garde l'ordre des cles
--    source_id, content, metadata.
-- -------------------------------------------------------------
\pset format unaligned
\pset tuples_only on
\pset footer off
\o base_connaissances.jsonl
SELECT json_build_object('source_id', source_id,
                         'content',   content,
                         'metadata',  metadata)
FROM export_unites
ORDER BY ordre, cle;
\o
\pset tuples_only off
\pset format aligned

-- -------------------------------------------------------------
-- 4. Bilan affiche a l'ecran
-- -------------------------------------------------------------
\echo
\echo 'Fichier ecrit : base_connaissances.jsonl'
SELECT metadata->>'type' AS type, COUNT(*) AS unites
FROM export_unites
GROUP BY ordre, metadata->>'type'
ORDER BY ordre;
