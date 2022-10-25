using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace pruebasTeamcity
{
    class Program
    {
        static void Main(string[] args)
        {
            for (int i = 0; i <= 10; i++)
            {
                Console.WriteLine($"{i}");            
            }

            Console.WriteLine(Calcular(null,1));
        }

        private static int? Calcular(int? a, int? b) => a + b;
    }
}
