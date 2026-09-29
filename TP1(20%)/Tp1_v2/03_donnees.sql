-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 3 : jeu de donnees fictives
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel"
-- (apres 01_create_schema.sql et 02_declencheurs.sql)
--   psql -U postgres -d tp1_vincent_trudel -f 03_donnees.sql
--
-- Relancable a volonte : TRUNCATE ... RESTART IDENTITY au debut.
-- Duree : environ une a deux minutes avec 50 000 commandes.
--
-- Toutes les donnees sont FICTIVES : noms tires au hasard de listes
-- de prenoms et de noms courants, courriels @exemple.test (domaine
-- reserve), telephones en 555, adresses inventees, mots de passe
-- remplaces par un hachage d'une chaine fictive.
--
-- Les commandes sont chargees en respectant les declencheurs (aucun
-- n'est desactive), dans cet ordre pour chaque commande :
--   INSERT « En attente » -> lignes -> paiement -> expedition
--   -> progression du statut, une etape a la fois, EN DERNIER.
-- Les dates sont relatives au moment de l'execution (LOCALTIMESTAMP).
-- =============================================================

SET search_path TO commerce, public;

-- Performance du chargement : les declencheurs (PL/pgSQL) gardent leurs
-- plans en cache. Planifies quand les tables sont presque vides, ils
-- choisiraient un parcours sequentiel qui deviendrait tres lent avec
-- 50 000 commandes. force_custom_plan : replanifier a chaque appel, avec
-- la taille reelle des tables (et ANALYZE regulier dans la boucle).
SET plan_cache_mode = force_custom_plan;

-- -------------------------------------------------------------
-- Parametres (a modifier ici)
-- -------------------------------------------------------------
DROP TABLE IF EXISTS pg_temp.parametres;
CREATE TEMP TABLE parametres AS
SELECT 1500   AS nb_clients,
       50000  AS nb_commandes,    -- table centrale (>= 100 exige)
       0.75   AS graine,          -- setseed : meme jeu de donnees a chaque execution
       365    AS jours_historique,
       30000  AS stock_initial,   -- reception initiale, par produit
       0.07   AS taux_annulation,
       0.04   AS taux_evaluation; -- part des achats livres qui recoivent une evaluation

SELECT setseed((SELECT graine FROM parametres)::FLOAT8);

-- -------------------------------------------------------------
-- Vider les tables
-- -------------------------------------------------------------
TRUNCATE audit_statut_commande, evaluation, info_expedition, expedition,
         paiement, info_commande, commande, info_reception, reception,
         specification_produit, produit, client, categorie, statut
         RESTART IDENTITY;

-- -------------------------------------------------------------
-- Fonctions utilitaires temporaires (disparaissent a la deconnexion)
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.sans_accent(p TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
AS $$
    SELECT translate(p, 'àâäéèêëîïôöùûüç', 'aaaeeeeiioouuuc');
$$;

-- Format : « 123 rue des Erables, Joliette (QC) J6E 3Z1 »
-- (l'export de l'etape 7 extrait la ville avec ', ([^,]+) \(QC\)')
CREATE OR REPLACE FUNCTION pg_temp.adresse_aleatoire()
RETURNS TEXT
LANGUAGE sql VOLATILE
AS $$
    SELECT (1 + floor(random() * 9999))::INT
        || ' '
        || (ARRAY['rue des Érables', 'rue Principale', 'boulevard des Pins',
                  'rue Saint-Charles', 'avenue du Lac', 'rue de la Gare',
                  'chemin du Rang-Double', 'rue des Cèdres', 'boulevard Industriel',
                  'rue Notre-Dame', 'avenue des Bouleaux', 'rue du Moulin'])
               [1 + floor(random() * 12)::INT]
        || ', '
        || (ARRAY['Joliette', 'Montréal', 'Laval', 'Terrebonne', 'Repentigny',
                  'Longueuil', 'Québec', 'Sherbrooke', 'Trois-Rivières', 'Gatineau',
                  'Saint-Jérôme', 'Mascouche', 'Lavaltrie', 'Rawdon', 'Berthierville'])
               [1 + floor(random() * 15)::INT]
        || ' (QC) '
        || (ARRAY['J', 'H', 'G'])[1 + floor(random() * 3)::INT]
        || floor(random() * 10)::INT
        || chr(65 + floor(random() * 26)::INT)
        || ' '
        || floor(random() * 10)::INT
        || chr(65 + floor(random() * 26)::INT)
        || floor(random() * 10)::INT;
$$;

-- -------------------------------------------------------------
-- Tables de reference
-- L'ordre d'insertion du statut compte : id 1 a 6 dans l'ordre du cycle.
-- -------------------------------------------------------------
INSERT INTO statut (nom_statut) VALUES
    ('En attente'), ('Payée'), ('En préparation'),
    ('Expédiée'), ('Livrée'), ('Annulée');

INSERT INTO categorie (nom_categorie) VALUES
    ('Ordinateurs portables'), ('Téléphones'), ('Audio'),
    ('Téléviseurs'), ('Accessoires'), ('Maison intelligente');

-- -------------------------------------------------------------
-- Produits et specifications JSONB
-- Les specifications varient selon la categorie (c'est la raison du
-- JSONB) : objets imbriques (dimensions, stockage), tableaux
-- (connectivite, protocoles, appareil_photo_mp). Certains accessoires
-- n'ont pas de dimensions (cle absente = sans objet).
-- -------------------------------------------------------------
DROP TABLE IF EXISTS pg_temp.produits_source;
CREATE TEMP TABLE produits_source (
    ordre     INTEGER,
    nom       VARCHAR(100),
    categorie VARCHAR(50),
    prix      NUMERIC(10,2),
    cout      NUMERIC(10,2),
    spec      JSONB
);

INSERT INTO produits_source VALUES
-- Ordinateurs portables
( 1, 'Portable Aurore Gamer X17', 'Ordinateurs portables', 2199.99, 1650.00,
  '{"marque":"Aurore","modele":"Gamer X17","garantie_mois":24,
    "processeur":"8 coeurs 4,8 GHz","memoire_go":32,
    "stockage":{"type":"SSD","capacite_go":1024},"ecran_po":17.3,
    "connectivite":["Wi-Fi 6E","Bluetooth 5.3","USB-C","HDMI"],
    "dimensions":{"largeur":39.6,"hauteur":2.6,"profondeur":29.0,"unite":"cm"}}'),
( 2, 'Portable Nordik Air 14', 'Ordinateurs portables', 1299.99, 950.00,
  '{"marque":"Nordik","modele":"Air 14","garantie_mois":12,
    "processeur":"6 coeurs 4,2 GHz","memoire_go":16,
    "stockage":{"type":"SSD","capacite_go":512},"ecran_po":14.0,
    "connectivite":["Wi-Fi 6","Bluetooth 5.2","USB-C"],
    "dimensions":{"largeur":31.2,"hauteur":1.5,"profondeur":22.1,"unite":"cm"}}'),
( 3, 'Portable Kappa Pro 16', 'Ordinateurs portables', 1799.00, 1320.00,
  '{"marque":"Kappa","modele":"Pro 16","garantie_mois":24,
    "processeur":"10 coeurs 4,6 GHz","memoire_go":32,
    "stockage":{"type":"SSD","capacite_go":1024},"ecran_po":16.0,
    "connectivite":["Wi-Fi 6E","Bluetooth 5.3","USB-C","Thunderbolt 4","HDMI"],
    "dimensions":{"largeur":35.6,"hauteur":1.8,"profondeur":24.8,"unite":"cm"}}'),
( 4, 'Portable Voltra Étudiant 15', 'Ordinateurs portables', 749.99, 540.00,
  '{"marque":"Voltra","modele":"Étudiant 15","garantie_mois":12,
    "processeur":"4 coeurs 3,6 GHz","memoire_go":8,
    "stockage":{"type":"SSD","capacite_go":256},"ecran_po":15.6,
    "connectivite":["Wi-Fi 5","Bluetooth 5.0","USB-A","HDMI"],
    "dimensions":{"largeur":36.0,"hauteur":2.0,"profondeur":23.5,"unite":"cm"}}'),
( 5, 'Portable Pixelis Flex 13', 'Ordinateurs portables', 1099.99, 800.00,
  '{"marque":"Pixelis","modele":"Flex 13","garantie_mois":12,
    "processeur":"6 coeurs 4,0 GHz","memoire_go":16,
    "stockage":{"type":"SSD","capacite_go":512},"ecran_po":13.3,"ecran_tactile":true,
    "connectivite":["Wi-Fi 6","Bluetooth 5.2","USB-C"],
    "dimensions":{"largeur":30.4,"hauteur":1.4,"profondeur":21.0,"unite":"cm"}}'),
-- Telephones
( 6, 'Téléphone Pixelis P8', 'Téléphones', 999.99, 720.00,
  '{"marque":"Pixelis","modele":"P8","garantie_mois":12,"ecran_po":6.3,
    "stockage":{"type":"interne","capacite_go":256},"appareil_photo_mp":[50,12,10],
    "connectivite":["5G","Wi-Fi 6E","Bluetooth 5.3","NFC","USB-C"],
    "dimensions":{"largeur":7.2,"hauteur":15.2,"profondeur":0.9,"unite":"cm"}}'),
( 7, 'Téléphone Voltra V5', 'Téléphones', 649.99, 460.00,
  '{"marque":"Voltra","modele":"V5","garantie_mois":12,"ecran_po":6.5,
    "stockage":{"type":"interne","capacite_go":128},"appareil_photo_mp":[48,8],
    "connectivite":["5G","Wi-Fi 6","Bluetooth 5.2","NFC","USB-C"],
    "dimensions":{"largeur":7.5,"hauteur":16.1,"profondeur":0.9,"unite":"cm"}}'),
( 8, 'Téléphone Kappa K2 Mini', 'Téléphones', 499.99, 350.00,
  '{"marque":"Kappa","modele":"K2 Mini","garantie_mois":12,"ecran_po":5.8,
    "stockage":{"type":"interne","capacite_go":128},"appareil_photo_mp":[24],
    "connectivite":["4G","Wi-Fi 5","Bluetooth 5.1","USB-C"],
    "dimensions":{"largeur":6.8,"hauteur":14.0,"profondeur":0.8,"unite":"cm"}}'),
( 9, 'Téléphone Nordik N1 Pro', 'Téléphones', 1149.99, 830.00,
  '{"marque":"Nordik","modele":"N1 Pro","garantie_mois":24,"ecran_po":6.7,
    "stockage":{"type":"interne","capacite_go":512},"appareil_photo_mp":[50,50,12],
    "connectivite":["5G","Wi-Fi 7","Bluetooth 5.4","NFC","USB-C"],
    "dimensions":{"largeur":7.7,"hauteur":16.3,"profondeur":0.9,"unite":"cm"}}'),
(10, 'Téléphone Aurore Lite', 'Téléphones', 349.99, 240.00,
  '{"marque":"Aurore","modele":"Lite","garantie_mois":12,"ecran_po":6.1,
    "stockage":{"type":"interne","capacite_go":64},"appareil_photo_mp":[13],
    "connectivite":["4G","Wi-Fi 5","Bluetooth 5.0","USB-C"],
    "dimensions":{"largeur":7.1,"hauteur":15.0,"profondeur":0.9,"unite":"cm"}}'),
-- Audio
(11, 'Casque Sonance Silence 700', 'Audio', 399.99, 260.00,
  '{"marque":"Sonance","modele":"Silence 700","garantie_mois":24,
    "autonomie_h":30,"reduction_bruit":true,
    "connectivite":["Bluetooth 5.3","Jack 3,5 mm","USB-C"],
    "dimensions":{"largeur":17.0,"hauteur":20.5,"profondeur":8.0,"unite":"cm"}}'),
(12, 'Écouteurs Sonance Pods 2', 'Audio', 199.99, 120.00,
  '{"marque":"Sonance","modele":"Pods 2","garantie_mois":12,
    "autonomie_h":8,"reduction_bruit":true,"resistance_eau":"IPX4",
    "connectivite":["Bluetooth 5.3"]}'),
(13, 'Barre de son Sonance Arc 5.1', 'Audio', 899.99, 610.00,
  '{"marque":"Sonance","modele":"Arc 5.1","garantie_mois":24,"canaux":"5.1",
    "connectivite":["HDMI eARC","Wi-Fi 6","Bluetooth 5.0","Optique"],
    "dimensions":{"largeur":114.0,"hauteur":8.7,"profondeur":11.6,"unite":"cm"}}'),
(14, 'Enceinte Voltra Boom Mini', 'Audio', 89.99, 50.00,
  '{"marque":"Voltra","modele":"Boom Mini","garantie_mois":12,
    "autonomie_h":12,"resistance_eau":"IP67",
    "connectivite":["Bluetooth 5.1","USB-C"],
    "dimensions":{"largeur":9.5,"hauteur":9.5,"profondeur":4.5,"unite":"cm"}}'),
(15, 'Casque Kappa Studio', 'Audio', 249.99, 160.00,
  '{"marque":"Kappa","modele":"Studio","garantie_mois":24,"filaire":true,
    "connectivite":["Jack 3,5 mm","Jack 6,35 mm"],
    "dimensions":{"largeur":18.0,"hauteur":21.0,"profondeur":9.0,"unite":"cm"}}'),
-- Televiseurs
(16, 'Téléviseur Pixelis QLED 55', 'Téléviseurs', 1199.99, 860.00,
  '{"marque":"Pixelis","modele":"QLED 55","garantie_mois":24,
    "diagonale_po":55,"resolution":"4K","taux_rafraichissement_hz":120,
    "connectivite":["HDMI 2.1","Wi-Fi 6","Bluetooth 5.2","Ethernet"],
    "dimensions":{"largeur":122.8,"hauteur":70.7,"profondeur":2.6,"unite":"cm"}}'),
(17, 'Téléviseur Pixelis OLED 65', 'Téléviseurs', 2499.99, 1840.00,
  '{"marque":"Pixelis","modele":"OLED 65","garantie_mois":24,
    "diagonale_po":65,"resolution":"4K","taux_rafraichissement_hz":144,
    "connectivite":["HDMI 2.1","Wi-Fi 6E","Bluetooth 5.3","Ethernet"],
    "dimensions":{"largeur":144.7,"hauteur":83.0,"profondeur":2.5,"unite":"cm"}}'),
(18, 'Téléviseur Nordik 43', 'Téléviseurs', 499.99, 350.00,
  '{"marque":"Nordik","modele":"TV 43","garantie_mois":12,
    "diagonale_po":43,"resolution":"4K","taux_rafraichissement_hz":60,
    "connectivite":["HDMI 2.0","Wi-Fi 5"],
    "dimensions":{"largeur":96.0,"hauteur":56.0,"profondeur":7.8,"unite":"cm"}}'),
(19, 'Téléviseur Aurore Cinéma 75', 'Téléviseurs', 1899.99, 1380.00,
  '{"marque":"Aurore","modele":"Cinéma 75","garantie_mois":24,
    "diagonale_po":75,"resolution":"4K","taux_rafraichissement_hz":120,
    "connectivite":["HDMI 2.1","Wi-Fi 6","Bluetooth 5.2","Ethernet"],
    "dimensions":{"largeur":167.5,"hauteur":96.2,"profondeur":3.0,"unite":"cm"}}'),
(20, 'Projecteur Kappa Lumen 4K', 'Téléviseurs', 1399.99, 1010.00,
  '{"marque":"Kappa","modele":"Lumen 4K","garantie_mois":24,
    "resolution":"4K","luminosite_lumens":3000,
    "connectivite":["HDMI 2.0","Wi-Fi 5","Bluetooth 5.0"],
    "dimensions":{"largeur":33.0,"hauteur":11.5,"profondeur":25.0,"unite":"cm"}}'),
-- Accessoires
(21, 'Souris Voltra Précision', 'Accessoires', 59.99, 30.00,
  '{"marque":"Voltra","modele":"Précision","garantie_mois":12,"dpi":16000,
    "connectivite":["Bluetooth 5.1","Récepteur USB"]}'),
(22, 'Clavier Kappa Mécanique TKL', 'Accessoires', 129.99, 75.00,
  '{"marque":"Kappa","modele":"Mécanique TKL","garantie_mois":24,
    "disposition":"CSA","retroeclairage":true,
    "connectivite":["USB-C","Bluetooth 5.1"],
    "dimensions":{"largeur":36.0,"hauteur":3.8,"profondeur":13.5,"unite":"cm"}}'),
(23, 'Chargeur Nordik 65 W', 'Accessoires', 49.99, 22.00,
  '{"marque":"Nordik","modele":"65 W","garantie_mois":12,"puissance_w":65,
    "connectivite":["USB-C"]}'),
(24, 'Câble Aurore USB-C 2 m', 'Accessoires', 19.99, 6.00,
  '{"marque":"Aurore","modele":"USB-C 2 m","longueur_m":2,
    "connectivite":["USB-C"]}'),
(25, 'Station d''accueil Pixelis Dock 11-en-1', 'Accessoires', 179.99, 110.00,
  '{"marque":"Pixelis","modele":"Dock 11-en-1","garantie_mois":24,
    "connectivite":["USB-C","USB-A","HDMI","Ethernet","Lecteur SD"],
    "dimensions":{"largeur":16.0,"hauteur":2.0,"profondeur":7.0,"unite":"cm"}}'),
-- Maison intelligente
(26, 'Thermostat Nordik Éco', 'Maison intelligente', 229.99, 140.00,
  '{"marque":"Nordik","modele":"Éco","garantie_mois":36,
    "protocoles":["Zigbee","Matter"],
    "connectivite":["Wi-Fi 5","Bluetooth 5.0"],
    "dimensions":{"largeur":8.5,"hauteur":8.5,"profondeur":2.4,"unite":"cm"}}'),
(27, 'Caméra Voltra Sécurité 360', 'Maison intelligente', 129.99, 70.00,
  '{"marque":"Voltra","modele":"Sécurité 360","garantie_mois":12,
    "resolution":"2K","vision_nocturne":true,
    "connectivite":["Wi-Fi 5"],
    "dimensions":{"largeur":7.8,"hauteur":11.8,"profondeur":7.8,"unite":"cm"}}'),
(28, 'Ampoules Aurore Couleur (4)', 'Maison intelligente', 69.99, 32.00,
  '{"marque":"Aurore","modele":"Couleur E26","garantie_mois":24,"nombre":4,
    "protocoles":["Matter"],
    "connectivite":["Wi-Fi 4","Bluetooth 5.0"]}'),
(29, 'Sonnette Kappa Vidéo', 'Maison intelligente', 179.99, 100.00,
  '{"marque":"Kappa","modele":"Vidéo","garantie_mois":12,"resolution":"1080p",
    "connectivite":["Wi-Fi 5"],
    "dimensions":{"largeur":4.5,"hauteur":13.0,"profondeur":2.5,"unite":"cm"}}'),
(30, 'Assistant vocal Sonance Écho Mini', 'Maison intelligente', 79.99, 38.00,
  '{"marque":"Sonance","modele":"Écho Mini","garantie_mois":12,
    "protocoles":["Matter","Thread"],
    "connectivite":["Wi-Fi 5","Bluetooth 5.2"],
    "dimensions":{"largeur":10.0,"hauteur":9.0,"profondeur":10.0,"unite":"cm"}}');

-- ORDER BY : les id_produit suivent l'ordre de la liste ci-dessus.
INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit, id_categorie)
SELECT ps.nom, ps.prix, ps.cout, c.id_categorie
FROM produits_source ps
JOIN categorie c ON c.nom_categorie = ps.categorie
ORDER BY ps.ordre;

INSERT INTO specification_produit (id_produit, specifications_produit)
SELECT p.id_produit, ps.spec
FROM produits_source ps
JOIN produit p ON p.nom_produit = ps.nom;

-- -------------------------------------------------------------
-- Clients
-- -------------------------------------------------------------
INSERT INTO client (nom_client, courriel_client, telephone_client,
                    hash_mot_passe_client, adresse_client)
SELECT x.prenom || ' ' || x.nom,
       pg_temp.sans_accent(lower(x.prenom || '.' || x.nom)) || '.' || x.g || '@exemple.test',
       CASE WHEN x.r_tel < 0.85 THEN '450-555-' || lpad(x.g::TEXT, 4, '0') END,
       'sha256$' || encode(sha256(convert_to('mot-de-passe-fictif-' || x.g, 'UTF8')), 'hex'),
       CASE WHEN x.r_adr < 0.95 THEN pg_temp.adresse_aleatoire() END
FROM (
    SELECT g,
           (ARRAY['Émile', 'Léa', 'Olivier', 'Florence', 'Félix', 'Alice', 'William',
                  'Charlotte', 'Thomas', 'Rosalie', 'Jacob', 'Béatrice', 'Noah',
                  'Juliette', 'Samuel', 'Zoé', 'Nathan', 'Clara', 'Gabriel', 'Maëlle',
                  'Liam', 'Emma', 'Louis', 'Chloé', 'Raphaël', 'Camille', 'Antoine',
                  'Sophie', 'Mathis', 'Laurence', 'Xavier', 'Mégane', 'Hugo', 'Anaïs',
                  'Jérémie', 'Océane', 'Alexis', 'Marianne', 'Tristan', 'Élodie'])
               [1 + floor(random() * 40)::INT] AS prenom,
           (ARRAY['Tremblay', 'Gagnon', 'Roy', 'Côté', 'Bouchard', 'Gauthier', 'Morin',
                  'Lavoie', 'Fortin', 'Gagné', 'Ouellet', 'Pelletier', 'Bélanger',
                  'Lévesque', 'Bergeron', 'Leblanc', 'Paquette', 'Girard', 'Simard',
                  'Boucher', 'Caron', 'Beaulieu', 'Cloutier', 'Dubé', 'Poirier',
                  'Fournier', 'Lapointe', 'Leclerc', 'Lefebvre', 'Poulin', 'Thibault',
                  'St-Pierre', 'Nadeau', 'Martin', 'Landry', 'Martel', 'Bédard',
                  'Grenier', 'Lessard', 'Bernier'])
               [1 + floor(random() * 40)::INT] AS nom,
           random() AS r_tel,
           random() AS r_adr
    FROM generate_series(1, (SELECT nb_clients FROM parametres)) AS g
) x
ORDER BY x.g;

-- -------------------------------------------------------------
-- Receptions
--   1) reception initiale validee : stock de depart de chaque produit;
--   2) reapprovisionnements valides au fil de l'annee;
--   3) receptions attendues (non validees) : v_receptions_attendues.
-- Les lignes sont inserees AVANT la validation (une reception
-- validee est figee), puis on valide : le declencheur ajoute au stock.
-- -------------------------------------------------------------
INSERT INTO reception (fournisseur_reception, date_prevue_reception)
VALUES ('Distribution Boréale inc.',
        (LOCALTIMESTAMP - ((SELECT jours_historique FROM parametres) + 35) * INTERVAL '1 day')::DATE);

