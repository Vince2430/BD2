-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 7 : export de la base de connaissances (JSONL)
-- =============================================================
-- PSQL SEULEMENT (utilise \o et \pset). Lecture seule.
--   Recommande : lancer_export.command (double-clic)
--   psql -X -v ON_ERROR_STOP=1 -d tp1_vincent_trudel -f export_connaissances.sql
--   (a lancer DEPUIS le dossier export : le fichier est ecrit a cote)
--
-- Sortie : base_connaissances.jsonl, une unite documentaire par ligne :
--   {"source_id": "...", "content": "...", "metadata": {...}}
--
-- Tranche exportee (volontairement petite et lisible) :
--   produit     : les 2 plus petits id_produit de chaque categorie (12)
--   categorie   : toutes (6)
--   commande    : les 2 premieres (id_commande) de chaque statut, parmi
--                 celles qui contiennent au moins un des 12 produits (12)
--   client      : les clients de ces commandes (1 a 12), PSEUDONYMISES
--   evaluation  : les 24 premieres de la table (id_evaluation)
--   -> 55 a 66 unites (>= 50 exige)
--
-- Donnees personnelles : aucun nom, courriel, telephone, adresse
-- complete, hash, ni utilisateur de l'audit. Pseudonyme client-NNNN;
-- seule la VILLE de livraison est conservee.
-- Revenus et ventes : commandes annulees exclues, prix figes.
-- =============================================================

\set ON_ERROR_STOP on
\set QUIET on
SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- Fonctions utilitaires temporaires
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.montant(p NUMERIC)
RETURNS TEXT LANGUAGE sql IMMUTABLE
AS $$ SELECT replace(round(p, 2)::TEXT, '.', ',') || ' $' $$;

CREATE OR REPLACE FUNCTION pg_temp.pseudo(p_id_client INTEGER)
RETURNS TEXT LANGUAGE sql IMMUTABLE
AS $$ SELECT 'client-' || lpad(p_id_client::TEXT, 4, '0') $$;

