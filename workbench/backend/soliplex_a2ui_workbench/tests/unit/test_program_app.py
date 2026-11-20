"""App windows share the authenticated program transaction and retained IDs."""

import asyncio
import copy
import json
import os
from pathlib import Path

from ag_ui.core import ActivitySnapshotEvent
import pytest

from test_open_demo import publication
from soliplex_a2ui_workbench.program_actions import apply_program_actions
from soliplex_a2ui_workbench import workbench_tools as tools

FIXTURE = Path(__file__).parents[5] / 'packages/soliplex_monty/example/test/fixtures/program_app.json'


def test_app_transactions_reuse_reopen_close_and_freeze_real_wire_fixture():
    context, result = asyncio.run(publication())
    working = context.deps._workbench_context
    projection = working.repository
    record = working.snapshot()['content'][0]
    initial = [e.model_dump(mode='json', by_alias=True) for e in result.metadata]
    for event in initial:
        for op in event['content']['a2ui_operations']:
            if 'updateDataModel' in op and 'source' in op['updateDataModel'].get('value', {}):
                op['updateDataModel']['value']['source'] = '__SOURCE__'

    def apply(actions):
        events = apply_program_actions(projection, working.scope, 'gesture', record, actions)
        for event in events:
            projection._fold(ActivitySnapshotEvent.model_validate(event))
        return events

    opened = apply([{'op': 'show_app'}])
    app_id, owner = next(iter(projection.layout['shared']['programApps'].items()))
    assert owner == record['surfaceId']
    app = next(n for n in projection.layout['nodes'] if n['id'] == app_id)
    assert app['title'] == 'Monty GUI demo app'
    assert app['children'] == []
    canvas = next(n for n in projection.layout['nodes'] if n['id'] == 'r_canvas')
    assert canvas['children'][1] == app_id
    count = len(projection.layout['nodes'])
    apply([{'op': 'show_app'}])
    assert len(projection.layout['nodes']) == count
    closed = apply([{'op': 'close', 'window_id': app_id}])
    assert projection.content[record['activityMessageId']]['source']
    reopened = apply([{'op': 'show_app'}])
    assert len(projection.layout['nodes']) == count
    assert next(n for n in projection.layout['nodes'] if n['id'] == app_id)['visibility'] == 'open'
    program_window = canvas['children'][0]
    leaf = next(n for n in projection.layout['nodes'] if n['kind'] == 'surface')
    working.expected_revision = projection.layout['layoutRevision']
    cascade = tools.close_panel(working, leaf['id'])
    final = projection.layout
    assert next(n for n in final['nodes'] if n['id'] == app_id)['visibility'] == 'closed'
    assert next(n for n in final['nodes'] if n['id'] == program_window)['visibility'] == 'closed'
    fixture = {'initial': initial, 'open': opened, 'closed': closed, 'reopened': reopened,
               'cascade': [e['event'] for e in cascade['events']]}
    if os.environ.get('WB_REGENERATE_APP_FIXTURE') == '1':
        FIXTURE.parent.mkdir(parents=True, exist_ok=True)
        FIXTURE.write_text(json.dumps(fixture, indent=2) + '\n')
    assert json.loads(FIXTURE.read_text()) == fixture


def test_app_counts_in_action_limit_and_rejects_unowned_requests():
    context, _ = asyncio.run(publication())
    working = context.deps._workbench_context
    projection = working.repository
    record = working.snapshot()['content'][0]
    before = copy.deepcopy(projection.layout)
    for actions in [[{'op': 'show_app'}] * 9,
                    [{'op': 'show_app', 'window_id': 'arbitrary'}],
                    [{'op': 'show_app'}, {'op': 'close', 'window_id': 'unowned'}]]:
        with pytest.raises(ValueError):
            apply_program_actions(projection, working.scope, 'reject', record, actions)
        assert projection.layout == before
    assert len(apply_program_actions(projection, working.scope, 'limit', record,
                                    [{'op': 'show_app'}] * 8)) == 1


def test_demo_counts_app_and_log_in_three_total_window_limit():
    context, _ = asyncio.run(publication())
    working = context.deps._workbench_context
    projection = working.repository
    record = working.snapshot()['content'][0]
    actions = [{'op': 'show_app'}, {'op': 'open', 'window_id': 'log',
               'title': 'Monty event log', 'kind': 'text', 'content': 'last event: run, count 0'},
               {'op': 'move', 'window_id': 'log', 'order': 1}]
    for event in apply_program_actions(projection, working.scope, 'run', record, actions):
        projection._fold(ActivitySnapshotEvent.model_validate(event))
    assert sum(n['kind'] == 'window' and n['visibility'] == 'open' for n in projection.layout['nodes']) == 3
    with pytest.raises(ValueError, match='capacity'):
        apply_program_actions(projection, working.scope, 'full', record,
                              [{**actions[1], 'window_id': 'fourth'}])
    repeated_run = [
        {'op': 'show_app'}, {'op': 'close', 'window_id': 'log'},
        {**actions[1], 'window_id': 'log_again'},
        {'op': 'move', 'window_id': 'log_again', 'order': 1},
    ]
    for event in apply_program_actions(projection, working.scope, 'rerun', record, repeated_run):
        projection._fold(ActivitySnapshotEvent.model_validate(event))
    assert sum(n['kind'] == 'window' and n['visibility'] == 'open' for n in projection.layout['nodes']) == 3
    assert len(projection.layout['shared']['programApps']) == 1


@pytest.mark.parametrize('binding', ['unknown_program', {}, ['not_a_program']])
def test_app_binding_requires_an_authenticated_program(binding):
    from soliplex_a2ui_workbench.workbench_schemas import LayoutSnapshot

    context, _ = asyncio.run(publication())
    working = context.deps._workbench_context
    record = working.snapshot()['content'][0]
    events = apply_program_actions(working.repository, working.scope, 'show', record,
                                   [{'op': 'show_app'}])
    for event in events:
        working.repository._fold(ActivitySnapshotEvent.model_validate(event))
    layout = copy.deepcopy(working.repository.layout)
    app_id = next(iter(layout['shared']['programApps']))
    layout['shared']['programApps'][app_id] = binding
    with pytest.raises(ValueError, match='program app binding'):
        LayoutSnapshot.model_validate(layout, context={
            'authenticated_program_surfaces': {record['surfaceId']},
        })