INSERT INTO info_reception (id_reception, id_produit, quantite_attendue)
SELECT 1, id_produit, (SELECT stock_initial FROM parametres)
FROM produit
ORDER BY id_produit;

UPDATE reception
   SET est_complete = TRUE,
       date_complete_reception = LOCALTIMESTAMP
                                 - ((SELECT jours_historique FROM parametres) + 30) * INTERVAL '1 day'
 WHERE id_reception = 1;

DO $$
DECLARE
    v_fournisseurs TEXT[] := ARRAY['Distribution Boréale inc.', 'Grossiste Laurentides',
                                   'Import Saint-Laurent', 'Électro-Fournitures Lanaudière'];
    v_nb_produits  INTEGER := (SELECT COUNT(*) FROM produit);
    v_jours        INTEGER := (SELECT jours_historique FROM parametres);
    v_id           INTEGER;
    v_date         DATE;
BEGIN
    -- 2) 10 reapprovisionnements valides (5 produits chacun)
    FOR i IN 1..10 LOOP
        v_date := (LOCALTIMESTAMP - (v_jours - i * 33) * INTERVAL '1 day')::DATE;
        INSERT INTO reception (fournisseur_reception, date_prevue_reception)
        VALUES (v_fournisseurs[1 + (i % 4)], v_date)
        RETURNING id_reception INTO v_id;

        INSERT INTO info_reception (id_reception, id_produit, quantite_attendue)
        SELECT v_id, p, 100 + floor(random() * 700)::INT
        FROM (SELECT DISTINCT 1 + floor(random() * v_nb_produits)::INT AS p
              FROM generate_series(1, 8)) choix
        LIMIT 5;

        UPDATE reception
           SET est_complete = TRUE,
               date_complete_reception = v_date + TIME '10:30'
         WHERE id_reception = v_id;
    END LOOP;

    -- 3) 4 receptions attendues (non validees)
    FOR i IN 1..4 LOOP
        INSERT INTO reception (fournisseur_reception, date_prevue_reception)
        VALUES (v_fournisseurs[1 + ((i + 1) % 4)], CURRENT_DATE + i * 5)
        RETURNING id_reception INTO v_id;

        INSERT INTO info_reception (id_reception, id_produit, quantite_attendue)
        SELECT v_id, p, 50 + floor(random() * 450)::INT
        FROM (SELECT DISTINCT 1 + floor(random() * v_nb_produits)::INT AS p
              FROM generate_series(1, 6)) choix
        LIMIT 2 + i;
    END LOOP;
