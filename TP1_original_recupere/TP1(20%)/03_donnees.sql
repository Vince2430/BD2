-- =============================================================
-- TP1 - Base de donnees II (420-B56)
-- Etape 2 : jeu de donnees fictives
-- =============================================================
-- A EXECUTER PENDANT QUE VOUS ETES CONNECTE A "tp1_vincent_trudel",
-- apres 01_create_schema.sql et 02_declencheurs.sql.
--   psql -U postgres -d tp1_vincent_trudel -f 03_donnees.sql
--
-- Le script VIDE toutes les tables (TRUNCATE ... RESTART IDENTITY)
-- puis les recharge : on peut le relancer autant de fois qu'on veut.
--
-- Contenu :
--   fixe     : 6 statuts, 6 categories, 24 produits (+ specifications
--              JSONB), 12 receptions (9 validees, 3 attendues)
--   variable : clients et commandes (parametres ci-dessous), et tout
--              ce qui en decoule : lignes, paiements, expeditions,
--              evaluations, historique d'audit.
--
-- Toutes les donnees sont fictives : marques inventees, courriels
-- en @exemple.*, numeros en 555, faux hachages de mot de passe.
-- =============================================================

SET search_path TO commerce, public;

-- -------------------------------------------------------------
-- PARAMETRES : modifier ces trois lignes
--   graine : nombre entre -1 et 1 -> meme jeu de donnees a chaque
--            execution (utile pour comparer les EXPLAIN ANALYZE);
--            'aleatoire' -> un jeu different a chaque execution.
-- -------------------------------------------------------------
SET tp1.nb_clients   = '1500';
SET tp1.nb_commandes = '50000';
SET tp1.graine       = '0.75';

BEGIN;

TRUNCATE audit_statut_commande, evaluation, info_expedition, expedition,
         paiement, info_commande, commande, info_reception, reception,
         specification_produit, produit, client, statut, categorie
         RESTART IDENTITY CASCADE;

-- -------------------------------------------------------------
-- Fonctions utilitaires TEMPORAIRES (schema pg_temp) : elles
-- disparaissent a la fin de la session et ne polluent pas le schema.
-- -------------------------------------------------------------

-- Un element au hasard dans une liste
CREATE OR REPLACE FUNCTION pg_temp.au_hasard(p_liste TEXT[])
RETURNS TEXT LANGUAGE sql VOLATILE AS $f$
    SELECT p_liste[1 + floor(random() * array_length(p_liste, 1))::INT]
$f$;

-- Une adresse quebecoise fictive
CREATE OR REPLACE FUNCTION pg_temp.adresse_aleatoire()
RETURNS TEXT LANGUAGE sql VOLATILE AS $f$
    SELECT (10 + floor(random() * 9990))::INT || ' '
        || pg_temp.au_hasard(ARRAY['rue Principale', 'rue Saint-Denis',
               'boulevard René-Lévesque', 'avenue du Parc', 'rue Sherbrooke',
               'chemin de la Côte', 'rue des Érables', 'boulevard des Laurentides',
               'rue King', 'avenue Cartier', 'rue Notre-Dame', 'rue de la Montagne'])
        || ', '
        || pg_temp.au_hasard(ARRAY['Montréal', 'Laval', 'Longueuil', 'Québec',
               'Gatineau', 'Sherbrooke', 'Trois-Rivières', 'Terrebonne',
               'Saint-Jérôme', 'Lévis'])
        || ' (QC) '
        || pg_temp.au_hasard(ARRAY['H', 'J', 'G'])
        || floor(random() * 10)::INT || chr(65 + floor(random() * 26)::INT) || ' '
        || floor(random() * 10)::INT || chr(65 + floor(random() * 26)::INT)
        || floor(random() * 10)::INT
$f$;

-- Le colis (expedition) d'un camion pour une date : reutilise s'il
-- existe deja, sinon cree. Un colis regroupe donc plusieurs commandes.
CREATE OR REPLACE FUNCTION pg_temp.expedition_pour(p_date DATE, p_complete BOOLEAN)
RETURNS INTEGER LANGUAGE plpgsql VOLATILE AS $f$
DECLARE
    v_id     INTEGER;
    v_camion TEXT := 'CAM-0' || (1 + floor(random() * 3))::INT;
BEGIN
    SELECT id_expedition INTO v_id
      FROM expedition
     WHERE date_prevue_expedition = p_date
       AND camion_expedition      = v_camion
       AND est_complete           = p_complete;

    IF NOT FOUND THEN
        INSERT INTO expedition (date_prevue_expedition, date_complete_expedition,
                                est_complete, camion_expedition)
        VALUES (p_date,
                CASE WHEN p_complete
                     THEN p_date + floor(random() * 3)::INT + TIME '08:00'
                          + random() * INTERVAL '10 hours'
                END,
                p_complete, v_camion)
        RETURNING id_expedition INTO v_id;
    END IF;

    RETURN v_id;
END;
$f$;

