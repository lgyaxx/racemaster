import sys
import json

from bs4 import BeautifulSoup
import pygame


# Define the colors we will use in RGB format
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
BLUE = (0, 0, 255)
GREEN = (0, 255, 0)
RED = (255, 0, 0)


def extract_coords(coords_string):
    coords = coords_string.split(',')
    return {'latitude': float(coords[0]), 'longitude': float(coords[1])}


def min_coord(coordinates, dimension_name):
    if len(coordinates) <= 0:
        return False
    mc = coordinates[0][dimension_name]
    for c in coordinates:
        if c[dimension_name] < mc:
            mc = c[dimension_name]
    return mc


def max_coord(coordinates, dimension_name):
    if len(coordinates) < 0:
        return False
    mc = coordinates[0][dimension_name]
    for c in coordinates:
        if c[dimension_name] > mc:
            mc = c[dimension_name]
    return mc


def calc_offset(offset_scale, image_width, padding):
    return offset_scale * image_width + padding


def calc_offset_scale(upper_boundary, lower_boundary, scale):
    return abs(upper_boundary - lower_boundary) * scale


with open(f"kml/{sys.argv[1]}", 'r', encoding='utf-8') as kml:
    content = kml.read()

soup = BeautifulSoup(content, 'xml')

coordinates_string = soup.coordinates.contents[0].strip()
coordinates = coordinates_string.split(' ')

coordinates = list(map(extract_coords, coordinates))

latitude_lower_bound = min_coord(coordinates, 'latitude')
latitude_upper_bound = max_coord(coordinates, 'latitude')
# for longitude
longitude_upper_bound = max_coord(coordinates, 'longitude')
longitude_lower_bound = min_coord(coordinates, 'longitude')

lat_diff = latitude_upper_bound - latitude_lower_bound
long_diff = longitude_upper_bound - longitude_lower_bound
ratio = long_diff / lat_diff
print(ratio)

track_width = 500
track_height = round(track_width * ratio)

padding = max(track_height, track_width) / 20
track_height_padding = padding
track_width_padding = padding

if track_width >= track_height:
    map_width = track_width + padding * 2
    track_height_padding += (track_width - track_height) / 2
    line_width = int(track_width / 50)
else:
    map_width = track_height + padding * 2
    track_width_padding += (track_height - track_width) / 2
    line_width = int(track_height / 50)
map_height = map_width

track_unit_x = 1 / lat_diff
track_unit_y = 1 / long_diff

rect = pygame.Surface((map_width, map_height), pygame.SRCALPHA, 32)
rect.fill((255, 255, 255, 150))

i = 0
num_points = len(coordinates)
while i < num_points:
    point = coordinates[i]
    offset_x_scale = calc_offset_scale(point['latitude'], latitude_lower_bound, track_unit_x)
    offset_x = calc_offset(offset_x_scale, track_width, track_width_padding)
    offset_y_scale = calc_offset_scale(point['longitude'], longitude_upper_bound, track_unit_y)
    offset_y = calc_offset(offset_y_scale, track_height, track_height_padding)

    coordinates[i]['offset_x_scale'] = offset_x_scale
    coordinates[i]['offset_y_scale'] = offset_y_scale

    if i + 1 == num_points:     # this is the last point
        next_point = coordinates[0]

    else:
        next_point = coordinates[i + 1]

    offset_next_x_scale = calc_offset_scale(next_point['latitude'], latitude_lower_bound, track_unit_x)
    offset_next_x = calc_offset(offset_next_x_scale, track_width, track_width_padding)
    offset_next_y_scale = calc_offset_scale(next_point['longitude'], longitude_upper_bound, track_unit_y)
    offset_next_y = calc_offset(offset_next_y_scale, track_height, track_height_padding)

    pygame.draw.line(rect, WHITE, (offset_x, offset_y), (offset_next_x, offset_next_y), line_width)
    i += 1

filename = sys.argv[1].split(".")[0]
pygame.image.save(rect, f"maps/{filename}.png")

output_json = {'coordinates': coordinates, 'track_width_padding': track_width_padding, 'track_height_padding': track_height_padding}
coordinates_json = json.dumps(output_json)
with open(f"coordinates/{filename}.coordinates", 'w+', encoding='utf-8') as output:
    output.write(coordinates_json)

for coordinate in output_json['coordinates']:
    print(coordinate)
