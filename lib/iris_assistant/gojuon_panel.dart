import 'package:flutter/material.dart';

class JapaneseChar {
  final String hiragana;
  final String katakana;
  final String romaji;
  const JapaneseChar(this.hiragana, this.katakana, this.romaji);
}

// 韵母定义
const vowels = ['a', 'i', 'u', 'e', 'o'];
const hiraVowels = ['あ', 'い', 'う', 'え', 'お'];
const kataVowels = ['ア', 'イ', 'ウ', 'エ', 'オ'];

// 声母映射 (清音)
const seionMap = {
  '':  ['あ', 'い', 'う', 'え', 'お'],
  'k': ['か', 'き', 'く', 'け', 'こ'],
  's': ['さ', 'し', 'す', 'せ', 'そ'],
  't': ['た', 'ち', 'つ', 'て', 'と'],
  'n': ['な', 'に', 'ぬ', 'ね', 'の'],
  'h': ['は', 'ひ', 'ふ', 'へ', 'ほ'],
  'm': ['ま', 'み', 'む', 'め', 'も'],
  'y': ['や', null, 'ゆ', null, 'よ'], // y行有空缺
  'r': ['ら', 'り', 'る', 'れ', 'ろ'],
  'w': ['わ', null, null, null, 'を'], // w行空缺较多
};

const dakuonMap = {
'g': ['が', 'ぎ', 'ぐ', 'げ', 'ご'],
'z': ['ざ', 'じ', 'ず', 'ぜ', 'ぞ'],
'd': ['だ', 'ぢ', 'づ', 'で', 'ど'],
'b': ['ば', 'び', 'ぶ', 'べ', 'ぼ'],
'p': ['ぱ', 'ぴ', 'ぷ', 'ぺ', 'ぽ'],
};

// 罗马音特殊发音修正
String _fixRomaji(String s, String v) {
  Map<String, String> specials = {
    'si': 'shi', 'ti': 'chi', 'tu': 'tsu', 'hu': 'fu', 'zi': 'ji', 'di': 'ji', 'du': 'zu'
  };
  return specials['$s$v'] ?? '$s$v';
}

List<List<JapaneseChar?>> generateGrid(Map<String, List<String?>> sourceMap) {
  List<List<JapaneseChar?>> grid = [];

  sourceMap.forEach((consonant, chars) {
    List<JapaneseChar?> row = [];
    for (int i = 0; i < 5; i++) {
      String? hira = chars[i];
      if (hira == null) {
        row.add(null);
      } else {
        // 计算对应的片假名：平假名 Unicode + 96 = 片假名
        String kata = String.fromCharCode(hira.runes.first + 96);
        // 修正罗马音
        String roma = _fixRomaji(consonant, vowels[i]);
        row.add(JapaneseChar(hira, kata, roma));
      }
    }
    grid.add(row);
  });

  // 最后特殊处理 'ん'
  grid.add([JapaneseChar('ん', 'ン', 'n'), null, null, null, null]);
  return grid;
}

List<List<JapaneseChar?>> generateYouon() {
  const consonants = ['k', 's', 't', 'n', 'h', 'm', 'r', 'g', 'z', 'b', 'p'];
  const hiraBase = ['きゃ', 'きゅ', 'きょ']; // 以此为例推导

  // 定义i段的平假名开头
  const iRowHira = ['き', 'し', 'ち', 'に', 'ひ', 'み', 'り', 'ぎ', 'じ', 'び', 'ぴ'];
  const smallsHira = ['ゃ', 'ゅ', 'ょ'];
  const smallsKata = ['ャ', 'ュ', 'ョ'];
  const yVowels = ['ya', 'yu', 'yo'];

  List<List<JapaneseChar?>> grid = [];

  for (int i = 0; i < consonants.length; i++) {
    List<JapaneseChar?> row = [];
    for (int j = 0; j < 3; j++) {
      String hira = iRowHira[i] + smallsHira[j];
      String kata = String.fromCharCode(iRowHira[i].runes.first + 96) + smallsKata[j];

      // 罗马音逻辑：shi+ya = sha
      String c = consonants[i];
      String roma;
      if (c == 's' || c == 'z' || c == 't') { // 特殊处理 sha, ja, cha
        roma = (c == 'z' ? 'j' : (c == 't' ? 'ch' : 'sh')) + yVowels[j].substring(1);
      } else {
        roma = c + yVowels[j];
      }

      row.add(JapaneseChar(hira, kata, roma));
      if (j < 2) row.addAll([null]);
    }
    // 补齐到5列，方便 GridView 布局一致性（可选）
    // row.addAll([null, null]);
    grid.add(row);
  }
  print(grid);
  return grid;
}

// 数据
class GojuonManager {
  static final List<List<JapaneseChar?>> seion = generateGrid(seionMap);
  static final List<List<JapaneseChar?>> dakuon = generateGrid(dakuonMap);
  static final List<List<JapaneseChar?>> youon = generateYouon();
}

class GojuonPanel extends StatelessWidget {
  final Function(String hiragana) onCharTap;

  const GojuonPanel({super.key, required this.onCharTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.8,
      height: 500,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9F0), // 樱花白/和纸色
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD32F2F), width: 3), // 朱红色边框
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            // 自定义和风 TabBar
            const TabBar(
              indicatorColor: Color(0xFFD32F2F),
              labelColor: Color(0xFFD32F2F),
              unselectedLabelColor: Colors.grey,
              indicatorWeight: 4,
              tabs: [
                Tab(child: Text("清音", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                Tab(child: Text("浊音", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                Tab(child: Text("拗音", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              ],
            ),

            Expanded(
              child: TabBarView(
                children: [
                  _buildGrid(GojuonManager.seion),  // 清音列表
                  _buildGrid(GojuonManager.dakuon), // 浊音列表
                  _buildGrid(GojuonManager.youon),  // 拗音列表
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<List<JapaneseChar?>> data) {
    // 将二维数组扁平化
    final flatList = data.expand((i) => i).toList();

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5, // 五十音通常5列
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: flatList.length,
      itemBuilder: (context, index) {
        final char = flatList[index];
        if (char == null) return const SizedBox.shrink();
        return _GojuonItem(char: char, onTap: onCharTap);
      },
    );
  }
}

class _GojuonItem extends StatelessWidget {
  final JapaneseChar char;
  final Function(String) onTap;

  const _GojuonItem({required this.char, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white, // 将背景色移到这里
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias, // 剪裁水波纹，防止它超出圆角边框
      child: InkWell(
        onTap: () => onTap(char.hiragana),
        splashColor: const Color(0xFFF48FB1).withOpacity(0.1),
        child: Container(
          // 使用 Decoration 而不是直接设置 color，保持边框和阴影
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF48FB1).withOpacity(0.3)),
            // 注意：如果阴影导致溢出，可以暂时删掉 boxShadow 测试
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2), // 减少内边距
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 使用 FittedBox 确保文字太大时自动缩小，而不是直接报错
              Expanded(
                flex: 3,
                child: Center(
                  child: FittedBox(
                    child: Text(
                      char.hiragana,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C3E50),
                        fontFamily: 'ZCOOL',
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start, // 紧贴上方
                  children: [
                    Text(char.katakana, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    const SizedBox(width: 4),
                    Text(char.romaji, style: const TextStyle(fontSize: 9, color: Color(0xFFD32F2F))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}