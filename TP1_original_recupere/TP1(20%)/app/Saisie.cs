namespace Tp1Commerce;

public static class Saisie
{
    public static int LireEntier(string invite, int min = 1, int max = int.MaxValue, int? defaut = null)
    {
        while (true)
        {
            Console.Write(invite);
            string texte = Lire();

            if (texte.Length == 0 && defaut.HasValue)
                return defaut.Value;

            if (int.TryParse(texte, out int valeur) && valeur >= min && valeur <= max)
                return valeur;

            Console.WriteLine(max == int.MaxValue
                ? $"  Entrez un nombre entier supérieur ou égal à {min}."
                : $"  Entrez un nombre entier entre {min} et {max}.");
        }
    }

    public static string LireTexte(string invite)
    {
        while (true)
        {
            Console.Write(invite);
            string texte = Lire();
            if (texte.Length > 0)
                return texte;
            Console.WriteLine("  Cette valeur est obligatoire.");
        }
    }

    public static string? LireTexteOptionnel(string invite)
    {
        Console.Write(invite);
        string texte = Lire();
        return texte.Length == 0 ? null : texte;
    }

    public static bool Confirmer(string invite)
    {
        while (true)
        {
            Console.Write($"{invite} (o/n) : ");
            string texte = Lire().ToLowerInvariant();
            if (texte is "o" or "oui") return true;
            if (texte is "n" or "non") return false;
            Console.WriteLine("  Répondez o ou n.");
        }
    }

    public static int LireChoix(string titre, IReadOnlyList<string> options)
    {
        Console.WriteLine(titre);
        for (int i = 0; i < options.Count; i++)
            Console.WriteLine($"  {i + 1}. {options[i]}");
        return LireEntier("Choix : ", 1, options.Count) - 1;
    }

    private static string Lire()
    {
        string? texte = Console.ReadLine();
        if (texte is null)
        {
            Console.WriteLine();
            Environment.Exit(0);
        }
        return texte.Trim();
    }
}