END;
$$;

-- Quantite entrante (previsionnel) = ce qui est attendu et pas encore recu.
UPDATE produit p
   SET quantite_entrante_produit = a.total
  FROM (SELECT ir.id_produit, SUM(ir.quantite_attendue) AS total
        FROM info_reception ir
        JOIN reception r ON r.id_reception = ir.id_reception
        WHERE NOT r.est_complete
        GROUP BY ir.id_produit) a
 WHERE a.id_produit = p.id_produit;

-- -------------------------------------------------------------
-- Commandes, lignes, paiements, expeditions, statuts
-- Etapes : 0 En attente, 1 Payee, 2 En preparation, 3 Expediee,
--          4 Livree. Une commande recente est moins avancee qu'une
--          ancienne. Environ 7 % sont annulees (depuis l'etape 0, 1 ou 2).
-- -------------------------------------------------------------
DO $$
DECLARE
    p_nb_commandes INTEGER := (SELECT nb_commandes FROM parametres);
    p_nb_clients   INTEGER := (SELECT nb_clients FROM parametres);
    p_jours        INTEGER := (SELECT jours_historique FROM parametres);
    p_annulation   FLOAT8  := (SELECT taux_annulation FROM parametres);

    v_prix        NUMERIC[] := ARRAY(SELECT prix_produit FROM produit ORDER BY id_produit);
    v_nb_produits INTEGER   := (SELECT COUNT(*) FROM produit);
    v_adresses    TEXT[]    := ARRAY(SELECT adresse_client FROM client ORDER BY id_client);
    v_statut      INTEGER[] := ARRAY(SELECT id_statut FROM statut ORDER BY id_statut);

    v_client    INTEGER;
    v_age       FLOAT8;    -- age de la commande, en jours
    v_date      TIMESTAMP;
    v_cmd       INTEGER;
    v_nb_lignes INTEGER;
    v_choisis   INTEGER[];
    v_prod      INTEGER;
    v_qte       INTEGER;
    v_total     NUMERIC(12,2);
    v_etape     INTEGER;
    v_annulee   BOOLEAN;
    v_r         FLOAT8;
    v_exp       INTEGER;
BEGIN
    FOR i IN 1..p_nb_commandes LOOP
        v_client := 1 + floor(random() * p_nb_clients)::INT;
        v_age    := random() * p_jours;
        v_date   := date_trunc('minute', LOCALTIMESTAMP - v_age * INTERVAL '1 day');

        -- 1) la commande, toujours « En attente »
        INSERT INTO commande (date_commande, adresse_livraison_commande, id_client, id_statut)
        VALUES (v_date,
                CASE WHEN random() < 0.1 OR v_adresses[v_client] IS NULL
                     THEN pg_temp.adresse_aleatoire()
                     ELSE v_adresses[v_client] END,
                v_client,
                v_statut[1])
        RETURNING id_commande INTO v_cmd;

        -- 2) 1 a 4 lignes (surtout 1 ou 2), produits distincts; les
        --    premiers produits sont plus populaires (random()^1.5).
        v_nb_lignes := 1 + floor(random() ^ 2 * 4)::INT;
        v_choisis   := '{}';
        v_total     := 0;
        WHILE cardinality(v_choisis) < v_nb_lignes LOOP
            v_prod := 1 + floor(random() ^ 1.5 * v_nb_produits)::INT;
            IF NOT (v_prod = ANY (v_choisis)) THEN
                v_choisis := v_choisis || v_prod;
                v_qte     := 1 + floor(random() ^ 3 * 3)::INT;
                INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire)
                VALUES (v_cmd, v_prod, v_qte, v_prix[v_prod]);
                v_total := v_total + v_qte * v_prix[v_prod];
            END IF;
        END LOOP;

        -- Etape visee selon l'age de la commande
        v_r := random();
        IF v_age < 1 THEN
            v_etape := CASE WHEN v_r < 0.5 THEN 0 ELSE 1 END;
        ELSIF v_age < 3 THEN
            v_etape := 1 + floor(v_r * 3)::INT;      -- 1 a 3
        ELSIF v_age < 10 THEN
            v_etape := 2 + floor(v_r * 3)::INT;      -- 2 a 4
        ELSE
            v_etape := 4;
        END IF;

        v_annulee := random() < p_annulation;
        IF v_annulee THEN
            v_etape := LEAST(v_etape, floor(random() * 3)::INT);  -- annulee depuis 0, 1 ou 2
        END IF;

        -- 3) paiement : autorisation (FALSE) ou capture (TRUE) du total
        v_r := random();
        INSERT INTO paiement (id_commande, mode_paiement, date_paiement,
                              montant_paiement, est_complete)
        VALUES (v_cmd,
                CASE WHEN v_r < 0.7 THEN 'Carte de crédit'
                     WHEN v_r < 0.9 THEN 'PayPal'
                     ELSE 'Carte de débit' END,
                v_date + INTERVAL '10 minutes',
                v_total,
                v_etape >= 1);

        -- 4) expedition (etape 3 et plus), completee si livree
        IF v_etape >= 3 THEN
            INSERT INTO expedition (date_prevue_expedition, date_complete_expedition,
                                    est_complete, camion_expedition)
            VALUES ((v_date + INTERVAL '2 days')::DATE,
                    CASE WHEN v_etape >= 4
                         THEN LEAST(v_date + INTERVAL '4 days', LOCALTIMESTAMP) END,
                    v_etape >= 4,
                    'Camion-' || lpad((1 + floor(random() * 12))::INT::TEXT, 2, '0'))
            RETURNING id_expedition INTO v_exp;

            INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
            SELECT id_info_commande, v_exp, quantite
            FROM info_commande
            WHERE id_commande = v_cmd;
        END IF;

        -- 5) progression du statut, une etape a la fois (regle f)
        FOR k IN 1..v_etape LOOP
            UPDATE commande SET id_statut = v_statut[k + 1] WHERE id_commande = v_cmd;
        END LOOP;

        IF v_annulee THEN
            UPDATE commande SET id_statut = v_statut[6] WHERE id_commande = v_cmd;
        END IF;

        -- Statistiques a jour toutes les 5 000 commandes
        IF i % 5000 = 0 THEN
            EXECUTE 'ANALYZE commande, info_commande, paiement, expedition, '
                 || 'info_expedition, audit_statut_commande, produit';
            RAISE NOTICE '% commandes chargees', i;
        END IF;
    END LOOP;
