using Npgsql;

namespace Tp1Commerce;

// Énoncé : gerer les erreurs sans afficher le mot de passe ni la chaine
// de connexion. On n'affiche que le SQLSTATE, une categorie lisible et
// le message du serveur (MessageText), jamais ex.ToString().
public static class Erreurs
{
    // Execute une option du menu; une erreur n'arrete pas l'application.
    public static async Task ExecuterAsync(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            Afficher(ex);
        }
    }

    public static void Afficher(Exception ex)
    {
        switch (ex)
        {
            // PostgresException herite de NpgsqlException : elle doit venir avant.
            case PostgresException pg:
                Console.WriteLine($"Refusé par la base [{pg.SqlState}] {Categorie(pg.SqlState)}");
                Console.WriteLine("  " + pg.MessageText);
                break;

            case NpgsqlException:
                Console.WriteLine("Erreur : impossible de joindre le serveur de base de données.");
                break;

            default:
                Console.WriteLine($"Erreur inattendue ({ex.GetType().Name}).");
                break;
        }
    }

    public static string Categorie(string sqlState) => sqlState switch
    {
        "P0002" => "donnée introuvable",
        "23505" => "doublon (contrainte UNIQUE)",
        "23503" => "référence inexistante (clé étrangère)",
        "23514" => "règle métier ou contrainte CHECK",
        "23502" => "valeur obligatoire manquante",
        "22001" => "valeur trop longue",
        "42501" => "permission refusée pour cet utilisateur",
        "28P01" => "authentification refusée",
        _       => "erreur"
    };
}
