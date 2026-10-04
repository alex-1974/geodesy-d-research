/*
 * Batch probe for GeographicLib LocalCartesian.
 *
 * This is a research/reference executable only. GeographicLib is not a
 * geodesy-d runtime dependency.
 *
 * Invocation:
 *
 *   geographiclib_localcartesian_probe OP a f lat0 lon0 h0
 *
 * OP:
 *   forward  input lat lon h  -> output east north up
 *   reverse  input east north up -> output lat lon h
 *
 * Angles at the process boundary are degrees.
 */

#include <exception>
#include <iomanip>
#include <iostream>
#include <string>

#include <GeographicLib/Geocentric.hpp>
#include <GeographicLib/LocalCartesian.hpp>


int main(int argc, char** argv)
{
    if (argc != 7)
    {
        std::cerr
            << "usage: "
            << argv[0]
            << " OP a f lat0 lon0 h0\n";

        return 2;
    }

    try
    {
        const std::string operation =
            argv[1];

        const double a =
            std::stod(argv[2]);

        const double f =
            std::stod(argv[3]);

        const double lat0 =
            std::stod(argv[4]);

        const double lon0 =
            std::stod(argv[5]);

        const double h0 =
            std::stod(argv[6]);

        const GeographicLib::Geocentric earth(
            a,
            f);

        const GeographicLib::LocalCartesian frame(
            lat0,
            lon0,
            h0,
            earth);

        std::cout
            << std::setprecision(17);

        double first;
        double second;
        double third;

        while (
            std::cin
            >> first
            >> second
            >> third)
        {
            double out1;
            double out2;
            double out3;

            if (operation == "forward")
            {
                frame.Forward(
                    first,
                    second,
                    third,
                    out1,
                    out2,
                    out3);
            }
            else if (operation == "reverse")
            {
                frame.Reverse(
                    first,
                    second,
                    third,
                    out1,
                    out2,
                    out3);
            }
            else
            {
                std::cerr
                    << "unknown operation: "
                    << operation
                    << '\n';

                return 2;
            }

            std::cout
                << out1 << ' '
                << out2 << ' '
                << out3 << '\n';
        }

        if (!std::cin.eof())
        {
            std::cerr
                << "invalid input row\n";

            return 4;
        }
    }
    catch (const std::exception& error)
    {
        std::cerr
            << error.what()
            << '\n';

        return 5;
    }

    return 0;
}
