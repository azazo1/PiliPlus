import 'dart:convert';

class FilterRule {
  const FilterRule({
    required this.value,
    this.enabled = true,
    this.useRegex = false,
  });

  final String value;
  final bool enabled;
  final bool useRegex;

  factory FilterRule.fromJson(Map<String, dynamic> json) => FilterRule(
    value: json['value']?.toString() ?? '',
    enabled: json['enabled'] != false,
    useRegex: json['useRegex'] == true,
  );

  FilterRule copyWith({
    String? value,
    bool? enabled,
    bool? useRegex,
  }) => FilterRule(
    value: value ?? this.value,
    enabled: enabled ?? this.enabled,
    useRegex: useRegex ?? this.useRegex,
  );

  Map<String, dynamic> toJson() => {
    'value': value,
    'enabled': enabled,
    'useRegex': useRegex,
  };

  RegExp? toRegExp({bool caseSensitive = false}) {
    final pattern = useRegex ? value : RegExp.escape(value);
    if (pattern.trim().isEmpty) {
      return null;
    }
    try {
      return RegExp(pattern, caseSensitive: caseSensitive);
    } catch (_) {
      return null;
    }
  }

  bool get isValid => toRegExp() != null;

  bool hasMatch(String input, {bool caseSensitive = false}) {
    final regExp = toRegExp(caseSensitive: caseSensitive);
    return regExp?.hasMatch(input) == true;
  }
}

List<FilterRule> parseFilterRules(dynamic rawValue) {
  if (rawValue == null) {
    return const [];
  }
  if (rawValue is String) {
    if (rawValue.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is List) {
        return _parseFilterRuleList(decoded);
      }
    } catch (_) {}
    return [FilterRule(value: rawValue, enabled: true, useRegex: true)];
  }
  if (rawValue is List) {
    return _parseFilterRuleList(rawValue);
  }
  return const [];
}

String encodeFilterRules(List<FilterRule> rules) =>
    jsonEncode(rules.map((e) => e.toJson()).toList());

bool hasEnabledFilterRule(List<FilterRule> rules) =>
    rules.any((rule) => rule.enabled && rule.isValid);

bool matchFilterRules(
  List<FilterRule> rules,
  String input, {
  bool caseSensitive = false,
}) => rules.any(
  (rule) =>
      rule.enabled && rule.hasMatch(input, caseSensitive: caseSensitive),
);

List<FilterRule> _parseFilterRuleList(List rawList) {
  final List<FilterRule> rules = [];
  for (final item in rawList) {
    if (item is String) {
      if (item.isNotEmpty) {
        rules.add(FilterRule(value: item, enabled: true, useRegex: true));
      }
      continue;
    }
    if (item is Map) {
      rules.add(FilterRule.fromJson(Map<String, dynamic>.from(item)));
    }
  }
  return rules;
}
