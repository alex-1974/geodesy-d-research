# R69.2 — prolate GeographicLib 2.7 reference corpus

Issue: alex-1974/geodesy-d#69

This slice freezes independent direct/inverse reference evidence before any
production-domain change.

## Models

All cases use a = 6,378,137 in caller-selected linear units.

Three negative flattenings are covered:

- mild: f = -1/300;
- moderate: f = -0.01;
- strong research-only stress case: f = -0.05.

The strong case is evidence for numerical behavior only. It is **not** a
proposal for the eventual public supported domain.

## Direct corpus

12 direct cases cover:

- ordinary mid-latitude propagation;
- polar propagation;
- equatorial propagation;
- long propagation;
- negative-distance/reverse propagation;
- all three prolate strengths where meaningful.

Each record stores:

- input ellipsoid and start state;
- signed distance;
- final latitude/longitude/azimuth;
- auxiliary-sphere arc a12.

## Inverse corpus

15 inverse cases cover:

- ordinary;
- equatorial;
- polar;
- symmetric near-antipodal;
- asymmetric near-antipodal;
- all three prolate strengths.

Each record stores:

- input ellipsoid/endpoints;
- shortest distance;
- forward/reverse azimuths;
- auxiliary-sphere arc a12.

## Purpose

R69.2 does not test geodesy-d yet. It establishes a stable GeographicLib 2.7
oracle surface that R69.3 can consume while experimenting with the smallest
possible D kernel changes.

The verifier checks:

- exact required case set;
- finite outputs;
- canonical latitude/longitude/azimuth ranges;
- non-negative inverse shortest distances;
- negative flattening identity per model class;
- difficult near-antipodal cases remain genuinely long.

## Run

    GEOGRAPHICLIB_ROOT=/path/to/geographiclib-2.7       bash research/m5-69-prolate-reference-corpus/run.sh
