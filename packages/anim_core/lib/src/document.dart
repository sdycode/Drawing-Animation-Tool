/// The document root (docs/v3/01 §11, docs/v3/02 §3.1).
library;

import 'animation.dart';
import 'decode.dart';
import 'json.dart';
import 'node.dart';
import 'primitives.dart';
import 'track.dart';
import 'uuid.dart';

final class Document {
  const Document({
    this.schemaVersion = currentSchemaVersion,
    required this.id,
    required this.name,
    required this.artboard,
    this.background = Rgba.transparent,
    required this.root,
    this.animations = const [],
    this.defaultAnimationId,
    this.rev = 0,
    this.unknownKeys = const {},
  });

  static const int currentSchemaVersion = 3;

  final int schemaVersion;

  /// UUID v4.
  final String id;

  /// Display name. **Not** an identity — two projects may share one.
  final String name;

  /// Document size in units. Origin is top-left, y-down.
  final Vec2 artboard;

  final Rgba background;

  final GroupNode root;

  /// A **list from day one**. v1 creates exactly one and the UI hides the
  /// concept; this is the state-machine seam and it costs v1 nothing.
  final List<Animation> animations;

  /// Never `animations.first` — doc 01 §11 names it: twenty call sites doing
  /// that is twenty crashes on an empty list, and the list is empty for every
  /// document written before this field existed. Resolve through
  /// [defaultAnimation], which returns null and makes the caller say what
  /// "no animation" renders as.
  final AnimationId? defaultAnimationId;

  /// Monotonic save counter, incremented by exactly 1 on every **persisted**
  /// save — never on an in-memory edit, never on undo.
  ///
  /// The only persisted field the evaluator never reads: it is save metadata,
  /// so it lives here (it must survive reload) but sits outside every
  /// evaluation stage. v1 writes and round-trips it; v1.1 turns this same field
  /// into optimistic concurrency, which is what detects the two-tab clobber.
  final int rev;

  /// Forward-compat passthrough (docs/v3/02 §7). `components` and
  /// `stateMachines` ride here; both are reserved and v1 never writes them.
  final Map<String, Object?> unknownKeys;

  /// The animation [defaultAnimationId] names, or **null**.
  ///
  /// The lookup is the point: a `defaultAnimationId` pointing at an animation
  /// that no longer exists is stale data, not a crash, and a document decoded
  /// with no animations at all is a legal document that renders its rest pose.
  Animation? get defaultAnimation {
    final wanted = defaultAnimationId;
    if (wanted == null) return null;
    for (final a in animations) {
      if (a.id == wanted) return a;
    }
    return null;
  }

  /// A newer document opens **read-only** and every save path is disabled.
  ///
  /// Key preservation protects syntax, not semantics: a v3 client cannot know
  /// that a v4 `skin` field must stay consistent with the anchors it just let
  /// the user delete.
  bool get isReadOnly => schemaVersion > currentSchemaVersion;

  /// A fresh, empty document with an explicit artboard.
  ///
  /// The artboard is explicit from day one because legacy inferred it from
  /// whatever the first canvas happened to measure, so the same file rendered
  /// at different proportions on different screens.
  /// Mints exactly **one** [Animation] and points [defaultAnimationId] at it —
  /// the v1 document invariant (docs/v3/01 §11).
  ///
  /// Creation is the only place that invariant is established. Decode
  /// deliberately does **not** synthesize one: a document that legitimately has
  /// no animations would be silently rewritten on the next autosave, and
  /// rewriting the user's data to satisfy an invariant is how you lose it.
  factory Document.create({
    required String name,
    Vec2 artboard = const Vec2(450.2, 250.4),
    Rgba background = Rgba.transparent,
  }) {
    final animation = Animation(id: AnimationId(uuidV4()), name: 'Main');
    return Document(
      id: uuidV4(),
      name: name,
      artboard: artboard,
      background: background,
      root: GroupNode(id: NodeId(uuidV4()), name: 'Root'),
      animations: <Animation>[animation],
      defaultAnimationId: animation.id,
    );
  }

