"""AID DISTRIBUTION — LLM-callable tools that mutate `state.ui`.

The four tools here advance the humanitarian-relief scenario. Each
mirrors the canonical ``soliplex.tools.bump_ui`` pattern:

1. Read & validate the current ``state.ui`` slice as
   :class:`soliplex.agui.features.UIDemoState`.
2. Mutate a copy.
3. Diff before/after with ``jsonpatch`` and emit a
   :class:`ag_ui.core.StateDeltaEvent` via
   :class:`pydantic_ai.ToolReturn`'s ``metadata`` channel.
4. Persist the new state back into ``ctx.deps.state["ui"]``.

The Flutter client's ``StateBus`` projects ``agentState['ui']`` into
the map / HUD / narration surfaces; nothing else is required to make
the panels react.

Wire into a room via ``room_config.yaml``:

    tools:
      - tool_name: "soliplex.aid_distribution.tools.move_convoy"
      - tool_name: "soliplex.aid_distribution.tools.set_site_status"
      - tool_name: "soliplex.aid_distribution.tools.add_narration"
      - tool_name: "soliplex.aid_distribution.tools.set_hud"

All scenario content is humanitarian / civilian.
"""

from __future__ import annotations

import math
import typing

import jsonpatch
import pydantic_ai
from ag_ui import core as agui_core

from soliplex import agents
from soliplex.agui import features as agui_features


