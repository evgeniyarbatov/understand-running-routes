# understand-running-routes

Discover your running preferences with Open Street Map

## Overpass API

Convert OSM map:

```
osmconvert osm/hanoi.osm.pbf -o=/tmp/hanoi.osm
bzip2 -c /tmp/hanoi.osm > osm/hanoi.osm.bz2
```

## Run OSRM and Overpass API

```
docker compose up
```