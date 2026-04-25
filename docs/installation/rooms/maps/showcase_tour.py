# Maps room — showcase tour of every map_* tool shipped to date.
#
# Usage: open the Monty terminal in the maps room, paste this file's
# entire contents, run. Auto-dedent strips any leading whitespace from
# the paste so indentation comes through clean.
#
# Demonstrates:
#   map_geocode            — name → coords
#   map_fit_bounds         — auto-frame N points
#   map_fly_to (arc)       — long-distance camera arcs
#   map_latlng_to_mgrs     — military grid in label
#   map_add_marker         — drop pins
#   map_move_marker        — animate a marker between cities
#   map_add_path           — animated route trace
#   map_reverse_geocode    — coords → address
#   map_set_basemap        — basemap selection

map_set_basemap("osm")
map_clear_markers()

# ---- 1. Geocode the itinerary ----------------------------------------
cities = ["Tokyo", "Sydney", "Cape Town", "Reykjavik"]
points = []
for name in cities:
    hit = map_geocode(name)
    if hit is None:
        print(f"  miss: {name}")
        continue
    points.append([hit["lat"], hit["lng"], name])
    map_sleep_ms(1100)  # respect Nominatim's ~1 req/s

# ---- 2. Frame the whole tour. Camera arcs out → pan → zoom in --------
map_fit_bounds([[p[0], p[1]] for p in points], padding_pct=15)
map_sleep_ms(1500)

# ---- 3. Drop a marker at each city with the MGRS grid in the label ---
for lat, lng, name in points:
    grid = map_latlng_to_mgrs(lat, lng, precision=2)  # 1km grid
    map_add_marker(
        lat, lng,
        label=f"{name}  •  {grid}",
        color="orange",
        icon="place",
        pulse=False,
    )

# ---- 4. Spawn a helicopter and fly it through every city -------------
heli = map_add_marker(
    points[0][0], points[0][1],
    label="🚁",
    color="red",
    icon="flight",
    pulse=True,
)
for lat, lng, name in points[1:]:
    map_fly_to(lat, lng, zoom=5, duration_ms=2500)   # arc fly
    map_move_marker(heli, lat, lng, duration_ms=2200)
    map_sleep_ms(2200)

# ---- 5. Trace the full route as an animated dashed line --------------
route = [[p[0], p[1]] for p in points]
map_add_path(route, color="orange", width=3,
             animated=True, duration_ms=3500)
map_sleep_ms(3500)

# ---- 6. Reverse-geocode the helicopter's final resting spot ----------
final = points[-1]
addr = map_reverse_geocode(final[0], final[1])
print(f"Helicopter landed at: {addr.get('display_name')}")

# ---- 7. Closing shot — frame the whole route once more ---------------
map_fit_bounds(route, padding_pct=20, duration_ms=2500)

print("Tour complete.")
