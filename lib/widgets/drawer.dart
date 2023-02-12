import 'package:animated_icon_demo/Global/constants.dart';
import 'package:animated_icon_demo/Global/global.dart';
import 'package:animated_icon_demo/Landscape%20Widgets/sizes_landscape.dart';

import 'package:flutter/material.dart';

import 'package:url_launcher/url_launcher.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double minVerticalPadding = h * 0.022;
    double webiconW = 25;
    double webFont = 15;
    return Container(
      decoration:BoxDecoration(   
         borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
         color: Colors.transparent,) ,

      margin: EdgeInsets.symmetric(vertical: topbarHeight),
      child: Drawer(  backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20), bottomLeft: Radius.circular(20)),
        ),
        // backgroundColor: Colors.white,
        width: 200,
        child: Container(
          // color: Colors.white,
          decoration: BoxDecoration(
            color: Colors.transparent,
            // image: DecorationImage(
            //     image: AssetImage('assets/app_icons/bg1.jpg'), fit: BoxFit.cover),
          ),
          child: ListView(
            children: [
              SizedBox(
                height: h * 0.06,
              ),
              InkWell(
                onTap: () {
                  launch(C.playstorelink);
                },
                child: ListTile(
                  minVerticalPadding: minVerticalPadding,
                  leading: Image.asset(
                    'assets/app_icons/playstore.png',
                    width: webiconW,
                  ),
                  title: Text(
                    'Play Store',
                    style: TextStyle(color: Colors.black, fontSize: webFont),
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  launch(C.linkedinlink);
                },
                child: ListTile(
                  minVerticalPadding: minVerticalPadding,
                  leading: Image.asset(
                    'assets/app_icons/linkedin.png',
                    width: webiconW,
                  ),
                  title: Text(
                    'Linked In',
                    style: TextStyle(color: Colors.black, fontSize: webFont),
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  launch("https://www.youtube.com/@shubhamyeole2881/videos");
                },
                child: ListTile(
                  minVerticalPadding: minVerticalPadding,
                  leading: Image.asset(
                    'assets/app_icons/youtube.png',
                    width: webiconW,
                  ),
                  title: Text(
                    'YouTube',
                    style: TextStyle(color: Colors.black, fontSize: webFont),
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  launch("https://github.com/sdycode");
                },
                child: ListTile(
                  minVerticalPadding: minVerticalPadding,
                  leading: Image.asset(
                    'assets/app_icons/git.png',
                    width: webiconW,
                  ),
                  title: Text(
                    'Github',
                    style: TextStyle(color: Colors.black, fontSize: webFont),
                  ),
                ),
              ),
              ExpansionTile(
                collapsedIconColor: Colors.black,
                iconColor: Colors.blue,
                title: Text("Web Apps"),
                leading: Image.asset(
                  'assets/app_icons/webapp.png',
                  width: webiconW,
                ),
                children: [
                  InkWell(
                    onTap: () {
                      launch(
                          "https://sdycode.github.io/FlutterGradientMaker/#/");
                    },
                    child: ListTile(
                      minVerticalPadding: minVerticalPadding,
                      leading: Image.asset(
                        'assets/app_icons/gradient.png',
                        width: webiconW,
                      ),
                      title: Text(
                        'Gradinent Maker',
                        style:
                            TextStyle(color: Colors.black, fontSize: webFont),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      launch(
                          "https://sdycode.github.io/FlutterPathMaker/#/");
                    },
                    child: ListTile(
                      minVerticalPadding: minVerticalPadding,
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(webiconW*0.3),
                        child: Image.asset(
                          'assets/app_icons/paint.png',
                          width: webiconW,
                        ),
                      ),
                      title: Text(
                        'Path Maker',
                        style:
                            TextStyle(color: Colors.black, fontSize: webFont),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      launch("https://sdycode.github.io/shortnotes/");
                    },
                    child: ListTile(
                      minVerticalPadding: minVerticalPadding,
                      leading: Image.asset(
                        'assets/app_icons/notes.png',
                        width: webiconW,
                      ),
                      title: Text(
                        'Notes',
                        style:
                            TextStyle(color: Colors.black, fontSize: webFont),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      launch("https://sdycode.github.io/photofilterapp/#/");
                    },
                    child: ListTile(
                      minVerticalPadding: minVerticalPadding,
                      leading: Image.asset(
                        'assets/app_icons/filter.png',
                        width: webiconW,
                      ),
                      title: Text(
                        'Photofilter',
                        style:
                            TextStyle(color: Colors.black, fontSize: webFont),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      launch("https://sdycode.github.io/3DModel/#/");
                    },
                    child: ListTile(
                      minVerticalPadding: minVerticalPadding,
                      leading: Image.asset(
                        'assets/app_icons/flutter3dp.png',
                        width: webiconW,
                      ),
                      title: Text(
                        '3D Flutter',
                        style:
                            TextStyle(color: Colors.black, fontSize: webFont),
                      ),
                    ),
                  ),
                ],
              ),
              Divider(),
              InkWell(
                  onTap: () {
                    launch("https://github.com/sdycode/Drawing-Animation-Tool");
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "Source Code",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                         "https://github.com/sdycode/Drawing-Animation-Tool",
                          textAlign: TextAlign.center,
                        ),
                      )
                    ],
                  )),
              Divider(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    "Developed By",
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Shubham Yeole",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}
