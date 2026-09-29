// =============================================================
// TP1 - Base de donnees II (420-B56)
// Etape 5 : application cliente console (C# + Npgsql)
// =============================================================
// Squelette vide : le code de l'application reste a ecrire.
//
// Exigences de l'enonce (a couvrir) :
//   - Connexion par variables d'environnement (utilisateur demo_*),
//     jamais de mot de passe dans le code.
//   - Requetes parametrees pour TOUTES les valeurs saisies.
//   - Afficher une liste venant d'une jointure ou d'une vue.
//   - Recherche selon au moins 2 criteres (requete 8 de 07_requetes.sql).
//   - Ajout d'une donnee respectant les contraintes.
//   - Modification dans une transaction (scenario de paiement de
//     06_transactions.sql : COMMIT / ROLLBACK).
//   - Appel de details_commande (P0002 gere) et de avancer_commande.
//   - Gestion des erreurs sans afficher le mot de passe ni la chaine
//     de connexion.
//
// Lancement (depuis ce dossier) :
//   dotnet run
// =============================================================

Console.WriteLine("TP1 - Application cliente (squelette)");

