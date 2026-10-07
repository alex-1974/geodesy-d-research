#include <GeographicLib/Geodesic.hpp>
#include <GeographicLib/GeodesicLine.hpp>
#include <GeographicLib/Intersect.hpp>
#include <array>
#include <chrono>
#include <cstdio>

struct Case { const char* name; double latX,lonX,aziX,latY,lonY,aziY,p0x,p0y; };

int main() {
  const auto geod=GeographicLib::Geodesic::WGS84();
  const GeographicLib::Intersect inter(geod);
  constexpr std::array<Case,8> cases={{
    {"ordinary",0,-20,45,10,20,-60,0,0},
    {"offset",0,-20,45,10,20,-60,2.5e6,-1.0e6},
    {"antimeridian",15,175,80,-20,-175,10,0,0},
    {"polar",80,-60,20,82,50,-80,0,0},
    {"near_parallel",10,-30,85,10.1,-30,85.1,0,0},
    {"coincident_same",0,0,90,0,10,90,1.0e6,-2.0e6},
    {"large_offset",-20,-120,30,35,80,-110,1.5e7,-1.1e7},
    {"reverse_y",0,-20,45,10,20,120,0,0}
  }};
  std::array<GeographicLib::GeodesicLine,8> xlines={
    geod.Line(0,-20,45),geod.Line(0,-20,45),geod.Line(15,175,80),geod.Line(80,-60,20),
    geod.Line(10,-30,85),geod.Line(0,0,90),geod.Line(-20,-120,30),geod.Line(0,-20,45)};
  std::array<GeographicLib::GeodesicLine,8> ylines={
    geod.Line(10,20,-60),geod.Line(10,20,-60),geod.Line(-20,-175,10),geod.Line(82,50,-80),
    geod.Line(10.1,-30,85.1),geod.Line(0,10,90),geod.Line(35,80,-110),geod.Line(10,20,120)};
  constexpr std::size_t warmups=8, rounds=128;
  double checksum=0;
  auto one=[&](std::size_t i){
    int c=0;
    auto p=inter.Closest(xlines[i],ylines[i],GeographicLib::Intersect::Point(cases[i].p0x,cases[i].p0y),&c);
    checksum += p.first*1e-12 + p.second*1e-12;
  };
  for(std::size_t r=0;r<warmups;++r) for(std::size_t i=0;i<cases.size();++i) one(i);
  auto start=std::chrono::steady_clock::now();
  for(std::size_t r=0;r<rounds;++r) for(std::size_t i=0;i<cases.size();++i) one(i);
  auto end=std::chrono::steady_clock::now();
  constexpr std::size_t operations=rounds*cases.size();
  double ns=std::chrono::duration<double,std::nano>(end-start).count();
  std::printf("implementation=GeographicLib\noperations=%zu\nns_per_op=%.6f\nchecksum=%.12f\n",
    operations,ns/operations,checksum);
}
