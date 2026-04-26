"""AID DISTRIBUTION — humanitarian-relief GenUI demo agent.

A scripted, no-LLM factory agent. Emits a `StateSnapshotEvent`
seeding the four supply sites + the convoy at a hub, then yields a
short closing text. P1 minimum — the full ~75s timeline lands in P2.

Wiring:

  installation/rooms/aid_distribution/room_config.yaml
    agent:
      kind: "factory"
      factory_name: "soliplex.aid_distribution.aid_distribution_agent_factory"
      with_agent_config: true
    agui_feature_names:
      - "ui"

The state shape is `soliplex.agui.features.UIDemoState`. The Flutter
client subscribes to AG-UI `state_delta` / `state_snapshot` events
under `/ui/...` and projects them into map / HUD / narration
surfaces.

All scenario content is humanitarian / civilian — sites are
displaced-persons camps and supply hubs in a fictional region.
"""

from __future__ import annotations

import asyncio
import contextlib
import dataclasses
import typing
from collections import abc

import pydantic_ai
from ag_ui import core as agui_core
from pydantic_ai import messages as ai_messages
from pydantic_ai import output as ai_output
from pydantic_ai import run as ai_run
from pydantic_ai import tools as ai_tools

from soliplex import agents
from soliplex.agui import features as agui_features
from soliplex.config import agents as config_agents
from soliplex.config import tools as config_tools

MessageHistory = list[ai_messages.ModelMessage]
NativeEvent = ai_messages.AgentStreamEvent | ai_run.AgentRunResultEvent


# ---------------------------------------------------------------------------
# SCENARIO — tiny humanitarian-relief world
# ---------------------------------------------------------------------------
#
# Turkana basin, northern Kenya. Hub at Lodwar, four camps within
# ~50km in Turkana County. Convoy starts at the hub. P1 just emits
# the opening pose; P2 will animate convoy → site → offload → next
# site. Real humanitarian-relief geography, civilian framing only.

HUB_LAT = 3.12
HUB_LNG = 35.60


def _initial_state() -> agui_features.UIDemoState:
    return agui_features.UIDemoState(
        map=agui_features.MapState(
            convoy=agui_features.ConvoyState(
                lat=HUB_LAT,
                lng=HUB_LNG,
                heading=0.0,
            ),
            sites=[
                agui_features.SiteState(
                    id="hub",
                    name="Logistics Hub",
                    lat=HUB_LAT,
                    lng=HUB_LNG,
                    status="served",
                ),
                agui_features.SiteState(
                    id="camp-alpha",
                    name="Camp Alpha",
                    lat=HUB_LAT + 0.35,
                    lng=HUB_LNG + 0.20,
                ),
                agui_features.SiteState(
                    id="camp-bravo",
                    name="Camp Bravo",
                    lat=HUB_LAT - 0.30,
                    lng=HUB_LNG + 0.40,
                ),
                agui_features.SiteState(
                    id="camp-charlie",
                    name="Camp Charlie",
                    lat=HUB_LAT - 0.15,
                    lng=HUB_LNG - 0.45,
                ),
                agui_features.SiteState(
                    id="camp-delta",
                    name="Camp Delta",
                    lat=HUB_LAT + 0.40,
                    lng=HUB_LNG - 0.15,
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
                text="All four camps reachable. Starting with Camp Alpha.",
            ),
        ],
    )


# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------


@dataclasses.dataclass
class AidDistributionAgent:
    """Scripted factory agent for the AID DISTRIBUTION GenUI demo.

    Mirrors `soliplex.examples.FauxAgent`'s shape so it plugs into the
    same `pydantic_ai.ui.ag_ui.AGUIAdapter` pipeline. Each tool-result
    we yield carries AG-UI events in its metadata; the adapter
    translates them into SSE frames.
    """

    agent_config: config_agents.FactoryAgentConfig
    tool_configs: config_tools.ToolConfigMap = None
    mcp_client_toolset_configs: config_tools.MCP_ClientToolsetConfigMap = None
    skill_toolset_config: agents.SkillToolsetConfig | None = None

    output_type = None

    async def run(
        self,
        prompt: str,
        message_history: MessageHistory | None = None,
        deps: ai_tools.AgentDepsT = None,
    ):
        return _AidDistributionRun(prompt, self)

    @contextlib.asynccontextmanager
    async def run_stream(
        self,
        prompt,
        message_history: MessageHistory | None = None,
        deps: ai_tools.AgentDepsT = None,
    ):
        yield _AidDistributionRun(prompt, self)

    async def run_stream_events(
        self,
        output_type: ai_output.OutputSpec[typing.Any] | None = None,
        message_history: MessageHistory | None = None,
        deferred_tool_results: pydantic_ai.DeferredToolResults | None = None,
        deps: ai_tools.AgentDepsT = None,
        **kwargs,
    ) -> abc.AsyncIterator[NativeEvent]:
        # P1: emit a single StateSnapshotEvent then close.
        # P2 will replace this body with the full timeline.
        del output_type, message_history, deferred_tool_results, kwargs

        snapshot = _initial_state()
        if deps is not None and getattr(deps, "state", None) is not None:
            deps.state["ui"] = snapshot.model_dump(mode="python")

        # Synthesize a tool-call-result so we can attach AG-UI events
        # via metadata — same trick FauxAgent uses for its tools.
        tc_part = ai_messages.ToolCallPart(
            "aid_distribution_init",
            args="{}",
        )
        yield ai_messages.PartStartEvent(index=0, part=tc_part)
        yield ai_messages.PartEndEvent(index=0, part=tc_part)

        yield ai_messages.FunctionToolResultEvent(
            result=ai_messages.ToolReturnPart(
                tool_name="aid_distribution_init",
                tool_call_id=tc_part.tool_call_id,
                content="initial state seeded",
                metadata=[
                    agui_core.StateSnapshotEvent(
                        snapshot={
                            "ui": snapshot.model_dump(mode="json"),
                        },
                    ),
                ],
            ),
        )

        # Tiny pause so the snapshot lands before the closing text.
        await asyncio.sleep(0.2)

        text_part = ai_messages.TextPart(
            "Mission ready: 4 camps awaiting supplies. "
            "Convoy 1 standing by at the Logistics Hub. "
            "(P2 will animate the full distribution timeline.)",
        )
        yield ai_messages.PartStartEvent(index=1, part=text_part)
        yield ai_messages.PartEndEvent(index=1, part=text_part)

        yield ai_run.AgentRunResultEvent(result=text_part.content)


@dataclasses.dataclass
class _AidDistributionRun:
    """Parallel to `FauxAgentRun` — present so the run/run_stream methods
    on `AidDistributionAgent` have something to return. The real work
    happens in `run_stream_events`."""

    prompt: str
    agent: AidDistributionAgent


# ---------------------------------------------------------------------------
# Factory entry point — referenced from room_config.yaml
# ---------------------------------------------------------------------------


def aid_distribution_agent_factory(
    agent_config: config_agents.FactoryAgentConfig,
    tool_configs: config_tools.ToolConfigMap = None,
    mcp_client_toolset_configs: config_tools.MCP_ClientToolsetConfigMap = None,
    skill_toolset_config: agents.SkillToolsetConfig | None = None,
) -> AidDistributionAgent:
    """Build the scripted AID DISTRIBUTION agent for a room."""
    return AidDistributionAgent(
        agent_config=agent_config,
        tool_configs=tool_configs,
        mcp_client_toolset_configs=mcp_client_toolset_configs,
        skill_toolset_config=skill_toolset_config,
    )
