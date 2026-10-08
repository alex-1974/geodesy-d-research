#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/Intersect.hpp>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <string>

int main(int argc,char** argv)
{
    if(argc!=4) return 2;
    const std::string mode=argv[1];
    const double f=std::atof(argv[2]);
    const std::size_t rounds=std::strtoull(argv[3],nullptr,10);
    constexpr double a=6378137.0;
    const GeographicLib::Geodesic geod(a,f);

    double checksum=0;
    const auto start=std::chrono::steady_clock::now();

    if(mode=="direct")
    {
        for(std::size_t i=0;i<rounds;++i)
        {
            double lat2,lon2,azi2;
            const double s=2000000.0 + double(i%97)*123.0;
            geod.Direct(12.5,-33.0,47.0,s,lat2,lon2,azi2);
            checksum += lat2+lon2+azi2;
        }
    }
    else if(mode=="inverse")
    {
        for(std::size_t i=0;i<rounds;++i)
        {
            double s12,azi1,azi2;
            const double d=double(i%89)*0.001;
            geod.Inverse(10.0+d,20.0,-25.0,130.0-d,s12,azi1,azi2);
            checksum += s12+azi1+azi2;
        }
    }
    else if(mode=="intersection_prepare")
    {
        for(std::size_t i=0;i<rounds;++i)
        {
            GeographicLib::Intersect inter(geod);
            checksum += double(i&1);
        }
    }
    else return 7;

    const auto end=std::chrono::steady_clock::now();
    const double ns=double(std::chrono::duration_cast<std::chrono::nanoseconds>(end-start).count())/double(rounds);

    std::cout.precision(17);
    std::cout<<"mode="<<mode<<"\n";
    std::cout<<"f="<<f<<"\n";
    std::cout<<"rounds="<<rounds<<"\n";
    std::cout<<"ns_per_op="<<ns<<"\n";
    std::cout<<"checksum="<<checksum<<"\n";
}
