"""Features defined by soliplex"""

from __future__ import annotations

import typing

import pydantic


class EmptyFeatureModel(pydantic.BaseModel):
    """Empty feature model for testing"""


# ---------------------------------------------------------------------------
# UIDemoState — the AID DISTRIBUTION GenUI demo feature
#
# Drives a 60-90s scripted humanitarian-relief storyboard through AG-UI
# state events. Server emits StateSnapshotEvent + StateDeltaEvent (RFC
# 6902 patches under /ui/...); client projects map / HUD / narration
# from a single state stream — no Python externals, no LLM round-trip.
#
# Register in installation.yaml:
#
#   meta:
#     agui_features:
#       - name: "ui"
#         model_klass: "soliplex.agui.features.UIDemoState"
#         source: "server"
#
# views/agui.py:316-322 then auto-seeds agui_state["ui"] =
# UIDemoState().model_dump() at thread creation.
# ---------------------------------------------------------------------------


class ConvoyState(pydantic.BaseModel):
    """Position + heading of the supply convoy."""

    lat: float = 0.0
    lng: float = 0.0
    heading: float = 0.0  # degrees, 0=north, clockwise


class SiteSupplies(pydantic.BaseModel):
    """Supplies offloaded at a site."""

    water_l: int = 0
    food_kg: int = 0
    medkits: int = 0


class SiteState(pydantic.BaseModel):
    """A supply hub or displaced-persons camp."""

    id: str
    name: str
    lat: float
    lng: float
    status: typing.Literal["pending", "served"] = "pending"
    supplies: SiteSupplies = pydantic.Field(default_factory=SiteSupplies)


class MapState(pydantic.BaseModel):
    """Geographic state — convoy + sites."""

    convoy: ConvoyState = pydantic.Field(default_factory=ConvoyState)
    sites: list[SiteState] = pydantic.Field(default_factory=list)


class HUDState(pydantic.BaseModel):
    """Heads-up overlay: tonnage delivered, elapsed time, status."""

    tonnage_delivered: float = 0.0
    elapsed_minutes: int = 0
    status_banner: str = "Standing by"


class Narration(pydantic.BaseModel):
    """One line of narration from a humanitarian actor.

    The four canonical actor buckets the Flutter client recognises are
    ``coordinator | primary | secondary | field``. ``convoy`` is kept
    for backwards compatibility with the scripted seed; the client maps
    it to the ``primary`` bucket.
    """

    actor: typing.Literal[
        "coordinator", "primary", "secondary", "field", "convoy"
    ]
    text: str


class UIDemoState(pydantic.BaseModel):
    """Top-level AID DISTRIBUTION feature state.

    Mirrored to the client at `agentState['ui']` via AG-UI state
    events. The client's StateBus projects this into the map widget,
    HUD overlay, and narration log.
    """

    map: MapState = pydantic.Field(default_factory=MapState)
    hud: HUDState = pydantic.Field(default_factory=HUDState)
    narrations: list[Narration] = pydantic.Field(default_factory=list)
