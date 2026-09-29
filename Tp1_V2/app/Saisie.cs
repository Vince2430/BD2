namespace Tp1Commerce;

// Lecture des saisies au clavier, avec validation. Les valeurs lues
// sont ensuite TOUJOURS passees en parametres SQL (jamais concatenees).
public static class Saisie
{
    private static string LireLigne()
    {
        string? ligne = Console.ReadLine();
        if (ligne is null)
        {
            // Entree standard fermee (Ctrl+D) : on quitte proprement.
            Console.WriteLine();
            Environment.Exit(0);
        }
        return ligne.Trim();
    }

    // Entier entre min et max; Entree = defaut (si fourni).
    public static int LireEntier(string invite, int min, int max, int? defaut = null)
    {
        while (true)
        {
            Console.Write(invite);
            string texte = LireLigne();

            if (texte.Length == 0 && defaut.HasValue)
            {
                return defaut.Value;
            }
            if (int.TryParse(texte, out int valeur) && valeur >= min && valeur <= max)
            {
                return valeur;
            }
            Console.WriteLine($"  Entrez un nombre entier entre {min} et {max}.");
        }
    }

    // Entier >= min (ex. un numero de commande).
    public static int LireEntier(string invite, int min)
    {
        while (true)
        {
            Console.Write(invite);
            if (int.TryParse(LireLigne(), out int valeur) && valeur >= min)
            {
                return valeur;
            }
            Console.WriteLine($"  Entrez un nombre entier supérieur ou égal à {min}.");
        }
    }

    // Texte obligatoire, coupe a max caracteres.
    public static string LireTexte(string invite, int max = 200)
    {
        while (true)
        {
            Console.Write(invite);
            string texte = LireLigne();
            if (texte.Length > 0)
            {
                return texte.Length <= max ? texte : texte[..max];
            }
            Console.WriteLine("  Cette valeur est obligatoire.");
        }
    }

    // Texte facultatif : Entree = null (NULL dans la base).
    public static string? LireTexteOptionnel(string invite, int max = 1000)
    {
        Console.Write(invite);
        string texte = LireLigne();
        if (texte.Length == 0)
        {
            return null;
        }
        return texte.Length <= max ? texte : texte[..max];
    }

    public static bool Confirmer(string question)
    {
        while (true)
        {
            Console.Write(question + " (o/n) : ");
            string reponse = LireLigne().ToLowerInvariant();
            if (reponse == "o") return true;
            if (reponse == "n") return false;
            Console.WriteLine("  Répondez o ou n.");
        }
    }

    // Choix dans une liste; retourne l'INDEX (0 a n-1) de l'option choisie.
    public static int LireChoix(string titre, IReadOnlyList<string> options)
    {
        Console.WriteLine(titre);
        for (int i = 0; i < options.Count; i++)
        {
            Console.WriteLine($"  {i + 1}. {options[i]}");
        }
        return LireEntier("Choix : ", 1, options.Count) - 1;
    }
}
