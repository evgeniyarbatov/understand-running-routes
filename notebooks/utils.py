import gpxpy
import os

import pandas as pd

def parse_gpx(filepath):
  gpx_file = open(filepath, 'r')
  gpx = gpxpy.parse(gpx_file)

  data = []
  
  for track in gpx.tracks:
    for segment in track.segments:
      for point in segment.points:
        lat, lng = point.latitude, point.longitude
        
        data.append({
          'latitude': lat, 
          'longitude': lng,
        })

  return pd.DataFrame(data)
  
def get_output_path(output_dir, filename, extension):
  if not os.path.exists(output_dir):
    os.makedirs(output_dir, exist_ok=True)
  
  basename = os.path.splitext(os.path.basename(filename))[0]
  output_filename = basename + '.' + extension
  
  return os.path.join(output_dir, output_filename)