  Document copyWith({
    String? name,
    Vec2? artboard,
    Rgba? background,
    GroupNode? root,
    List<Animation>? animations,
    AnimationId? defaultAnimationId,
    int? rev,
  }) =>
      Document(
        schemaVersion: schemaVersion,
        id: id,
        name: name ?? this.name,
        artboard: artboard ?? this.artboard,
        background: background ?? this.background,
        root: root ?? this.root,
        animations: animations ?? this.animations,
        defaultAnimationId: defaultAnimationId ?? this.defaultAnimationId,
        rev: rev ?? this.rev,
        unknownKeys: unknownKeys,
      );

  /// The one place `rev` advances. Called by the store on a successful write,
  /// never by an editing command.
  Document bumpRev() => copyWith(rev: rev + 1);

  static const _known = <String>{
    'schemaVersion',
    'id',
    'name',
    'rev',
    'artboard',
    'background',
    'root',
    'animations',
    'defaultAnimationId',
  };

  /// The one entry point, and the **only** strict half of the decoder.
  ///
  /// `schemaVersion`, `id`, `artboard` and `root` are required: without any one
  /// of them there is no document to show, and an empty canvas reads to the
  /// user as data loss they have already suffered. Each failure carries the
  /// JSON path of the field, and nested required structure reports its real
  /// location — `root/children[2]/path/anchors[7]/position`, not "invalid
  /// document". Everything else degrades and is preserved. [DocumentException]
  /// carries the full statement of that boundary; it is written down once, and
  /// this is the half that points at it.
  ///
  /// Before M1 these four were bare `j['id']! as String` /
  /// `Vec2.fromJson(j['artboard'])` casts, so a corrupt file surfaced as a
  /// `TypeError` or a `NoSuchMethodError` from somewhere inside a decode — no
  /// field name, no location, nothing the user or a support thread could act
  /// on. docs/v3/01 §11: an invalid document with no location is what makes a
  /// corrupt file unfixable.
  factory Document.fromJson(Map<String, Object?> j) {
    final root = GroupNode.fromJson(reqObject(j['root'], 'root'), 'root');
    final rawAnimations = opt(
      j,
      'animations',
      (v) => reqArray(v, 'animations'),
      const <Object?>[],
    );
    final animations = <Animation>[
      for (var k = 0; k < rawAnimations.length; k++)
        Animation.fromJson(rawAnimations[k], jsonIndex('animations', k)),
    ];

    final doc = Document(
      schemaVersion: reqInt(j['schemaVersion'], 'schemaVersion'),
      id: reqString(j['id'], 'id'),
      // `name` is deliberately NOT required, whatever docs/v3/02 §3.1's table
      // says: an untitled document is a document, and the display name is not
      // an identity.
      name: opt(j, 'name', (v) => reqString(v, 'name'), ''),
      artboard: reqVec2(j['artboard'], 'artboard'),
      background: opt(
          j, 'background', (v) => reqRgba(v, 'background'), Rgba.transparent),
      root: root,
      animations: _dropOrphanPoses(root, animations),
      // `string | null` on the wire (docs/v3/02 §3.1): an explicit null means
      // absent and is never manufactured into a plausible id.
      defaultAnimationId: opt<AnimationId?>(j, 'defaultAnimationId',
          (v) => v is String ? AnimationId(v) : null, null),
      // Absent means written before `rev` existed, which is generation 1 — not
      // 0. A fresh in-memory document starts at 0 and reaches 1 on its first
      // persisted save, so both paths agree on what "saved once" means.
      rev: opt(j, 'rev', (v) => reqInt(v, 'rev'), 1),
      unknownKeys: unknownKeysOf(j, _known),
    );
    doc.validate();
    return doc;
  }

  Map<String, Object?> toJson() => withUnknown(unknownKeys, {
        'schemaVersion': schemaVersion,
        'id': id,
        'name': name,
        'rev': rev,
        'artboard': artboard.toJson(),
        'background': background.toJson(),
        'root': root.toJson(),
        'animations': animations.map((a) => a.toJson()).toList(growable: false),
        if (defaultAnimationId != null)
          'defaultAnimationId': defaultAnimationId!.v,
      });