-- Ville extraite du format « 123 rue X, Ville (QC) J6E 3Z1 »
CREATE OR REPLACE FUNCTION pg_temp.ville(p_adresse TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE
AS $$ SELECT COALESCE(substring(p_adresse FROM ', ([^,]+) \(QC\)'), 'ville non précisée') $$;

-- -------------------------------------------------------------
-- Tranche
-- -------------------------------------------------------------
DROP TABLE IF EXISTS pg_temp.tranche_produits, pg_temp.tranche_commandes, pg_temp.export_unites;

CREATE TEMP TABLE tranche_produits AS
SELECT id_produit
FROM (SELECT id_produit,
             ROW_NUMBER() OVER (PARTITION BY id_categorie ORDER BY id_produit) AS rn
      FROM produit) x
WHERE rn <= 2;

CREATE TEMP TABLE tranche_commandes AS
SELECT id_commande
FROM (SELECT c.id_commande,
             ROW_NUMBER() OVER (PARTITION BY c.id_statut ORDER BY c.id_commande) AS rn
      FROM commande c
      WHERE EXISTS (SELECT 1
                    FROM info_commande ic
                    JOIN tranche_produits tp ON tp.id_produit = ic.id_produit
                    WHERE ic.id_commande = c.id_commande)) x
WHERE rn <= 2;

CREATE TEMP TABLE export_unites (
    ordre     INTEGER,
    type_unite TEXT,
    source_id TEXT,
    content   TEXT,
    metadata  JSON   -- json (et non jsonb) : garde l'ordre des cles
);

-- Ventes et notes par produit (reutilisees par produit et categorie)
CREATE TEMP VIEW ventes_produit AS
SELECT ic.id_produit,
       SUM(ic.quantite)                    AS unites,
       SUM(ic.quantite * ic.prix_unitaire) AS revenu
FROM info_commande ic
JOIN commande c ON c.id_commande = ic.id_commande
JOIN statut s   ON s.id_statut   = c.id_statut
WHERE s.nom_statut <> 'Annulée'
GROUP BY ic.id_produit;

-- -------------------------------------------------------------
-- 1. Produits
-- -------------------------------------------------------------
INSERT INTO export_unites
SELECT 1, 'produit',
       'produit-' || p.id_produit,
       format('Produit « %s » (catégorie %s, marque %s, modèle %s), vendu %s. '
              || 'Unités vendues (commandes non annulées) : %s; revenu : %s. %s',
              p.nom_produit, cat.nom_categorie,
              sp.specifications_produit ->> 'marque',
              sp.specifications_produit ->> 'modele',
              pg_temp.montant(p.prix_produit),
              COALESCE(v.unites, 0), pg_temp.montant(COALESCE(v.revenu, 0)),
              CASE WHEN n.nb IS NULL THEN 'Aucune évaluation.'
                   ELSE format('Note moyenne : %s/5 sur %s évaluation(s).',
                               replace(round(n.moy, 1)::TEXT, '.', ','), n.nb) END),
       json_build_object(
           'type', 'produit',
           'source', 'commerce.produit, specification_produit',
           'id_produit', p.id_produit,
           'categorie', cat.nom_categorie,
           'marque', sp.specifications_produit ->> 'marque',
           'prix', p.prix_produit,
           'unites_vendues', COALESCE(v.unites, 0),
           'note_moyenne', round(n.moy, 2),
           'specifications', sp.specifications_produit)
FROM tranche_produits tp
JOIN produit p                ON p.id_produit    = tp.id_produit
JOIN categorie cat            ON cat.id_categorie = p.id_categorie
JOIN specification_produit sp ON sp.id_produit   = p.id_produit
LEFT JOIN ventes_produit v    ON v.id_produit    = p.id_produit
LEFT JOIN (SELECT id_produit, AVG(note_evaluation) AS moy, COUNT(*) AS nb
           FROM evaluation GROUP BY id_produit) n ON n.id_produit = p.id_produit;

-- -------------------------------------------------------------
-- 2. Categories
-- -------------------------------------------------------------
INSERT INTO export_unites
SELECT 2, 'categorie',
       'categorie-' || cat.id_categorie,
       format('Catégorie « %s » : %s produit(s) (%s). Unités vendues (commandes non annulées) : %s; revenu total : %s.',
              cat.nom_categorie, COUNT(p.id_produit),
              string_agg(p.nom_produit, ', ' ORDER BY p.nom_produit),
              COALESCE(SUM(v.unites), 0), pg_temp.montant(COALESCE(SUM(v.revenu), 0))),
       json_build_object(
           'type', 'categorie',
           'source', 'commerce.categorie',
           'id_categorie', cat.id_categorie,
           'nb_produits', COUNT(p.id_produit),
           'revenu_total', COALESCE(SUM(v.revenu), 0))
FROM categorie cat
LEFT JOIN produit p        ON p.id_categorie = cat.id_categorie
LEFT JOIN ventes_produit v ON v.id_produit   = p.id_produit
GROUP BY cat.id_categorie, cat.nom_categorie;

-- -------------------------------------------------------------
-- 3. Commandes
-- -------------------------------------------------------------
INSERT INTO export_unites
SELECT 3, 'commande',
       'commande-' || c.id_commande,
       format('Commande n° %s passée le %s par %s, livraison à %s. Statut : %s. '
              || 'Produits : %s. Total : %s. Historique : %s.',
              c.id_commande, to_char(c.date_commande, 'YYYY-MM-DD'),
              pg_temp.pseudo(c.id_client), pg_temp.ville(c.adresse_livraison_commande),
              s.nom_statut, l.produits, pg_temp.montant(l.total), h.historique),
       json_build_object(
           'type', 'commande',
           'source', 'commerce.commande, info_commande, audit_statut_commande',
           'id_commande', c.id_commande,
           'date', to_char(c.date_commande, 'YYYY-MM-DD'),
           'statut', s.nom_statut,
           'ville', pg_temp.ville(c.adresse_livraison_commande),
           'total', l.total,
           'client_ref', pg_temp.pseudo(c.id_client),
           'produits_ref', l.refs)
FROM tranche_commandes tc
JOIN commande c ON c.id_commande = tc.id_commande
JOIN statut s   ON s.id_statut   = c.id_statut
CROSS JOIN LATERAL (
    SELECT string_agg(format('%s x %s (%s)', ic.quantite, p.nom_produit,
                             pg_temp.montant(ic.prix_unitaire)), '; ' ORDER BY p.nom_produit) AS produits,
           SUM(ic.quantite * ic.prix_unitaire)                                              AS total,
           json_agg('produit-' || ic.id_produit ORDER BY ic.id_produit)                     AS refs
    FROM info_commande ic
    JOIN produit p ON p.id_produit = ic.id_produit
    WHERE ic.id_commande = c.id_commande
) l
CROSS JOIN LATERAL (
    SELECT string_agg(format('%s (%s)', a.nouveau_statut, to_char(a.date_operation, 'YYYY-MM-DD')),
                      ' → ' ORDER BY a.id_audit) AS historique
    FROM audit_statut_commande a
    WHERE a.id_commande = c.id_commande
) h;

-- -------------------------------------------------------------
-- 4. Clients (pseudonymises)
-- -------------------------------------------------------------
INSERT INTO export_unites
SELECT 4, 'client',
       pg_temp.pseudo(r.id_client),
       format('Client %s : %s commande(s) dont %s annulée(s); total dépensé (hors annulées) : %s; '
              || 'première commande le %s, dernière le %s; ville de livraison la plus fréquente : %s.',
              pg_temp.pseudo(r.id_client), r.nb, r.nb_annulees, pg_temp.montant(r.depense),
              r.premiere, r.derniere, r.ville),
       json_build_object(
           'type', 'client',
           'source', 'commerce.client, commande (pseudonymisé)',
           'nb_commandes', r.nb,
           'nb_annulees', r.nb_annulees,
           'total_depense', r.depense,
           'ville', r.ville)
FROM (
    SELECT c.id_client,
           COUNT(*)                                                  AS nb,
           COUNT(*) FILTER (WHERE s.nom_statut = 'Annulée')          AS nb_annulees,
           COALESCE(SUM(t.total) FILTER (WHERE s.nom_statut <> 'Annulée'), 0) AS depense,
           to_char(MIN(c.date_commande), 'YYYY-MM-DD')               AS premiere,
           to_char(MAX(c.date_commande), 'YYYY-MM-DD')               AS derniere,
           mode() WITHIN GROUP (ORDER BY pg_temp.ville(c.adresse_livraison_commande)) AS ville
    FROM commande c
    JOIN statut s ON s.id_statut = c.id_statut
    JOIN (SELECT id_commande, SUM(quantite * prix_unitaire) AS total
          FROM info_commande GROUP BY id_commande) t ON t.id_commande = c.id_commande
    WHERE c.id_client IN (SELECT c2.id_client
                          FROM tranche_commandes tc
                          JOIN commande c2 ON c2.id_commande = tc.id_commande)
    GROUP BY c.id_client
) r;

-- -------------------------------------------------------------
-- 5. Evaluations
-- -------------------------------------------------------------
INSERT INTO export_unites
SELECT 5, 'evaluation',
       'evaluation-' || e.id_evaluation,
       format('Évaluation du produit « %s » par %s le %s : note %s/5. Commentaire : %s',
              p.nom_produit, pg_temp.pseudo(e.id_client),
              to_char(e.date_evaluation, 'YYYY-MM-DD'), e.note_evaluation,
              COALESCE(e.commentaire_evaluation, 'aucun commentaire.')),
       json_build_object(
           'type', 'evaluation',
           'source', 'commerce.evaluation',
           'date', to_char(e.date_evaluation, 'YYYY-MM-DD'),
           'note', e.note_evaluation,
           'produit_ref', 'produit-' || e.id_produit,
           'client_ref', pg_temp.pseudo(e.id_client),
           'commentaire', COALESCE(e.commentaire_evaluation, 'aucun commentaire'))
FROM (SELECT * FROM evaluation ORDER BY id_evaluation LIMIT 24) e
JOIN produit p ON p.id_produit = e.id_produit;

-- -------------------------------------------------------------
-- Verifications AVANT d'ecrire le fichier (une erreur = pas de fichier)
-- -------------------------------------------------------------
DO $$
DECLARE
    v_nb INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_nb FROM export_unites;
    IF v_nb < 50 THEN
        RAISE EXCEPTION 'Seulement % unite(s) : 50 minimum.', v_nb;
    END IF;

    IF EXISTS (SELECT source_id FROM export_unites GROUP BY source_id HAVING COUNT(*) > 1) THEN
        RAISE EXCEPTION 'source_id en double.';
    END IF;

    IF EXISTS (SELECT 1 FROM export_unites
               WHERE content LIKE '%@%' OR metadata::TEXT LIKE '%@%') THEN
        RAISE EXCEPTION 'Un courriel (@) est present dans l''export.';
    END IF;

    IF EXISTS (SELECT 1 FROM export_unites u
               JOIN client c ON u.content LIKE '%' || c.nom_client || '%'
                            OR u.metadata::TEXT LIKE '%' || c.nom_client || '%') THEN
        RAISE EXCEPTION 'Un nom de client est present dans l''export.';
    END IF;

    IF (SELECT COUNT(*) FROM export_unites WHERE type_unite = 'commande')
       < 2 * (SELECT COUNT(*) FROM statut) THEN
        RAISE WARNING 'Moins de 2 commandes pour au moins un statut.';
    END IF;
END;
$$;

-- -------------------------------------------------------------
-- Ecriture du fichier JSONL
-- (\pset unaligned + tuples_only + \o : pas \copy, dont le format
--  texte doublerait les \ et casserait le JSON)
-- -------------------------------------------------------------
\pset format unaligned
\pset tuples_only on
\o base_connaissances.jsonl
SELECT json_build_object('source_id', source_id,
                         'content',   content,
                         'metadata',  metadata)::TEXT
FROM export_unites
ORDER BY ordre, source_id;
\o
\pset tuples_only off
\pset format aligned

-- Bilan
\echo 'Fichier ecrit : base_connaissances.jsonl'
SELECT type_unite, COUNT(*) AS unites
FROM export_unites
GROUP BY ordre, type_unite
ORDER BY ordre;
