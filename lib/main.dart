import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_page.dart';
import 'profile_page.dart';
import 'sessions_page.dart';
import 'perception_page.dart';
import 'practice_page.dart';
import 'iris_assistant/mascot_widget.dart';
import 'iris_assistant/mascot_controller.dart';
import 'jm/dictionary_service.dart';
import 'practice/vocabulary_service.dart';

void main() async {
  runApp(MaterialApp(home: SplashScreen()));
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _prepareApp();
  }

  Future<void> _prepareApp() async {
    // 1. 这里执行你 main 函数里的那些初始化逻辑
    await FlutterGemma.initialize();
    await dotenv.load(fileName: ".env");
    await Supabase.initialize(
      url: dotenv.get('SUPABASE_URL'),
      anonKey: dotenv.get('SUPABASE_ANON_KEY'),
    );
    await DictionaryService().init();
    await VocabularyService().init();
    await MascotController().init();

    // 检查是否需要保持登录状态
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? true;
    if (!rememberMe) {
      await Supabase.instance.client.auth.signOut();
      // 重置为 true，防止下次登录时默认不记住（取决于 UI 默认值）
      await prefs.setBool('remember_me', true);
    }

    // 2. 初始化完成后，跳转到主界面
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const IrisApp()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        // 这里换成你的视频播放器或 Lottie 动画
        child: Image.asset(
            'assets/img/Iris_Scarlet.png',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}

class IrisApp extends StatelessWidget {
  const IrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Iris',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      navigatorObservers: [MascotRouteObserver()],
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const IrisMascotOverlay(),
          ],
        );
      },
      home: const AuthStateWrapper(),
    );
  }
}

class MascotRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route route, Route? previousRoute) {
    MascotController().updateRoute(route);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    MascotController().updateRoute(previousRoute);
  }
}

class AuthStateWrapper extends StatelessWidget {
  const AuthStateWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // 监听 Auth 状态变化，以便在登录/登出时刷新 UI
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // 默认进入主界面，无论是否登录
        return const MainContainer();
      },
    );
  }
}

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _selectedIndex = 0; // Default to '幻境' (Center)

  final List<Widget> _pages = [
    const PracticePage(),
    const SessionsPage(),
    // const Center(child: Text('幻境 板块 (灵动中心)', style: TextStyle(fontSize: 24))),
    const PerceptionPage(),
    const ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _pages[_selectedIndex],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildNavItem(0, Icons.self_improvement, '修行'),
            _buildNavItem(1, Icons.chat_bubble_outline, '会话'),
            const SizedBox(width: 48), // Space for FAB
            _buildNavItem(2, Icons.visibility_outlined, '感知'),
            _buildNavItem(3, Icons.person_outline, '我的'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final color = isSelected 
        ? Theme.of(context).colorScheme.primary 
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () => _onItemTapped(index),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
