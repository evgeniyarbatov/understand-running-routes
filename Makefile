SOURCE = osm/hanoi.osm.pbf
TEMP_OUTPUT = /tmp/hanoi.osm
FINAL_OUTPUT = osm/hanoi.osm.bz2
CUSTOM_OSM = custom_osm/hanoi.osm.pbf

all: $(FINAL_OUTPUT) copy

$(FINAL_OUTPUT): $(TEMP_OUTPUT)
	bzip2 -c $(TEMP_OUTPUT) > $(FINAL_OUTPUT)

$(TEMP_OUTPUT): $(SOURCE)
	osmconvert $(SOURCE) -o=$(TEMP_OUTPUT)

copy:
	cp ${SOURCE} ${CUSTOM_OSM}

clean:
	rm -f $(TEMP_OUTPUT) $(FINAL_OUTPUT)

.PHONY: all clean copy
