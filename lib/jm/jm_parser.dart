import 'dart:ui';

import 'package:flutter/material.dart';

class JmParser {
  static const Map<String, String> _posMap = {
    'n': '名词',
    'pn': '代词',
    'adj-i': 'い形容词',
    'adj-na': 'な形容词',
    'v1': '一段动词',
    'v5u': '五段动词(う)',
    'v5k': '五段动词(く)',
    'v5s': '五段动词(す)',
    'v5t': '五段动词(つ)',
    'v5n': '五段动词(ぬ)',
    'v5m': '五段动词(む)',
    'v5r': '五段动词(る)',
    'v5g': '五段动词(ぐ)',
    'v5b': '五段动词(ぶ)',
    'vs': 'サ变动词(する)',
    'vk': 'カ变动词(来る)',
    'adv': '副词',
    'prt': '助词',
    'aux': '助动词',
    'conj': '接续词',
    'int': '感叹词',
    'exp': '惯用语',
    'ctr': '量词',
    'pref': '前缀',
    'suf': '后缀',
    'num': '数词',
    'unc': '未分类',
    // 你可以根据查询到的结果继续补充
  };

  /// 将缩写转换为中文，如果找不到则返回原样
  static String posToChinese(String pos) {
    return _posMap[pos.toLowerCase()] ?? pos;
  }

  static Color getPosColor(String pos) {
    if (pos.startsWith('v')) return Colors.orange; // 动词用橙色
    if (pos.startsWith('adj')) return Colors.green; // 形容词用绿色
    if (pos == 'n') return Colors.blue; // 名词用蓝色
    return Colors.grey; // 其他用灰色
  }
}