using Npgsql;

namespace Tp1Commerce;

// Énoncé : connexion par variables d'environnement; aucun mot de passe
// ni chaine de connexion dans le code ou a l'ecran.
public static class Connexion
{
    private static string? _chaineConnexion;

    // Lit l'environnement et prepare la chaine de connexion.
    // Retourne une description du serveur SANS le mot de passe.
    public static string Initialiser()
    {
        var manquantes = new[] { "PGUSER", "PGPASSWORD" }
            .Where(nom => string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(nom)))
            .ToList();

        if (manquantes.Count > 0)
        {
            // On dit QUOI manque, jamais la valeur.
            throw new InvalidOperationException(
                "variable(s) d'environnement manquante(s) : " + string.Join(", ", manquantes));
        }

        int port = 5432;
        string? textePort = Lire("PGPORT");
        if (textePort is not null
            && (!int.TryParse(textePort, out port) || port < 1 || port > 65535))
        {
            throw new InvalidOperationException("PGPORT doit être un nombre entre 1 et 65535.");
        }

        // Builder plutot que concatenation : les valeurs sont echappees.
        var builder = new NpgsqlConnectionStringBuilder
        {
            Host            = Lire("PGHOST") ?? "localhost",
            Port            = port,
            Database        = Lire("PGDATABASE") ?? "tp1_vincent_trudel",
            Username        = Lire("PGUSER"),
            Password        = Lire("PGPASSWORD"),
            SearchPath      = "commerce",
            ApplicationName = "Tp1Commerce",
            Timeout         = 5
        };

        _chaineConnexion = builder.ConnectionString;
        return $"{builder.Host}:{builder.Port}/{builder.Database}";
    }

    // Une connexion par option du menu (le pool de Npgsql la reutilise).
    // Les NOTICE du serveur (ex. avancer_commande) sont affichees.
    public static async Task<NpgsqlConnection> OuvrirAsync()
    {
        if (_chaineConnexion is null)
        {
            throw new InvalidOperationException("Connexion.Initialiser() n'a pas été appelée.");
        }

        var connexion = new NpgsqlConnection(_chaineConnexion);
        connexion.Notice += (_, args) => Console.WriteLine("  NOTICE : " + args.Notice.MessageText);

        try
        {
            await connexion.OpenAsync();
        }
        catch
        {
            await connexion.DisposeAsync();
            throw;
        }

        return connexion;
    }

    private static string? Lire(string nom)
    {
        string? valeur = Environment.GetEnvironmentVariable(nom);
        return string.IsNullOrWhiteSpace(valeur) ? null : valeur.Trim();
    }
}