END;
$$;

ANALYZE commande, info_commande, paiement, expedition, info_expedition,
        audit_statut_commande;

-- -------------------------------------------------------------
-- Audit : les lignes ont ete ecrites avec l'heure du chargement.
-- On les etale de facon realiste a partir de la date de la commande.
-- -------------------------------------------------------------
UPDATE audit_statut_commande a
   SET date_operation = LEAST(
           c.date_commande +
           CASE a.nouveau_statut
               WHEN 'En attente'     THEN INTERVAL '0 minutes'
               WHEN 'Payée'          THEN INTERVAL '10 minutes'
               WHEN 'En préparation' THEN INTERVAL '1 day'
               WHEN 'Expédiée'       THEN INTERVAL '2 days'
               WHEN 'Livrée'         THEN INTERVAL '4 days'
               WHEN 'Annulée'        THEN
                   CASE a.ancien_statut
                       WHEN 'En attente' THEN INTERVAL '3 hours'
                       WHEN 'Payée'      THEN INTERVAL '6 hours'
                       ELSE                   INTERVAL '1 day 6 hours'
                   END
           END,
           LOCALTIMESTAMP)
  FROM commande c
 WHERE c.id_commande = a.id_commande;

-- -------------------------------------------------------------
-- Evaluations : une partie des achats livres (couple client-produit
-- distinct), note plutot positive, 20 % sans commentaire.
-- -------------------------------------------------------------
DROP TABLE IF EXISTS pg_temp.commentaires_source;
CREATE TEMP TABLE commentaires_source (note SMALLINT, texte TEXT);
INSERT INTO commentaires_source VALUES
    (1, 'Déçu, le produit a cessé de fonctionner après quelques semaines.'),
    (1, 'Ne correspond pas à la description.'),
    (2, 'Qualité moyenne pour le prix.'),
    (2, 'Fonctionne, mais plusieurs petits défauts.'),
    (3, 'Correct, sans plus.'),
    (3, 'Bon produit, mais la livraison a été un peu longue.'),
    (4, 'Très bon rapport qualité-prix.'),
    (4, 'Satisfait de mon achat, je le recommande.'),
    (4, 'Bonne qualité, installation facile.'),
    (5, 'Excellent, dépasse mes attentes!'),
    (5, 'Parfait, exactement ce que je cherchais.'),
    (5, 'Produit impeccable et livraison rapide.');

