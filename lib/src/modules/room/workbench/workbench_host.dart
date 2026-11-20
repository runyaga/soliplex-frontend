import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkbenchClient;

import '../../../interfaces/workbench_presentation.dart';
import '../a2ui/surface_scope.dart';
import 'layout_reducer.dart';
import 'layout_tree.dart';
import 'panel_chrome.dart';
import 'surface_mount_registry.dart';

/// Room presentation backed by the authenticated U05 snapshot client.
class ClientWorkbenchPresentation implements WorkbenchPresentation {
  /// Creates an opt-in host with a registered-surface renderer.
  const ClientWorkbenchPresentation();

  @override
  Widget buildHost({
    required String roomId,
    required String threadId,
    required Widget chat,
    required WorkbenchClient client,
    required Widget Function(String activityMessageId, String surfaceId)
        surfaceBuilder,
  }) =>
      KeyedSubtree(
        key: ValueKey('$roomId\u0000$threadId'),
        child: _SnapshotHost(
          client: client,
          roomId: roomId,
          threadId: threadId,
          chat: chat,
          surfaceBuilder: surfaceBuilder,
        ),
      );
}

class _SnapshotHost extends StatefulWidget {
  const _SnapshotHost({
    required this.client,
    required this.roomId,
    required this.threadId,
    required this.chat,
    required this.surfaceBuilder,
  });
  final WorkbenchClient client;
  final String roomId;
  final String threadId;
  final Widget chat;
  final Widget Function(String activityMessageId, String surfaceId)
      surfaceBuilder;
  @override
  State<_SnapshotHost> createState() => _SnapshotHostState();
}

