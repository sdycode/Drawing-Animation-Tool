class Pair {
  int preIndex= 0;
  int nextIndex= 1;
  Pair(this.preIndex , this.nextIndex );

  Map<String, dynamic> toMap() => {
        "preIndex": preIndex,
        "nextIndex": nextIndex,
      };
  Pair.fromMap(Map<String, dynamic> json) {
    preIndex = json["preIndex"] ?? 0;
    nextIndex = json["nextIndex"] ?? 0;
    //  Pair(json["preIndex"] ??0,json["nextIndex"]??1 );
  }
}