INSERT INTO evaluation (id_produit, id_client, note_evaluation,
                        commentaire_evaluation, date_evaluation)
SELECT a.id_produit,
       a.id_client,
       a.note,
       CASE WHEN a.r_com < 0.2 THEN NULL
            ELSE (SELECT cs.texte FROM commentaires_source cs
                  WHERE cs.note = a.note
                  ORDER BY random() + a.r_com LIMIT 1) END,
       LEAST(a.date_commande + (5 + a.r_com * 25) * INTERVAL '1 day', LOCALTIMESTAMP)
FROM (
    SELECT achats.*,
           CASE WHEN r_note < 0.05 THEN 1
                WHEN r_note < 0.12 THEN 2
                WHEN r_note < 0.30 THEN 3
                WHEN r_note < 0.65 THEN 4
                ELSE 5 END::SMALLINT AS note,
           random() AS r_com
    FROM (
        SELECT DISTINCT ON (c.id_client, ic.id_produit)
               c.id_client, ic.id_produit, c.date_commande, random() AS r_note
        FROM info_commande ic
        JOIN commande c ON c.id_commande = ic.id_commande
        JOIN statut s   ON s.id_statut   = c.id_statut
        WHERE s.nom_statut = 'Livrée'
        ORDER BY c.id_client, ic.id_produit, c.date_commande
    ) achats
    WHERE random() < (SELECT taux_evaluation FROM parametres)
) a
ORDER BY a.date_commande;

