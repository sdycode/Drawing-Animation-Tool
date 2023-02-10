import 'package:animated_icon_demo/Animated/my_animated_icons.dart';
import 'package:animated_icon_demo/Global/global.dart';
import 'package:animated_icon_demo/providers/edit_pallet_provider.dart';
import 'package:animated_icon_demo/screens/landscape_layout.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/firebase_options.dart';
import 'package:animated_icon_demo/playpause.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/screens/username_page.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui' as ui show Paint, Path, Canvas;

import 'mypaint.dart';
import 'providers/drawing_board_provider.dart';

late BuildContext mainContext;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugLog("before firebaseapp");
  try {
    FirebaseApp firebaseApp = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugLog("after  firebaseapp app $firebaseApp ");
  } catch (e) {
    debugLog("after  firebaseapp err $e ");
  }

  await Shared.init();
  // DataService().usersInstance.add({
  //   "shubham": {'projects': [

  //   ]}
  // });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (context) => ProvData()),
          ChangeNotifierProvider(create: (context) => AnimSheetProvider()),
          ChangeNotifierProvider(create: (context) => EditPalletProvider()),
          ChangeNotifierProvider(create: (context) => DrawingBoardProvider()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          title: 'Animation Tool',
          theme: ThemeData.dark(

                  // primarySwatch: Colors.blue,
                  // backgroundColor: B
                  )
              .copyWith(
                  primaryColorLight: Colors.white,
                  textTheme: TextTheme(
                      displayMedium: TextStyle(color: Colors.grey.shade200)),
                  primaryColorDark: Color.fromARGB(255, 38, 37, 37),
                  primaryColor: Colors.black87),
          home: Builder(
            builder: (context) {
              w = MediaQuery.of(context).size.width;
                            h= MediaQuery.of(context).size.height;

              mainContext = context;
              return UserNamePage();
              // LandscapeLayoutScreen();
            },

            //  UserNamePage(),
          ),
        ));
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  late Widget animateChild = _animatedWidgetChild1();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Container(
          alignment: Alignment.center,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[PlayPause(), MyPaint1()],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }

  static ui.Path _pathFactory() => ui.Path();

  boxSwitcherPressed() {
    setState(() {
      if (animateChild.key == _animatedWidgetChild1().key) {
        animateChild = _animatedWidgetChild2();
      } else {
        animateChild = _animatedWidgetChild1();
      }
    });
  }

  boxSwitcher() {
    return AnimatedSwitcher(
      duration: Duration(seconds: 1),
      child: animateChild,
      transitionBuilder: (child, animation) {
        return SizeTransition(
            axis: Axis.vertical,
            axisAlignment: -0.8,
            child: child,
            sizeFactor: animation);
      },
    );
  }

  Widget _animatedWidgetChild1() {
    return Container(
      key: ValueKey(1),
      width: 150,
      height: 80,
      color: Colors.amber,
    );
  }

  Widget _animatedWidgetChild2() {
    return Container(
      key: ValueKey(2),
      width: 90,
      height: 160,
      color: Colors.red,
    );
  }
}
