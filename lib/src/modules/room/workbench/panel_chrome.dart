import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'layout_tree.dart';

/// Branded chrome around a mounted workbench node.
class PanelChrome extends StatelessWidget {
  /// Creates panel chrome.
  const PanelChrome({super.key, required this.node, required this.child});

  /// Stable layout node represented by this panel.
  final LayoutNode node;

  /// Nested panel content.
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.all(SoliplexSpacing.s2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.radii.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
            builder: (context, constraints) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(SoliplexSpacing.s2),
                      child: Text(
                        node.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (constraints.hasBoundedHeight)
                      Expanded(child: SingleChildScrollView(child: child))
                    else
                      child,
                  ],
                )),
      );
}