  /// Invariant P6 (docs/v3/01 §5): a pose entry for an `AnchorId` that is not
  /// in that node's topology is **dropped at decode**, with a warning.
  ///
  /// Orphan poses are the only way stale data survives the id join, and they
  /// arrive from real events — an anchor deleted by a build whose delete path
  /// missed one animation, a hand-edited file, a partial write. Keeping them
  /// costs nothing at render time (the evaluator iterates topology, so an
  /// orphan is simply never read) but they resurrect as soon as an id is reused
  /// or a track is retopologized, and they make the "poses == topology" commit
  /// invariant permanently red. Throwing is worse still: it makes an otherwise
  /// perfectly renderable document unopenable.
  static List<Animation> _dropOrphanPoses(
      GroupNode root, List<Animation> animations) {
    if (animations.isEmpty) return animations;

    final topology = <NodeId, Set<AnchorId>>{};
    for (final n in _visit(root)) {
      if (n is PathNode) {
        topology[n.id] = {for (final a in n.path.anchors) a.id};
      }
    }

    final out = <Animation>[];
    for (final animation in animations) {
      final repaired = <NodeId, TrackSet>{};
      var animationChanged = false;

      for (final entry in animation.tracks.entries) {
        final track = entry.value.pathTrack();
        if (track == null) {
          repaired[entry.key] = entry.value;
          continue;
        }
        // A node that is absent, or is not a PathNode, has no anchors at all,
        // so every pose on it is an orphan.
        final live = topology[entry.key] ?? const <AnchorId>{};

        var dropped = 0;
        final keys = <Keyframe<PathPose>>[];
        for (final k in track.keys) {
          final kept = <AnchorId, AnchorPose>{
            for (final pose in k.value.anchors.entries)
              if (live.contains(pose.key)) pose.key: pose.value,
          };
          dropped += k.value.anchors.length - kept.length;
          keys.add(kept.length == k.value.anchors.length
              ? k
              : Keyframe<PathPose>(
                  t: k.t,
                  value: PathPose(Map.unmodifiable(kept)),
                  easing: k.easing,
                ));
        }

        if (dropped == 0) {
          repaired[entry.key] = entry.value;
          continue;
        }
        onDecodeWarning('animation "${animation.id.v}": dropped $dropped '
            'orphan pose(s) on node "${entry.key.v}" — no such anchor in its '
            'topology');
        animationChanged = true;
        repaired[entry.key] = TrackSet(
          Map.unmodifiable(<PropertyKey, Track>{
            ...entry.value.byKey,
            const PropertyKey(PropKey.path): PathTrack(keys),
          }),
          unknownKeys: entry.value.unknownKeys,
        );
      }

      out.add(animationChanged
          ? animation.copyWith(tracks: Map.unmodifiable(repaired))
          : animation);
    }
    return List.unmodifiable(out);
  }

  /// Walks the tree depth-first in paint order.
  Iterable<Node> walk() => _visit(root);

  /// Static so decode-time repairs can walk a subtree before the [Document]
  /// that owns it exists.
  static Iterable<Node> _visit(Node n) sync* {
    yield n;
    if (n is GroupNode) {
      for (final c in n.children) {
        yield* _visit(c);
      }
    }
  }

  /// `NodeId` → node, rebuilt on demand and **never persisted**.
  ///
  /// Derived state (docs/v3/01 §11): the tree is the single source of truth for
  /// hierarchy, and this index exists only to make track lookup O(1).
  ///
  /// **It is NOT memoised, and it will not be.** Every read re-walks the whole
  /// tree and returns a fresh map, so a caller that needs it more than once —
  /// or once per item in a loop — hoists it into a local (`NodeOps.createGroup`
  /// and `NodeOps.reparent` do exactly that; reading it inside their member
  /// loops is what made them O(n·m)). A cache field here would be the
  /// "storing anything derived on `Document`" antipattern docs/v3/08 §4 names
  /// by name, and it desyncs precisely when two features mutate in one command.
  /// An earlier version of this comment promised M2 would memoise it; M2
  /// shipped, it does not, and the promise was the bug.
  Map<NodeId, Node> get nodeIndex => {for (final n in walk()) n.id: n};

  /// `NodeId` is unique within a `Document` — governing rule 2 (docs/v3/01 §1).
  ///
  /// Checked at decode rather than trusted: every track lookup and every future
  /// cross-tree reference joins on this id, so a duplicate does not fail loudly
  /// at load, it silently animates the wrong node.
  void validate() {
    final seen = <String>{};
    for (final n in walk()) {
      if (!seen.add(n.id.v)) {
        throw DocumentException('duplicate NodeId "${n.id.v}"',
            path: 'root/${n.name}');
      }
    }
  }
}
