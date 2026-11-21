import 'package:flutter/material.dart';
import 'package:soliplex_catalogs/soliplex_catalogs.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../interfaces/workbench_presentation.dart';
import '../a2ui/surface_scope.dart';
import 'layout_tree.dart';
import 'panel_chrome.dart';
import 'surface_mount_registry.dart';
import 'walkthrough_player.dart';
import 'walkthrough_programs.dart';

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
  final _apps = ProgramApps();
  WalkthroughPlayer? _player;
  ChatSurfaceStore? _store;

  Future<void> _perform(Map<String, dynamic> step) async {
    if (_player?.active != true) return;
    final effect = step['effect'];
    if (effect == 'none') return;
    final nodes = step['nodes'] as Map;
    if (effect == 'fill') {
      final form = nodes['form'] as Map;
      final controller = _store?[form['activityMessageId'] as String];
      final surface = controller?.surfaces.single;
      if (surface == null) throw StateError('Tour form is not mounted');
      surface.dataModel.set('/values', {
        'name': 'Sample visitor',
        'color': ['Blue'],
        'subscribe': true,
      });
      return;
    }
    final program = nodes['program'] as Map;
    final controls = _apps.controls(program['surfaceId'] as String);
    if (controls == null) throw StateError('Tour program is not mounted');
    await WalkthroughPrograms.perform(controls, effect as String);
    if (_apps.view(program['surfaceId'] as String) == null) {
      throw StateError('Curated program did not open its app');
    }
  }

  @override
  void dispose() {
    if (_player?.perform == _perform) {
      _player?.send = null;
      _player?.perform = null;
    }
    _apps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ChatSurfaceScope.maybeOf(context)!;
    final scope = ChatSurfaceScope.scopeOf(context)!;
    _store = store;
    _apps.readFile = store.readProgramFile;
    _apps.writeFile = store.writeProgramFile;
    store.programSnapshot = _apps.snapshot;
    _player = WalkthroughScope.of(context);
    _player?.perform = _perform;
    _player?.send = (name, values) {
      final activity = store.layoutActivityId;
      final surface = store.layoutSurfaceId;
      if (activity == null || surface == null) return;
      store.onAction?.call(activity, {
        'name': 'workbench.walkthrough.$name',
        'surfaceId': surface,
        'sourceComponentId': 'root',
        'context': values,
      });
    };
    return ProgramAppScope(
        apps: _apps,
        child: ChatSurfaceScope(
            store: store,
            activeRunId: scope.activeRunId,
            hostsWorkbench: true,
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                final tree = store.layout;
                final tour = tree?.layout['shared'] is Map
                    ? (tree!.layout['shared'] as Map)['walkthrough']
                    : null;
                if (tour is Map<String, dynamic>) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _player?.observe(tour);
                  });
                }
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
            )));
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
      final player = WalkthroughScope.of(context);
      final tourTray = player != null &&
          hasContent('tray') &&
          (tree.layout['shared'] as Map)['walkthrough'] is Map;
      return DefaultTabController(
        key: ValueKey(WalkthroughScope.of(context)?.active == true),
        initialIndex: WalkthroughScope.of(context)?.active == true ? 1 : 0,
        length: 2,
        child: Column(
          children: [
            if (tourTray) WalkthroughControls(player: player),
            const TabBar(
              tabs: [Tab(text: 'Chat'), Tab(text: 'Workspace')],
            ),
            Expanded(
              flex: tourTray ? 3 : 1,
              child: TabBarView(children: [
                chatPane,
                SingleChildScrollView(
                  key: const ValueKey('workbench-workspace-scroll'),
                  padding: const EdgeInsets.all(SoliplexSpacing.s1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final role in [
                        'left',
                        'canvas',
                        'right',
                        if (!tourTray) 'tray'
                      ])
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
            if (tourTray) Expanded(flex: 2, child: region('tray')),
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

  // Semantic sizes weight split children and bound tabbed viewports.
  // Ordinary windows measure their content within the viewport cap.
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
    if (node.id == 'r_canvas') {
      final appOwners = (tree.layout['shared'] as Map)['programApps'];
      final paired = <String>{};
      final rows = <Widget>[];
      for (final child in children) {
        if (paired.contains(child.id)) continue;
        final programIds = <String>{};
        void collect(LayoutNode n) {
          if (n.kind == 'surface') {
            programIds.add(n.payload['surfaceId']! as String);
          }
          for (final id in n.children) {
            collect(tree.nodes[id]!);
          }
        }

        collect(child);
        final appNodes = appOwners is Map
            ? children
                .where((n) =>
                    n.visibility == 'open' &&
                    programIds.contains(appOwners[n.id]))
                .toList()
            : <LayoutNode>[];
        // An app can precede its owner after a server move.
        if (appOwners is Map && appOwners.containsKey(child.id)) continue;
        if (appNodes.isNotEmpty && child.visibility == 'open') {
          paired.addAll(appNodes.map((app) => app.id));
          Widget appViews(BuildContext context) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final app in appNodes) _render(context, app)],
              );
          rows.add(LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < SoliplexBreakpoints.tablet) {
              // Keep the live controls first when two readable columns do not fit.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [appViews(context), _render(context, child)],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _render(context, child)),
                Expanded(child: appViews(context)),
              ],
            );
          }));
        } else {
          rows.add(_render(context, child));
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    }

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
                for (final child in children) _render(context, child),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final child in children)
                Expanded(flex: _weight(child), child: _render(context, child)),
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
      final appOwner = (tree.layout['shared'] as Map)['programApps'];
      final owner = appOwner is Map ? appOwner[node.id] : null;
      final apps = ProgramAppScope.maybeOf(context);
      final content = owner is String && apps != null
          ? Padding(
              padding: const EdgeInsets.all(SoliplexSpacing.s3),
              child: ProgramAppView(program: owner, apps: apps),
            )
          : children.isEmpty || children.first.visibility != 'open'
              ? const Padding(
                  padding: EdgeInsets.all(SoliplexSpacing.s3),
                  child: Text('No open content.'),
                )
              : _render(context, children.first);
      final tour = (tree.layout['shared'] as Map)['walkthrough'];
      final player = WalkthroughScope.of(context);
      final isNarration =
          tour is Map && node.children.contains(tour['narrationNode']);
      final narratedContent = isNarration && player != null
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              WalkthroughControls(player: player),
              content,
            ])
          : content;
      final chrome = PanelChrome(
        key: ValueKey(node.id),
        node: node,
        child: narratedContent,
      );
      final sized = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height.clamp(
                SoliplexBreakpoints.mobile,
                SoliplexBreakpoints.desktop,
              ),
        ),
        child: chrome,
      );
      return node.kind == 'window'
          ? Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'Workbench window ${node.title}',
              child: sized,
            )
          : sized;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children.map((child) => _render(context, child)).toList(),
    );
  }
}
