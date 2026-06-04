import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_page.dart';
import 'sessions_page.dart';
import 'perception_page.dart';
import 'practice_page.dart';
import 'iris_assistant/mascot_widget.dart';
import 'iris_assistant/mascot_controller.dart';
import 'jm/dictionary_service.dart';
import 'practice/vocabulary_service.dart';

Future<void> main() async {
  // 1. 确保基础环境就绪
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IrisApp());
}

class IrisApp extends StatelessWidget {
  const IrisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Iris',
      debugShowCheckedModeBanner: false,
      navigatorKey: MascotController().navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      navigatorObservers: [MascotRouteObserver()],
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            const GlobalMascotWrapper(),
          ],
        );
      },
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _initStatus = "正在唤醒 Iris...";

  @override
  void initState() {
    super.initState();
    // 关键：给原生层 200ms 的准备时间，彻底规避通道未建立的问题
    Future.delayed(const Duration(milliseconds: 200), () => _prepareApp());
  }

  Future<void> _prepareApp() async {
    try {
      // 1. 加载配置
      await dotenv.load(fileName: ".env");

      // 2. 初始化云服务 (最容易触发 channel-error)
      setState(() => _initStatus = "正在连接云端服务...");
      await Supabase.initialize(
        url: dotenv.get('SUPABASE_URL', fallback: ''),
        anonKey: dotenv.get('SUPABASE_ANON_KEY', fallback: ''),
      );

      // 3. AI 引擎
      setState(() => _initStatus = "正在初始化 AI 引擎...");
      await FlutterGemma.initialize();

      // 4. 本地数据
      setState(() => _initStatus = "正在加载本地词典...");
      await DictionaryService().init();
      setState(() => _initStatus = "正在同步学习数据...");
      await VocabularyService().init();

      // 5. 看板娘控制器 (先触发加载，不完全阻塞)
      setState(() => _initStatus = "Iris 正在降临...");
      await MascotController().init().catchError((e) {
        debugPrint("Mascot Init Error: $e");
      });

      // 6. 检查登录状态
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? true;
      if (!rememberMe) {
        await Supabase.instance.client.auth.signOut();
        await prefs.setBool('remember_me', true);
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthStateWrapper()),
        );
      }
    } catch (e) {
      setState(() => _initStatus = "启动异常: $e\n建议清除应用数据重新运行");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/img/Iris_Scarlet.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image, size: 50)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 30),
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  const SizedBox(height: 20),
                  Text(
                    _initStatus,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GlobalMascotWrapper extends StatelessWidget {
  const GlobalMascotWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: MascotController(),
      builder: (context, _) {
        if (MascotController().isInitialized) {
          return const IrisMascotOverlay();
        }
        return const SizedBox.shrink();
      },
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
  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    MascotController().updateRoute(newRoute);
  }
}

class AuthStateWrapper extends StatelessWidget {
  const AuthStateWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
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
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const PracticePage(),
    const SessionsPage(),
    const PerceptionPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _pages[_selectedIndex],
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _buildNavItem(0, Icons.self_improvement, '修行'),
            _buildNavItem(1, Icons.chat_bubble_outline, '会话'),
            const SizedBox(width: 48), 
            _buildNavItem(2, Icons.visibility_outlined, '感知'),
            _buildNavItem(3, Icons.person_outline, '我的'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final color = isSelected ? Theme.of(context).colorScheme.primary : Colors.grey;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
