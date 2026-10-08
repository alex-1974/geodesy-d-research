#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>

#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

struct Geometry {
    const char* name;
    double latX, lonX, aziX;
    double latY, lonY, aziY;
};

int main(int argc, char** argv)
{
    std::size_t rounds = 8;
    if (argc > 1)
        rounds = static_cast<std::size_t>(
            std::strtoull(argv[1], nullptr, 10));
    if (rounds == 0)
        return 1;

    const auto geod = GeographicLib::Geodesic::WGS84();
    const GeographicLib::Intersect inter(geod);

    constexpr std::array<Geometry,4> geometries={{
        {"ordinary",0,-20,45, 10,20,-60},
        {"near_parallel",10,20,45, 11,21,45.1},
        {"symmetric",0,0,45, 0,0,135},
        {"coincident",0,0,90, 0,0,90}
    }};

    constexpr std::array<double,4> radii={{
        20'000'000.0,
        40'000'000.0,
        80'000'000.0,
        160'000'000.0
    }};

    constexpr std::size_t warmups = 2;
    double checksum = 0.0;

    auto runAll = [&](const Geometry& item, double radius) {
        std::vector<int> coincidence;
        const auto points = inter.All(
            item.latX,item.lonX,item.aziX,
            item.latY,item.lonY,item.aziY,
            radius,
            coincidence,
            GeographicLib::Intersect::Point(0.0,0.0));

        double value =
            static_cast<double>(points.size()) * 1e-6;

        for (const auto& point : points)
            value +=
                point.first * 1e-12
                + point.second * 1e-12;

        checksum += value;
        return points.size();
    };

    for (std::size_t w = 0; w < warmups; ++w)
        for (const auto& item : geometries)
            for (const auto radius : radii)
                runAll(item, radius);

    double totalNs = 0.0;
    std::size_t totalResults = 0;
    std::size_t caseCount = 0;

    for (const auto& item : geometries)
    {
        for (const auto radius : radii)
        {
            std::size_t observedResults = 0;

            const auto start =
                std::chrono::steady_clock::now();

            for (std::size_t r = 0; r < rounds; ++r)
                observedResults = runAll(item, radius);

            const auto end =
                std::chrono::steady_clock::now();

            const double ns =
                std::chrono::duration<double,std::nano>(
                    end-start).count()
                / static_cast<double>(rounds);

            std::printf(
                "case.%s.r%.0f.exact_ns=%.6f results=%zu ns_per_result=%.6f\n",
                item.name,
                radius,
                ns,
                observedResults,
                observedResults == 0
                    ? 0.0
                    : ns / static_cast<double>(observedResults));

            totalNs += ns;
            totalResults += observedResults;
            ++caseCount;
        }
    }

    std::printf("implementation=GeographicLib\n");
    std::printf("queries=%zu\n",caseCount);
    std::printf(
        "exact_ns_per_query=%.6f\n",
        totalNs / static_cast<double>(caseCount));
    std::printf(
        "exact_ns_per_result=%.6f\n",
        totalResults == 0
            ? 0.0
            : totalNs / static_cast<double>(totalResults));
    std::printf("total_results=%zu\n",totalResults);
    std::printf("checksum=%.12f\n",checksum);

    return std::isfinite(checksum) ? 0 : 2;
}
