# Helicopter tour — Gulf Coast: New Orleans → Slidell → Biloxi → Pensacola.
#
# Tight regional hops (50–340 km). Demonstrates leg-aware adaptive zoom
# (omit zoom on map_fly_with_image; framework picks per-leg) and the
# parallel sprite-and-path pattern (line traces under the helicopter
# as it flies, via asyncio.gather).
#
# Open the Monty terminal in the maps room, paste, run.

map_set_basemap("satellite")
map_clear_markers()

cities = [
    "New Orleans, LA",
    "Slidell, LA",
    "Biloxi, MS",
    "Pensacola, FL",
]

points = []
for name in cities:
    hit = map_geocode(name)
    if hit is None:
        print(f"  miss: {name}")
        continue
    points.append((name, hit["lat"], hit["lng"]))
    map_sleep_ms(1100)  # Nominatim ~1 req/sec

# Drop labeled pins at every stop up front.
for name, lat, lng in points:
    short = name.split(",")[0]
    map_add_marker(lat, lng, label=short, color="orange", icon="place")

# Spawn the helicopter at New Orleans. Open the camera on it so the
# user sees the starting position before the first leg begins.
heli = map_add_image(
    "assets/maps/helicopter.png",
    points[0][1], points[0][2],
    width=80, height=80,
)
map_fly_to(points[0][1], points[0][2], zoom=10, duration_ms=2500)
map_sleep_ms(800)

# Fly leg by leg. map_add_path returns immediately; its animation
# runs in the background. map_fly_with_image blocks until the
# camera+sprite arrive. Calling them in this order with matching
# duration_ms makes the line trace under the helicopter as it flies.
prev_lat, prev_lng = points[0][1], points[0][2]
for name, lat, lng in points[1:]:
    map_add_path(
        [[prev_lat, prev_lng], [lat, lng]],
        color="orange", width=4,
        animated=True, duration_ms=4500,
    )
    map_fly_with_image(heli, lat, lng, duration_ms=4500)
    map_sleep_ms(600)
    prev_lat, prev_lng = lat, lng

# Closing review shot — frame the whole route.
route = [[lat, lng] for _, lat, lng in points]
map_fit_bounds(route, padding_pct=20, duration_ms=2500)

print("Tour complete.")
