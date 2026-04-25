# Helicopter flying from Mobile, AL to Pensacola, FL.
# Demonstrates map_add_image (PNG/GIF sprite at lat/lng) +
# map_move_image (animate sprite between positions) + map_add_path
# (animated route trace) + the satellite basemap.
#
# Open the Monty terminal in the maps room, paste this whole file,
# run. Auto-dedent strips the leading whitespace from the paste.

mobile = {'lat': 30.6954, 'lng': -88.0399, 'name': 'Mobile, AL'}
pensacola = {'lat': 30.4213, 'lng': -87.2169, 'name': 'Pensacola, FL'}

# Wikimedia Commons UH-60 silhouette — public domain, permissive CORS.
helo_url = (
    'https://upload.wikimedia.org/wikipedia/commons/thumb/'
    '4/4b/UH-60M_Black_Hawk.svg/120px-UH-60M_Black_Hawk.svg.png'
)

map_set_basemap('satellite')
map_clear_markers()

# Frame the route up front.
map_fit_bounds(
    [[mobile['lat'], mobile['lng']],
     [pensacola['lat'], pensacola['lng']]],
    padding_pct=25,
)
map_sleep_ms(2000)

# Endpoint pins.
map_add_marker(
    mobile['lat'], mobile['lng'],
    label=mobile['name'], color='green', icon='place',
)
map_add_marker(
    pensacola['lat'], pensacola['lng'],
    label=pensacola['name'], color='red', icon='place',
)

# Drop the helicopter sprite at Mobile.
helo = map_add_image(
    helo_url,
    mobile['lat'], mobile['lng'],
    width=80, height=80,
)
map_sleep_ms(800)

# Trace the flight path AS the helicopter flies it (same duration so
# they animate together).
map_add_path(
    [[mobile['lat'], mobile['lng']],
     [pensacola['lat'], pensacola['lng']]],
    color='orange', width=2,
    animated=True, duration_ms=6000,
)

# And move the helicopter across the gulf coast.
map_move_image(helo, pensacola['lat'], pensacola['lng'], duration_ms=6000)

print('Helicopter en route from Mobile to Pensacola.')
