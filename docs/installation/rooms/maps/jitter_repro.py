# Minimal jitter reproducer.
#
# Usage: open the Monty terminal in the maps room, paste this file's
# entire contents, run.
#
# What it does: geocodes 4 cities, then triggers a single arc fly_to
# (via map_fit_bounds) and stops. No markers, no helicopter, no path —
# just one camera transition you can inspect frame-by-frame.
#
# When you record this in Chrome DevTools / a screen capture, the
# jitter (if any) will be the only camera motion in the recording.
# Look for the visual jump at ~75% through the fly — the boundary
# where the pan phase ends and zoom-in begins.

map_set_basemap("osm")
map_clear_markers()

cities = ["Tokyo", "Sydney", "Cape Town", "Reykjavik"]
points = []
for name in cities:
    hit = map_geocode(name)
    if hit is None:
        print(f"  miss: {name}")
        continue
    points.append([hit["lat"], hit["lng"]])
    map_sleep_ms(1100)  # respect Nominatim's ~1 req/s

# One arc fly — frames all four cities at the smallest zoom that fits.
# Long-distance hops trigger the three-phase _arcCamera path.
map_fit_bounds(points, padding_pct=15)

print("Done. Watch the camera transition for jitter.")
