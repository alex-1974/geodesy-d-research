#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>
#include <GeographicLib/Intersect.hpp>

#include <array>
#include <chrono>
#include <cstdio>

struct Case {
    const char* name;
    double lat,lon,aziX,aziY;
};

int main()
{
    const auto geod =
        GeographicLib::Geodesic::WGS84();

    const GeographicLib::Intersect inter(geod);

    constexpr std::array<Case,8> cases={{
        {"ordinary",0,0,30,120},
        {"orthogonal",0,0,0,90},
        {"near_parallel",10,20,45,45.1},
        {"polar",82,-40,20,145},
        {"reverse",-25,70,-35,140},
        {"coincident_same",0,0,90,90},
        {"coincident_reverse",0,0,90,-90},
        {"almost_symmetric",0.0001,0,45,135}
    }};

    std::array<GeographicLib::GeodesicLine,8> xlines = {
        geod.Line(0,0,30),
        geod.Line(0,0,0),
        geod.Line(10,20,45),
        geod.Line(82,-40,20),
        geod.Line(-25,70,-35),
        geod.Line(0,0,90),
        geod.Line(0,0,90),
        geod.Line(0.0001,0,45)
    };

    std::array<GeographicLib::GeodesicLine,8> ylines = {
        geod.Line(0,0,120),
        geod.Line(0,0,90),
        geod.Line(10,20,45.1),
        geod.Line(82,-40,145),
        geod.Line(-25,70,140),
        geod.Line(0,0,90),
        geod.Line(0,0,-90),
        geod.Line(0.0001,0,135)
    };

    constexpr std::size_t warmups=4;
    constexpr std::size_t rounds=64;

    double checksum=0;

    auto one=[&](std::size_t i) {
        int c=0;
        const auto p =
            inter.Next(
                xlines[i],
                ylines[i],
                &c);

        checksum +=
            p.first * 1e-12
            + p.second * 1e-12;
    };

    for(std::size_t r=0;r<warmups;++r)
        for(std::size_t i=0;i<cases.size();++i)
            one(i);

    const auto start =
        std::chrono::steady_clock::now();

    for(std::size_t r=0;r<rounds;++r)
        for(std::size_t i=0;i<cases.size();++i)
            one(i);

    const auto end =
        std::chrono::steady_clock::now();

    constexpr std::size_t operations =
        rounds * cases.size();

    const double ns =
        std::chrono::duration<double,std::nano>(
            end-start).count();

    std::printf("implementation=GeographicLib\n");
    std::printf("operations=%zu\n",operations);
    std::printf("ns_per_op=%.6f\n",ns/operations);
    std::printf("checksum=%.12f\n",checksum);
}
