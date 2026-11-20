import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkbenchClient;

import '../../../interfaces/workbench_presentation.dart';
import 'layout_reducer.dart';
import 'layout_tree.dart';
import 'panel_chrome.dart';
import 'surface_mount_registry.dart';

/// Room presentation backed by the authenticated U05 snapshot client.
class ClientWorkbenchPresentation implements WorkbenchPresentation {
  /// Creates an opt-in host with a registered-surface renderer.
  ClientWorkbenchPresentation({
    required this.client,
    required this.surfaceBuilder,
  });

  /// Authenticated snapshot and action client for this server session.
  final WorkbenchClient client;

  /// Renders the already registered content surface identity.
  final Widget Function(String activityMessageId, String surfaceId)
      surfaceBuilder;

  @override
  Widget buildHost({
    required String roomId,
    required String threadId,
    required Widget chat,
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

  @override
  void initState() {
    super.initState();
    _load = _hydrate();
  }

  @override
  void didUpdateWidget(_SnapshotHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.roomId != widget.roomId ||
        oldWidget.threadId != widget.threadId) {
      _load = _hydrate();
    }
  }

  Future<void> _hydrate() async {
    final snapshot = await widget.client.getSnapshot(
      roomId: widget.roomId,
      threadId: widget.threadId,
    );
    _reducer.acceptSnapshot(snapshot);
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
    final root = tree.root;
    final chatNode = tree.node('r_chat');
    final contentNodes = root.children
        .map(tree.node)
        .whereType<LayoutNode>()
        .where((node) => node.id != chatNode?.id)
        .toList();
    final workspace = SingleChildScrollView(
      key: const ValueKey('workbench-workspace-scroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: contentNodes.map((node) => _render(context, node)).toList(),
      ),
    );
    if (width < SoliplexBreakpoints.desktop) {
      return DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Chat'),
                Tab(text: 'Workspace'),
              ],
            ),
            Expanded(child: TabBarView(children: [chat, workspace])),
          ],
        ),
      );
    }
    return Row(
      children: [
        SizedBox(width: 320, child: chat),
        Expanded(child: workspace),
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
          return Flex(
            direction: horizontal ? Axis.horizontal : Axis.vertical,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children)
                Expanded(child: _render(context, child)),
            ],
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
      final chrome = PanelChrome(node: node, child: content);
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
