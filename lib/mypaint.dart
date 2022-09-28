import 'dart:developer';

import 'package:animated_icon_demo/play_pause_points.dart';
import 'package:flutter/material.dart';

int _frameno = 0;
int _pointNo = 0;

class MyPaint1 extends StatefulWidget {
  MyPaint1({Key? key}) : super(key: key);

  @override
  State<MyPaint1> createState() => _MyPaint1State();
}

class _MyPaint1State extends State<MyPaint1> with TickerProviderStateMixin {
  late AnimationController controller;
  bool isPlaying = false;

  @override
  void initState() {
    // TODO: implement initState
    controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.amber.shade100.withAlpha(120),
      width: double.infinity,
      height: 500,
      // height: 300,
      child: Column(children: [
        Container(
          width: double.infinity,
          height: 300,
          child: Stack(
            children: [
              Center(
                child: Transform.scale(
                  scale: 4,
                  child: Container(
                    color: Colors.pink.shade100.withAlpha(160),
                    child: CustomPaint(
                      painter:
                          _Painter1(getListAllPointsForThisFrame(_frameno)),
                      size: Size(48, 48),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Spacer(),
        Align(child: Text(_frameno.toString() + "  //   ${playpauselistOfList.length}")),
        Center(
          child: Container(
            height: 50,
            width: double.infinity,
            child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: 16,
                itemBuilder: (c, i) {
                  return InkWell(
                    onTap: () async {
                      runForLoop(i);
                    },
                    child: CircleAvatar(
                      backgroundColor: i == _pointNo ? Colors.red : Colors.blue,
                      radius: 14,
                      child: Text(i.toString()),
                    ),
                  );
                }),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              // mainAxisSize: ,
              children: [
                IconButton(
                  onPressed: () {
                    _frameno--;
                    _frameno = _frameno % (playpauselistOfList.length);
                    _frameno = _frameno.abs();
                    setState(() {});
                  },
                  icon: Icon(Icons.arrow_left_sharp),
                ),
                IconButton(
                    onPressed: () {
                      _frameno++;
                      _frameno = _frameno % (playpauselistOfList.length);
                      _frameno = _frameno.abs();
                      setState(() {});
                    },
                    icon: Icon(Icons.arrow_right_sharp))
              ],
            ),
          ),
        )
      ]),
    );
  }

  List<Offset> getListAllPointsForThisFrame(int i) {
    List<Offset> framePoints = [];
    playpauselistOfList.forEach((element) {
      framePoints.add(element[i]);
    });
    return framePoints;
  }

  void runForLoop(int i) async {
    setState(() {
      _pointNo = i;
    });

    Future.forEach(List<int>.generate(13, (index) => index),
        (int element) async {
      await Future.delayed(Duration(milliseconds: 400));
      setState(() {
        _frameno = element;
      });
    });
  }
}

class _Painter1 extends CustomPainter {
  List<Offset> fp;
  _Painter1(this.fp);
  @override
  void paint(Canvas canvas, Size size) {
    // TODO: implement paint
    Path path = Path();
    Paint paint = Paint();
    // log("size ${size} ${fp} ");
    // for (Offset e in fp) {
    //   log("point $e");
    // }
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.red
      ..strokeWidth = 1;
    for (Offset e in fp) {
      canvas.drawCircle(e, 0.5, paint);
    }
    path.moveTo(fp.first.dx, fp.first.dy);
    path.cubicTo(fp[1].dx, fp[1].dy, fp[2].dx, fp[2].dy, fp[3].dx, fp[3].dy);
    path.cubicTo(fp[4].dx, fp[4].dy, fp[5].dx, fp[5].dy, fp[6].dx, fp[6].dy);
    path.cubicTo(fp[7].dx, fp[7].dy, fp[8].dx, fp[8].dy, fp[9].dx, fp[9].dy);
    path.cubicTo(fp[10].dx, fp[10].dy, fp[11].dx, fp[11].dy, fp[12].dx, fp[12].dy);

    path.close();
    canvas.drawPath(path, paint);
    log("path ${getTrianglePath(size.width, size.height).toString()}");
    // canvas.drawPath(getTrianglePath(size.width, size.height), paint);
  }

  Path getTrianglePath(double x, double y) {
    return Path()
      ..moveTo(0, y)
      ..lineTo(x / 2, 0)
      ..lineTo(x, y)
      ..lineTo(0, y);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    // TODO: implement shouldRepaint
    return true;
  }
}

List<List<Offset>> playpauseplaypauselistOfList = [
  <Offset>[
    Offset(16.046875, 10.039062500000002),
    Offset(16.316498427194905, 9.888877552610037),
    Offset(17.350168694919763, 9.372654593279519),
    Offset(19.411307079826894, 8.531523285503246),
    Offset(22.581365240485308, 7.589125591600418),
    Offset(25.499178877190392, 6.946027752843147),
    Offset(28.464059662259196, 6.878006546805963),
    Offset(30.817518246129985, 7.278084288616373),
    Offset(32.55729037951853, 7.8522502852455425),
    Offset(33.815177617779455, 8.44633949301522),
    Offset(34.712260860180656, 8.99474841944718),
    Offset(35.33082450786742, 9.453096000457315),
    Offset(35.71938467416858, 9.764269500343072),
    Offset(35.93041292728106, 9.940652668613495),
    Offset(35.999770475547926, 9.999803268019111),
    Offset(36.0, 10.0),
  ],
  <Offset>[
    Offset(16.046875, 10.039062500000002),
    Offset(16.316498427194905, 9.888877552610037),
    Offset(17.350168694919763, 9.372654593279519),
    Offset(19.411307079826894, 8.531523285503246),
    Offset(22.581365240485308, 7.589125591600418),
    Offset(25.499178877190392, 6.946027752843147),
    Offset(28.464059662259196, 6.878006546805963),
    Offset(30.817518246129985, 7.278084288616373),
    Offset(32.55729037951853, 7.8522502852455425),
    Offset(33.815177617779455, 8.44633949301522),
    Offset(34.712260860180656, 8.99474841944718),
    Offset(35.33082450786742, 9.453096000457315),
    Offset(35.71938467416858, 9.764269500343072),
    Offset(35.93041292728106, 9.940652668613495),
    Offset(35.999770475547926, 9.999803268019111),
    Offset(36.0, 10.0),
  ],
  <Offset>[
    Offset(16.046875, 24.0),
    Offset(16.048342217256838, 23.847239495401816),
    Offset(16.077346902872737, 23.272630763824544),
    Offset(16.048056811677085, 21.774352893256555),
    Offset(16.312852147291277, 18.33792251536507),
    Offset(17.783803270262858, 14.342870123090869),
    Offset(20.317723014778526, 11.617364447163006),
    Offset(22.6612333095366, 10.320666923510533),
    Offset(24.489055761050455, 9.794101160418514),
    Offset(25.820333134665205, 9.653975058221658),
    Offset(26.739449095852216, 9.704987479092615),
    Offset(27.339611564620206, 9.827950233030684),
    Offset(27.720964836869285, 9.92326668993185),
    Offset(27.930511332768496, 9.98033236260651),
    Offset(27.999770476623045, 9.999934423927339),
    Offset(27.999999999999996, 10.0),
  ],
  <Offset>[
    Offset(16.046875, 24.0),
    Offset(16.048342217256838, 23.847239495401816),
    Offset(16.077346902872737, 23.272630763824544),
    Offset(16.048056811677085, 21.774352893256555),
    Offset(16.312852147291277, 18.33792251536507),
    Offset(17.783803270262858, 14.342870123090869),
    Offset(20.317723014778526, 11.617364447163006),
    Offset(22.6612333095366, 10.320666923510533),
    Offset(24.489055761050455, 9.794101160418514),
    Offset(25.820333134665205, 9.653975058221658),
    Offset(26.739449095852216, 9.704987479092615),
    Offset(27.339611564620206, 9.827950233030684),
    Offset(27.720964836869285, 9.92326668993185),
    Offset(27.930511332768496, 9.98033236260651),
    Offset(27.999770476623045, 9.999934423927339),
    Offset(27.999999999999996, 10.0),
  ],
  <Offset>[
    Offset(16.046875, 24.0),
    Offset(16.048342217256838, 23.847239495401816),
    Offset(16.077346902872737, 23.272630763824544),
    Offset(16.048056811677085, 21.774352893256555),
    Offset(16.312852147291277, 18.33792251536507),
    Offset(17.783803270262858, 14.342870123090869),
    Offset(20.317723014778526, 11.617364447163006),
    Offset(22.6612333095366, 10.320666923510533),
    Offset(24.489055761050455, 9.794101160418514),
    Offset(25.820333134665205, 9.653975058221658),
    Offset(26.739449095852216, 9.704987479092615),
    Offset(27.339611564620206, 9.827950233030684),
    Offset(27.720964836869285, 9.92326668993185),
    Offset(27.930511332768496, 9.98033236260651),
    Offset(27.999770476623045, 9.999934423927339),
    Offset(27.999999999999996, 10.0),
  ],
  <Offset>[
    Offset(37.984375, 24.0),
    Offset(37.98179511896882, 24.268606388242382),
    Offset(37.92629019604922, 25.273340032354483),
    Offset(37.60401862920776, 27.24886978355857),
    Offset(36.59673961336577, 30.16713606026377),
    Offset(35.26901818749416, 32.58105797429066),
    Offset(33.66938906523204, 34.56713290494057),
    Offset(32.196778918797094, 35.8827095523761),
    Offset(30.969894470496282, 36.721466129987085),
    Offset(29.989349224706995, 37.25388702486493),
    Offset(29.223528593231507, 37.59010302049878),
    Offset(28.651601378627003, 37.79719553439594),
    Offset(28.27745500043001, 37.91773612047938),
    Offset(28.069390261744058, 37.979987943400474),
    Offset(28.000229522301836, 37.99993442016443),
    Offset(28.0, 38.0),
  ],
  <Offset>[
    Offset(37.984375, 24.0),
    Offset(37.98179511896882, 24.268606388242382),
    Offset(37.92629019604922, 25.273340032354483),
    Offset(37.60401862920776, 27.24886978355857),
    Offset(36.59673961336577, 30.16713606026377),
    Offset(35.26901818749416, 32.58105797429066),
    Offset(33.66938906523204, 34.56713290494057),
    Offset(32.196778918797094, 35.8827095523761),
    Offset(30.969894470496282, 36.721466129987085),
    Offset(29.989349224706995, 37.25388702486493),
    Offset(29.223528593231507, 37.59010302049878),
    Offset(28.651601378627003, 37.79719553439594),
    Offset(28.27745500043001, 37.91773612047938),
    Offset(28.069390261744058, 37.979987943400474),
    Offset(28.000229522301836, 37.99993442016443),
    Offset(28.0, 38.0),
  ],
  <Offset>[
    Offset(37.984375, 24.0),
    Offset(37.98179511896882, 24.268606388242382),
    Offset(37.92629019604922, 25.273340032354483),
    Offset(37.60401862920776, 27.24886978355857),
    Offset(36.59673961336577, 30.16713606026377),
    Offset(35.26901818749416, 32.58105797429066),
    Offset(33.66938906523204, 34.56713290494057),
    Offset(32.196778918797094, 35.8827095523761),
    Offset(30.969894470496282, 36.721466129987085),
    Offset(29.989349224706995, 37.25388702486493),
    Offset(29.223528593231507, 37.59010302049878),
    Offset(28.651601378627003, 37.79719553439594),
    Offset(28.27745500043001, 37.91773612047938),
    Offset(28.069390261744058, 37.979987943400474),
    Offset(28.000229522301836, 37.99993442016443),
    Offset(28.0, 38.0),
  ],
  <Offset>[
    Offset(37.984375, 24.0),
    Offset(37.98179511896882, 24.268606388242382),
    Offset(37.92663369548548, 25.26958881281347),
    Offset(37.702366207906195, 26.86162526614268),
    Offset(37.62294586290445, 28.407471142252255),
    Offset(38.43944238184115, 29.541526367903558),
    Offset(38.93163276984633, 31.5056762828673),
    Offset(38.80537374713073, 33.4174700441868),
    Offset(38.35814295213548, 34.94327332096457),
    Offset(37.78610517302408, 36.076173087300646),
    Offset(37.186112675124534, 36.8807750697281),
    Offset(36.64281432187422, 37.42234130182257),
    Offset(36.275874837729305, 37.7587389308906),
    Offset(36.06929185625662, 37.94030824940746),
    Offset(36.00022952122672, 37.9998032642562),
    Offset(36.0, 38.0),
  ],
  <Offset>[
    Offset(37.984375, 24.0),
    Offset(37.98179511896882, 24.268606388242382),
    Offset(37.92663369548548, 25.26958881281347),
    Offset(37.702366207906195, 26.86162526614268),
    Offset(37.62294586290445, 28.407471142252255),
    Offset(38.43944238184115, 29.541526367903558),
    Offset(38.93163276984633, 31.5056762828673),
    Offset(38.80537374713073, 33.4174700441868),
    Offset(38.35814295213548, 34.94327332096457),
    Offset(37.78610517302408, 36.076173087300646),
    Offset(37.186112675124534, 36.8807750697281),
    Offset(36.64281432187422, 37.42234130182257),
    Offset(36.275874837729305, 37.7587389308906),
    Offset(36.06929185625662, 37.94030824940746),
    Offset(36.00022952122672, 37.9998032642562),
    Offset(36.0, 38.0),
  ],
  <Offset>[
    Offset(37.984375, 24.0),
    Offset(37.98179511896882, 24.268606388242382),
    Offset(37.92663369548548, 25.26958881281347),
    Offset(37.702366207906195, 26.86162526614268),
    Offset(37.62294586290445, 28.407471142252255),
    Offset(38.43944238184115, 29.541526367903558),
    Offset(38.93163276984633, 31.5056762828673),
    Offset(38.80537374713073, 33.4174700441868),
    Offset(38.35814295213548, 34.94327332096457),
    Offset(37.78610517302408, 36.076173087300646),
    Offset(37.186112675124534, 36.8807750697281),
    Offset(36.64281432187422, 37.42234130182257),
    Offset(36.275874837729305, 37.7587389308906),
    Offset(36.06929185625662, 37.94030824940746),
    Offset(36.00022952122672, 37.9998032642562),
    Offset(36.0, 38.0),
  ],
  <Offset>[
    Offset(16.046875, 10.039062500000002),
    Offset(16.316498427194905, 9.888877552610037),
    Offset(17.35016869491465, 9.372654593335355),
    Offset(19.411307079839695, 8.531523285452844),
    Offset(22.58136524050546, 7.589125591565864),
    Offset(25.499178877175954, 6.946027752856988),
    Offset(28.464059662259196, 6.878006546805963),
    Offset(30.817518246129985, 7.278084288616373),
    Offset(32.55729037951755, 7.852250285245777),
    Offset(33.81517761778539, 8.446339493014325),
    Offset(34.71226086018563, 8.994748419446736),
    Offset(35.33082450786742, 9.453096000457315),
    Offset(35.71938467416858, 9.764269500343072),
    Offset(35.93041292728106, 9.940652668613495),
    Offset(35.999770475547926, 9.999803268019111),
    Offset(36.0, 10.0),
  ],
  <Offset>[
    Offset(16.046875, 10.039062500000002),
    Offset(16.316498427194905, 9.888877552610037),
    Offset(17.35016869491465, 9.372654593335355),
    Offset(19.411307079839695, 8.531523285452844),
    Offset(22.58136524050546, 7.589125591565864),
    Offset(25.499178877175954, 6.946027752856988),
    Offset(28.464059662259196, 6.878006546805963),
    Offset(30.817518246129985, 7.278084288616373),
    Offset(32.55729037951755, 7.852250285245777),
    Offset(33.81517761778539, 8.446339493014325),
    Offset(34.71226086018563, 8.994748419446736),
    Offset(35.33082450786742, 9.453096000457315),
    Offset(35.71938467416858, 9.764269500343072),
    Offset(35.93041292728106, 9.940652668613495),
    Offset(35.999770475547926, 9.999803268019111),
    Offset(36.0, 10.0),
  ],
];