ANALYZE;
RESET plan_cache_mode;

-- -------------------------------------------------------------
-- Bilan
-- -------------------------------------------------------------
SELECT 'categorie' AS table_cible, COUNT(*) AS lignes FROM categorie
UNION ALL SELECT 'statut',                COUNT(*) FROM statut
UNION ALL SELECT 'produit',               COUNT(*) FROM produit
UNION ALL SELECT 'specification_produit', COUNT(*) FROM specification_produit
UNION ALL SELECT 'client',                COUNT(*) FROM client
UNION ALL SELECT 'commande',              COUNT(*) FROM commande
UNION ALL SELECT 'info_commande',         COUNT(*) FROM info_commande
UNION ALL SELECT 'paiement',              COUNT(*) FROM paiement
UNION ALL SELECT 'expedition',            COUNT(*) FROM expedition
UNION ALL SELECT 'info_expedition',       COUNT(*) FROM info_expedition
UNION ALL SELECT 'reception',             COUNT(*) FROM reception
UNION ALL SELECT 'info_reception',        COUNT(*) FROM info_reception
UNION ALL SELECT 'evaluation',            COUNT(*) FROM evaluation
UNION ALL SELECT 'audit_statut_commande', COUNT(*) FROM audit_statut_commande;

SELECT s.nom_statut, COUNT(*) AS commandes
FROM commande c
JOIN statut s ON s.id_statut = c.id_statut
GROUP BY s.id_statut, s.nom_statut
ORDER BY s.id_statut;
