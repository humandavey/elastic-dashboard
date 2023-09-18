import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:elastic_dashboard/services/nt4.dart';
import 'package:elastic_dashboard/services/nt4_connection.dart';
import 'package:elastic_dashboard/widgets/draggable_containers/draggable_nt4_widget_container.dart';
import 'package:elastic_dashboard/widgets/draggable_containers/draggable_widget_container.dart';
import 'package:elastic_dashboard/widgets/network_tree/tree_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_fancy_tree_view/flutter_fancy_tree_view.dart';

class NetworkTableTree extends StatefulWidget {
  final Function(Offset globalPosition, DraggableNT4WidgetContainer widget)?
      onDragUpdate;
  final Function(DraggableNT4WidgetContainer widget)? onDragEnd;
  final DraggableNT4WidgetContainer? Function(WidgetContainer? widget)?
      widgetContainerBuilder;

  const NetworkTableTree(
      {super.key,
      this.onDragUpdate,
      this.onDragEnd,
      this.widgetContainerBuilder});

  @override
  State<NetworkTableTree> createState() => _NetworkTableTreeState();
}

class _NetworkTableTreeState extends State<NetworkTableTree> {
  final TreeRow root = TreeRow(topic: '/', rowName: '');
  late final TreeController<TreeRow> treeController;

  late final Function(
          Offset globalPosition, DraggableNT4WidgetContainer widget)?
      onDragUpdate = widget.onDragUpdate;
  late final Function(DraggableNT4WidgetContainer widget)? onDragEnd =
      widget.onDragEnd;
  late final DraggableNT4WidgetContainer? Function(WidgetContainer? widget)?
      widgetContainerBuilder = widget.widgetContainerBuilder;

  late final Function(NT4Topic topic) onNewTopicAnnounced;

  @override
  void initState() {
    super.initState();

    treeController = TreeController<TreeRow>(
        roots: root.children, childrenProvider: (node) => node.children);

    nt4Connection.nt4Client
        .addTopicAnnounceListener(onNewTopicAnnounced = (topic) {
      setState(() {
        treeController.rebuild();
      });
    });
  }

  @override
  void dispose() {
    nt4Connection.nt4Client.removeTopicAnnounceListener(onNewTopicAnnounced);

    super.dispose();
  }

  void createRows(NT4Topic nt4Topic) {
    String topic = nt4Topic.name;

    List<String> rows = topic.substring(1).split('/');
    TreeRow? current;
    String currentTopic = '';

    for (String row in rows) {
      currentTopic += '/$row';

      bool lastElement = currentTopic == topic;

      if (current != null) {
        if (current.hasRow(row)) {
          current = current.getRow(row);
        } else {
          current = current.createNewRow(
              topic: currentTopic,
              name: row,
              nt4Topic: (lastElement) ? nt4Topic : null);
        }
      } else {
        if (root.hasRow(row)) {
          current = root.getRow(row);
        } else {
          current = root.createNewRow(
              topic: currentTopic,
              name: row,
              nt4Topic: (lastElement) ? nt4Topic : null);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<NT4Topic> topics = [];

    for (NT4Topic topic in nt4Connection.nt4Client.announcedTopics.values) {
      if (topic.name == 'Time') {
        continue;
      }

      topics.add(topic);
    }

    for (NT4Topic topic in topics) {
      createRows(topic);
    }

    root.sort();

    return TreeView<TreeRow>(
      treeController: treeController,
      nodeBuilder: (BuildContext context, TreeEntry<TreeRow> entry) {
        return TreeTile(
          key: UniqueKey(),
          entry: entry,
          onDragUpdate: onDragUpdate,
          onDragEnd: onDragEnd,
          widgetContainerBuilder: widgetContainerBuilder,
          onTap: () {
            setState(() => treeController.toggleExpansion(entry.node));
          },
        );
      },
    );
  }
}

class TreeTile extends StatelessWidget {
  TreeTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.onDragUpdate,
    this.onDragEnd,
    this.widgetContainerBuilder,
  });

  final TreeEntry<TreeRow> entry;
  final VoidCallback onTap;
  final Function(Offset globalPosition, DraggableNT4WidgetContainer widget)?
      onDragUpdate;
  final Function(DraggableNT4WidgetContainer widget)? onDragEnd;
  final DraggableNT4WidgetContainer? Function(WidgetContainer? widget)?
      widgetContainerBuilder;

  DraggableNT4WidgetContainer? draggingWidget;

  @override
  Widget build(BuildContext context) {
    TextStyle trailingStyle =
        Theme.of(context).textTheme.bodySmall!.copyWith(color: Colors.grey);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: GestureDetector(
            supportedDevices: PointerDeviceKind.values
                .whereNot((element) => element == PointerDeviceKind.trackpad)
                .toSet(),
            onPanStart: (details) async {
              if (draggingWidget != null) {
                return;
              }

              draggingWidget = widgetContainerBuilder
                  ?.call(await entry.node.toWidgetContainer());
            },
            onPanUpdate: (details) {
              if (draggingWidget == null) {
                return;
              }

              draggingWidget!.cursorLocation = Offset(
                    draggingWidget!.displayRect.width,
                    draggingWidget!.displayRect.height,
                  ) /
                  2;

              onDragUpdate?.call(
                  details.globalPosition - draggingWidget!.cursorLocation,
                  draggingWidget!);
            },
            onPanEnd: (details) {
              if (draggingWidget == null) {
                return;
              }

              onDragEnd?.call(draggingWidget!);

              draggingWidget = null;
            },
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: entry.level * 16.0),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(right: 20.0),
                    leading: (entry.hasChildren)
                        ? FolderButton(
                            openedIcon: const Icon(Icons.arrow_drop_down),
                            closedIcon: const Icon(Icons.arrow_right),
                            iconSize: 24,
                            isOpen: entry.hasChildren ? entry.isExpanded : null,
                            onPressed: entry.hasChildren ? onTap : null,
                          )
                        : const SizedBox(width: 8.0),
                    title: Text(entry.node.rowName),
                    trailing: (entry.node.nt4Topic != null)
                        ? Text(entry.node.nt4Topic!.type, style: trailingStyle)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 0),
      ],
    );
  }
}
