import 'package:animated_icon_demo/Animated/my_animated_icons.dart';
import 'package:animated_icon_demo/drawing_grid_canvas/drawing_grid_canvas.dart';
import 'package:animated_icon_demo/firebase_options.dart';
import 'package:animated_icon_demo/playpause.dart';
import 'package:animated_icon_demo/screens/username_page.dart';
import 'package:animated_icon_demo/service/firebase_service.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui show Paint, Path, Canvas;

import 'mypaint.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: UserNamePage(),
    );
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
