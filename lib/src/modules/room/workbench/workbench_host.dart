import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../interfaces/workbench_presentation.dart';
import '../a2ui/surface_scope.dart';
import 'layout_tree.dart';
import 'panel_chrome.dart';
import 'surface_mount_registry.dart';

/// Room presentation driven by accepted thread activity publications.
class ClientWorkbenchPresentation implements WorkbenchPresentation {
  const ClientWorkbenchPresentation();

  @override
  Widget buildHost({
    required String roomId,
    required String threadId,
    required Widget chat,
    required Widget Function(String activityMessageId, String surfaceId)
        surfaceBuilder,
  }) =>
      KeyedSubtree(
        key: ValueKey('$roomId\u0000$threadId'),
        child: _ActivityHost(chat: chat, surfaceBuilder: surfaceBuilder),
      );
}

class _ActivityHost extends StatefulWidget {
  const _ActivityHost({required this.chat, required this.surfaceBuilder});
  final Widget chat;
  final Widget Function(String activityMessageId, String surfaceId)
      surfaceBuilder;

  @override
  State<_ActivityHost> createState() => _ActivityHostState();
}

class _ActivityHostState extends State<_ActivityHost> {
  final _mounts = SurfaceMountRegistry();

  @override
  Widget build(BuildContext context) {
    final store = ChatSurfaceScope.maybeOf(context)!;
    final scope = ChatSurfaceScope.scopeOf(context)!;
    return ChatSurfaceScope(
        store: store,
        activeRunId: scope.activeRunId,
        hostsWorkbench: true,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final tree = store.layout;
            if (tree == null) {
              return Column(children: [
                if (store.layoutError case final error?) Text(error),
                Expanded(child: widget.chat),
              ]);
            }
            _mounts.retain([
              for (final node in tree.nodes.values)
                if (node.kind == 'surface')
                  '${node.payload['activityMessageId']}\u0000${node.payload['surfaceId']}',
            ]);
            return Column(children: [
              if (store.layoutError case final error?) Text(error),
              Expanded(
                  child: WorkbenchHost(
                tree: tree,
                chat: widget.chat,
                surfaceBuilder: widget.surfaceBuilder,
                mounts: _mounts,
              )),
            ]);
          },
        ));
  }
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
    final chatPane = Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Workbench region chat',
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
    Widget region(String role) => Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Workbench region $role',
          child: !hasContent(role)
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  key: ValueKey('workbench-region-$role'),
                  padding: const EdgeInsets.all(SoliplexSpacing.s1),
                  child: regions[role] == null
                      ? const SizedBox.shrink()
                      : _render(context, regions[role]!),
                ),
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
                          Semantics(
                            container: true,
                            explicitChildNodes: true,
                            label: 'Workbench region $role',
                            child: _render(context, node),
                          ),
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
              if (hasContent('left'))
                Expanded(flex: 2, child: region('left'))
              else
                region('left'),
              Expanded(flex: 3, child: chatPane),
              Expanded(flex: 5, child: region('canvas')),
              if (hasContent('right'))
                Expanded(flex: 2, child: region('right'))
              else
                region('right'),
            ],
          ),
        ),
        if (hasContent('tray'))
          Expanded(child: region('tray'))
        else
          region('tray'),
      ],
    );
  }

  // Semantic sizes use the review's 1/2/3 weights. Small windows retain a
  // readable mobile-sized viewport; taller content scrolls inside the chrome.
  int _weight(LayoutNode node) => switch (node.size) {
        'small' => 1,
        'large' => 3,
        _ => 2,
      };

  double _height(LayoutNode node) =>
      SoliplexBreakpoints.mobile * (_weight(node) + 1) / 2;

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
          final stacked = !horizontal ||
              constraints.maxWidth <
                  SoliplexBreakpoints.tablet / 2 * children.length;
          if (stacked && constraints.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children)
                  Expanded(
                      flex: _weight(child), child: _render(context, child)),
              ],
            );
          }
          if (!horizontal ||
              constraints.maxWidth <
                  SoliplexBreakpoints.tablet / 2 * children.length) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children)
                  SizedBox(
                      height: _height(child), child: _render(context, child)),
              ],
            );
          }
          return SizedBox(
            height: children.map(_height).reduce((a, b) => a > b ? a : b),
            child: Flex(
              direction: horizontal ? Axis.horizontal : Axis.vertical,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final child in children)
                  Expanded(
                      flex: _weight(child), child: _render(context, child)),
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
          height: _height(node),
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
      final content = children.isEmpty || children.first.visibility != 'open'
          ? const Padding(
              padding: EdgeInsets.all(SoliplexSpacing.s3),
              child: Text('No open content.'),
            )
          : _render(context, children.first);
      final chrome = PanelChrome(
        key: ValueKey(node.id),
        node: node,
        child: content,
      );
      return node.kind == 'window'
          ? Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Workbench window ${node.title}',
              child: SizedBox(height: _height(node), child: chrome),
            )
          : SizedBox(height: _height(node), child: chrome);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children.map((child) => _render(context, child)).toList(),
    );
  }
}
