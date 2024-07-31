HANOI_SOURCE = osm/hanoi.osm.pbf
HANOI_COMPRESSED = osm/hanoi.osm.bz2
HANOI_CUSTOM_OSM = custom_osm/hanoi.osm.pbf

SG_SOURCE = osm/singapore.osm.pbf
SG_COMPRESSED = osm/singapore.osm.bz2
SG_CUSTOM_OSM = custom_osm/singapore.osm.pbf

TEMP_OUTPUT = /tmp/map.osm

all: compress copy

compress:
	osmconvert $(HANOI_SOURCE) -o=$(TEMP_OUTPUT)
	bzip2 -c $(TEMP_OUTPUT) > $(HANOI_COMPRESSED)

	osmconvert $(SG_SOURCE) -o=$(TEMP_OUTPUT)
	bzip2 -c $(TEMP_OUTPUT) > $(SG_COMPRESSED)

copy:
	cp ${HANOI_SOURCE} ${HANOI_CUSTOM_OSM}
	cp ${SG_SOURCE} ${SG_CUSTOM_OSM}

.PHONY: all compress copy
