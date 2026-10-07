#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>

#include <array>
#include <chrono>
#include <cstdio>

struct Case {
    const char* name;
    double a1lat,a1lon,a2lat,a2lon;
    double b1lat,b1lon,b2lat,b2lon;
};

int main()
{
    const auto geod=GeographicLib::Geodesic::WGS84();
    const GeographicLib::Intersect intersect(geod);

    constexpr std::array<Case,8> cases={{
        {"crossing",0,-10,0,10,-10,0,10,0},
        {"shared_endpoint",0,-10,0,0,0,0,10,0},
        {"separate",0,-10,0,-5,10,5,10,10},
        {"overlap_same",0,-10,0,10,0,-5,0,15},
        {"overlap_reverse",0,-10,0,10,0,15,0,-5},
        {"antimeridian",0,170,0,-170,-10,180,10,180},
        {"oblique",35,-20,55,30,50,-15,30,25},
        {"polar",84,-60,84,60,82,0,89,0}
    }};

    constexpr std::size_t warmups=8;
    constexpr std::size_t rounds=128;
    double checksum=0;

    auto one=[&](const Case& c) {
        int segmode=99, coincidence=0;
        const auto p=intersect.Segment(
            c.a1lat,c.a1lon,c.a2lat,c.a2lon,
            c.b1lat,c.b1lon,c.b2lat,c.b2lon,
            segmode,&coincidence);
        int kind=segmode==0 ? (coincidence==0?2:3) : 1;
        checksum += kind;
        checksum += p.first*1e-12;
    };

    for(std::size_t r=0;r<warmups;++r)
        for(const auto& c:cases) one(c);

    const auto start=std::chrono::steady_clock::now();

    for(std::size_t r=0;r<rounds;++r)
        for(const auto& c:cases) one(c);

    const auto end=std::chrono::steady_clock::now();

    constexpr std::size_t operations=rounds*cases.size();
    const double ns=
        std::chrono::duration<double,std::nano>(end-start).count();

    std::printf("implementation=GeographicLib\n");
    std::printf("operations=%zu\n",operations);
    std::printf("ns_per_op=%.6f\n",ns/operations);
    std::printf("checksum=%.12f\n",checksum);

    constexpr std::size_t diagnosticRounds=512;

    for(const auto& item:cases) {
        double localChecksum=0.0;
        const auto localStart=std::chrono::steady_clock::now();

        for(std::size_t r=0;r<diagnosticRounds;++r) {
            int segmode=99, coincidence=0;
            const auto p=intersect.Segment(
                item.a1lat,item.a1lon,item.a2lat,item.a2lon,
                item.b1lat,item.b1lon,item.b2lat,item.b2lon,
                segmode,&coincidence);
            localChecksum += segmode==0 ? (coincidence==0?2:3) : 1;
            localChecksum += p.first*0.0;
        }

        const auto localEnd=std::chrono::steady_clock::now();
        const double localNs=
            std::chrono::duration<double,std::nano>(
                localEnd-localStart).count()/diagnosticRounds;

        std::printf(
            "case_ns_per_op.%s=%.6f checksum=%.3f\n",
            item.name,
            localNs,
            localChecksum);
    }
}
