import 'package:PiliPlus/common/style.dart';
import 'package:PiliPlus/utils/filter_rule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class FilterRuleDialog extends StatefulWidget {
  const FilterRuleDialog({
    super.key,
    required this.title,
    required this.initValues,
  });

  final String title;
  final List<FilterRule> initValues;

  @override
  State<FilterRuleDialog> createState() => _FilterRuleDialogState();
}

class _FilterRuleDialogState extends State<FilterRuleDialog> {
  late List<FilterRule> _tempValues;

  @override
  void initState() {
    super.initState();
    _tempValues = List<FilterRule>.from(widget.initValues);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      clipBehavior: Clip.hardEdge,
      constraints: Style.dialogFixedConstraints,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 12, 8),
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          IconButton(
            onPressed: _addRule,
            icon: const Icon(Icons.add),
            tooltip: '新增',
          ),
        ],
      ),
      contentPadding: const EdgeInsets.only(top: 8),
      content: SizedBox(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: _tempValues.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '暂无规则, 点击右上角 + 新增.',
                      style: TextStyle(color: theme.colorScheme.outline),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _tempValues.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: theme.colorScheme.outline.withValues(alpha: 0.08),
                  ),
                  itemBuilder: (context, index) {
                    final item = _tempValues[index];
                    final isValid = item.isValid;
                    return ListTile(
                      dense: true,
                      onTap: () => _editRule(index),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: Switch(
                        value: item.enabled,
                        onChanged: (value) {
                          setState(() {
                            _tempValues[index] = item.copyWith(enabled: value);
                          });
                        },
                      ),
                      title: Text(
                        item.value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: isValid
                            ? null
                            : TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: Text(
                        '${item.useRegex ? '正则表达式' : '原文匹配'}${isValid ? '' : ', 当前规则无效'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _editRule(index),
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: '编辑',
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _tempValues.removeAt(index);
                              });
                            },
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除',
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
      actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text(
            '取消',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () => Get.back(result: _tempValues),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Future<void> _addRule() async {
    final result = await _showRuleEditDialog(context);
    if (result != null) {
      setState(() {
        _tempValues.add(result);
      });
    }
  }

  Future<void> _editRule(int index) async {
    final result = await _showRuleEditDialog(
      context,
      initialValue: _tempValues[index],
    );
    if (result != null) {
      setState(() {
        _tempValues[index] = result;
      });
    }
  }
}

Future<FilterRule?> _showRuleEditDialog(
  BuildContext context, {
  FilterRule? initialValue,
}) {
  String value = initialValue?.value ?? '';
  bool useRegex = initialValue?.useRegex ?? false;
  return showDialog<FilterRule>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        constraints: Style.dialogFixedConstraints,
        title: Text(initialValue == null ? '新增过滤规则' : '编辑过滤规则'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              autofocus: true,
              initialValue: value,
              minLines: 1,
              maxLines: 4,
              onChanged: (newValue) => value = newValue,
              decoration: const InputDecoration(
                labelText: '匹配内容',
                hintText: '输入正则表达式或原文字符串',
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: useRegex,
              title: const Text('按正则表达式匹配'),
              subtitle: const Text('关闭后会按原文匹配, 并自动转义特殊字符'),
              onChanged: (newValue) {
                setState(() {
                  useRegex = newValue;
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () {
              final newValue = value.trim();
              if (newValue.isEmpty) {
                SmartDialog.showToast('内容不能为空');
                return;
              }
              if (useRegex) {
                try {
                  RegExp(newValue, caseSensitive: false);
                } catch (e) {
                  SmartDialog.showToast('正则表达式无效: $e');
                  return;
                }
              }
              Get.back(
                result: FilterRule(
                  value: newValue,
                  enabled: initialValue?.enabled ?? true,
                  useRegex: useRegex,
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}
