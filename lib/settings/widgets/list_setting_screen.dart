import 'package:clock_app/common/logic/customize_screen.dart';
import 'package:clock_app/common/types/list_controller.dart';
import 'package:clock_app/common/types/list_item.dart';
import 'package:clock_app/common/widgets/list/customize_list_item_screen.dart';
import 'package:clock_app/common/widgets/fab.dart';
import 'package:clock_app/common/widgets/list/custom_list_view.dart';
import 'package:clock_app/navigation/widgets/app_top_bar.dart';
import 'package:clock_app/settings/types/setting.dart';
import 'package:clock_app/settings/widgets/list_setting_add_bottom_sheet.dart';
import 'package:flutter/material.dart';

class CustomizableListSettingScreen<Item extends CustomizableListItem>
    extends StatefulWidget {
  const CustomizableListSettingScreen({
    super.key,
    required this.setting,
    required this.onChanged,
  });

  final CustomizableListSetting<Item> setting;
  final void Function(BuildContext context) onChanged;

  @override
  State<CustomizableListSettingScreen> createState() => _CustomizableListSettingScreenState<Item>();
}

class _CustomizableListSettingScreenState<Item extends CustomizableListItem>
    extends State<CustomizableListSettingScreen<Item>> {
  final _listController = ListController<Item>();

  Future<Item?> _openAddBottomSheet() async {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    return await showModalBottomSheet(
      context: context,
      builder: (context) => CustomizableListSettingAddBottomSheet(setting: widget.setting),
    );
  }

  _handleCustomizeItem(Item itemToCustomize) async {
    openCustomizeScreen<Item>(
      context,
      CustomizeListItemScreen<Item>(
        item: itemToCustomize,
        isNewItem: false,
        itemPreviewBuilder: (item) => widget.setting.getPreviewCard(item),
      ),
      onSave: (newItem) async {
        itemToCustomize.copyFrom(newItem);
        _listController.changeItems((items) {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: widget.setting.displayName(context)),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: CustomListView<Item>(
                  listController: _listController,
                  items: widget.setting.value,
                  itemBuilder: (item) =>
                      widget.setting.getItemCard(item, onDelete: () {
                    _listController.deleteItem(item);
                  }, onDuplicate: () {
                    _listController.duplicateItem(item);
                  }),
                  onTapItem: (task, index) {
                    _handleCustomizeItem(task);
                  },
                  onModifyList: () => widget.onChanged(context),
                  isReorderable: true,
                  isSelectable: true,
                  placeholderText:
                      "No ${widget.setting.displayName(context).toLowerCase()} added yet",
                ),
              ),
            ],
          ),
          FAB(
            bottomPadding: 8,
            onPressed: () async {
              Item? item = await _openAddBottomSheet();
              if (item == null) return;
              // Guard the post-await use of `context` (async gap).
              if (!mounted) return;
              final Item newItem = item.copy();
              // Items that are unusable until configured (a scan task needs a
              // registered code — D-REG-REQUIRED) must pass the SAME Save gate
              // as the edit path before being committed. Previously the add
              // path called addItem() directly, bypassing validate() entirely,
              // which let an unregistered scan task land in the list and become
              // un-dismissable at ring time (CR-01). validate() is a no-op
              // (returns null) for every other item type (themes, timers, math
              // tasks, etc.), so those keep the unchanged direct-add path.
              if (newItem.validate(context) != null) {
                openCustomizeScreen<Item>(
                  context,
                  CustomizeListItemScreen<Item>(
                    item: newItem,
                    isNewItem: true,
                    itemPreviewBuilder: (item) =>
                        widget.setting.getPreviewCard(item),
                  ),
                  // onSave only fires when CustomizeScreen actually pops with the
                  // item, which it does ONLY when validate() returns null. So an
                  // item that never satisfies its gate is never committed.
                  onSave: (savedItem) async {
                    newItem.copyFrom(savedItem);
                    _listController.addItem(newItem);
                  },
                );
              } else {
                _listController.addItem(newItem);
              }
            },
          )
        ],
      ),
    );
  }
}