def _bearing(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Great-circle bearing in degrees (0=N, clockwise)."""
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dlng = math.radians(lng2 - lng1)
    y = math.sin(dlng) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(
        dlng
    )
    return (math.degrees(math.atan2(y, x)) + 360.0) % 360.0


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _load_state(
    agui_state: dict[str, typing.Any],
) -> agui_features.UIDemoState:
    """Return a validated :class:`UIDemoState` from `state.ui`.

    Falls back to a default-constructed model when the slice is unset
    (defensive — the room declares ``agui_feature_names: ["ui"]`` so
    the framework should already have seeded it).
    """
    raw = agui_state.get("ui")
    if raw is None:
        return agui_features.UIDemoState()
    return agui_features.UIDemoState.model_validate(raw)


def _ui_metadata(
    before: agui_features.UIDemoState,
    after: agui_features.UIDemoState,
) -> list[agui_core.Event]:
    """Build a one-element ``StateDeltaEvent`` list for the metadata channel.

    Uses RFC 6902 paths under ``/ui/...`` so the client's reactive
    projections re-fire on the right slice.
    """
    before_dump = {"ui": before.model_dump(mode="json")}
    after_dump = {"ui": after.model_dump(mode="json")}
    patch = jsonpatch.make_patch(before_dump, after_dump)

    if not patch.patch:
        return []
    return [agui_core.StateDeltaEvent(delta=patch.patch)]


def _persist(
    agui_state: dict[str, typing.Any],
    after: agui_features.UIDemoState,
) -> None:
    """Write the new state back into the room's AG-UI state dict."""
    agui_state["ui"] = after.model_dump(mode="python")


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


async def move_convoy(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
    lat: float,
    lng: float,
    heading: float = 0.0,
) -> pydantic_ai.ToolReturn:
    """Move the convoy sprite on the map.

    Args:
        lat: New latitude (decimal degrees).
        lng: New longitude (decimal degrees).
        heading: Compass bearing in degrees, ``0`` = north, clockwise.
            Defaults to ``0`` if you don't know.
    """
    agui_state = ctx.deps.state
    before = _load_state(agui_state)
    after = before.model_copy(deep=True)

    after.map.convoy = agui_features.ConvoyState(
        lat=lat,
        lng=lng,
        heading=heading,
    )

    metadata = _ui_metadata(before, after)
    _persist(agui_state, after)

    summary = f"convoy → ({lat:.4f}, {lng:.4f}) heading {heading:.0f}°"
    return pydantic_ai.ToolReturn(summary, metadata=metadata)


async def set_site_status(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
    site_id: str,
    status: typing.Literal["pending", "served"],
    water_l: int = 0,
    food_kg: int = 0,
    medkits: int = 0,
) -> pydantic_ai.ToolReturn:
    """Update the status / supplies for a known site.

    Args:
        site_id: One of the seeded site ids — ``hub``, ``camp-alpha``,
            ``camp-bravo``, ``camp-charlie``, ``camp-delta``.
        status: ``"pending"`` (orange marker) or ``"served"`` (green).
        water_l: Litres of water offloaded at this site.
        food_kg: Kilograms of food rations offloaded at this site.
        medkits: Number of medical kits offloaded at this site.
    """
    agui_state = ctx.deps.state
    before = _load_state(agui_state)
    after = before.model_copy(deep=True)

    matched = False
    for site in after.map.sites:
        if site.id == site_id:
            site.status = status
            site.supplies = agui_features.SiteSupplies(
                water_l=water_l,
                food_kg=food_kg,
                medkits=medkits,
            )
            matched = True
            break

    if not matched:
        known = ", ".join(s.id for s in before.map.sites)
        return pydantic_ai.ToolReturn(
            f"unknown site_id '{site_id}'. known: {known}",
            metadata=[],
        )

    metadata = _ui_metadata(before, after)
    _persist(agui_state, after)

    summary = (
        f"site '{site_id}' → {status} "
        f"(water_l={water_l}, food_kg={food_kg}, medkits={medkits})"
    )
    return pydantic_ai.ToolReturn(summary, metadata=metadata)


async def add_narration(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
    actor: typing.Literal["coordinator", "primary", "secondary", "field"],
    text: str,
) -> pydantic_ai.ToolReturn:
    """Append a single narration line to the chat-side narration log.

    Args:
        actor: One of the four canonical buckets:
            ``"coordinator"`` (HQ / dispatch),
            ``"primary"`` (lead convoy),
            ``"secondary"`` (support / wing),
            ``"field"`` (on-site reporter).
        text: One-sentence line of narration.
    """
    agui_state = ctx.deps.state
    before = _load_state(agui_state)
    after = before.model_copy(deep=True)

    after.narrations.append(agui_features.Narration(actor=actor, text=text))

    metadata = _ui_metadata(before, after)
    _persist(agui_state, after)

    return pydantic_ai.ToolReturn(
        f"narrated [{actor}]: {text}",
        metadata=metadata,
    )


async def start_mission(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
) -> pydantic_ai.ToolReturn:
    """Reset / seed the AID DISTRIBUTION scenario.

    Drops the convoy at the Logistics Hub and seeds five sites:
    the hub plus four pending displaced-persons camps (Alpha,
    Bravo, Charlie, Delta). Clears any prior narrations and
    HUD state. Call this once at the start of the conversation
    or whenever the user asks to "reset" or "begin again".
    """
    agui_state = ctx.deps.state
    before = _load_state(agui_state)

    # Turkana basin, northern Kenya — hub at Lodwar.
    hub_lat, hub_lng = 3.12, 35.60
    after = agui_features.UIDemoState(
        map=agui_features.MapState(
            convoy=agui_features.ConvoyState(
                lat=hub_lat,
                lng=hub_lng,
                heading=0.0,
            ),
            sites=[
                agui_features.SiteState(
                    id="hub",
                    name="Logistics Hub",
                    lat=hub_lat,
                    lng=hub_lng,
                    status="served",
                ),
                agui_features.SiteState(
                    id="camp-alpha",
                    name="Camp Alpha",
                    lat=hub_lat + 0.35,
                    lng=hub_lng + 0.20,
                ),
                agui_features.SiteState(
                    id="camp-bravo",
                    name="Camp Bravo",
                    lat=hub_lat - 0.30,
                    lng=hub_lng + 0.40,
                ),
                agui_features.SiteState(
                    id="camp-charlie",
                    name="Camp Charlie",
                    lat=hub_lat - 0.15,
                    lng=hub_lng - 0.45,
                ),
                agui_features.SiteState(
                    id="camp-delta",
                    name="Camp Delta",
                    lat=hub_lat + 0.40,
                    lng=hub_lng - 0.15,
                ),
            ],
        ),
        hud=agui_features.HUDState(
            tonnage_delivered=0.0,
            elapsed_minutes=0,
            status_banner="Convoy at hub — preparing departure",
        ),
        narrations=[
            agui_features.Narration(
                actor="coordinator",
                text="Convoy 1 standing by at the Logistics Hub.",
            ),
            agui_features.Narration(
                actor="field",
                text=("All four camps reachable. Starting with Camp Alpha."),
            ),
        ],
    )

    metadata = _ui_metadata(before, after)
    _persist(agui_state, after)

    return pydantic_ai.ToolReturn(
        "mission seeded: hub + 4 camps; convoy at hub.",
        metadata=metadata,
    )


async def set_hud(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
    banner: str | None = None,
    tonnage_delivered: float | None = None,
    elapsed_minutes: int | None = None,
) -> pydantic_ai.ToolReturn:
    """Update one or more HUD overlay fields.

    Pass ``None`` (or omit) for fields you don't want to change.

    Args:
        banner: New ``status_banner`` text (top-of-HUD headline).
        tonnage_delivered: Cumulative tonnage delivered so far.
        elapsed_minutes: Mission clock minutes — informational only;
            the client renders a smoothly-ticking clock independent of
            this field.
    """
    agui_state = ctx.deps.state
    before = _load_state(agui_state)
    after = before.model_copy(deep=True)

    if banner is not None:
        after.hud.status_banner = banner
    if tonnage_delivered is not None:
        after.hud.tonnage_delivered = tonnage_delivered
    if elapsed_minutes is not None:
        after.hud.elapsed_minutes = elapsed_minutes

    metadata = _ui_metadata(before, after)
    _persist(agui_state, after)

    summary = (
        f"hud banner='{after.hud.status_banner}' "
        f"tonnage={after.hud.tonnage_delivered} "
        f"elapsed_minutes={after.hud.elapsed_minutes}"
    )
    return pydantic_ai.ToolReturn(summary, metadata=metadata)


async def where_is_convoy(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
) -> dict[str, typing.Any]:
    """Return the site closest to the convoy's current position.

    Read-only convenience over ``agui_state`` so the LLM doesn't
    need to do lat/lng → site_id matching itself. Returns
    ``{site_id, name, lat, lng, heading}`` for the nearest known
    site (by squared lat/lng distance — fine over the demo's
    sub-degree spread).
    """
    state = _load_state(ctx.deps.state)
    convoy = state.map.convoy
    nearest = min(
        state.map.sites,
        key=lambda s: (s.lat - convoy.lat) ** 2 + (s.lng - convoy.lng) ** 2,
    )
    return {
        "site_id": nearest.id,
        "name": nearest.name,
        "lat": convoy.lat,
        "lng": convoy.lng,
        "heading": convoy.heading,
    }


async def move_convoy_to_site(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
    site_id: str,
) -> pydantic_ai.ToolReturn:
    """Move the convoy to a known site (id-based; no coords).

    Args:
        site_id: One of the seeded site ids — ``hub``,
            ``camp-alpha``, ``camp-bravo``, ``camp-charlie``,
            ``camp-delta``. Coordinates and heading are looked
            up from live state — the caller never passes
            lat/lng. Heading is the great-circle bearing from
            the convoy's current position to the target.
    """
    agui_state = ctx.deps.state
    before = _load_state(agui_state)
    target = next(
        (s for s in before.map.sites if s.id == site_id),
        None,
    )
    if target is None:
        known = ", ".join(s.id for s in before.map.sites)
        return pydantic_ai.ToolReturn(
            (f"unknown site_id '{site_id}'. valid ids: {known}"),
            metadata=[],
        )

    after = before.model_copy(deep=True)
    after.map.convoy = agui_features.ConvoyState(
        lat=target.lat,
        lng=target.lng,
        heading=_bearing(
            before.map.convoy.lat,
            before.map.convoy.lng,
            target.lat,
            target.lng,
        ),
    )

    metadata = _ui_metadata(before, after)
    _persist(agui_state, after)

    return pydantic_ai.ToolReturn(
        f"convoy → {site_id} ({target.name})",
        metadata=metadata,
    )


async def serve_site(
    ctx: pydantic_ai.RunContext[agents.AgentDependencies],
    site_id: str,
    water_l: int = 0,
    food_kg: int = 0,
    medkits: int = 0,
) -> pydantic_ai.ToolReturn:
    """Mark a known site as served and stamp supplies.

    Convenience wrapper over :func:`set_site_status` —
    callers don't pass coords or status.

    Args:
        site_id: One of the seeded site ids — ``hub``,
            ``camp-alpha``, ``camp-bravo``, ``camp-charlie``,
            ``camp-delta``.
        water_l: Litres of water offloaded at this site.
        food_kg: Kilograms of food rations offloaded at this
            site.
        medkits: Number of medical kits offloaded at this
            site.
    """
    return await set_site_status(
        ctx,
        site_id=site_id,
        status="served",
        water_l=water_l,
        food_kg=food_kg,
        medkits=medkits,
    )
