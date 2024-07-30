# Makefile for converting OSM PBF to OSM XML and compressing it

# Variables
OSMCONVERT = osmconvert
BZ2 = bzip2
SOURCE = osm/hanoi.osm.pbf
TEMP_OUTPUT = /tmp/hanoi.osm
FINAL_OUTPUT = osm/hanoi.osm.bz2

all: $(FINAL_OUTPUT)

$(FINAL_OUTPUT): $(TEMP_OUTPUT)
	$(BZ2) -c $(TEMP_OUTPUT) > $(FINAL_OUTPUT)

$(TEMP_OUTPUT): $(SOURCE)
	$(OSMCONVERT) $(SOURCE) -o=$(TEMP_OUTPUT)

clean:
	rm -f $(TEMP_OUTPUT) $(FINAL_OUTPUT)

.PHONY: all clean