class _SnapshotHostState extends State<_SnapshotHost> {
  final _reducer = LayoutReducer();
  final _mounts = SurfaceMountRegistry();
  late Future<void> _load;
  ChatSurfaceStore? _store;
  String? _activeRunId;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load = _hydrate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = ChatSurfaceScope.maybeOf(context);
    final activeRunId = ChatSurfaceScope.activeRunIdOf(context);
    final finished = _activeRunId != null && _activeRunId != activeRunId;
    _activeRunId = activeRunId;
    if (finished) _load = _hydrate();
  }

  @override
  void didUpdateWidget(_SnapshotHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // RoomScreen constructs a client on rebuild. Only a scope change needs a
    // fetch; run completion is observed through the thread's surface scope.
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.threadId != widget.threadId) {
      _load = _hydrate();
    }
  }

  Future<void> _hydrate() async {
    final request = ++_request;
    final snapshot = await widget.client.getSnapshot(
      roomId: widget.roomId,
      threadId: widget.threadId,
    );
    if (!mounted || request != _request) return;
    if (!_reducer.acceptSnapshot(snapshot)) return;
    // Recover publications made before tools forwarded AG-UI metadata too.
    // Existing controllers keep their local bindings and mounted identity.
    for (final part in snapshot.records) {
      final activity = part.content['activityMessageId'];
      final operations = part.content['a2ui_operations'];
      if (activity is String &&
          operations is List &&
          _store?[activity] == null) {
        _store?.obtain(
          activity,
          operations.map((m) => Map<String, Object?>.from(m as Map)).toList(),
        );
      }
    }
    _mounts.retain([
      for (final node in _reducer.current!.nodes.values)
        if (node.kind == 'surface')
          '${node.payload['activityMessageId']}\u0000${node.payload['surfaceId']}',
    ]);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _load,
        builder: (context, state) {
          final tree = _reducer.current;
          if (state.hasError && tree == null) {
            return Center(
              child: Text(
                'Workbench is unavailable',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }
          if (tree == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return WorkbenchHost(
            tree: tree,
            chat: widget.chat,
            surfaceBuilder: widget.surfaceBuilder,
            mounts: _mounts,
          );
        },
      );
}

/// Renders a validated nested layout without changing its accepted edges.
class WorkbenchHost extends StatelessWidget {
  /// Creates a host over an already validated tree.
  const WorkbenchHost({
    super.key,
    required this.tree,
    required this.chat,
    required this.surfaceBuilder,
    required this.mounts,
  });

  final LayoutTree tree;
  final Widget chat;
  final Widget Function(String activityMessageId, String surfaceId)
      surfaceBuilder;
  final SurfaceMountRegistry mounts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) =>
            _buildAtWidth(context, constraints.maxWidth),
      );

  Widget _buildAtWidth(BuildContext context, double width) {
    final scope = ChatSurfaceScope.scopeOf(context);
    final hostedIds = {
      for (final node in tree.nodes.values)
        if (node.kind == 'surface')
          node.payload['activityMessageId']! as String,
    };
    final chatPane = KeyedSubtree(
      key: const ValueKey('workbench-region-chat'),
      child: scope == null
          ? chat
          : ChatSurfaceScope(
              store: scope.store,
              activeRunId: scope.activeRunId,
              hostedActivityIds: hostedIds,
              hostsWorkbench: true,
              child: chat,
            ),
    );
    final regions = {
      for (final id in tree.root.children)
        if (tree.node(id) case final LayoutNode node)
          node.payload['role']: node,
    };
    bool hasContent(String role) =>
        regions[role]?.children.any(
              (id) => tree.node(id)?.visibility == 'open',
            ) ??
        false;
    Widget region(String role) => SingleChildScrollView(
          key: ValueKey('workbench-region-$role'),
          padding: const EdgeInsets.all(SoliplexSpacing.s1),
          child: regions[role] == null
              ? const SizedBox.shrink()
              : _render(context, regions[role]!),
        );
    if (width < SoliplexBreakpoints.desktop) {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [Tab(text: 'Chat'), Tab(text: 'Workspace')],
            ),
            Expanded(
              child: TabBarView(children: [
                chatPane,
                SingleChildScrollView(
                  key: const ValueKey('workbench-workspace-scroll'),
                  padding: const EdgeInsets.all(SoliplexSpacing.s1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final role in ['left', 'canvas', 'right', 'tray'])
                        if (regions[role] case final LayoutNode node)
                          _render(context, node),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasContent('left')) Expanded(flex: 2, child: region('left')),
              Expanded(flex: 3, child: chatPane),
              Expanded(flex: 5, child: region('canvas')),
              if (hasContent('right'))
                Expanded(flex: 2, child: region('right')),
            ],
          ),
        ),
        if (hasContent('tray')) Expanded(child: region('tray')),
      ],
    );
  }

  Widget _render(BuildContext context, LayoutNode node) {
    if (node.visibility != 'open') return const SizedBox.shrink();
    if (node.kind == 'region' && node.payload['role'] == 'chat') return chat;
    if (node.kind == 'surface') {
      final activity = node.payload['activityMessageId']! as String;
      final surface = node.payload['surfaceId']! as String;
      return KeyedSubtree(
        key: mounts.keyFor(activity, surface),
        child: surfaceBuilder(activity, surface),
      );
    }
    final children =
        node.children.map(tree.node).whereType<LayoutNode>().toList();
    if (node.kind == 'split' && children.isNotEmpty) {
      final horizontal = node.payload['axis'] == 'horizontal';
      return LayoutBuilder(
        builder: (context, constraints) {
          if (!horizontal || constraints.maxWidth < 240 * children.length) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children)
                  SizedBox(height: 240, child: _render(context, child)),
              ],
            );
          }
          return SizedBox(
            height: SoliplexBreakpoints.tablet / 2,
            child: Flex(
              direction: horizontal ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children)
                  Expanded(child: _render(context, child)),
              ],
            ),
          );
        },
      );
    }
    if (node.kind == 'tabs') {
      if (children.isEmpty) return const SizedBox.shrink();
      return DefaultTabController(
        length: children.length,
        child: SizedBox(
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                  tabs: [for (final child in children) Tab(text: child.title)]),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final child in children) _render(context, child)
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (node.kind == 'panel' || node.kind == 'window') {
      final content = children.isEmpty
          ? const SizedBox.shrink()
          : _render(context, children.first);
      final chrome = PanelChrome(
        key: ValueKey(node.id),
        node: node,
        child: SingleChildScrollView(child: content),
      );
      return node.kind == 'window'
          ? SizedBox(width: 640, height: 480, child: chrome)
          : SizedBox(height: 240, child: chrome);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children.map((child) => _render(context, child)).toList(),
    );
  }
}
