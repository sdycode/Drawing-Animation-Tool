import 'package:animated_icon_demo/Global/global.dart';
import 'package:animated_icon_demo/providers/edit_pallet_provider.dart';
import 'package:animated_icon_demo/providers/user_page_provider.dart';
import 'package:animated_icon_demo/firebase_options.dart';
import 'package:animated_icon_demo/providers/animation_sheet_provider.dart';
import 'package:animated_icon_demo/providers/prov.dart';
import 'package:animated_icon_demo/state/editor_controller.dart';
import 'package:animated_icon_demo/screens/username_page.dart';
import 'package:animated_icon_demo/shared/shared.dart';
import 'package:animated_icon_demo/utils/text_field_methods/debugLog.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          ChangeNotifierProvider(create: (context) => UserPageProvider()),
          // .value (not create:) — EditorController is a long-lived singleton,
          // so Provider must NOT own/dispose it.
          ChangeNotifierProvider.value(value: EditorController.instance),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          title: 'Annimation',
          theme: ThemeData.dark().copyWith(
              primaryColorLight: Colors.white,
              textTheme: TextTheme(
                  displayMedium: TextStyle(color: Colors.grey.shade200)),
              primaryColorDark: const Color.fromARGB(255, 38, 37, 37),
              primaryColor: Colors.black87),
          home: Builder(
            builder: (context) {
              w = MediaQuery.of(context).size.width;
              h = MediaQuery.of(context).size.height;

              mainContext = context;
              return const UserNamePage();
            },
          ),
        ));
  }
}