-- -------------------------------------------------------------
-- 1. Statuts (en premier : aucune commande n'est insérable sans eux)
--    Cycle normal : En attente -> Payée -> En préparation
--                   -> Expédiée -> Livrée
--    Annulée : possible depuis En attente.
-- -------------------------------------------------------------
INSERT INTO statut (nom_statut) VALUES
    ('En attente'), ('Payée'), ('En préparation'),
    ('Expédiée'), ('Livrée'), ('Annulée');

-- -------------------------------------------------------------
-- 2. Categories
-- -------------------------------------------------------------
INSERT INTO categorie (nom_categorie) VALUES
    ('Ordinateurs portables'), ('Téléphones'), ('Tablettes'),
    ('Audio'), ('Écrans'), ('Accessoires');

-- -------------------------------------------------------------
-- 3. Produits (le stock initial est fixe plus bas, selon le nombre
--    de commandes demandees)
-- -------------------------------------------------------------
INSERT INTO produit (nom_produit, prix_produit, cout_procuration_produit, id_categorie)
SELECT v.nom, v.prix, v.cout, c.id_categorie
FROM (VALUES
    ('Portable Nordik NB-14 Air',       1299.99,  910.00, 'Ordinateurs portables'),
    ('Portable Voltra Pro 16',          2199.00, 1540.00, 'Ordinateurs portables'),
    ('Portable Kappa Étude 15',          749.99,  520.00, 'Ordinateurs portables'),
    ('Portable Aurore Gamer X17',       1899.99, 1330.00, 'Ordinateurs portables'),
    ('Téléphone Pixelis P8',             999.00,  640.00, 'Téléphones'),
    ('Téléphone Pixelis P8 Lite',        549.00,  350.00, 'Téléphones'),
    ('Téléphone Voltra Z5',             1149.99,  760.00, 'Téléphones'),
    ('Téléphone Kappa Essentiel',        299.99,  180.00, 'Téléphones'),
    ('Tablette Nordik Tab 11',           649.99,  420.00, 'Tablettes'),
    ('Tablette Aurore Pad Mini',         449.00,  290.00, 'Tablettes'),
    ('Tablette Voltra Tab Pro 13',      1249.00,  820.00, 'Tablettes'),
    ('Tablette Kappa Junior 8',          179.99,  105.00, 'Tablettes'),
    ('Casque Sonance ANC 700',           429.99,  250.00, 'Audio'),
    ('Écouteurs Sonance Buds 3',         229.99,  120.00, 'Audio'),
    ('Haut-parleur Sonance Galet',       129.99,   70.00, 'Audio'),
    ('Barre de son Aurore SB-2',         349.00,  210.00, 'Audio'),
    ('Écran Pixelis 27 QHD',             399.99,  260.00, 'Écrans'),
    ('Écran Pixelis 32 4K',              699.99,  460.00, 'Écrans'),
    ('Écran Kappa 24 Bureau',            189.99,  115.00, 'Écrans'),
    ('Écran Aurore 34 Incurvé',          849.00,  560.00, 'Écrans'),
    ('Souris Nordik Ergo',                79.99,   32.00, 'Accessoires'),
    ('Clavier Nordik Mécanique K2',      149.99,   70.00, 'Accessoires'),
    ('Chargeur Voltra GaN 65 W',          69.99,   28.00, 'Accessoires'),
    ('Station d''accueil Voltra USB-C',  249.99,  140.00, 'Accessoires')
) AS v (nom, prix, cout, cat)
JOIN categorie c ON c.nom_categorie = v.cat;

-- -------------------------------------------------------------
-- 4. Specifications JSONB (une par produit; attributs variables
--    selon la categorie)
-- -------------------------------------------------------------
INSERT INTO specification_produit (id_produit, specifications_produit)
SELECT p.id_produit, v.spec::JSONB
FROM (VALUES
    ('Portable Nordik NB-14 Air', '{"marque":"Nordik","modele":"NB-14 Air","garantie_mois":12,
      "dimensions":{"largeur_mm":312,"profondeur_mm":221,"hauteur_mm":16,"poids_g":1290},
      "connectivite":["Wi-Fi 6E","Bluetooth 5.3","USB-C","USB-C"],
      "ecran":{"taille_po":14,"resolution":"2560x1600","type":"IPS","frequence_hz":60},
      "materiel":{"processeur":"8 coeurs 3,2 GHz","memoire_go":16,"stockage_go":512},
      "batterie_wh":56}'),
    ('Portable Voltra Pro 16', '{"marque":"Voltra","modele":"Pro 16","garantie_mois":24,
      "dimensions":{"largeur_mm":356,"profondeur_mm":248,"hauteur_mm":18,"poids_g":2100},
      "connectivite":["Wi-Fi 7","Bluetooth 5.4","USB-C","HDMI","Thunderbolt 4"],
      "ecran":{"taille_po":16,"resolution":"3456x2234","type":"OLED","frequence_hz":120},
      "materiel":{"processeur":"14 coeurs 4,0 GHz","memoire_go":32,"stockage_go":1024,"carte_graphique":"12 Go dédiée"},
      "batterie_wh":99}'),
    ('Portable Kappa Étude 15', '{"marque":"Kappa","modele":"Étude 15","garantie_mois":12,
      "dimensions":{"largeur_mm":359,"profondeur_mm":236,"hauteur_mm":19,"poids_g":1700},
      "connectivite":["Wi-Fi 6","Bluetooth 5.2","USB-A","USB-C","HDMI"],
      "ecran":{"taille_po":15.6,"resolution":"1920x1080","type":"IPS","frequence_hz":60},
      "materiel":{"processeur":"6 coeurs 2,8 GHz","memoire_go":8,"stockage_go":256},
      "batterie_wh":42}'),
    ('Portable Aurore Gamer X17', '{"marque":"Aurore","modele":"Gamer X17","garantie_mois":24,
      "dimensions":{"largeur_mm":395,"profondeur_mm":282,"hauteur_mm":25,"poids_g":2900},
      "connectivite":["Wi-Fi 6E","Bluetooth 5.3","USB-A","USB-C","HDMI","Ethernet"],
      "ecran":{"taille_po":17.3,"resolution":"2560x1440","type":"IPS","frequence_hz":240},
      "materiel":{"processeur":"16 coeurs 4,5 GHz","memoire_go":32,"stockage_go":2048,"carte_graphique":"16 Go dédiée"},
      "batterie_wh":90,"clavier_rgb":true}'),
    ('Téléphone Pixelis P8', '{"marque":"Pixelis","modele":"P8","garantie_mois":12,
      "dimensions":{"largeur_mm":72,"profondeur_mm":8,"hauteur_mm":152,"poids_g":187},
      "connectivite":["5G","Wi-Fi 7","Bluetooth 5.3","NFC","USB-C"],
      "ecran":{"taille_po":6.3,"resolution":"2424x1080","type":"OLED","frequence_hz":120},
      "materiel":{"processeur":"8 coeurs","memoire_go":12,"stockage_go":256},
      "batterie_mah":4700,"appareil_photo_mp":50}'),
    ('Téléphone Pixelis P8 Lite', '{"marque":"Pixelis","modele":"P8 Lite","garantie_mois":12,
      "dimensions":{"largeur_mm":73,"profondeur_mm":9,"hauteur_mm":155,"poids_g":190},
      "connectivite":["5G","Wi-Fi 6","Bluetooth 5.3","NFC","USB-C"],
      "ecran":{"taille_po":6.1,"resolution":"2400x1080","type":"OLED","frequence_hz":90},
      "materiel":{"processeur":"8 coeurs","memoire_go":8,"stockage_go":128},
      "batterie_mah":4400,"appareil_photo_mp":48}'),
    ('Téléphone Voltra Z5', '{"marque":"Voltra","modele":"Z5","garantie_mois":24,
      "dimensions":{"largeur_mm":76,"profondeur_mm":8,"hauteur_mm":163,"poids_g":213},
      "connectivite":["5G","Wi-Fi 7","Bluetooth 5.4","NFC","USB-C"],
      "ecran":{"taille_po":6.8,"resolution":"3120x1440","type":"OLED","frequence_hz":120},
      "materiel":{"processeur":"8 coeurs","memoire_go":16,"stockage_go":512},
      "batterie_mah":5000,"appareil_photo_mp":200,"resistance_eau":"IP68"}'),
    ('Téléphone Kappa Essentiel', '{"marque":"Kappa","modele":"Essentiel","garantie_mois":12,
      "dimensions":{"largeur_mm":76,"profondeur_mm":9,"hauteur_mm":165,"poids_g":195},
      "connectivite":["4G","Wi-Fi 5","Bluetooth 5.0","USB-C"],
      "ecran":{"taille_po":6.5,"resolution":"1600x720","type":"LCD","frequence_hz":60},
      "materiel":{"processeur":"8 coeurs","memoire_go":4,"stockage_go":64},
      "batterie_mah":5000,"appareil_photo_mp":13}'),
    ('Tablette Nordik Tab 11', '{"marque":"Nordik","modele":"Tab 11","garantie_mois":12,
      "dimensions":{"largeur_mm":250,"profondeur_mm":6,"hauteur_mm":178,"poids_g":480},
      "connectivite":["Wi-Fi 6E","Bluetooth 5.3","USB-C"],
      "ecran":{"taille_po":11,"resolution":"2360x1640","type":"IPS","frequence_hz":120},
      "materiel":{"processeur":"8 coeurs","memoire_go":8,"stockage_go":128},
      "batterie_mah":8000,"stylet_compatible":true}'),
    ('Tablette Aurore Pad Mini', '{"marque":"Aurore","modele":"Pad Mini","garantie_mois":12,
      "dimensions":{"largeur_mm":195,"profondeur_mm":6,"hauteur_mm":134,"poids_g":293},
      "connectivite":["Wi-Fi 6","Bluetooth 5.2","USB-C"],
      "ecran":{"taille_po":8.3,"resolution":"2266x1488","type":"IPS","frequence_hz":60},
      "materiel":{"processeur":"6 coeurs","memoire_go":4,"stockage_go":64},
      "batterie_mah":5100,"stylet_compatible":false}'),
    ('Tablette Voltra Tab Pro 13', '{"marque":"Voltra","modele":"Tab Pro 13","garantie_mois":24,
      "dimensions":{"largeur_mm":281,"profondeur_mm":5,"hauteur_mm":215,"poids_g":580},
      "connectivite":["5G","Wi-Fi 7","Bluetooth 5.4","USB-C","Thunderbolt 4"],
      "ecran":{"taille_po":13,"resolution":"2752x2064","type":"OLED","frequence_hz":120},
      "materiel":{"processeur":"10 coeurs","memoire_go":16,"stockage_go":512},
      "batterie_mah":10200,"stylet_compatible":true}'),
    ('Tablette Kappa Junior 8', '{"marque":"Kappa","modele":"Junior 8","garantie_mois":6,
      "dimensions":{"largeur_mm":212,"profondeur_mm":10,"hauteur_mm":125,"poids_g":350},
      "connectivite":["Wi-Fi 5","Bluetooth 5.0"],
      "ecran":{"taille_po":8,"resolution":"1280x800","type":"LCD","frequence_hz":60},
      "materiel":{"processeur":"4 coeurs","memoire_go":2,"stockage_go":32},
      "batterie_mah":4500,"coque_protection":true}'),
    ('Casque Sonance ANC 700', '{"marque":"Sonance","modele":"ANC 700","garantie_mois":24,
      "dimensions":{"largeur_mm":170,"profondeur_mm":80,"hauteur_mm":200,"poids_g":250},
      "connectivite":["Bluetooth 5.3","USB-C","Jack 3,5 mm"],
      "autonomie_h":30,"reduction_bruit":true}'),
    ('Écouteurs Sonance Buds 3', '{"marque":"Sonance","modele":"Buds 3","garantie_mois":12,
      "dimensions":{"largeur_mm":60,"profondeur_mm":25,"hauteur_mm":50,"poids_g":48},
      "connectivite":["Bluetooth 5.3","USB-C"],
      "autonomie_h":8,"reduction_bruit":true,"resistance_eau":"IPX4"}'),
    ('Haut-parleur Sonance Galet', '{"marque":"Sonance","modele":"Galet","garantie_mois":12,
      "dimensions":{"largeur_mm":95,"profondeur_mm":95,"hauteur_mm":110,"poids_g":540},
      "connectivite":["Bluetooth 5.1","USB-C"],
      "autonomie_h":12,"puissance_w":10,"resistance_eau":"IP67"}'),
    ('Barre de son Aurore SB-2', '{"marque":"Aurore","modele":"SB-2","garantie_mois":24,
      "dimensions":{"largeur_mm":900,"profondeur_mm":100,"hauteur_mm":65,"poids_g":3200},
      "connectivite":["HDMI ARC","Optique","Bluetooth 5.0","Wi-Fi 5"],
      "puissance_w":300,"caisson_basses":true}'),
    ('Écran Pixelis 27 QHD', '{"marque":"Pixelis","modele":"27 QHD","garantie_mois":36,
      "dimensions":{"largeur_mm":614,"profondeur_mm":200,"hauteur_mm":450,"poids_g":5400},
      "connectivite":["HDMI","DisplayPort","USB-C"],
      "ecran":{"taille_po":27,"resolution":"2560x1440","type":"IPS","frequence_hz":165},
      "reglable_hauteur":true}'),
    ('Écran Pixelis 32 4K', '{"marque":"Pixelis","modele":"32 4K","garantie_mois":36,
      "dimensions":{"largeur_mm":714,"profondeur_mm":230,"hauteur_mm":520,"poids_g":7800},
      "connectivite":["HDMI","DisplayPort","USB-C","USB-A"],
      "ecran":{"taille_po":32,"resolution":"3840x2160","type":"IPS","frequence_hz":144},
      "reglable_hauteur":true,"hdr":"HDR600"}'),
    ('Écran Kappa 24 Bureau', '{"marque":"Kappa","modele":"24 Bureau","garantie_mois":12,
      "dimensions":{"largeur_mm":540,"profondeur_mm":180,"hauteur_mm":410,"poids_g":3100},
      "connectivite":["HDMI","VGA"],
      "ecran":{"taille_po":23.8,"resolution":"1920x1080","type":"VA","frequence_hz":75},
      "reglable_hauteur":false}'),
    ('Écran Aurore 34 Incurvé', '{"marque":"Aurore","modele":"34 Incurvé","garantie_mois":36,
      "dimensions":{"largeur_mm":810,"profondeur_mm":250,"hauteur_mm":470,"poids_g":8200},
      "connectivite":["HDMI","DisplayPort","USB-C"],
      "ecran":{"taille_po":34,"resolution":"3440x1440","type":"VA","frequence_hz":165,"courbure":"1500R"},
      "reglable_hauteur":true}'),
    ('Souris Nordik Ergo', '{"marque":"Nordik","modele":"Ergo","garantie_mois":12,
      "dimensions":{"largeur_mm":72,"profondeur_mm":120,"hauteur_mm":45,"poids_g":110},
      "connectivite":["Bluetooth 5.1","Récepteur USB"],
      "compatibilite":["Windows","macOS","Linux"],"dpi_max":4000}'),
    ('Clavier Nordik Mécanique K2', '{"marque":"Nordik","modele":"Mécanique K2","garantie_mois":24,
      "dimensions":{"largeur_mm":360,"profondeur_mm":130,"hauteur_mm":38,"poids_g":820},
      "connectivite":["USB-C","Bluetooth 5.1"],
      "compatibilite":["Windows","macOS"],"disposition":"CSA (français canadien)","retroeclairage":true}'),
    ('Chargeur Voltra GaN 65 W', '{"marque":"Voltra","modele":"GaN 65","garantie_mois":12,
      "dimensions":{"largeur_mm":45,"profondeur_mm":30,"hauteur_mm":45,"poids_g":110},
      "connectivite":["USB-C","USB-C","USB-A"],
      "puissance_w":65,"ports":{"usb_c":2,"usb_a":1}}'),
    ('Station d''accueil Voltra USB-C', '{"marque":"Voltra","modele":"Dock 11-en-1","garantie_mois":24,
      "dimensions":{"largeur_mm":120,"profondeur_mm":60,"hauteur_mm":20,"poids_g":180},
      "connectivite":["USB-C","HDMI","HDMI","Ethernet","USB-A","Lecteur SD"],
      "puissance_w":100,"compatibilite":["Windows","macOS"]}')
) AS v (nom, spec)
JOIN produit p ON p.nom_produit = v.nom;

-- -------------------------------------------------------------
-- 5. Donnees generees : stock, receptions, clients, commandes,
--    lignes, paiements, expeditions, evaluations, audit
-- -------------------------------------------------------------
DO $$
DECLARE
    v_nb_clients   INTEGER := current_setting('tp1.nb_clients')::INTEGER;
    v_nb_commandes INTEGER := current_setting('tp1.nb_commandes')::INTEGER;
    v_graine       TEXT    := current_setting('tp1.graine');

    v_prenoms TEXT[] := ARRAY['Émilie', 'Olivier', 'Camille', 'Félix', 'Léa',
        'William', 'Chloé', 'Thomas', 'Sarah', 'Samuel', 'Rosalie', 'Gabriel',
        'Maude', 'Nathan', 'Juliette', 'Antoine', 'Florence', 'Mathis',
        'Charlotte', 'Jérémy', 'Audrey', 'Louis', 'Mégane', 'Éric', 'Isabelle',
        'Marc-André', 'Noémie', 'Alexandre', 'Sophie', 'Karim', 'Aïcha', 'Minh'];
    v_noms TEXT[] := ARRAY['Tremblay', 'Gagnon', 'Roy', 'Côté', 'Bouchard',
        'Gauthier', 'Morin', 'Lavoie', 'Fortin', 'Gagné', 'Ouellet', 'Pelletier',
        'Bélanger', 'Lévesque', 'Bergeron', 'Leblanc', 'Paquette', 'Girard',
        'Simard', 'Boucher', 'Caron', 'Beaulieu', 'Cloutier', 'Dubé', 'Poirier',
        'Fournier', 'Lapointe', 'Nguyen', 'Diallo', 'Haddad', 'Rodriguez', 'Chen'];
    v_indicatifs TEXT[] := ARRAY['514', '438', '450', '418', '819', '579'];
    v_domaines   TEXT[] := ARRAY['exemple.com', 'exemple.ca', 'courriel.test'];
    v_modes      TEXT[] := ARRAY['Carte de crédit', 'Carte de débit', 'PayPal', 'Virement Interac'];

    v_st      INTEGER[];   -- [1] En attente .. [5] Livrée, [6] Annulée
    v_clients INTEGER[];

    v_id_rec   INTEGER;
    v_date_rec DATE;

    v_client   INTEGER;
    v_cmd      INTEGER;
    v_date     TIMESTAMP;
    v_age      NUMERIC;    -- age de la commande, en jours
    v_final    INTEGER;    -- indice du statut final dans v_st
    v_adresse  TEXT;
    v_tirage   DOUBLE PRECISION;
    v_nb_lignes INTEGER;
    v_qte      INTEGER;
    v_prod     INTEGER;
    v_prix     NUMERIC(10,2);
    v_total    NUMERIC(10,2);
    v_exp      INTEGER;
    v_date_exp DATE;
    v_ligne    RECORD;
    v_ligne_nb INTEGER;
    v_r        RECORD;
BEGIN
    IF v_graine <> 'aleatoire' THEN
        PERFORM setseed(v_graine::DOUBLE PRECISION);
    END IF;

    v_st := ARRAY[
        (SELECT id_statut FROM statut WHERE nom_statut = 'En attente'),
        (SELECT id_statut FROM statut WHERE nom_statut = 'Payée'),
        (SELECT id_statut FROM statut WHERE nom_statut = 'En préparation'),
        (SELECT id_statut FROM statut WHERE nom_statut = 'Expédiée'),
        (SELECT id_statut FROM statut WHERE nom_statut = 'Livrée'),
        (SELECT id_statut FROM statut WHERE nom_statut = 'Annulée')];

    -- ---------------------------------------------------------
    -- Stock initial : proportionnel au nombre de commandes, pour
    -- que le declencheur de stock ne bloque pas la generation.
    -- ---------------------------------------------------------
    UPDATE produit
       SET quantite_totale_produit = 20 + ceil(v_nb_commandes * 0.3)::INT
                                        + floor(random() * 30)::INT;

    -- ---------------------------------------------------------
    -- Receptions : 9 validees (passees, ajoutent au stock par le
    -- declencheur), 3 attendues (futures).
    -- ---------------------------------------------------------
    FOR r IN 1..12 LOOP
        IF r <= 9 THEN
            v_date_rec := CURRENT_DATE - 540 + (r - 1) * 60;
        ELSE
            v_date_rec := CURRENT_DATE + (r - 9) * 7;
        END IF;

        INSERT INTO reception (numero_reception, date_prevue_reception)
        VALUES ('REC-' || to_char(v_date_rec, 'YYYY') || '-' || lpad(r::TEXT, 3, '0'),
                v_date_rec)
        RETURNING id_reception INTO v_id_rec;

        INSERT INTO info_reception (id_reception, id_produit, quantite_recu)
        SELECT v_id_rec, id_produit, 10 + floor(random() * 51)::INT
          FROM produit
         ORDER BY random()
         LIMIT 2 + floor(random() * 4)::INT;

        IF r <= 9 THEN
            UPDATE reception
               SET est_complete = TRUE,
                   date_complete_reception = v_date_rec + floor(random() * 3)::INT
                                             + TIME '09:00' + random() * INTERVAL '8 hours'
             WHERE id_reception = v_id_rec;
        END IF;
    END LOOP;

    -- ---------------------------------------------------------
    -- Clients (5 % sans adresse, 10 % sans telephone)
    -- ---------------------------------------------------------
    INSERT INTO client (nom_client, courriel_client, telephone_client,
                        hash_mot_passe_client, adresse_client)
    SELECT s.prenom || ' ' || s.nom,
           lower(translate(s.prenom || '.' || s.nom,
                           'àâäçéèêëîïôöùûüÿÀÂÇÉÈÊÎÔ''-',
                           'aaaceeeeiioouuuyaaceeeio'))
               || s.i || '@' || pg_temp.au_hasard(v_domaines),
           CASE WHEN random() < 0.10 THEN NULL
                ELSE '(' || pg_temp.au_hasard(v_indicatifs) || ') 555-'
                     || lpad(floor(random() * 10000)::INT::TEXT, 4, '0')
           END,
           -- faux hachage au format bcrypt : aucun vrai mot de passe
           '$2b$12$' || substr(md5(random()::TEXT) || md5(random()::TEXT), 1, 53),
           CASE WHEN random() < 0.05 THEN NULL ELSE pg_temp.adresse_aleatoire() END
      FROM (SELECT i,
                   pg_temp.au_hasard(v_prenoms) AS prenom,
                   pg_temp.au_hasard(v_noms)    AS nom
              FROM generate_series(1, v_nb_clients) AS i
            OFFSET 0) AS s;

    v_clients := ARRAY(SELECT id_client FROM client ORDER BY id_client);

    -- ---------------------------------------------------------
    -- Commandes
    -- ---------------------------------------------------------
    FOR i IN 1..v_nb_commandes LOOP

        -- Client : distribution biaisee (quelques clients fideles
        -- commandent beaucoup, d'autres jamais)
        v_client := v_clients[1 + floor(v_nb_clients * power(random(), 1.5))::INT];

        -- Date : sur 18 mois, plus dense dans les derniers mois
        v_date := LOCALTIMESTAMP - power(random(), 1.6) * INTERVAL '540 days';
        v_age  := EXTRACT(EPOCH FROM (LOCALTIMESTAMP - v_date)) / 86400.0;

        -- Statut final selon l'age de la commande
        v_tirage := random();
        v_final := CASE
            WHEN v_age > 20 THEN CASE WHEN v_tirage < 0.92 THEN 5 ELSE 6 END
            WHEN v_age > 7  THEN CASE WHEN v_tirage < 0.70 THEN 5
                                      WHEN v_tirage < 0.92 THEN 4 ELSE 6 END
            WHEN v_age > 2  THEN CASE WHEN v_tirage < 0.10 THEN 2
                                      WHEN v_tirage < 0.50 THEN 3
                                      WHEN v_tirage < 0.95 THEN 4 ELSE 6 END
            ELSE                 CASE WHEN v_tirage < 0.40 THEN 1
                                      WHEN v_tirage < 0.80 THEN 2
                                      WHEN v_tirage < 0.95 THEN 3 ELSE 6 END
        END;

        -- Adresse de livraison : celle du client, sinon (ou 10 % du
        -- temps) une autre adresse
        SELECT adresse_client INTO v_adresse FROM client WHERE id_client = v_client;
        IF v_adresse IS NULL OR random() < 0.10 THEN
            v_adresse := pg_temp.adresse_aleatoire();
        END IF;

        -- Toute commande nait "En attente" (l'audit enregistre l'INSERT)
        INSERT INTO commande (date_commande, adresse_livraison_commande, id_client, id_statut)
        VALUES (v_date, v_adresse, v_client, v_st[1])
        RETURNING id_commande INTO v_cmd;

        -- Lignes : 1 a 4 produits distincts, quantite 1 a 3
        v_tirage := random();
        v_nb_lignes := CASE WHEN v_tirage < 0.45 THEN 1
                            WHEN v_tirage < 0.75 THEN 2
                            WHEN v_tirage < 0.92 THEN 3 ELSE 4 END;

        FOR l IN 1..v_nb_lignes LOOP
            v_tirage := random();
            v_qte := CASE WHEN v_tirage < 0.70 THEN 1
                          WHEN v_tirage < 0.92 THEN 2 ELSE 3 END;

            -- Tirage pondere : certains produits sont plus populaires
            -- (poids 1 a 5 selon le produit). Seuls les produits en
            -- stock suffisant et pas deja dans la commande sont candidats.
            SELECT p.id_produit, p.prix_produit INTO v_prod, v_prix
              FROM produit p
             WHERE p.quantite_totale_produit >= v_qte
               AND NOT EXISTS (SELECT 1 FROM info_commande ic
                                WHERE ic.id_commande = v_cmd
                                  AND ic.id_produit  = p.id_produit)
             ORDER BY power(random(), 1.0 / (1 + (p.id_produit * 7) % 5)::DOUBLE PRECISION) DESC
             LIMIT 1;

            CONTINUE WHEN NOT FOUND;

            -- Prix fige : 20 % des lignes ont ete payees a un prix
            -- different du prix actuel (promotion ou ancien prix)
            IF random() < 0.20 THEN
                v_prix := round(v_prix * (0.90 + random() * 0.20)::NUMERIC, 2);
            END IF;

            -- Le declencheur trg_maj_stock_produit decremente le stock
            INSERT INTO info_commande (id_commande, id_produit, quantite, prix_unitaire)
            VALUES (v_cmd, v_prod, v_qte, v_prix);
        END LOOP;

        -- Paiement
        -- Cree AVANT la progression du statut : trg_proteger_commande
        -- refuse le passage a "Payée" sans paiement complete couvrant
        -- le total. Une commande sans ligne (total 0) ne peut pas etre
        -- payee : elle reste "En attente" (sauf si elle devait etre annulee).
        SELECT COALESCE(SUM(quantite * prix_unitaire), 0) INTO v_total
          FROM info_commande WHERE id_commande = v_cmd;

        IF v_total = 0 AND v_final BETWEEN 2 AND 5 THEN
            v_final := 1;
        END IF;

        IF v_total > 0 THEN
            IF v_final BETWEEN 2 AND 5 THEN
                -- paye : paiement complete
                INSERT INTO paiement (id_commande, mode_paiement, date_paiement,
                                      montant_paiement, est_complete)
                VALUES (v_cmd, pg_temp.au_hasard(v_modes),
                        LEAST(v_date + random() * INTERVAL '6 hours', LOCALTIMESTAMP),
                        v_total, TRUE);
            ELSIF random() < 0.50 THEN
                -- En attente ou Annulée : paiement amorce, jamais complete
                INSERT INTO paiement (id_commande, mode_paiement, date_paiement,
                                      montant_paiement, est_complete)
                VALUES (v_cmd, pg_temp.au_hasard(v_modes), NULL, v_total, FALSE);
            END IF;
        END IF;

        -- Expeditions : Expédiée (colis en route) ou Livrée (colis complete)
        IF v_final IN (4, 5) THEN
            v_date_exp := (v_date + INTERVAL '2 days')::DATE;
            v_exp := pg_temp.expedition_pour(v_date_exp, v_final = 5);

            FOR v_ligne IN
                SELECT id_info_commande, quantite
                  FROM info_commande WHERE id_commande = v_cmd
            LOOP
                -- Livraison partielle : 30 % des lignes de 2+ unites
                -- partent en deux colis
                IF v_final = 5 AND v_age > 15 AND v_ligne.quantite >= 2
                   AND random() < 0.30 THEN
                    INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
                    VALUES (v_ligne.id_info_commande, v_exp, v_ligne.quantite - 1);

                    INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
                    VALUES (v_ligne.id_info_commande,
                            pg_temp.expedition_pour(v_date_exp + 5, TRUE), 1);
                ELSE
                    INSERT INTO info_expedition (id_info_commande, id_expedition, quantite_expediee)
                    VALUES (v_ligne.id_info_commande, v_exp, v_ligne.quantite);
                END IF;
            END LOOP;
        END IF;

        -- Progression du statut, etape par etape, EN DERNIER : le
        -- paiement et les expeditions existent deja, donc chaque
        -- transition respecte trg_proteger_commande (ordre des statuts,
        -- paiement complete pour "Payée", quantites couvertes pour
        -- "Expédiée", expeditions completees pour "Livrée").
        -- Chaque UPDATE est enregistre par trg_audit_statut_commande.
        IF v_final = 6 THEN
            UPDATE commande SET id_statut = v_st[6] WHERE id_commande = v_cmd;
        ELSE
            FOR s IN 2..v_final LOOP
                UPDATE commande SET id_statut = v_st[s] WHERE id_commande = v_cmd;
            END LOOP;
        END IF;
    END LOOP;

    -- ---------------------------------------------------------
    -- Audit : le declencheur a horodate toutes les lignes au moment
    -- du script. On etale les changements dans le temps a partir de
    -- la date de commande (1 jour et 2 h entre chaque etape) pour
    -- que l'historique soit vraisemblable.
    -- ---------------------------------------------------------
    UPDATE audit_statut_commande a
       SET date_changement = LEAST(x.date_commande
                                   + (x.rang - 1) * INTERVAL '1 day 2 hours',
                                   LOCALTIMESTAMP)
      FROM (SELECT a2.id_audit_statut_commande, c.date_commande,
                   row_number() OVER (PARTITION BY a2.id_commande
                                      ORDER BY a2.id_audit_statut_commande) AS rang
              FROM audit_statut_commande a2
              JOIN commande c ON c.id_commande = a2.id_commande) AS x
     WHERE a.id_audit_statut_commande = x.id_audit_statut_commande;

    -- ---------------------------------------------------------
    -- Evaluations : environ 35 % des couples (client, produit)
    -- livres. Insérées APRES les commandes : le declencheur
    -- trg_valider_achat_avant_evaluation l'exige.
    -- ---------------------------------------------------------
    INSERT INTO evaluation (id_produit, id_client, note_evaluation,
                            commentaire_evaluation, date_evaluation)
    SELECT n.id_produit, n.id_client, n.note,
           CASE WHEN random() < 0.20 THEN NULL
                ELSE pg_temp.au_hasard(CASE n.note
                    WHEN 1 THEN ARRAY['Déçu, ne fonctionne pas comme annoncé.',
                                      'Produit défectueux à la réception.']
                    WHEN 2 THEN ARRAY['Qualité inférieure à mes attentes.',
                                      'Correct, mais trop cher pour ce que c''est.']
                    WHEN 3 THEN ARRAY['Fait le travail, sans plus.',
                                      'Bon produit, mais la livraison a été lente.']
                    WHEN 4 THEN ARRAY['Très satisfait, je recommande.',
                                      'Bon rapport qualité-prix.']
                    ELSE        ARRAY['Excellent produit!',
                                      'Parfait, exactement ce que je cherchais.',
                                      'Au-delà de mes attentes.']
                END)
           END,
           LEAST(n.date_commande + (5 + random() * 25) * INTERVAL '1 day', LOCALTIMESTAMP)
      FROM (SELECT d.*,
                   CASE WHEN d.t < 0.05 THEN 1
                        WHEN d.t < 0.12 THEN 2
                        WHEN d.t < 0.27 THEN 3
                        WHEN d.t < 0.60 THEN 4 ELSE 5 END AS note
              FROM (SELECT DISTINCT ON (c.id_client, ic.id_produit)
                           c.id_client, ic.id_produit, c.date_commande,
                           random() AS t
                      FROM commande c
                      JOIN info_commande ic ON ic.id_commande = c.id_commande
                     WHERE c.id_statut = v_st[5]
                     ORDER BY c.id_client, ic.id_produit, c.date_commande) AS d
             OFFSET 0) AS n
     WHERE random() < 0.35;

    -- Resume (onglet Messages de pgAdmin)
    FOR v_r IN
        SELECT s.nom_statut, count(c.id_commande) AS nb
          FROM statut s
          LEFT JOIN commande c ON c.id_statut = s.id_statut
         GROUP BY s.id_statut, s.nom_statut
         ORDER BY s.id_statut
    LOOP
        RAISE NOTICE 'Commandes %-15s : %', v_r.nom_statut, v_r.nb;
    END LOOP;
END;
$$;

COMMIT;

-- -------------------------------------------------------------
-- Verification : nombre de lignes par table
-- -------------------------------------------------------------
SELECT 'statut'                AS table_nom, count(*) AS nb FROM statut
UNION ALL SELECT 'categorie',             count(*) FROM categorie
UNION ALL SELECT 'produit',               count(*) FROM produit
UNION ALL SELECT 'specification_produit', count(*) FROM specification_produit
UNION ALL SELECT 'reception',             count(*) FROM reception
UNION ALL SELECT 'info_reception',        count(*) FROM info_reception
UNION ALL SELECT 'client',                count(*) FROM client
UNION ALL SELECT 'commande',              count(*) FROM commande
UNION ALL SELECT 'info_commande',         count(*) FROM info_commande
UNION ALL SELECT 'paiement',              count(*) FROM paiement
UNION ALL SELECT 'expedition',            count(*) FROM expedition
UNION ALL SELECT 'info_expedition',       count(*) FROM info_expedition
UNION ALL SELECT 'evaluation',            count(*) FROM evaluation
UNION ALL SELECT 'audit_statut_commande', count(*) FROM audit_statut_commande
UNION ALL SELECT '== TOTAL ==', (
      (SELECT count(*) FROM statut) + (SELECT count(*) FROM categorie)
    + (SELECT count(*) FROM produit) + (SELECT count(*) FROM specification_produit)
    + (SELECT count(*) FROM reception) + (SELECT count(*) FROM info_reception)
    + (SELECT count(*) FROM client) + (SELECT count(*) FROM commande)
    + (SELECT count(*) FROM info_commande) + (SELECT count(*) FROM paiement)
    + (SELECT count(*) FROM expedition) + (SELECT count(*) FROM info_expedition)
    + (SELECT count(*) FROM evaluation) + (SELECT count(*) FROM audit_statut_commande));
