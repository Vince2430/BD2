using Npgsql;

namespace Tp1Commerce;

// Énoncé : gérer les erreurs sans afficher le mot de passe ni la chaîne de connexion complète
public static class Erreurs
{
    public static async Task ExecuterAsync(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (PostgresException ex)
        {
            Afficher(ex);
        }
        catch (NpgsqlException)
        {
            Console.WriteLine("Erreur : impossible de joindre le serveur de base de données.");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Erreur inattendue ({ex.GetType().Name}).");
        }
    }

    public static void Afficher(PostgresException ex)
    {
        Console.WriteLine($"Refusé par la base [{ex.SqlState}] {Categorie(ex.SqlState)}");
        Console.WriteLine($"  {ex.MessageText}");
    }

    private static string Categorie(string sqlState) => sqlState switch
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
