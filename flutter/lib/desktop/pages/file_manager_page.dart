import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_breadcrumb/flutter_breadcrumb.dart';
import 'package:flutter_hbb/mobile/pages/file_manager_page.dart';
import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';

import '../../common.dart';
import '../../models/model.dart';

class FileManagerPage extends StatefulWidget {
  FileManagerPage({Key? key, required this.id}) : super(key: key);
  final String id;

  @override
  State<StatefulWidget> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage>
    with AutomaticKeepAliveClientMixin {
  final _selectedItems = SelectedItems();
  final _breadCrumbLocalScroller = ScrollController();
  final _breadCrumbRemoteScroller = ScrollController();

  /// FFI with name file_transfer_id
  FFI get _ffi => ffi('ft_${widget.id}');

  FileModel get model => _ffi.fileModel;

  @override
  void initState() {
    super.initState();
    Get.put(FFI.newFFI()..connect(widget.id, isFileTransfer: true),
        tag: 'ft_${widget.id}');
    // _ffi.ffiModel.updateEventListener(widget.id);
    if (!Platform.isLinux) {
      Wakelock.enable();
    }
    print("init success with id ${widget.id}");
  }

  @override
  void dispose() {
    model.onClose();
    _ffi.close();
    SmartDialog.dismiss();
    if (!Platform.isLinux) {
      Wakelock.disable();
    }
    Get.delete<FFI>(tag: 'ft_${widget.id}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ChangeNotifierProvider.value(
        value: _ffi.fileModel,
        child: Consumer<FileModel>(builder: (_context, _model, _child) {
          return WillPopScope(
              onWillPop: () async {
                if (model.selectMode) {
                  model.toggleSelectMode();
                }
                return false;
              },
              child: Scaffold(
                backgroundColor: MyTheme.grayBg,
                body: Row(
                  children: [
                    Flexible(flex: 3, child: body(isLocal: true)),
                    Flexible(flex: 3, child: body(isLocal: false)),
                    Flexible(flex: 2, child: statusList())
                  ],
                ),
                bottomSheet: bottomSheet(),
              ));
        }));
  }

  bool needShowCheckBox() {
    if (!model.selectMode) {
      return false;
    }
    return !_selectedItems.isOtherPage(model.isLocal);
  }

  Widget menu({bool isLocal = false}) {
    return PopupMenuButton<String>(
        icon: Icon(Icons.more_vert),
        itemBuilder: (context) {
          return [
            PopupMenuItem(
              child: Row(
                children: [
                  Icon(Icons.refresh, color: Colors.black),
                  SizedBox(width: 5),
                  Text(translate("Refresh File"))
                ],
              ),
              value: "refresh",
            ),
            PopupMenuItem(
              child: Row(
                children: [
                  Icon(Icons.check, color: Colors.black),
                  SizedBox(width: 5),
                  Text(translate("Multi Select"))
                ],
              ),
              value: "select",
            ),
            PopupMenuItem(
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      color: Colors.black),
                  SizedBox(width: 5),
                  Text(translate("Create Folder"))
                ],
              ),
              value: "folder",
            ),
            PopupMenuItem(
              child: Row(
                children: [
                  Icon(
                      model.currentShowHidden
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      color: Colors.black),
                  SizedBox(width: 5),
                  Text(translate("Show Hidden Files"))
                ],
              ),
              value: "hidden",
            )
          ];
        },
        onSelected: (v) {
          if (v == "refresh") {
            model.refresh();
          } else if (v == "select") {
            _selectedItems.clear();
            model.toggleSelectMode();
          } else if (v == "folder") {
            final name = TextEditingController();
            DialogManager.show((setState, close) =>
                CustomAlertDialog(
                    title: Text(translate("Create Folder")),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextFormField(
                          decoration: InputDecoration(
                            labelText: translate(
                                "Please enter the folder name"),
                          ),
                          controller: name,
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                          style: flatButtonStyle,
                          onPressed: () => close(false),
                          child: Text(translate("Cancel"))),
                      ElevatedButton(
                          style: flatButtonStyle,
                          onPressed: () {
                            if (name.value.text.isNotEmpty) {
                              model.createDir(PathUtil.join(
                                  model.currentDir.path,
                                  name.value.text,
                                  model.currentIsWindows));
                              close();
                            }
                          },
                          child: Text(translate("OK")))
                    ]));
          } else if (v == "hidden") {
            model.toggleShowHidden(local: isLocal);
          }
        });
  }

  Widget body({bool isLocal = false}) {
    final fd = isLocal ? model.currentLocalDir : model.currentRemoteDir;
    final entries = fd.entries;
    return Column(children: [
      headTools(isLocal),
      Expanded(
          child: ListView.builder(
        itemCount: entries.length + 1,
        itemBuilder: (context, index) {
          if (index >= entries.length) {
            return listTail(isLocal: isLocal);
          }
          var selected = false;
          if (model.selectMode) {
            selected = _selectedItems.contains(entries[index]);
          }

          final sizeStr = entries[index].isFile
              ? readableFileSize(entries[index].size.toDouble())
              : "";
          return Card(
            child: ListTile(
              leading: Icon(
                  entries[index].isFile ? Icons.feed_outlined : Icons.folder,
                  size: 40),
              title: Text(entries[index].name),
              selected: selected,
              subtitle: Text(
                entries[index]
                        .lastModified()
                        .toString()
                        .replaceAll(".000", "") +
                    "   " +
                    sizeStr,
                style: TextStyle(fontSize: 12, color: MyTheme.darkGray),
              ),
              trailing: needShowCheckBox()
                  ? Checkbox(
                      value: selected,
                      onChanged: (v) {
                        if (v == null) return;
                        if (v && !selected) {
                          _selectedItems.add(isLocal, entries[index]);
                        } else if (!v && selected) {
                          _selectedItems.remove(entries[index]);
                        }
                        setState(() {});
                      })
                  : PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert),
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem(
                            child: Text(translate("Delete")),
                            value: "delete",
                          ),
                          PopupMenuItem(
                            child: Text(translate("Multi Select")),
                            value: "multi_select",
                          ),
                          PopupMenuItem(
                            child: Text(translate("Properties")),
                            value: "properties",
                            enabled: false,
                          )
                        ];
                      },
                      onSelected: (v) {
                        if (v == "delete") {
                          final items = SelectedItems();
                          items.add(isLocal, entries[index]);
                          model.removeAction(items);
                        } else if (v == "multi_select") {
                          _selectedItems.clear();
                          model.toggleSelectMode();
                        }
                      }),
              onTap: () {
                if (model.selectMode && !_selectedItems.isOtherPage(isLocal)) {
                  if (selected) {
                    _selectedItems.remove(entries[index]);
                  } else {
                    _selectedItems.add(isLocal, entries[index]);
                  }
                  setState(() {});
                  return;
                }
                if (entries[index].isDirectory) {
                  model.openDirectory(entries[index].path, isLocal: isLocal);
                  breadCrumbScrollToEnd(isLocal);
                } else {
                  // Perform file-related tasks.
                }
              },
              onLongPress: () {
                _selectedItems.clear();
                model.toggleSelectMode();
                if (model.selectMode) {
                  _selectedItems.add(isLocal, entries[index]);
                }
                setState(() {});
              },
            ),
          );
        },
      ))
    ]);
  }

  /// transfer status list
  /// watch transfer status
  Widget statusList() {
    return PreferredSize(child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white70)
      ),
    ), preferredSize: Size(200, double.infinity));
  }

  goBack({bool? isLocal}) {
    model.goToParentDirectory(isLocal: isLocal);
  }

  breadCrumbScrollToEnd(bool isLocal) {
    final controller = isLocal ? _breadCrumbLocalScroller : _breadCrumbRemoteScroller;
    Future.delayed(Duration(milliseconds: 200), () {
      controller.animateTo(
          controller.position.maxScrollExtent,
          duration: Duration(milliseconds: 200),
          curve: Curves.fastLinearToSlowEaseIn);
    });
  }

  Widget headTools(bool isLocal) => Container(
          child: Row(
        children: [
          Expanded(
              child: BreadCrumb(
            items: getPathBreadCrumbItems(() => model.goHome(), (list) {
              var path = "";
              if (model.currentHome.startsWith(list[0])) {
                // absolute path
                for (var item in list) {
                  path = PathUtil.join(path, item, model.currentIsWindows);
                }
              } else {
                path += model.currentHome;
                for (var item in list) {
                  path = PathUtil.join(path, item, model.currentIsWindows);
                }
              }
              model.openDirectory(path, isLocal: isLocal);
            }, isLocal),
            divider: Icon(Icons.chevron_right),
            overflow: ScrollableOverflow(controller: isLocal ? _breadCrumbLocalScroller : _breadCrumbRemoteScroller),
          )),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_upward),
                onPressed: () {
                  goBack(isLocal: isLocal);
                },
              ),
              PopupMenuButton<SortBy>(
                  icon: Icon(Icons.sort),
                  itemBuilder: (context) {
                    return SortBy.values
                        .map((e) => PopupMenuItem(
                              child:
                                  Text(translate(e.toString().split(".").last)),
                              value: e,
                            ))
                        .toList();
                  },
                  onSelected: (sort) {
                    model.changeSortStyle(sort, isLocal: isLocal);
                  }),
              menu(isLocal: isLocal)
            ],
          )
        ],
      ));

  Widget listTail({bool isLocal = false}) {
    final dir = isLocal ? model.currentLocalDir : model.currentRemoteDir;
    return Container(
      height: 100,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(30, 5, 30, 0),
            child: Text(
              dir.path,
              style: TextStyle(color: MyTheme.darkGray),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(2),
            child: Text(
              "${translate("Total")}: ${dir.entries.length} ${translate("items")}",
              style: TextStyle(color: MyTheme.darkGray),
            ),
          )
        ],
      ),
    );
  }

  Widget? bottomSheet() {
    final state = model.jobState;
    final isOtherPage = _selectedItems.isOtherPage(model.isLocal);
    final selectedItemsLen = "${_selectedItems.length} ${translate("items")}";
    final local = _selectedItems.isLocal == null
        ? ""
        : " [${_selectedItems.isLocal! ? translate("Local") : translate("Remote")}]";

    if (model.selectMode) {
      if (_selectedItems.length == 0 || !isOtherPage) {
        return BottomSheetBody(
            leading: Icon(Icons.check),
            title: translate("Selected"),
            text: selectedItemsLen + local,
            onCanceled: () => model.toggleSelectMode(),
            actions: [
              IconButton(
                icon: Icon(Icons.compare_arrows),
                onPressed: model.togglePage,
              ),
              IconButton(
                icon: Icon(Icons.delete_forever),
                onPressed: () {
                  if (_selectedItems.length > 0) {
                    model.removeAction(_selectedItems);
                  }
                },
              )
            ]);
      } else {
        return BottomSheetBody(
            leading: Icon(Icons.input),
            title: translate("Paste here?"),
            text: selectedItemsLen + local,
            onCanceled: () => model.toggleSelectMode(),
            actions: [
              IconButton(
                icon: Icon(Icons.compare_arrows),
                onPressed: model.togglePage,
              ),
              IconButton(
                icon: Icon(Icons.paste),
                onPressed: () {
                  model.toggleSelectMode();
                  model.sendFiles(_selectedItems);
                },
              )
            ]);
      }
    }

    switch (state) {
      case JobState.inProgress:
        return BottomSheetBody(
          leading: CircularProgressIndicator(),
          title: translate("Waiting"),
          text:
              "${translate("Speed")}:  ${readableFileSize(model.jobProgress.speed)}/s",
          onCanceled: () => model.cancelJob(model.jobProgress.id),
        );
      case JobState.done:
        return BottomSheetBody(
          leading: Icon(Icons.check),
          title: "${translate("Successful")}!",
          text: "",
          onCanceled: () => model.jobReset(),
        );
      case JobState.error:
        return BottomSheetBody(
          leading: Icon(Icons.error),
          title: "${translate("Error")}!",
          text: "",
          onCanceled: () => model.jobReset(),
        );
      case JobState.none:
        break;
    }
    return null;
  }

  List<BreadCrumbItem> getPathBreadCrumbItems(
      void Function() onHome, void Function(List<String>) onPressed, bool isLocal) {
    final path = model.shortPath(isLocal);
    final list = PathUtil.split(path, model.currentIsWindows);
    final breadCrumbList = [
      BreadCrumbItem(
          content: IconButton(
        icon: Icon(Icons.home_filled),
        onPressed: onHome,
      ))
    ];
    breadCrumbList.addAll(list.asMap().entries.map((e) => BreadCrumbItem(
        content: TextButton(
            child: Text(e.value),
            style:
                ButtonStyle(minimumSize: MaterialStateProperty.all(Size(0, 0))),
            onPressed: () => onPressed(list.sublist(0, e.key + 1))))));
    return breadCrumbList;
  }

  @override
  bool get wantKeepAlive => true;
}

class BottomSheetBody extends StatelessWidget {
  BottomSheetBody(
      {required this.leading,
      required this.title,
      required this.text,
      this.onCanceled,
      this.actions});

  final Widget leading;
  final String title;
  final String text;
  final VoidCallback? onCanceled;
  final List<IconButton>? actions;

  @override
  BottomSheet build(BuildContext context) {
    final _actions = actions ?? [];
    return BottomSheet(
      builder: (BuildContext context) {
        return Container(
            height: 65,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
                color: MyTheme.accent50,
                borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      leading,
                      SizedBox(width: 16),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 18)),
                          Text(text,
                              style: TextStyle(
                                  fontSize: 14, color: MyTheme.grayBg))
                        ],
                      )
                    ],
                  ),
                  Row(children: () {
                    _actions.add(IconButton(
                      icon: Icon(Icons.cancel_outlined),
                      onPressed: onCanceled,
                    ));
                    return _actions;
                  }())
                ],
              ),
            ));
      },
      onClosing: () {},
      backgroundColor: MyTheme.grayBg,
      enableDrag: false,
    );
  }
}
