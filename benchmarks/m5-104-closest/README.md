# M5 #104 closest-intersection performance

Compares the prepared-line hot path of geodesy-d closest intersection with
GeographicLib 2.7 Intersect::Closest using preconstructed GeodesicLine values.

Final evidence uses LDC 1.41, g++ -O3 -march=native, CPU pinning and 12
separate process runs on the XPS. Hosted CI is only a build/smoke check.
