// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ncnote_format.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

Chapter _$ChapterFromJson(Map<String, dynamic> json) {
  return _Chapter.fromJson(json);
}

/// @nodoc
mixin _$Chapter {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  List<String> get pageIds => throw _privateConstructorUsedError;

  /// Serializes this Chapter to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Chapter
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChapterCopyWith<Chapter> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChapterCopyWith<$Res> {
  factory $ChapterCopyWith(Chapter value, $Res Function(Chapter) then) =
      _$ChapterCopyWithImpl<$Res, Chapter>;
  @useResult
  $Res call({String id, String title, List<String> pageIds});
}

/// @nodoc
class _$ChapterCopyWithImpl<$Res, $Val extends Chapter>
    implements $ChapterCopyWith<$Res> {
  _$ChapterCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Chapter
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? pageIds = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      pageIds: null == pageIds
          ? _value.pageIds
          : pageIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ChapterImplCopyWith<$Res> implements $ChapterCopyWith<$Res> {
  factory _$$ChapterImplCopyWith(
          _$ChapterImpl value, $Res Function(_$ChapterImpl) then) =
      __$$ChapterImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String title, List<String> pageIds});
}

/// @nodoc
class __$$ChapterImplCopyWithImpl<$Res>
    extends _$ChapterCopyWithImpl<$Res, _$ChapterImpl>
    implements _$$ChapterImplCopyWith<$Res> {
  __$$ChapterImplCopyWithImpl(
      _$ChapterImpl _value, $Res Function(_$ChapterImpl) _then)
      : super(_value, _then);

  /// Create a copy of Chapter
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? pageIds = null,
  }) {
    return _then(_$ChapterImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      pageIds: null == pageIds
          ? _value._pageIds
          : pageIds // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ChapterImpl implements _Chapter {
  const _$ChapterImpl(
      {required this.id,
      required this.title,
      final List<String> pageIds = const []})
      : _pageIds = pageIds;

  factory _$ChapterImpl.fromJson(Map<String, dynamic> json) =>
      _$$ChapterImplFromJson(json);

  @override
  final String id;
  @override
  final String title;
  final List<String> _pageIds;
  @override
  @JsonKey()
  List<String> get pageIds {
    if (_pageIds is EqualUnmodifiableListView) return _pageIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_pageIds);
  }

  @override
  String toString() {
    return 'Chapter(id: $id, title: $title, pageIds: $pageIds)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChapterImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality().equals(other._pageIds, _pageIds));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, id, title, const DeepCollectionEquality().hash(_pageIds));

  /// Create a copy of Chapter
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChapterImplCopyWith<_$ChapterImpl> get copyWith =>
      __$$ChapterImplCopyWithImpl<_$ChapterImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ChapterImplToJson(
      this,
    );
  }
}

abstract class _Chapter implements Chapter {
  const factory _Chapter(
      {required final String id,
      required final String title,
      final List<String> pageIds}) = _$ChapterImpl;

  factory _Chapter.fromJson(Map<String, dynamic> json) = _$ChapterImpl.fromJson;

  @override
  String get id;
  @override
  String get title;
  @override
  List<String> get pageIds;

  /// Create a copy of Chapter
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChapterImplCopyWith<_$ChapterImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

NotebookMetadata _$NotebookMetadataFromJson(Map<String, dynamic> json) {
  return _NotebookMetadata.fromJson(json);
}

/// @nodoc
mixin _$NotebookMetadata {
  String get id => throw _privateConstructorUsedError;
  String get title => throw _privateConstructorUsedError;
  int get formatVersion => throw _privateConstructorUsedError;
  DateTime get createdAt => throw _privateConstructorUsedError;
  DateTime get modifiedAt => throw _privateConstructorUsedError;
  String get coverStyle => throw _privateConstructorUsedError;
  int get coverColor => throw _privateConstructorUsedError; // Material Blue 800
  String get paperType =>
      throw _privateConstructorUsedError; // blank, lined, grid, dotted
  int get paperColor => throw _privateConstructorUsedError;
  int get pageCount => throw _privateConstructorUsedError;
  List<String> get tags => throw _privateConstructorUsedError;
  List<Chapter> get chapters => throw _privateConstructorUsedError;
  String? get author => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;

  /// Serializes this NotebookMetadata to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of NotebookMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $NotebookMetadataCopyWith<NotebookMetadata> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $NotebookMetadataCopyWith<$Res> {
  factory $NotebookMetadataCopyWith(
          NotebookMetadata value, $Res Function(NotebookMetadata) then) =
      _$NotebookMetadataCopyWithImpl<$Res, NotebookMetadata>;
  @useResult
  $Res call(
      {String id,
      String title,
      int formatVersion,
      DateTime createdAt,
      DateTime modifiedAt,
      String coverStyle,
      int coverColor,
      String paperType,
      int paperColor,
      int pageCount,
      List<String> tags,
      List<Chapter> chapters,
      String? author,
      String? description});
}

/// @nodoc
class _$NotebookMetadataCopyWithImpl<$Res, $Val extends NotebookMetadata>
    implements $NotebookMetadataCopyWith<$Res> {
  _$NotebookMetadataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of NotebookMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? formatVersion = null,
    Object? createdAt = null,
    Object? modifiedAt = null,
    Object? coverStyle = null,
    Object? coverColor = null,
    Object? paperType = null,
    Object? paperColor = null,
    Object? pageCount = null,
    Object? tags = null,
    Object? chapters = null,
    Object? author = freezed,
    Object? description = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      formatVersion: null == formatVersion
          ? _value.formatVersion
          : formatVersion // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      modifiedAt: null == modifiedAt
          ? _value.modifiedAt
          : modifiedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      coverStyle: null == coverStyle
          ? _value.coverStyle
          : coverStyle // ignore: cast_nullable_to_non_nullable
              as String,
      coverColor: null == coverColor
          ? _value.coverColor
          : coverColor // ignore: cast_nullable_to_non_nullable
              as int,
      paperType: null == paperType
          ? _value.paperType
          : paperType // ignore: cast_nullable_to_non_nullable
              as String,
      paperColor: null == paperColor
          ? _value.paperColor
          : paperColor // ignore: cast_nullable_to_non_nullable
              as int,
      pageCount: null == pageCount
          ? _value.pageCount
          : pageCount // ignore: cast_nullable_to_non_nullable
              as int,
      tags: null == tags
          ? _value.tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      chapters: null == chapters
          ? _value.chapters
          : chapters // ignore: cast_nullable_to_non_nullable
              as List<Chapter>,
      author: freezed == author
          ? _value.author
          : author // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$NotebookMetadataImplCopyWith<$Res>
    implements $NotebookMetadataCopyWith<$Res> {
  factory _$$NotebookMetadataImplCopyWith(_$NotebookMetadataImpl value,
          $Res Function(_$NotebookMetadataImpl) then) =
      __$$NotebookMetadataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String title,
      int formatVersion,
      DateTime createdAt,
      DateTime modifiedAt,
      String coverStyle,
      int coverColor,
      String paperType,
      int paperColor,
      int pageCount,
      List<String> tags,
      List<Chapter> chapters,
      String? author,
      String? description});
}

/// @nodoc
class __$$NotebookMetadataImplCopyWithImpl<$Res>
    extends _$NotebookMetadataCopyWithImpl<$Res, _$NotebookMetadataImpl>
    implements _$$NotebookMetadataImplCopyWith<$Res> {
  __$$NotebookMetadataImplCopyWithImpl(_$NotebookMetadataImpl _value,
      $Res Function(_$NotebookMetadataImpl) _then)
      : super(_value, _then);

  /// Create a copy of NotebookMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? title = null,
    Object? formatVersion = null,
    Object? createdAt = null,
    Object? modifiedAt = null,
    Object? coverStyle = null,
    Object? coverColor = null,
    Object? paperType = null,
    Object? paperColor = null,
    Object? pageCount = null,
    Object? tags = null,
    Object? chapters = null,
    Object? author = freezed,
    Object? description = freezed,
  }) {
    return _then(_$NotebookMetadataImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      formatVersion: null == formatVersion
          ? _value.formatVersion
          : formatVersion // ignore: cast_nullable_to_non_nullable
              as int,
      createdAt: null == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      modifiedAt: null == modifiedAt
          ? _value.modifiedAt
          : modifiedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      coverStyle: null == coverStyle
          ? _value.coverStyle
          : coverStyle // ignore: cast_nullable_to_non_nullable
              as String,
      coverColor: null == coverColor
          ? _value.coverColor
          : coverColor // ignore: cast_nullable_to_non_nullable
              as int,
      paperType: null == paperType
          ? _value.paperType
          : paperType // ignore: cast_nullable_to_non_nullable
              as String,
      paperColor: null == paperColor
          ? _value.paperColor
          : paperColor // ignore: cast_nullable_to_non_nullable
              as int,
      pageCount: null == pageCount
          ? _value.pageCount
          : pageCount // ignore: cast_nullable_to_non_nullable
              as int,
      tags: null == tags
          ? _value._tags
          : tags // ignore: cast_nullable_to_non_nullable
              as List<String>,
      chapters: null == chapters
          ? _value._chapters
          : chapters // ignore: cast_nullable_to_non_nullable
              as List<Chapter>,
      author: freezed == author
          ? _value.author
          : author // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$NotebookMetadataImpl implements _NotebookMetadata {
  const _$NotebookMetadataImpl(
      {required this.id,
      required this.title,
      this.formatVersion = 1,
      required this.createdAt,
      required this.modifiedAt,
      this.coverStyle = 'default',
      this.coverColor = 0xFF1565C0,
      this.paperType = 'lined',
      this.paperColor = 0xFFFFFFFF,
      this.pageCount = 0,
      final List<String> tags = const [],
      final List<Chapter> chapters = const [],
      this.author,
      this.description})
      : _tags = tags,
        _chapters = chapters;

  factory _$NotebookMetadataImpl.fromJson(Map<String, dynamic> json) =>
      _$$NotebookMetadataImplFromJson(json);

  @override
  final String id;
  @override
  final String title;
  @override
  @JsonKey()
  final int formatVersion;
  @override
  final DateTime createdAt;
  @override
  final DateTime modifiedAt;
  @override
  @JsonKey()
  final String coverStyle;
  @override
  @JsonKey()
  final int coverColor;
// Material Blue 800
  @override
  @JsonKey()
  final String paperType;
// blank, lined, grid, dotted
  @override
  @JsonKey()
  final int paperColor;
  @override
  @JsonKey()
  final int pageCount;
  final List<String> _tags;
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  final List<Chapter> _chapters;
  @override
  @JsonKey()
  List<Chapter> get chapters {
    if (_chapters is EqualUnmodifiableListView) return _chapters;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_chapters);
  }

  @override
  final String? author;
  @override
  final String? description;

  @override
  String toString() {
    return 'NotebookMetadata(id: $id, title: $title, formatVersion: $formatVersion, createdAt: $createdAt, modifiedAt: $modifiedAt, coverStyle: $coverStyle, coverColor: $coverColor, paperType: $paperType, paperColor: $paperColor, pageCount: $pageCount, tags: $tags, chapters: $chapters, author: $author, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$NotebookMetadataImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.title, title) || other.title == title) &&
            (identical(other.formatVersion, formatVersion) ||
                other.formatVersion == formatVersion) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.modifiedAt, modifiedAt) ||
                other.modifiedAt == modifiedAt) &&
            (identical(other.coverStyle, coverStyle) ||
                other.coverStyle == coverStyle) &&
            (identical(other.coverColor, coverColor) ||
                other.coverColor == coverColor) &&
            (identical(other.paperType, paperType) ||
                other.paperType == paperType) &&
            (identical(other.paperColor, paperColor) ||
                other.paperColor == paperColor) &&
            (identical(other.pageCount, pageCount) ||
                other.pageCount == pageCount) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            const DeepCollectionEquality().equals(other._chapters, _chapters) &&
            (identical(other.author, author) || other.author == author) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      title,
      formatVersion,
      createdAt,
      modifiedAt,
      coverStyle,
      coverColor,
      paperType,
      paperColor,
      pageCount,
      const DeepCollectionEquality().hash(_tags),
      const DeepCollectionEquality().hash(_chapters),
      author,
      description);

  /// Create a copy of NotebookMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$NotebookMetadataImplCopyWith<_$NotebookMetadataImpl> get copyWith =>
      __$$NotebookMetadataImplCopyWithImpl<_$NotebookMetadataImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$NotebookMetadataImplToJson(
      this,
    );
  }
}

abstract class _NotebookMetadata implements NotebookMetadata {
  const factory _NotebookMetadata(
      {required final String id,
      required final String title,
      final int formatVersion,
      required final DateTime createdAt,
      required final DateTime modifiedAt,
      final String coverStyle,
      final int coverColor,
      final String paperType,
      final int paperColor,
      final int pageCount,
      final List<String> tags,
      final List<Chapter> chapters,
      final String? author,
      final String? description}) = _$NotebookMetadataImpl;

  factory _NotebookMetadata.fromJson(Map<String, dynamic> json) =
      _$NotebookMetadataImpl.fromJson;

  @override
  String get id;
  @override
  String get title;
  @override
  int get formatVersion;
  @override
  DateTime get createdAt;
  @override
  DateTime get modifiedAt;
  @override
  String get coverStyle;
  @override
  int get coverColor; // Material Blue 800
  @override
  String get paperType; // blank, lined, grid, dotted
  @override
  int get paperColor;
  @override
  int get pageCount;
  @override
  List<String> get tags;
  @override
  List<Chapter> get chapters;
  @override
  String? get author;
  @override
  String? get description;

  /// Create a copy of NotebookMetadata
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$NotebookMetadataImplCopyWith<_$NotebookMetadataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DocumentStructure _$DocumentStructureFromJson(Map<String, dynamic> json) {
  return _DocumentStructure.fromJson(json);
}

/// @nodoc
mixin _$DocumentStructure {
  String get notebookId => throw _privateConstructorUsedError;
  int get formatVersion => throw _privateConstructorUsedError;
  List<PageEntry> get pages => throw _privateConstructorUsedError;

  /// Serializes this DocumentStructure to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DocumentStructure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DocumentStructureCopyWith<DocumentStructure> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DocumentStructureCopyWith<$Res> {
  factory $DocumentStructureCopyWith(
          DocumentStructure value, $Res Function(DocumentStructure) then) =
      _$DocumentStructureCopyWithImpl<$Res, DocumentStructure>;
  @useResult
  $Res call({String notebookId, int formatVersion, List<PageEntry> pages});
}

/// @nodoc
class _$DocumentStructureCopyWithImpl<$Res, $Val extends DocumentStructure>
    implements $DocumentStructureCopyWith<$Res> {
  _$DocumentStructureCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DocumentStructure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? notebookId = null,
    Object? formatVersion = null,
    Object? pages = null,
  }) {
    return _then(_value.copyWith(
      notebookId: null == notebookId
          ? _value.notebookId
          : notebookId // ignore: cast_nullable_to_non_nullable
              as String,
      formatVersion: null == formatVersion
          ? _value.formatVersion
          : formatVersion // ignore: cast_nullable_to_non_nullable
              as int,
      pages: null == pages
          ? _value.pages
          : pages // ignore: cast_nullable_to_non_nullable
              as List<PageEntry>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$DocumentStructureImplCopyWith<$Res>
    implements $DocumentStructureCopyWith<$Res> {
  factory _$$DocumentStructureImplCopyWith(_$DocumentStructureImpl value,
          $Res Function(_$DocumentStructureImpl) then) =
      __$$DocumentStructureImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String notebookId, int formatVersion, List<PageEntry> pages});
}

/// @nodoc
class __$$DocumentStructureImplCopyWithImpl<$Res>
    extends _$DocumentStructureCopyWithImpl<$Res, _$DocumentStructureImpl>
    implements _$$DocumentStructureImplCopyWith<$Res> {
  __$$DocumentStructureImplCopyWithImpl(_$DocumentStructureImpl _value,
      $Res Function(_$DocumentStructureImpl) _then)
      : super(_value, _then);

  /// Create a copy of DocumentStructure
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? notebookId = null,
    Object? formatVersion = null,
    Object? pages = null,
  }) {
    return _then(_$DocumentStructureImpl(
      notebookId: null == notebookId
          ? _value.notebookId
          : notebookId // ignore: cast_nullable_to_non_nullable
              as String,
      formatVersion: null == formatVersion
          ? _value.formatVersion
          : formatVersion // ignore: cast_nullable_to_non_nullable
              as int,
      pages: null == pages
          ? _value._pages
          : pages // ignore: cast_nullable_to_non_nullable
              as List<PageEntry>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$DocumentStructureImpl implements _DocumentStructure {
  const _$DocumentStructureImpl(
      {required this.notebookId,
      this.formatVersion = 1,
      required final List<PageEntry> pages})
      : _pages = pages;

  factory _$DocumentStructureImpl.fromJson(Map<String, dynamic> json) =>
      _$$DocumentStructureImplFromJson(json);

  @override
  final String notebookId;
  @override
  @JsonKey()
  final int formatVersion;
  final List<PageEntry> _pages;
  @override
  List<PageEntry> get pages {
    if (_pages is EqualUnmodifiableListView) return _pages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_pages);
  }

  @override
  String toString() {
    return 'DocumentStructure(notebookId: $notebookId, formatVersion: $formatVersion, pages: $pages)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DocumentStructureImpl &&
            (identical(other.notebookId, notebookId) ||
                other.notebookId == notebookId) &&
            (identical(other.formatVersion, formatVersion) ||
                other.formatVersion == formatVersion) &&
            const DeepCollectionEquality().equals(other._pages, _pages));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, notebookId, formatVersion,
      const DeepCollectionEquality().hash(_pages));

  /// Create a copy of DocumentStructure
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DocumentStructureImplCopyWith<_$DocumentStructureImpl> get copyWith =>
      __$$DocumentStructureImplCopyWithImpl<_$DocumentStructureImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DocumentStructureImplToJson(
      this,
    );
  }
}

abstract class _DocumentStructure implements DocumentStructure {
  const factory _DocumentStructure(
      {required final String notebookId,
      final int formatVersion,
      required final List<PageEntry> pages}) = _$DocumentStructureImpl;

  factory _DocumentStructure.fromJson(Map<String, dynamic> json) =
      _$DocumentStructureImpl.fromJson;

  @override
  String get notebookId;
  @override
  int get formatVersion;
  @override
  List<PageEntry> get pages;

  /// Create a copy of DocumentStructure
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DocumentStructureImplCopyWith<_$DocumentStructureImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PageEntry _$PageEntryFromJson(Map<String, dynamic> json) {
  return _PageEntry.fromJson(json);
}

/// @nodoc
mixin _$PageEntry {
  String get pageId => throw _privateConstructorUsedError;
  int get pageNumber => throw _privateConstructorUsedError;
  String get fileName =>
      throw _privateConstructorUsedError; // es. "page_001.json"
  double get width => throw _privateConstructorUsedError;
  double get height => throw _privateConstructorUsedError;
  String? get thumbnailFile => throw _privateConstructorUsedError;
  String? get chapterId => throw _privateConstructorUsedError;
  DateTime? get lastModified => throw _privateConstructorUsedError;

  /// Serializes this PageEntry to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PageEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PageEntryCopyWith<PageEntry> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PageEntryCopyWith<$Res> {
  factory $PageEntryCopyWith(PageEntry value, $Res Function(PageEntry) then) =
      _$PageEntryCopyWithImpl<$Res, PageEntry>;
  @useResult
  $Res call(
      {String pageId,
      int pageNumber,
      String fileName,
      double width,
      double height,
      String? thumbnailFile,
      String? chapterId,
      DateTime? lastModified});
}

/// @nodoc
class _$PageEntryCopyWithImpl<$Res, $Val extends PageEntry>
    implements $PageEntryCopyWith<$Res> {
  _$PageEntryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PageEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pageId = null,
    Object? pageNumber = null,
    Object? fileName = null,
    Object? width = null,
    Object? height = null,
    Object? thumbnailFile = freezed,
    Object? chapterId = freezed,
    Object? lastModified = freezed,
  }) {
    return _then(_value.copyWith(
      pageId: null == pageId
          ? _value.pageId
          : pageId // ignore: cast_nullable_to_non_nullable
              as String,
      pageNumber: null == pageNumber
          ? _value.pageNumber
          : pageNumber // ignore: cast_nullable_to_non_nullable
              as int,
      fileName: null == fileName
          ? _value.fileName
          : fileName // ignore: cast_nullable_to_non_nullable
              as String,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      thumbnailFile: freezed == thumbnailFile
          ? _value.thumbnailFile
          : thumbnailFile // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterId: freezed == chapterId
          ? _value.chapterId
          : chapterId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastModified: freezed == lastModified
          ? _value.lastModified
          : lastModified // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PageEntryImplCopyWith<$Res>
    implements $PageEntryCopyWith<$Res> {
  factory _$$PageEntryImplCopyWith(
          _$PageEntryImpl value, $Res Function(_$PageEntryImpl) then) =
      __$$PageEntryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String pageId,
      int pageNumber,
      String fileName,
      double width,
      double height,
      String? thumbnailFile,
      String? chapterId,
      DateTime? lastModified});
}

/// @nodoc
class __$$PageEntryImplCopyWithImpl<$Res>
    extends _$PageEntryCopyWithImpl<$Res, _$PageEntryImpl>
    implements _$$PageEntryImplCopyWith<$Res> {
  __$$PageEntryImplCopyWithImpl(
      _$PageEntryImpl _value, $Res Function(_$PageEntryImpl) _then)
      : super(_value, _then);

  /// Create a copy of PageEntry
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pageId = null,
    Object? pageNumber = null,
    Object? fileName = null,
    Object? width = null,
    Object? height = null,
    Object? thumbnailFile = freezed,
    Object? chapterId = freezed,
    Object? lastModified = freezed,
  }) {
    return _then(_$PageEntryImpl(
      pageId: null == pageId
          ? _value.pageId
          : pageId // ignore: cast_nullable_to_non_nullable
              as String,
      pageNumber: null == pageNumber
          ? _value.pageNumber
          : pageNumber // ignore: cast_nullable_to_non_nullable
              as int,
      fileName: null == fileName
          ? _value.fileName
          : fileName // ignore: cast_nullable_to_non_nullable
              as String,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      thumbnailFile: freezed == thumbnailFile
          ? _value.thumbnailFile
          : thumbnailFile // ignore: cast_nullable_to_non_nullable
              as String?,
      chapterId: freezed == chapterId
          ? _value.chapterId
          : chapterId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastModified: freezed == lastModified
          ? _value.lastModified
          : lastModified // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PageEntryImpl implements _PageEntry {
  const _$PageEntryImpl(
      {required this.pageId,
      required this.pageNumber,
      required this.fileName,
      this.width = 595.0,
      this.height = 842.0,
      this.thumbnailFile,
      this.chapterId,
      this.lastModified});

  factory _$PageEntryImpl.fromJson(Map<String, dynamic> json) =>
      _$$PageEntryImplFromJson(json);

  @override
  final String pageId;
  @override
  final int pageNumber;
  @override
  final String fileName;
// es. "page_001.json"
  @override
  @JsonKey()
  final double width;
  @override
  @JsonKey()
  final double height;
  @override
  final String? thumbnailFile;
  @override
  final String? chapterId;
  @override
  final DateTime? lastModified;

  @override
  String toString() {
    return 'PageEntry(pageId: $pageId, pageNumber: $pageNumber, fileName: $fileName, width: $width, height: $height, thumbnailFile: $thumbnailFile, chapterId: $chapterId, lastModified: $lastModified)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PageEntryImpl &&
            (identical(other.pageId, pageId) || other.pageId == pageId) &&
            (identical(other.pageNumber, pageNumber) ||
                other.pageNumber == pageNumber) &&
            (identical(other.fileName, fileName) ||
                other.fileName == fileName) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height) &&
            (identical(other.thumbnailFile, thumbnailFile) ||
                other.thumbnailFile == thumbnailFile) &&
            (identical(other.chapterId, chapterId) ||
                other.chapterId == chapterId) &&
            (identical(other.lastModified, lastModified) ||
                other.lastModified == lastModified));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, pageId, pageNumber, fileName,
      width, height, thumbnailFile, chapterId, lastModified);

  /// Create a copy of PageEntry
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PageEntryImplCopyWith<_$PageEntryImpl> get copyWith =>
      __$$PageEntryImplCopyWithImpl<_$PageEntryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PageEntryImplToJson(
      this,
    );
  }
}

abstract class _PageEntry implements PageEntry {
  const factory _PageEntry(
      {required final String pageId,
      required final int pageNumber,
      required final String fileName,
      final double width,
      final double height,
      final String? thumbnailFile,
      final String? chapterId,
      final DateTime? lastModified}) = _$PageEntryImpl;

  factory _PageEntry.fromJson(Map<String, dynamic> json) =
      _$PageEntryImpl.fromJson;

  @override
  String get pageId;
  @override
  int get pageNumber;
  @override
  String get fileName; // es. "page_001.json"
  @override
  double get width;
  @override
  double get height;
  @override
  String? get thumbnailFile;
  @override
  String? get chapterId;
  @override
  DateTime? get lastModified;

  /// Create a copy of PageEntry
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PageEntryImplCopyWith<_$PageEntryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PageData _$PageDataFromJson(Map<String, dynamic> json) {
  return _PageData.fromJson(json);
}

/// @nodoc
mixin _$PageData {
  String get pageId => throw _privateConstructorUsedError;
  int get pageNumber => throw _privateConstructorUsedError;
  double get width => throw _privateConstructorUsedError;
  double get height => throw _privateConstructorUsedError;
  RenderingLayers get layers => throw _privateConstructorUsedError;
  List<String> get assetReferences => throw _privateConstructorUsedError;
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get modifiedAt => throw _privateConstructorUsedError;

  /// Selectable/searchable text overlaid on an imported PDF page. Null for
  /// ordinary pages. Populated at import time from the PDF's embedded text
  /// layer (see [PdfTextLayer]); it is overlay-only metadata and never
  /// painted, so it stays out of the z-ordered [RenderingLayers.content].
  PdfTextLayer? get pdfTextLayer => throw _privateConstructorUsedError;

  /// Serializes this PageData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PageData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PageDataCopyWith<PageData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PageDataCopyWith<$Res> {
  factory $PageDataCopyWith(PageData value, $Res Function(PageData) then) =
      _$PageDataCopyWithImpl<$Res, PageData>;
  @useResult
  $Res call(
      {String pageId,
      int pageNumber,
      double width,
      double height,
      RenderingLayers layers,
      List<String> assetReferences,
      DateTime? createdAt,
      DateTime? modifiedAt,
      PdfTextLayer? pdfTextLayer});

  $RenderingLayersCopyWith<$Res> get layers;
  $PdfTextLayerCopyWith<$Res>? get pdfTextLayer;
}

/// @nodoc
class _$PageDataCopyWithImpl<$Res, $Val extends PageData>
    implements $PageDataCopyWith<$Res> {
  _$PageDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PageData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pageId = null,
    Object? pageNumber = null,
    Object? width = null,
    Object? height = null,
    Object? layers = null,
    Object? assetReferences = null,
    Object? createdAt = freezed,
    Object? modifiedAt = freezed,
    Object? pdfTextLayer = freezed,
  }) {
    return _then(_value.copyWith(
      pageId: null == pageId
          ? _value.pageId
          : pageId // ignore: cast_nullable_to_non_nullable
              as String,
      pageNumber: null == pageNumber
          ? _value.pageNumber
          : pageNumber // ignore: cast_nullable_to_non_nullable
              as int,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      layers: null == layers
          ? _value.layers
          : layers // ignore: cast_nullable_to_non_nullable
              as RenderingLayers,
      assetReferences: null == assetReferences
          ? _value.assetReferences
          : assetReferences // ignore: cast_nullable_to_non_nullable
              as List<String>,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      modifiedAt: freezed == modifiedAt
          ? _value.modifiedAt
          : modifiedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      pdfTextLayer: freezed == pdfTextLayer
          ? _value.pdfTextLayer
          : pdfTextLayer // ignore: cast_nullable_to_non_nullable
              as PdfTextLayer?,
    ) as $Val);
  }

  /// Create a copy of PageData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $RenderingLayersCopyWith<$Res> get layers {
    return $RenderingLayersCopyWith<$Res>(_value.layers, (value) {
      return _then(_value.copyWith(layers: value) as $Val);
    });
  }

  /// Create a copy of PageData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $PdfTextLayerCopyWith<$Res>? get pdfTextLayer {
    if (_value.pdfTextLayer == null) {
      return null;
    }

    return $PdfTextLayerCopyWith<$Res>(_value.pdfTextLayer!, (value) {
      return _then(_value.copyWith(pdfTextLayer: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$PageDataImplCopyWith<$Res>
    implements $PageDataCopyWith<$Res> {
  factory _$$PageDataImplCopyWith(
          _$PageDataImpl value, $Res Function(_$PageDataImpl) then) =
      __$$PageDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String pageId,
      int pageNumber,
      double width,
      double height,
      RenderingLayers layers,
      List<String> assetReferences,
      DateTime? createdAt,
      DateTime? modifiedAt,
      PdfTextLayer? pdfTextLayer});

  @override
  $RenderingLayersCopyWith<$Res> get layers;
  @override
  $PdfTextLayerCopyWith<$Res>? get pdfTextLayer;
}

/// @nodoc
class __$$PageDataImplCopyWithImpl<$Res>
    extends _$PageDataCopyWithImpl<$Res, _$PageDataImpl>
    implements _$$PageDataImplCopyWith<$Res> {
  __$$PageDataImplCopyWithImpl(
      _$PageDataImpl _value, $Res Function(_$PageDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of PageData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pageId = null,
    Object? pageNumber = null,
    Object? width = null,
    Object? height = null,
    Object? layers = null,
    Object? assetReferences = null,
    Object? createdAt = freezed,
    Object? modifiedAt = freezed,
    Object? pdfTextLayer = freezed,
  }) {
    return _then(_$PageDataImpl(
      pageId: null == pageId
          ? _value.pageId
          : pageId // ignore: cast_nullable_to_non_nullable
              as String,
      pageNumber: null == pageNumber
          ? _value.pageNumber
          : pageNumber // ignore: cast_nullable_to_non_nullable
              as int,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      layers: null == layers
          ? _value.layers
          : layers // ignore: cast_nullable_to_non_nullable
              as RenderingLayers,
      assetReferences: null == assetReferences
          ? _value._assetReferences
          : assetReferences // ignore: cast_nullable_to_non_nullable
              as List<String>,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      modifiedAt: freezed == modifiedAt
          ? _value.modifiedAt
          : modifiedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      pdfTextLayer: freezed == pdfTextLayer
          ? _value.pdfTextLayer
          : pdfTextLayer // ignore: cast_nullable_to_non_nullable
              as PdfTextLayer?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PageDataImpl implements _PageData {
  const _$PageDataImpl(
      {required this.pageId,
      required this.pageNumber,
      required this.width,
      required this.height,
      required this.layers,
      final List<String> assetReferences = const [],
      this.createdAt,
      this.modifiedAt,
      this.pdfTextLayer})
      : _assetReferences = assetReferences;

  factory _$PageDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$PageDataImplFromJson(json);

  @override
  final String pageId;
  @override
  final int pageNumber;
  @override
  final double width;
  @override
  final double height;
  @override
  final RenderingLayers layers;
  final List<String> _assetReferences;
  @override
  @JsonKey()
  List<String> get assetReferences {
    if (_assetReferences is EqualUnmodifiableListView) return _assetReferences;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_assetReferences);
  }

  @override
  final DateTime? createdAt;
  @override
  final DateTime? modifiedAt;

  /// Selectable/searchable text overlaid on an imported PDF page. Null for
  /// ordinary pages. Populated at import time from the PDF's embedded text
  /// layer (see [PdfTextLayer]); it is overlay-only metadata and never
  /// painted, so it stays out of the z-ordered [RenderingLayers.content].
  @override
  final PdfTextLayer? pdfTextLayer;

  @override
  String toString() {
    return 'PageData(pageId: $pageId, pageNumber: $pageNumber, width: $width, height: $height, layers: $layers, assetReferences: $assetReferences, createdAt: $createdAt, modifiedAt: $modifiedAt, pdfTextLayer: $pdfTextLayer)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PageDataImpl &&
            (identical(other.pageId, pageId) || other.pageId == pageId) &&
            (identical(other.pageNumber, pageNumber) ||
                other.pageNumber == pageNumber) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height) &&
            (identical(other.layers, layers) || other.layers == layers) &&
            const DeepCollectionEquality()
                .equals(other._assetReferences, _assetReferences) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.modifiedAt, modifiedAt) ||
                other.modifiedAt == modifiedAt) &&
            (identical(other.pdfTextLayer, pdfTextLayer) ||
                other.pdfTextLayer == pdfTextLayer));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      pageId,
      pageNumber,
      width,
      height,
      layers,
      const DeepCollectionEquality().hash(_assetReferences),
      createdAt,
      modifiedAt,
      pdfTextLayer);

  /// Create a copy of PageData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PageDataImplCopyWith<_$PageDataImpl> get copyWith =>
      __$$PageDataImplCopyWithImpl<_$PageDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PageDataImplToJson(
      this,
    );
  }
}

abstract class _PageData implements PageData {
  const factory _PageData(
      {required final String pageId,
      required final int pageNumber,
      required final double width,
      required final double height,
      required final RenderingLayers layers,
      final List<String> assetReferences,
      final DateTime? createdAt,
      final DateTime? modifiedAt,
      final PdfTextLayer? pdfTextLayer}) = _$PageDataImpl;

  factory _PageData.fromJson(Map<String, dynamic> json) =
      _$PageDataImpl.fromJson;

  @override
  String get pageId;
  @override
  int get pageNumber;
  @override
  double get width;
  @override
  double get height;
  @override
  RenderingLayers get layers;
  @override
  List<String> get assetReferences;
  @override
  DateTime? get createdAt;
  @override
  DateTime? get modifiedAt;

  /// Selectable/searchable text overlaid on an imported PDF page. Null for
  /// ordinary pages. Populated at import time from the PDF's embedded text
  /// layer (see [PdfTextLayer]); it is overlay-only metadata and never
  /// painted, so it stays out of the z-ordered [RenderingLayers.content].
  @override
  PdfTextLayer? get pdfTextLayer;

  /// Create a copy of PageData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PageDataImplCopyWith<_$PageDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

RenderingLayers _$RenderingLayersFromJson(Map<String, dynamic> json) {
  return _RenderingLayers.fromJson(json);
}

/// @nodoc
mixin _$RenderingLayers {
  BackgroundLayer get background => throw _privateConstructorUsedError;
  List<ContentElement> get content => throw _privateConstructorUsedError;

  /// Serializes this RenderingLayers to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RenderingLayers
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RenderingLayersCopyWith<RenderingLayers> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RenderingLayersCopyWith<$Res> {
  factory $RenderingLayersCopyWith(
          RenderingLayers value, $Res Function(RenderingLayers) then) =
      _$RenderingLayersCopyWithImpl<$Res, RenderingLayers>;
  @useResult
  $Res call({BackgroundLayer background, List<ContentElement> content});

  $BackgroundLayerCopyWith<$Res> get background;
}

/// @nodoc
class _$RenderingLayersCopyWithImpl<$Res, $Val extends RenderingLayers>
    implements $RenderingLayersCopyWith<$Res> {
  _$RenderingLayersCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RenderingLayers
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? background = null,
    Object? content = null,
  }) {
    return _then(_value.copyWith(
      background: null == background
          ? _value.background
          : background // ignore: cast_nullable_to_non_nullable
              as BackgroundLayer,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as List<ContentElement>,
    ) as $Val);
  }

  /// Create a copy of RenderingLayers
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $BackgroundLayerCopyWith<$Res> get background {
    return $BackgroundLayerCopyWith<$Res>(_value.background, (value) {
      return _then(_value.copyWith(background: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$RenderingLayersImplCopyWith<$Res>
    implements $RenderingLayersCopyWith<$Res> {
  factory _$$RenderingLayersImplCopyWith(_$RenderingLayersImpl value,
          $Res Function(_$RenderingLayersImpl) then) =
      __$$RenderingLayersImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({BackgroundLayer background, List<ContentElement> content});

  @override
  $BackgroundLayerCopyWith<$Res> get background;
}

/// @nodoc
class __$$RenderingLayersImplCopyWithImpl<$Res>
    extends _$RenderingLayersCopyWithImpl<$Res, _$RenderingLayersImpl>
    implements _$$RenderingLayersImplCopyWith<$Res> {
  __$$RenderingLayersImplCopyWithImpl(
      _$RenderingLayersImpl _value, $Res Function(_$RenderingLayersImpl) _then)
      : super(_value, _then);

  /// Create a copy of RenderingLayers
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? background = null,
    Object? content = null,
  }) {
    return _then(_$RenderingLayersImpl(
      background: null == background
          ? _value.background
          : background // ignore: cast_nullable_to_non_nullable
              as BackgroundLayer,
      content: null == content
          ? _value._content
          : content // ignore: cast_nullable_to_non_nullable
              as List<ContentElement>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$RenderingLayersImpl implements _RenderingLayers {
  const _$RenderingLayersImpl(
      {this.background = const BackgroundLayer(),
      final List<ContentElement> content = const []})
      : _content = content;

  factory _$RenderingLayersImpl.fromJson(Map<String, dynamic> json) =>
      _$$RenderingLayersImplFromJson(json);

  @override
  @JsonKey()
  final BackgroundLayer background;
  final List<ContentElement> _content;
  @override
  @JsonKey()
  List<ContentElement> get content {
    if (_content is EqualUnmodifiableListView) return _content;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_content);
  }

  @override
  String toString() {
    return 'RenderingLayers(background: $background, content: $content)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RenderingLayersImpl &&
            (identical(other.background, background) ||
                other.background == background) &&
            const DeepCollectionEquality().equals(other._content, _content));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, background, const DeepCollectionEquality().hash(_content));

  /// Create a copy of RenderingLayers
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RenderingLayersImplCopyWith<_$RenderingLayersImpl> get copyWith =>
      __$$RenderingLayersImplCopyWithImpl<_$RenderingLayersImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RenderingLayersImplToJson(
      this,
    );
  }
}

abstract class _RenderingLayers implements RenderingLayers {
  const factory _RenderingLayers(
      {final BackgroundLayer background,
      final List<ContentElement> content}) = _$RenderingLayersImpl;

  factory _RenderingLayers.fromJson(Map<String, dynamic> json) =
      _$RenderingLayersImpl.fromJson;

  @override
  BackgroundLayer get background;
  @override
  List<ContentElement> get content;

  /// Create a copy of RenderingLayers
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RenderingLayersImplCopyWith<_$RenderingLayersImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

BackgroundLayer _$BackgroundLayerFromJson(Map<String, dynamic> json) {
  return _BackgroundLayer.fromJson(json);
}

/// @nodoc
mixin _$BackgroundLayer {
  String get type =>
      throw _privateConstructorUsedError; // blank, lined, grid, dotted
  int get color => throw _privateConstructorUsedError;
  double get lineSpacing => throw _privateConstructorUsedError;
  int get lineColor => throw _privateConstructorUsedError;
  String? get pdfAsset =>
      throw _privateConstructorUsedError; // path in assets/ se è un PDF annotato
  int get pdfPage => throw _privateConstructorUsedError;

  /// Serializes this BackgroundLayer to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of BackgroundLayer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BackgroundLayerCopyWith<BackgroundLayer> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BackgroundLayerCopyWith<$Res> {
  factory $BackgroundLayerCopyWith(
          BackgroundLayer value, $Res Function(BackgroundLayer) then) =
      _$BackgroundLayerCopyWithImpl<$Res, BackgroundLayer>;
  @useResult
  $Res call(
      {String type,
      int color,
      double lineSpacing,
      int lineColor,
      String? pdfAsset,
      int pdfPage});
}

/// @nodoc
class _$BackgroundLayerCopyWithImpl<$Res, $Val extends BackgroundLayer>
    implements $BackgroundLayerCopyWith<$Res> {
  _$BackgroundLayerCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BackgroundLayer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? color = null,
    Object? lineSpacing = null,
    Object? lineColor = null,
    Object? pdfAsset = freezed,
    Object? pdfPage = null,
  }) {
    return _then(_value.copyWith(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      lineSpacing: null == lineSpacing
          ? _value.lineSpacing
          : lineSpacing // ignore: cast_nullable_to_non_nullable
              as double,
      lineColor: null == lineColor
          ? _value.lineColor
          : lineColor // ignore: cast_nullable_to_non_nullable
              as int,
      pdfAsset: freezed == pdfAsset
          ? _value.pdfAsset
          : pdfAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      pdfPage: null == pdfPage
          ? _value.pdfPage
          : pdfPage // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BackgroundLayerImplCopyWith<$Res>
    implements $BackgroundLayerCopyWith<$Res> {
  factory _$$BackgroundLayerImplCopyWith(_$BackgroundLayerImpl value,
          $Res Function(_$BackgroundLayerImpl) then) =
      __$$BackgroundLayerImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String type,
      int color,
      double lineSpacing,
      int lineColor,
      String? pdfAsset,
      int pdfPage});
}

/// @nodoc
class __$$BackgroundLayerImplCopyWithImpl<$Res>
    extends _$BackgroundLayerCopyWithImpl<$Res, _$BackgroundLayerImpl>
    implements _$$BackgroundLayerImplCopyWith<$Res> {
  __$$BackgroundLayerImplCopyWithImpl(
      _$BackgroundLayerImpl _value, $Res Function(_$BackgroundLayerImpl) _then)
      : super(_value, _then);

  /// Create a copy of BackgroundLayer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? color = null,
    Object? lineSpacing = null,
    Object? lineColor = null,
    Object? pdfAsset = freezed,
    Object? pdfPage = null,
  }) {
    return _then(_$BackgroundLayerImpl(
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      lineSpacing: null == lineSpacing
          ? _value.lineSpacing
          : lineSpacing // ignore: cast_nullable_to_non_nullable
              as double,
      lineColor: null == lineColor
          ? _value.lineColor
          : lineColor // ignore: cast_nullable_to_non_nullable
              as int,
      pdfAsset: freezed == pdfAsset
          ? _value.pdfAsset
          : pdfAsset // ignore: cast_nullable_to_non_nullable
              as String?,
      pdfPage: null == pdfPage
          ? _value.pdfPage
          : pdfPage // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$BackgroundLayerImpl implements _BackgroundLayer {
  const _$BackgroundLayerImpl(
      {this.type = 'lined',
      this.color = 0xFFFFFFFF,
      this.lineSpacing = 30.0,
      this.lineColor = 0xFFB0B8C0,
      this.pdfAsset,
      this.pdfPage = 0});

  factory _$BackgroundLayerImpl.fromJson(Map<String, dynamic> json) =>
      _$$BackgroundLayerImplFromJson(json);

  @override
  @JsonKey()
  final String type;
// blank, lined, grid, dotted
  @override
  @JsonKey()
  final int color;
  @override
  @JsonKey()
  final double lineSpacing;
  @override
  @JsonKey()
  final int lineColor;
  @override
  final String? pdfAsset;
// path in assets/ se è un PDF annotato
  @override
  @JsonKey()
  final int pdfPage;

  @override
  String toString() {
    return 'BackgroundLayer(type: $type, color: $color, lineSpacing: $lineSpacing, lineColor: $lineColor, pdfAsset: $pdfAsset, pdfPage: $pdfPage)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BackgroundLayerImpl &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.lineSpacing, lineSpacing) ||
                other.lineSpacing == lineSpacing) &&
            (identical(other.lineColor, lineColor) ||
                other.lineColor == lineColor) &&
            (identical(other.pdfAsset, pdfAsset) ||
                other.pdfAsset == pdfAsset) &&
            (identical(other.pdfPage, pdfPage) || other.pdfPage == pdfPage));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, type, color, lineSpacing, lineColor, pdfAsset, pdfPage);

  /// Create a copy of BackgroundLayer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BackgroundLayerImplCopyWith<_$BackgroundLayerImpl> get copyWith =>
      __$$BackgroundLayerImplCopyWithImpl<_$BackgroundLayerImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BackgroundLayerImplToJson(
      this,
    );
  }
}

abstract class _BackgroundLayer implements BackgroundLayer {
  const factory _BackgroundLayer(
      {final String type,
      final int color,
      final double lineSpacing,
      final int lineColor,
      final String? pdfAsset,
      final int pdfPage}) = _$BackgroundLayerImpl;

  factory _BackgroundLayer.fromJson(Map<String, dynamic> json) =
      _$BackgroundLayerImpl.fromJson;

  @override
  String get type; // blank, lined, grid, dotted
  @override
  int get color;
  @override
  double get lineSpacing;
  @override
  int get lineColor;
  @override
  String? get pdfAsset; // path in assets/ se è un PDF annotato
  @override
  int get pdfPage;

  /// Create a copy of BackgroundLayer
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BackgroundLayerImplCopyWith<_$BackgroundLayerImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ContentElement _$ContentElementFromJson(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'stroke':
      return StrokeElement.fromJson(json);
    case 'text':
      return TextElement.fromJson(json);
    case 'image':
      return ImageElement.fromJson(json);
    case 'shape':
      return ShapeElement.fromJson(json);
    case 'math':
      return MathElement.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'type', 'ContentElement',
          'Invalid union type "${json['type']}"!');
  }
}

/// @nodoc
mixin _$ContentElement {
  String get id => throw _privateConstructorUsedError;
  int get zIndex => throw _privateConstructorUsedError;
  Object get data => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, int zIndex, StrokeData data) stroke,
    required TResult Function(String id, int zIndex, TextData data) text,
    required TResult Function(String id, int zIndex, ImageData data) image,
    required TResult Function(String id, int zIndex, ShapeData data) shape,
    required TResult Function(String id, int zIndex, MathData data) math,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, int zIndex, StrokeData data)? stroke,
    TResult? Function(String id, int zIndex, TextData data)? text,
    TResult? Function(String id, int zIndex, ImageData data)? image,
    TResult? Function(String id, int zIndex, ShapeData data)? shape,
    TResult? Function(String id, int zIndex, MathData data)? math,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, int zIndex, StrokeData data)? stroke,
    TResult Function(String id, int zIndex, TextData data)? text,
    TResult Function(String id, int zIndex, ImageData data)? image,
    TResult Function(String id, int zIndex, ShapeData data)? shape,
    TResult Function(String id, int zIndex, MathData data)? math,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StrokeElement value) stroke,
    required TResult Function(TextElement value) text,
    required TResult Function(ImageElement value) image,
    required TResult Function(ShapeElement value) shape,
    required TResult Function(MathElement value) math,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StrokeElement value)? stroke,
    TResult? Function(TextElement value)? text,
    TResult? Function(ImageElement value)? image,
    TResult? Function(ShapeElement value)? shape,
    TResult? Function(MathElement value)? math,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StrokeElement value)? stroke,
    TResult Function(TextElement value)? text,
    TResult Function(ImageElement value)? image,
    TResult Function(ShapeElement value)? shape,
    TResult Function(MathElement value)? math,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;

  /// Serializes this ContentElement to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ContentElementCopyWith<ContentElement> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ContentElementCopyWith<$Res> {
  factory $ContentElementCopyWith(
          ContentElement value, $Res Function(ContentElement) then) =
      _$ContentElementCopyWithImpl<$Res, ContentElement>;
  @useResult
  $Res call({String id, int zIndex});
}

/// @nodoc
class _$ContentElementCopyWithImpl<$Res, $Val extends ContentElement>
    implements $ContentElementCopyWith<$Res> {
  _$ContentElementCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? zIndex = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      zIndex: null == zIndex
          ? _value.zIndex
          : zIndex // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$StrokeElementImplCopyWith<$Res>
    implements $ContentElementCopyWith<$Res> {
  factory _$$StrokeElementImplCopyWith(
          _$StrokeElementImpl value, $Res Function(_$StrokeElementImpl) then) =
      __$$StrokeElementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, int zIndex, StrokeData data});

  $StrokeDataCopyWith<$Res> get data;
}

/// @nodoc
class __$$StrokeElementImplCopyWithImpl<$Res>
    extends _$ContentElementCopyWithImpl<$Res, _$StrokeElementImpl>
    implements _$$StrokeElementImplCopyWith<$Res> {
  __$$StrokeElementImplCopyWithImpl(
      _$StrokeElementImpl _value, $Res Function(_$StrokeElementImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? zIndex = null,
    Object? data = null,
  }) {
    return _then(_$StrokeElementImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      zIndex: null == zIndex
          ? _value.zIndex
          : zIndex // ignore: cast_nullable_to_non_nullable
              as int,
      data: null == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as StrokeData,
    ));
  }

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $StrokeDataCopyWith<$Res> get data {
    return $StrokeDataCopyWith<$Res>(_value.data, (value) {
      return _then(_value.copyWith(data: value));
    });
  }
}

/// @nodoc
@JsonSerializable()
class _$StrokeElementImpl implements StrokeElement {
  const _$StrokeElementImpl(
      {required this.id,
      required this.zIndex,
      required this.data,
      final String? $type})
      : $type = $type ?? 'stroke';

  factory _$StrokeElementImpl.fromJson(Map<String, dynamic> json) =>
      _$$StrokeElementImplFromJson(json);

  @override
  final String id;
  @override
  final int zIndex;
  @override
  final StrokeData data;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'ContentElement.stroke(id: $id, zIndex: $zIndex, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StrokeElementImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.zIndex, zIndex) || other.zIndex == zIndex) &&
            (identical(other.data, data) || other.data == data));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, zIndex, data);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StrokeElementImplCopyWith<_$StrokeElementImpl> get copyWith =>
      __$$StrokeElementImplCopyWithImpl<_$StrokeElementImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, int zIndex, StrokeData data) stroke,
    required TResult Function(String id, int zIndex, TextData data) text,
    required TResult Function(String id, int zIndex, ImageData data) image,
    required TResult Function(String id, int zIndex, ShapeData data) shape,
    required TResult Function(String id, int zIndex, MathData data) math,
  }) {
    return stroke(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, int zIndex, StrokeData data)? stroke,
    TResult? Function(String id, int zIndex, TextData data)? text,
    TResult? Function(String id, int zIndex, ImageData data)? image,
    TResult? Function(String id, int zIndex, ShapeData data)? shape,
    TResult? Function(String id, int zIndex, MathData data)? math,
  }) {
    return stroke?.call(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, int zIndex, StrokeData data)? stroke,
    TResult Function(String id, int zIndex, TextData data)? text,
    TResult Function(String id, int zIndex, ImageData data)? image,
    TResult Function(String id, int zIndex, ShapeData data)? shape,
    TResult Function(String id, int zIndex, MathData data)? math,
    required TResult orElse(),
  }) {
    if (stroke != null) {
      return stroke(id, zIndex, data);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StrokeElement value) stroke,
    required TResult Function(TextElement value) text,
    required TResult Function(ImageElement value) image,
    required TResult Function(ShapeElement value) shape,
    required TResult Function(MathElement value) math,
  }) {
    return stroke(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StrokeElement value)? stroke,
    TResult? Function(TextElement value)? text,
    TResult? Function(ImageElement value)? image,
    TResult? Function(ShapeElement value)? shape,
    TResult? Function(MathElement value)? math,
  }) {
    return stroke?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StrokeElement value)? stroke,
    TResult Function(TextElement value)? text,
    TResult Function(ImageElement value)? image,
    TResult Function(ShapeElement value)? shape,
    TResult Function(MathElement value)? math,
    required TResult orElse(),
  }) {
    if (stroke != null) {
      return stroke(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$StrokeElementImplToJson(
      this,
    );
  }
}

abstract class StrokeElement implements ContentElement {
  const factory StrokeElement(
      {required final String id,
      required final int zIndex,
      required final StrokeData data}) = _$StrokeElementImpl;

  factory StrokeElement.fromJson(Map<String, dynamic> json) =
      _$StrokeElementImpl.fromJson;

  @override
  String get id;
  @override
  int get zIndex;
  @override
  StrokeData get data;

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StrokeElementImplCopyWith<_$StrokeElementImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$TextElementImplCopyWith<$Res>
    implements $ContentElementCopyWith<$Res> {
  factory _$$TextElementImplCopyWith(
          _$TextElementImpl value, $Res Function(_$TextElementImpl) then) =
      __$$TextElementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, int zIndex, TextData data});

  $TextDataCopyWith<$Res> get data;
}

/// @nodoc
class __$$TextElementImplCopyWithImpl<$Res>
    extends _$ContentElementCopyWithImpl<$Res, _$TextElementImpl>
    implements _$$TextElementImplCopyWith<$Res> {
  __$$TextElementImplCopyWithImpl(
      _$TextElementImpl _value, $Res Function(_$TextElementImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? zIndex = null,
    Object? data = null,
  }) {
    return _then(_$TextElementImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      zIndex: null == zIndex
          ? _value.zIndex
          : zIndex // ignore: cast_nullable_to_non_nullable
              as int,
      data: null == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as TextData,
    ));
  }

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $TextDataCopyWith<$Res> get data {
    return $TextDataCopyWith<$Res>(_value.data, (value) {
      return _then(_value.copyWith(data: value));
    });
  }
}

/// @nodoc
@JsonSerializable()
class _$TextElementImpl implements TextElement {
  const _$TextElementImpl(
      {required this.id,
      required this.zIndex,
      required this.data,
      final String? $type})
      : $type = $type ?? 'text';

  factory _$TextElementImpl.fromJson(Map<String, dynamic> json) =>
      _$$TextElementImplFromJson(json);

  @override
  final String id;
  @override
  final int zIndex;
  @override
  final TextData data;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'ContentElement.text(id: $id, zIndex: $zIndex, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TextElementImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.zIndex, zIndex) || other.zIndex == zIndex) &&
            (identical(other.data, data) || other.data == data));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, zIndex, data);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TextElementImplCopyWith<_$TextElementImpl> get copyWith =>
      __$$TextElementImplCopyWithImpl<_$TextElementImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, int zIndex, StrokeData data) stroke,
    required TResult Function(String id, int zIndex, TextData data) text,
    required TResult Function(String id, int zIndex, ImageData data) image,
    required TResult Function(String id, int zIndex, ShapeData data) shape,
    required TResult Function(String id, int zIndex, MathData data) math,
  }) {
    return text(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, int zIndex, StrokeData data)? stroke,
    TResult? Function(String id, int zIndex, TextData data)? text,
    TResult? Function(String id, int zIndex, ImageData data)? image,
    TResult? Function(String id, int zIndex, ShapeData data)? shape,
    TResult? Function(String id, int zIndex, MathData data)? math,
  }) {
    return text?.call(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, int zIndex, StrokeData data)? stroke,
    TResult Function(String id, int zIndex, TextData data)? text,
    TResult Function(String id, int zIndex, ImageData data)? image,
    TResult Function(String id, int zIndex, ShapeData data)? shape,
    TResult Function(String id, int zIndex, MathData data)? math,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(id, zIndex, data);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StrokeElement value) stroke,
    required TResult Function(TextElement value) text,
    required TResult Function(ImageElement value) image,
    required TResult Function(ShapeElement value) shape,
    required TResult Function(MathElement value) math,
  }) {
    return text(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StrokeElement value)? stroke,
    TResult? Function(TextElement value)? text,
    TResult? Function(ImageElement value)? image,
    TResult? Function(ShapeElement value)? shape,
    TResult? Function(MathElement value)? math,
  }) {
    return text?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StrokeElement value)? stroke,
    TResult Function(TextElement value)? text,
    TResult Function(ImageElement value)? image,
    TResult Function(ShapeElement value)? shape,
    TResult Function(MathElement value)? math,
    required TResult orElse(),
  }) {
    if (text != null) {
      return text(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$TextElementImplToJson(
      this,
    );
  }
}

abstract class TextElement implements ContentElement {
  const factory TextElement(
      {required final String id,
      required final int zIndex,
      required final TextData data}) = _$TextElementImpl;

  factory TextElement.fromJson(Map<String, dynamic> json) =
      _$TextElementImpl.fromJson;

  @override
  String get id;
  @override
  int get zIndex;
  @override
  TextData get data;

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TextElementImplCopyWith<_$TextElementImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ImageElementImplCopyWith<$Res>
    implements $ContentElementCopyWith<$Res> {
  factory _$$ImageElementImplCopyWith(
          _$ImageElementImpl value, $Res Function(_$ImageElementImpl) then) =
      __$$ImageElementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, int zIndex, ImageData data});

  $ImageDataCopyWith<$Res> get data;
}

/// @nodoc
class __$$ImageElementImplCopyWithImpl<$Res>
    extends _$ContentElementCopyWithImpl<$Res, _$ImageElementImpl>
    implements _$$ImageElementImplCopyWith<$Res> {
  __$$ImageElementImplCopyWithImpl(
      _$ImageElementImpl _value, $Res Function(_$ImageElementImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? zIndex = null,
    Object? data = null,
  }) {
    return _then(_$ImageElementImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      zIndex: null == zIndex
          ? _value.zIndex
          : zIndex // ignore: cast_nullable_to_non_nullable
              as int,
      data: null == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as ImageData,
    ));
  }

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ImageDataCopyWith<$Res> get data {
    return $ImageDataCopyWith<$Res>(_value.data, (value) {
      return _then(_value.copyWith(data: value));
    });
  }
}

/// @nodoc
@JsonSerializable()
class _$ImageElementImpl implements ImageElement {
  const _$ImageElementImpl(
      {required this.id,
      required this.zIndex,
      required this.data,
      final String? $type})
      : $type = $type ?? 'image';

  factory _$ImageElementImpl.fromJson(Map<String, dynamic> json) =>
      _$$ImageElementImplFromJson(json);

  @override
  final String id;
  @override
  final int zIndex;
  @override
  final ImageData data;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'ContentElement.image(id: $id, zIndex: $zIndex, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImageElementImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.zIndex, zIndex) || other.zIndex == zIndex) &&
            (identical(other.data, data) || other.data == data));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, zIndex, data);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ImageElementImplCopyWith<_$ImageElementImpl> get copyWith =>
      __$$ImageElementImplCopyWithImpl<_$ImageElementImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, int zIndex, StrokeData data) stroke,
    required TResult Function(String id, int zIndex, TextData data) text,
    required TResult Function(String id, int zIndex, ImageData data) image,
    required TResult Function(String id, int zIndex, ShapeData data) shape,
    required TResult Function(String id, int zIndex, MathData data) math,
  }) {
    return image(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, int zIndex, StrokeData data)? stroke,
    TResult? Function(String id, int zIndex, TextData data)? text,
    TResult? Function(String id, int zIndex, ImageData data)? image,
    TResult? Function(String id, int zIndex, ShapeData data)? shape,
    TResult? Function(String id, int zIndex, MathData data)? math,
  }) {
    return image?.call(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, int zIndex, StrokeData data)? stroke,
    TResult Function(String id, int zIndex, TextData data)? text,
    TResult Function(String id, int zIndex, ImageData data)? image,
    TResult Function(String id, int zIndex, ShapeData data)? shape,
    TResult Function(String id, int zIndex, MathData data)? math,
    required TResult orElse(),
  }) {
    if (image != null) {
      return image(id, zIndex, data);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StrokeElement value) stroke,
    required TResult Function(TextElement value) text,
    required TResult Function(ImageElement value) image,
    required TResult Function(ShapeElement value) shape,
    required TResult Function(MathElement value) math,
  }) {
    return image(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StrokeElement value)? stroke,
    TResult? Function(TextElement value)? text,
    TResult? Function(ImageElement value)? image,
    TResult? Function(ShapeElement value)? shape,
    TResult? Function(MathElement value)? math,
  }) {
    return image?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StrokeElement value)? stroke,
    TResult Function(TextElement value)? text,
    TResult Function(ImageElement value)? image,
    TResult Function(ShapeElement value)? shape,
    TResult Function(MathElement value)? math,
    required TResult orElse(),
  }) {
    if (image != null) {
      return image(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ImageElementImplToJson(
      this,
    );
  }
}

abstract class ImageElement implements ContentElement {
  const factory ImageElement(
      {required final String id,
      required final int zIndex,
      required final ImageData data}) = _$ImageElementImpl;

  factory ImageElement.fromJson(Map<String, dynamic> json) =
      _$ImageElementImpl.fromJson;

  @override
  String get id;
  @override
  int get zIndex;
  @override
  ImageData get data;

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ImageElementImplCopyWith<_$ImageElementImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$ShapeElementImplCopyWith<$Res>
    implements $ContentElementCopyWith<$Res> {
  factory _$$ShapeElementImplCopyWith(
          _$ShapeElementImpl value, $Res Function(_$ShapeElementImpl) then) =
      __$$ShapeElementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, int zIndex, ShapeData data});

  $ShapeDataCopyWith<$Res> get data;
}

/// @nodoc
class __$$ShapeElementImplCopyWithImpl<$Res>
    extends _$ContentElementCopyWithImpl<$Res, _$ShapeElementImpl>
    implements _$$ShapeElementImplCopyWith<$Res> {
  __$$ShapeElementImplCopyWithImpl(
      _$ShapeElementImpl _value, $Res Function(_$ShapeElementImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? zIndex = null,
    Object? data = null,
  }) {
    return _then(_$ShapeElementImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      zIndex: null == zIndex
          ? _value.zIndex
          : zIndex // ignore: cast_nullable_to_non_nullable
              as int,
      data: null == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as ShapeData,
    ));
  }

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ShapeDataCopyWith<$Res> get data {
    return $ShapeDataCopyWith<$Res>(_value.data, (value) {
      return _then(_value.copyWith(data: value));
    });
  }
}

/// @nodoc
@JsonSerializable()
class _$ShapeElementImpl implements ShapeElement {
  const _$ShapeElementImpl(
      {required this.id,
      required this.zIndex,
      required this.data,
      final String? $type})
      : $type = $type ?? 'shape';

  factory _$ShapeElementImpl.fromJson(Map<String, dynamic> json) =>
      _$$ShapeElementImplFromJson(json);

  @override
  final String id;
  @override
  final int zIndex;
  @override
  final ShapeData data;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'ContentElement.shape(id: $id, zIndex: $zIndex, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ShapeElementImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.zIndex, zIndex) || other.zIndex == zIndex) &&
            (identical(other.data, data) || other.data == data));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, zIndex, data);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ShapeElementImplCopyWith<_$ShapeElementImpl> get copyWith =>
      __$$ShapeElementImplCopyWithImpl<_$ShapeElementImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, int zIndex, StrokeData data) stroke,
    required TResult Function(String id, int zIndex, TextData data) text,
    required TResult Function(String id, int zIndex, ImageData data) image,
    required TResult Function(String id, int zIndex, ShapeData data) shape,
    required TResult Function(String id, int zIndex, MathData data) math,
  }) {
    return shape(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, int zIndex, StrokeData data)? stroke,
    TResult? Function(String id, int zIndex, TextData data)? text,
    TResult? Function(String id, int zIndex, ImageData data)? image,
    TResult? Function(String id, int zIndex, ShapeData data)? shape,
    TResult? Function(String id, int zIndex, MathData data)? math,
  }) {
    return shape?.call(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, int zIndex, StrokeData data)? stroke,
    TResult Function(String id, int zIndex, TextData data)? text,
    TResult Function(String id, int zIndex, ImageData data)? image,
    TResult Function(String id, int zIndex, ShapeData data)? shape,
    TResult Function(String id, int zIndex, MathData data)? math,
    required TResult orElse(),
  }) {
    if (shape != null) {
      return shape(id, zIndex, data);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StrokeElement value) stroke,
    required TResult Function(TextElement value) text,
    required TResult Function(ImageElement value) image,
    required TResult Function(ShapeElement value) shape,
    required TResult Function(MathElement value) math,
  }) {
    return shape(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StrokeElement value)? stroke,
    TResult? Function(TextElement value)? text,
    TResult? Function(ImageElement value)? image,
    TResult? Function(ShapeElement value)? shape,
    TResult? Function(MathElement value)? math,
  }) {
    return shape?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StrokeElement value)? stroke,
    TResult Function(TextElement value)? text,
    TResult Function(ImageElement value)? image,
    TResult Function(ShapeElement value)? shape,
    TResult Function(MathElement value)? math,
    required TResult orElse(),
  }) {
    if (shape != null) {
      return shape(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$ShapeElementImplToJson(
      this,
    );
  }
}

abstract class ShapeElement implements ContentElement {
  const factory ShapeElement(
      {required final String id,
      required final int zIndex,
      required final ShapeData data}) = _$ShapeElementImpl;

  factory ShapeElement.fromJson(Map<String, dynamic> json) =
      _$ShapeElementImpl.fromJson;

  @override
  String get id;
  @override
  int get zIndex;
  @override
  ShapeData get data;

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ShapeElementImplCopyWith<_$ShapeElementImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MathElementImplCopyWith<$Res>
    implements $ContentElementCopyWith<$Res> {
  factory _$$MathElementImplCopyWith(
          _$MathElementImpl value, $Res Function(_$MathElementImpl) then) =
      __$$MathElementImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, int zIndex, MathData data});

  $MathDataCopyWith<$Res> get data;
}

/// @nodoc
class __$$MathElementImplCopyWithImpl<$Res>
    extends _$ContentElementCopyWithImpl<$Res, _$MathElementImpl>
    implements _$$MathElementImplCopyWith<$Res> {
  __$$MathElementImplCopyWithImpl(
      _$MathElementImpl _value, $Res Function(_$MathElementImpl) _then)
      : super(_value, _then);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? zIndex = null,
    Object? data = null,
  }) {
    return _then(_$MathElementImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      zIndex: null == zIndex
          ? _value.zIndex
          : zIndex // ignore: cast_nullable_to_non_nullable
              as int,
      data: null == data
          ? _value.data
          : data // ignore: cast_nullable_to_non_nullable
              as MathData,
    ));
  }

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $MathDataCopyWith<$Res> get data {
    return $MathDataCopyWith<$Res>(_value.data, (value) {
      return _then(_value.copyWith(data: value));
    });
  }
}

/// @nodoc
@JsonSerializable()
class _$MathElementImpl implements MathElement {
  const _$MathElementImpl(
      {required this.id,
      required this.zIndex,
      required this.data,
      final String? $type})
      : $type = $type ?? 'math';

  factory _$MathElementImpl.fromJson(Map<String, dynamic> json) =>
      _$$MathElementImplFromJson(json);

  @override
  final String id;
  @override
  final int zIndex;
  @override
  final MathData data;

  @JsonKey(name: 'type')
  final String $type;

  @override
  String toString() {
    return 'ContentElement.math(id: $id, zIndex: $zIndex, data: $data)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MathElementImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.zIndex, zIndex) || other.zIndex == zIndex) &&
            (identical(other.data, data) || other.data == data));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, id, zIndex, data);

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MathElementImplCopyWith<_$MathElementImpl> get copyWith =>
      __$$MathElementImplCopyWithImpl<_$MathElementImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String id, int zIndex, StrokeData data) stroke,
    required TResult Function(String id, int zIndex, TextData data) text,
    required TResult Function(String id, int zIndex, ImageData data) image,
    required TResult Function(String id, int zIndex, ShapeData data) shape,
    required TResult Function(String id, int zIndex, MathData data) math,
  }) {
    return math(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String id, int zIndex, StrokeData data)? stroke,
    TResult? Function(String id, int zIndex, TextData data)? text,
    TResult? Function(String id, int zIndex, ImageData data)? image,
    TResult? Function(String id, int zIndex, ShapeData data)? shape,
    TResult? Function(String id, int zIndex, MathData data)? math,
  }) {
    return math?.call(id, zIndex, data);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String id, int zIndex, StrokeData data)? stroke,
    TResult Function(String id, int zIndex, TextData data)? text,
    TResult Function(String id, int zIndex, ImageData data)? image,
    TResult Function(String id, int zIndex, ShapeData data)? shape,
    TResult Function(String id, int zIndex, MathData data)? math,
    required TResult orElse(),
  }) {
    if (math != null) {
      return math(id, zIndex, data);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(StrokeElement value) stroke,
    required TResult Function(TextElement value) text,
    required TResult Function(ImageElement value) image,
    required TResult Function(ShapeElement value) shape,
    required TResult Function(MathElement value) math,
  }) {
    return math(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(StrokeElement value)? stroke,
    TResult? Function(TextElement value)? text,
    TResult? Function(ImageElement value)? image,
    TResult? Function(ShapeElement value)? shape,
    TResult? Function(MathElement value)? math,
  }) {
    return math?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(StrokeElement value)? stroke,
    TResult Function(TextElement value)? text,
    TResult Function(ImageElement value)? image,
    TResult Function(ShapeElement value)? shape,
    TResult Function(MathElement value)? math,
    required TResult orElse(),
  }) {
    if (math != null) {
      return math(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MathElementImplToJson(
      this,
    );
  }
}

abstract class MathElement implements ContentElement {
  const factory MathElement(
      {required final String id,
      required final int zIndex,
      required final MathData data}) = _$MathElementImpl;

  factory MathElement.fromJson(Map<String, dynamic> json) =
      _$MathElementImpl.fromJson;

  @override
  String get id;
  @override
  int get zIndex;
  @override
  MathData get data;

  /// Create a copy of ContentElement
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MathElementImplCopyWith<_$MathElementImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

StrokeData _$StrokeDataFromJson(Map<String, dynamic> json) {
  return _StrokeData.fromJson(json);
}

/// @nodoc
mixin _$StrokeData {
  List<StrokePoint> get points => throw _privateConstructorUsedError;
  String get toolType =>
      throw _privateConstructorUsedError; // pen, ballpoint, brush, highlighter
  int get color => throw _privateConstructorUsedError;
  double get baseWidth => throw _privateConstructorUsedError;
  bool get isHighlighter => throw _privateConstructorUsedError;
  double get opacity => throw _privateConstructorUsedError;
  DateTime? get timestamp => throw _privateConstructorUsedError;

  /// Serializes this StrokeData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of StrokeData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StrokeDataCopyWith<StrokeData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StrokeDataCopyWith<$Res> {
  factory $StrokeDataCopyWith(
          StrokeData value, $Res Function(StrokeData) then) =
      _$StrokeDataCopyWithImpl<$Res, StrokeData>;
  @useResult
  $Res call(
      {List<StrokePoint> points,
      String toolType,
      int color,
      double baseWidth,
      bool isHighlighter,
      double opacity,
      DateTime? timestamp});
}

/// @nodoc
class _$StrokeDataCopyWithImpl<$Res, $Val extends StrokeData>
    implements $StrokeDataCopyWith<$Res> {
  _$StrokeDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StrokeData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? points = null,
    Object? toolType = null,
    Object? color = null,
    Object? baseWidth = null,
    Object? isHighlighter = null,
    Object? opacity = null,
    Object? timestamp = freezed,
  }) {
    return _then(_value.copyWith(
      points: null == points
          ? _value.points
          : points // ignore: cast_nullable_to_non_nullable
              as List<StrokePoint>,
      toolType: null == toolType
          ? _value.toolType
          : toolType // ignore: cast_nullable_to_non_nullable
              as String,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      baseWidth: null == baseWidth
          ? _value.baseWidth
          : baseWidth // ignore: cast_nullable_to_non_nullable
              as double,
      isHighlighter: null == isHighlighter
          ? _value.isHighlighter
          : isHighlighter // ignore: cast_nullable_to_non_nullable
              as bool,
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$StrokeDataImplCopyWith<$Res>
    implements $StrokeDataCopyWith<$Res> {
  factory _$$StrokeDataImplCopyWith(
          _$StrokeDataImpl value, $Res Function(_$StrokeDataImpl) then) =
      __$$StrokeDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {List<StrokePoint> points,
      String toolType,
      int color,
      double baseWidth,
      bool isHighlighter,
      double opacity,
      DateTime? timestamp});
}

/// @nodoc
class __$$StrokeDataImplCopyWithImpl<$Res>
    extends _$StrokeDataCopyWithImpl<$Res, _$StrokeDataImpl>
    implements _$$StrokeDataImplCopyWith<$Res> {
  __$$StrokeDataImplCopyWithImpl(
      _$StrokeDataImpl _value, $Res Function(_$StrokeDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of StrokeData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? points = null,
    Object? toolType = null,
    Object? color = null,
    Object? baseWidth = null,
    Object? isHighlighter = null,
    Object? opacity = null,
    Object? timestamp = freezed,
  }) {
    return _then(_$StrokeDataImpl(
      points: null == points
          ? _value._points
          : points // ignore: cast_nullable_to_non_nullable
              as List<StrokePoint>,
      toolType: null == toolType
          ? _value.toolType
          : toolType // ignore: cast_nullable_to_non_nullable
              as String,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      baseWidth: null == baseWidth
          ? _value.baseWidth
          : baseWidth // ignore: cast_nullable_to_non_nullable
              as double,
      isHighlighter: null == isHighlighter
          ? _value.isHighlighter
          : isHighlighter // ignore: cast_nullable_to_non_nullable
              as bool,
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: freezed == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$StrokeDataImpl implements _StrokeData {
  const _$StrokeDataImpl(
      {required final List<StrokePoint> points,
      this.toolType = 'pen',
      this.color = 0xFF000000,
      this.baseWidth = 2.0,
      this.isHighlighter = false,
      this.opacity = 1.0,
      this.timestamp})
      : _points = points;

  factory _$StrokeDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$StrokeDataImplFromJson(json);

  final List<StrokePoint> _points;
  @override
  List<StrokePoint> get points {
    if (_points is EqualUnmodifiableListView) return _points;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_points);
  }

  @override
  @JsonKey()
  final String toolType;
// pen, ballpoint, brush, highlighter
  @override
  @JsonKey()
  final int color;
  @override
  @JsonKey()
  final double baseWidth;
  @override
  @JsonKey()
  final bool isHighlighter;
  @override
  @JsonKey()
  final double opacity;
  @override
  final DateTime? timestamp;

  @override
  String toString() {
    return 'StrokeData(points: $points, toolType: $toolType, color: $color, baseWidth: $baseWidth, isHighlighter: $isHighlighter, opacity: $opacity, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StrokeDataImpl &&
            const DeepCollectionEquality().equals(other._points, _points) &&
            (identical(other.toolType, toolType) ||
                other.toolType == toolType) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.baseWidth, baseWidth) ||
                other.baseWidth == baseWidth) &&
            (identical(other.isHighlighter, isHighlighter) ||
                other.isHighlighter == isHighlighter) &&
            (identical(other.opacity, opacity) || other.opacity == opacity) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      const DeepCollectionEquality().hash(_points),
      toolType,
      color,
      baseWidth,
      isHighlighter,
      opacity,
      timestamp);

  /// Create a copy of StrokeData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StrokeDataImplCopyWith<_$StrokeDataImpl> get copyWith =>
      __$$StrokeDataImplCopyWithImpl<_$StrokeDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$StrokeDataImplToJson(
      this,
    );
  }
}

abstract class _StrokeData implements StrokeData {
  const factory _StrokeData(
      {required final List<StrokePoint> points,
      final String toolType,
      final int color,
      final double baseWidth,
      final bool isHighlighter,
      final double opacity,
      final DateTime? timestamp}) = _$StrokeDataImpl;

  factory _StrokeData.fromJson(Map<String, dynamic> json) =
      _$StrokeDataImpl.fromJson;

  @override
  List<StrokePoint> get points;
  @override
  String get toolType; // pen, ballpoint, brush, highlighter
  @override
  int get color;
  @override
  double get baseWidth;
  @override
  bool get isHighlighter;
  @override
  double get opacity;
  @override
  DateTime? get timestamp;

  /// Create a copy of StrokeData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StrokeDataImplCopyWith<_$StrokeDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

StrokePoint _$StrokePointFromJson(Map<String, dynamic> json) {
  return _StrokePoint.fromJson(json);
}

/// @nodoc
mixin _$StrokePoint {
  double get x => throw _privateConstructorUsedError;
  double get y => throw _privateConstructorUsedError;
  double get pressure => throw _privateConstructorUsedError; // 0.0 - 1.0
  double get tilt => throw _privateConstructorUsedError; // radianti
  int get timestamp => throw _privateConstructorUsedError;

  /// Serializes this StrokePoint to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of StrokePoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $StrokePointCopyWith<StrokePoint> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $StrokePointCopyWith<$Res> {
  factory $StrokePointCopyWith(
          StrokePoint value, $Res Function(StrokePoint) then) =
      _$StrokePointCopyWithImpl<$Res, StrokePoint>;
  @useResult
  $Res call({double x, double y, double pressure, double tilt, int timestamp});
}

/// @nodoc
class _$StrokePointCopyWithImpl<$Res, $Val extends StrokePoint>
    implements $StrokePointCopyWith<$Res> {
  _$StrokePointCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of StrokePoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? pressure = null,
    Object? tilt = null,
    Object? timestamp = null,
  }) {
    return _then(_value.copyWith(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      pressure: null == pressure
          ? _value.pressure
          : pressure // ignore: cast_nullable_to_non_nullable
              as double,
      tilt: null == tilt
          ? _value.tilt
          : tilt // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$StrokePointImplCopyWith<$Res>
    implements $StrokePointCopyWith<$Res> {
  factory _$$StrokePointImplCopyWith(
          _$StrokePointImpl value, $Res Function(_$StrokePointImpl) then) =
      __$$StrokePointImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double x, double y, double pressure, double tilt, int timestamp});
}

/// @nodoc
class __$$StrokePointImplCopyWithImpl<$Res>
    extends _$StrokePointCopyWithImpl<$Res, _$StrokePointImpl>
    implements _$$StrokePointImplCopyWith<$Res> {
  __$$StrokePointImplCopyWithImpl(
      _$StrokePointImpl _value, $Res Function(_$StrokePointImpl) _then)
      : super(_value, _then);

  /// Create a copy of StrokePoint
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? pressure = null,
    Object? tilt = null,
    Object? timestamp = null,
  }) {
    return _then(_$StrokePointImpl(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      pressure: null == pressure
          ? _value.pressure
          : pressure // ignore: cast_nullable_to_non_nullable
              as double,
      tilt: null == tilt
          ? _value.tilt
          : tilt // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$StrokePointImpl implements _StrokePoint {
  const _$StrokePointImpl(
      {required this.x,
      required this.y,
      this.pressure = 0.5,
      this.tilt = 0.0,
      this.timestamp = 0});

  factory _$StrokePointImpl.fromJson(Map<String, dynamic> json) =>
      _$$StrokePointImplFromJson(json);

  @override
  final double x;
  @override
  final double y;
  @override
  @JsonKey()
  final double pressure;
// 0.0 - 1.0
  @override
  @JsonKey()
  final double tilt;
// radianti
  @override
  @JsonKey()
  final int timestamp;

  @override
  String toString() {
    return 'StrokePoint(x: $x, y: $y, pressure: $pressure, tilt: $tilt, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$StrokePointImpl &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.pressure, pressure) ||
                other.pressure == pressure) &&
            (identical(other.tilt, tilt) || other.tilt == tilt) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, x, y, pressure, tilt, timestamp);

  /// Create a copy of StrokePoint
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$StrokePointImplCopyWith<_$StrokePointImpl> get copyWith =>
      __$$StrokePointImplCopyWithImpl<_$StrokePointImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$StrokePointImplToJson(
      this,
    );
  }
}

abstract class _StrokePoint implements StrokePoint {
  const factory _StrokePoint(
      {required final double x,
      required final double y,
      final double pressure,
      final double tilt,
      final int timestamp}) = _$StrokePointImpl;

  factory _StrokePoint.fromJson(Map<String, dynamic> json) =
      _$StrokePointImpl.fromJson;

  @override
  double get x;
  @override
  double get y;
  @override
  double get pressure; // 0.0 - 1.0
  @override
  double get tilt; // radianti
  @override
  int get timestamp;

  /// Create a copy of StrokePoint
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$StrokePointImplCopyWith<_$StrokePointImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TextSpanData _$TextSpanDataFromJson(Map<String, dynamic> json) {
  return _TextSpanData.fromJson(json);
}

/// @nodoc
mixin _$TextSpanData {
  String get text => throw _privateConstructorUsedError;
  bool get bold => throw _privateConstructorUsedError;
  bool get italic => throw _privateConstructorUsedError;
  bool get underline => throw _privateConstructorUsedError;
  bool get strikethrough => throw _privateConstructorUsedError;
  int? get color => throw _privateConstructorUsedError;
  double? get fontSize => throw _privateConstructorUsedError;

  /// Per-span font family override (e.g. 'monospace' for inline/code
  /// runs from pasted Markdown). Null inherits the element-level
  /// `TextData.fontFamily`.
  String? get fontFamily => throw _privateConstructorUsedError;

  /// Serializes this TextSpanData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TextSpanData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TextSpanDataCopyWith<TextSpanData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TextSpanDataCopyWith<$Res> {
  factory $TextSpanDataCopyWith(
          TextSpanData value, $Res Function(TextSpanData) then) =
      _$TextSpanDataCopyWithImpl<$Res, TextSpanData>;
  @useResult
  $Res call(
      {String text,
      bool bold,
      bool italic,
      bool underline,
      bool strikethrough,
      int? color,
      double? fontSize,
      String? fontFamily});
}

/// @nodoc
class _$TextSpanDataCopyWithImpl<$Res, $Val extends TextSpanData>
    implements $TextSpanDataCopyWith<$Res> {
  _$TextSpanDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TextSpanData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? text = null,
    Object? bold = null,
    Object? italic = null,
    Object? underline = null,
    Object? strikethrough = null,
    Object? color = freezed,
    Object? fontSize = freezed,
    Object? fontFamily = freezed,
  }) {
    return _then(_value.copyWith(
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      bold: null == bold
          ? _value.bold
          : bold // ignore: cast_nullable_to_non_nullable
              as bool,
      italic: null == italic
          ? _value.italic
          : italic // ignore: cast_nullable_to_non_nullable
              as bool,
      underline: null == underline
          ? _value.underline
          : underline // ignore: cast_nullable_to_non_nullable
              as bool,
      strikethrough: null == strikethrough
          ? _value.strikethrough
          : strikethrough // ignore: cast_nullable_to_non_nullable
              as bool,
      color: freezed == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int?,
      fontSize: freezed == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as double?,
      fontFamily: freezed == fontFamily
          ? _value.fontFamily
          : fontFamily // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TextSpanDataImplCopyWith<$Res>
    implements $TextSpanDataCopyWith<$Res> {
  factory _$$TextSpanDataImplCopyWith(
          _$TextSpanDataImpl value, $Res Function(_$TextSpanDataImpl) then) =
      __$$TextSpanDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String text,
      bool bold,
      bool italic,
      bool underline,
      bool strikethrough,
      int? color,
      double? fontSize,
      String? fontFamily});
}

/// @nodoc
class __$$TextSpanDataImplCopyWithImpl<$Res>
    extends _$TextSpanDataCopyWithImpl<$Res, _$TextSpanDataImpl>
    implements _$$TextSpanDataImplCopyWith<$Res> {
  __$$TextSpanDataImplCopyWithImpl(
      _$TextSpanDataImpl _value, $Res Function(_$TextSpanDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of TextSpanData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? text = null,
    Object? bold = null,
    Object? italic = null,
    Object? underline = null,
    Object? strikethrough = null,
    Object? color = freezed,
    Object? fontSize = freezed,
    Object? fontFamily = freezed,
  }) {
    return _then(_$TextSpanDataImpl(
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      bold: null == bold
          ? _value.bold
          : bold // ignore: cast_nullable_to_non_nullable
              as bool,
      italic: null == italic
          ? _value.italic
          : italic // ignore: cast_nullable_to_non_nullable
              as bool,
      underline: null == underline
          ? _value.underline
          : underline // ignore: cast_nullable_to_non_nullable
              as bool,
      strikethrough: null == strikethrough
          ? _value.strikethrough
          : strikethrough // ignore: cast_nullable_to_non_nullable
              as bool,
      color: freezed == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int?,
      fontSize: freezed == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as double?,
      fontFamily: freezed == fontFamily
          ? _value.fontFamily
          : fontFamily // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TextSpanDataImpl implements _TextSpanData {
  const _$TextSpanDataImpl(
      {required this.text,
      this.bold = false,
      this.italic = false,
      this.underline = false,
      this.strikethrough = false,
      this.color,
      this.fontSize,
      this.fontFamily});

  factory _$TextSpanDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$TextSpanDataImplFromJson(json);

  @override
  final String text;
  @override
  @JsonKey()
  final bool bold;
  @override
  @JsonKey()
  final bool italic;
  @override
  @JsonKey()
  final bool underline;
  @override
  @JsonKey()
  final bool strikethrough;
  @override
  final int? color;
  @override
  final double? fontSize;

  /// Per-span font family override (e.g. 'monospace' for inline/code
  /// runs from pasted Markdown). Null inherits the element-level
  /// `TextData.fontFamily`.
  @override
  final String? fontFamily;

  @override
  String toString() {
    return 'TextSpanData(text: $text, bold: $bold, italic: $italic, underline: $underline, strikethrough: $strikethrough, color: $color, fontSize: $fontSize, fontFamily: $fontFamily)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TextSpanDataImpl &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.bold, bold) || other.bold == bold) &&
            (identical(other.italic, italic) || other.italic == italic) &&
            (identical(other.underline, underline) ||
                other.underline == underline) &&
            (identical(other.strikethrough, strikethrough) ||
                other.strikethrough == strikethrough) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.fontSize, fontSize) ||
                other.fontSize == fontSize) &&
            (identical(other.fontFamily, fontFamily) ||
                other.fontFamily == fontFamily));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, text, bold, italic, underline,
      strikethrough, color, fontSize, fontFamily);

  /// Create a copy of TextSpanData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TextSpanDataImplCopyWith<_$TextSpanDataImpl> get copyWith =>
      __$$TextSpanDataImplCopyWithImpl<_$TextSpanDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TextSpanDataImplToJson(
      this,
    );
  }
}

abstract class _TextSpanData implements TextSpanData {
  const factory _TextSpanData(
      {required final String text,
      final bool bold,
      final bool italic,
      final bool underline,
      final bool strikethrough,
      final int? color,
      final double? fontSize,
      final String? fontFamily}) = _$TextSpanDataImpl;

  factory _TextSpanData.fromJson(Map<String, dynamic> json) =
      _$TextSpanDataImpl.fromJson;

  @override
  String get text;
  @override
  bool get bold;
  @override
  bool get italic;
  @override
  bool get underline;
  @override
  bool get strikethrough;
  @override
  int? get color;
  @override
  double? get fontSize;

  /// Per-span font family override (e.g. 'monospace' for inline/code
  /// runs from pasted Markdown). Null inherits the element-level
  /// `TextData.fontFamily`.
  @override
  String? get fontFamily;

  /// Create a copy of TextSpanData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TextSpanDataImplCopyWith<_$TextSpanDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

TextData _$TextDataFromJson(Map<String, dynamic> json) {
  return _TextData.fromJson(json);
}

/// @nodoc
mixin _$TextData {
  double get x => throw _privateConstructorUsedError;
  double get y => throw _privateConstructorUsedError;
  double get width => throw _privateConstructorUsedError;
  double get height => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  String get fontFamily => throw _privateConstructorUsedError;
  double get fontSize => throw _privateConstructorUsedError;
  int get color => throw _privateConstructorUsedError;
  bool get bold => throw _privateConstructorUsedError;
  bool get italic => throw _privateConstructorUsedError;
  String get alignment =>
      throw _privateConstructorUsedError; // left, center, right
  /// Rich formatting runs. Empty = legacy plain text (render `content`
  /// with the element-level style). Non-empty = concat(span.text) ==
  /// content, rendered with per-span styling.
  List<TextSpanData> get spans => throw _privateConstructorUsedError;

  /// Serializes this TextData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of TextData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TextDataCopyWith<TextData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TextDataCopyWith<$Res> {
  factory $TextDataCopyWith(TextData value, $Res Function(TextData) then) =
      _$TextDataCopyWithImpl<$Res, TextData>;
  @useResult
  $Res call(
      {double x,
      double y,
      double width,
      double height,
      String content,
      String fontFamily,
      double fontSize,
      int color,
      bool bold,
      bool italic,
      String alignment,
      List<TextSpanData> spans});
}

/// @nodoc
class _$TextDataCopyWithImpl<$Res, $Val extends TextData>
    implements $TextDataCopyWith<$Res> {
  _$TextDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TextData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
    Object? content = null,
    Object? fontFamily = null,
    Object? fontSize = null,
    Object? color = null,
    Object? bold = null,
    Object? italic = null,
    Object? alignment = null,
    Object? spans = null,
  }) {
    return _then(_value.copyWith(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      fontFamily: null == fontFamily
          ? _value.fontFamily
          : fontFamily // ignore: cast_nullable_to_non_nullable
              as String,
      fontSize: null == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as double,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      bold: null == bold
          ? _value.bold
          : bold // ignore: cast_nullable_to_non_nullable
              as bool,
      italic: null == italic
          ? _value.italic
          : italic // ignore: cast_nullable_to_non_nullable
              as bool,
      alignment: null == alignment
          ? _value.alignment
          : alignment // ignore: cast_nullable_to_non_nullable
              as String,
      spans: null == spans
          ? _value.spans
          : spans // ignore: cast_nullable_to_non_nullable
              as List<TextSpanData>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TextDataImplCopyWith<$Res>
    implements $TextDataCopyWith<$Res> {
  factory _$$TextDataImplCopyWith(
          _$TextDataImpl value, $Res Function(_$TextDataImpl) then) =
      __$$TextDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double x,
      double y,
      double width,
      double height,
      String content,
      String fontFamily,
      double fontSize,
      int color,
      bool bold,
      bool italic,
      String alignment,
      List<TextSpanData> spans});
}

/// @nodoc
class __$$TextDataImplCopyWithImpl<$Res>
    extends _$TextDataCopyWithImpl<$Res, _$TextDataImpl>
    implements _$$TextDataImplCopyWith<$Res> {
  __$$TextDataImplCopyWithImpl(
      _$TextDataImpl _value, $Res Function(_$TextDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of TextData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
    Object? content = null,
    Object? fontFamily = null,
    Object? fontSize = null,
    Object? color = null,
    Object? bold = null,
    Object? italic = null,
    Object? alignment = null,
    Object? spans = null,
  }) {
    return _then(_$TextDataImpl(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      content: null == content
          ? _value.content
          : content // ignore: cast_nullable_to_non_nullable
              as String,
      fontFamily: null == fontFamily
          ? _value.fontFamily
          : fontFamily // ignore: cast_nullable_to_non_nullable
              as String,
      fontSize: null == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as double,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      bold: null == bold
          ? _value.bold
          : bold // ignore: cast_nullable_to_non_nullable
              as bool,
      italic: null == italic
          ? _value.italic
          : italic // ignore: cast_nullable_to_non_nullable
              as bool,
      alignment: null == alignment
          ? _value.alignment
          : alignment // ignore: cast_nullable_to_non_nullable
              as String,
      spans: null == spans
          ? _value._spans
          : spans // ignore: cast_nullable_to_non_nullable
              as List<TextSpanData>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$TextDataImpl implements _TextData {
  const _$TextDataImpl(
      {required this.x,
      required this.y,
      required this.width,
      required this.height,
      required this.content,
      this.fontFamily = 'sans-serif',
      this.fontSize = 16.0,
      this.color = 0xFF000000,
      this.bold = false,
      this.italic = false,
      this.alignment = 'left',
      final List<TextSpanData> spans = const <TextSpanData>[]})
      : _spans = spans;

  factory _$TextDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$TextDataImplFromJson(json);

  @override
  final double x;
  @override
  final double y;
  @override
  final double width;
  @override
  final double height;
  @override
  final String content;
  @override
  @JsonKey()
  final String fontFamily;
  @override
  @JsonKey()
  final double fontSize;
  @override
  @JsonKey()
  final int color;
  @override
  @JsonKey()
  final bool bold;
  @override
  @JsonKey()
  final bool italic;
  @override
  @JsonKey()
  final String alignment;
// left, center, right
  /// Rich formatting runs. Empty = legacy plain text (render `content`
  /// with the element-level style). Non-empty = concat(span.text) ==
  /// content, rendered with per-span styling.
  final List<TextSpanData> _spans;
// left, center, right
  /// Rich formatting runs. Empty = legacy plain text (render `content`
  /// with the element-level style). Non-empty = concat(span.text) ==
  /// content, rendered with per-span styling.
  @override
  @JsonKey()
  List<TextSpanData> get spans {
    if (_spans is EqualUnmodifiableListView) return _spans;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_spans);
  }

  @override
  String toString() {
    return 'TextData(x: $x, y: $y, width: $width, height: $height, content: $content, fontFamily: $fontFamily, fontSize: $fontSize, color: $color, bold: $bold, italic: $italic, alignment: $alignment, spans: $spans)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TextDataImpl &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.fontFamily, fontFamily) ||
                other.fontFamily == fontFamily) &&
            (identical(other.fontSize, fontSize) ||
                other.fontSize == fontSize) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.bold, bold) || other.bold == bold) &&
            (identical(other.italic, italic) || other.italic == italic) &&
            (identical(other.alignment, alignment) ||
                other.alignment == alignment) &&
            const DeepCollectionEquality().equals(other._spans, _spans));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      x,
      y,
      width,
      height,
      content,
      fontFamily,
      fontSize,
      color,
      bold,
      italic,
      alignment,
      const DeepCollectionEquality().hash(_spans));

  /// Create a copy of TextData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TextDataImplCopyWith<_$TextDataImpl> get copyWith =>
      __$$TextDataImplCopyWithImpl<_$TextDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TextDataImplToJson(
      this,
    );
  }
}

abstract class _TextData implements TextData {
  const factory _TextData(
      {required final double x,
      required final double y,
      required final double width,
      required final double height,
      required final String content,
      final String fontFamily,
      final double fontSize,
      final int color,
      final bool bold,
      final bool italic,
      final String alignment,
      final List<TextSpanData> spans}) = _$TextDataImpl;

  factory _TextData.fromJson(Map<String, dynamic> json) =
      _$TextDataImpl.fromJson;

  @override
  double get x;
  @override
  double get y;
  @override
  double get width;
  @override
  double get height;
  @override
  String get content;
  @override
  String get fontFamily;
  @override
  double get fontSize;
  @override
  int get color;
  @override
  bool get bold;
  @override
  bool get italic;
  @override
  String get alignment; // left, center, right
  /// Rich formatting runs. Empty = legacy plain text (render `content`
  /// with the element-level style). Non-empty = concat(span.text) ==
  /// content, rendered with per-span styling.
  @override
  List<TextSpanData> get spans;

  /// Create a copy of TextData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TextDataImplCopyWith<_$TextDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

MathData _$MathDataFromJson(Map<String, dynamic> json) {
  return _MathData.fromJson(json);
}

/// @nodoc
mixin _$MathData {
  double get x => throw _privateConstructorUsedError;
  double get y => throw _privateConstructorUsedError;
  double get width => throw _privateConstructorUsedError;
  double get height => throw _privateConstructorUsedError;
  String get latex => throw _privateConstructorUsedError;
  bool get displayMode => throw _privateConstructorUsedError;
  int get color => throw _privateConstructorUsedError;
  double get fontSize => throw _privateConstructorUsedError;

  /// Serializes this MathData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MathData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MathDataCopyWith<MathData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MathDataCopyWith<$Res> {
  factory $MathDataCopyWith(MathData value, $Res Function(MathData) then) =
      _$MathDataCopyWithImpl<$Res, MathData>;
  @useResult
  $Res call(
      {double x,
      double y,
      double width,
      double height,
      String latex,
      bool displayMode,
      int color,
      double fontSize});
}

/// @nodoc
class _$MathDataCopyWithImpl<$Res, $Val extends MathData>
    implements $MathDataCopyWith<$Res> {
  _$MathDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MathData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
    Object? latex = null,
    Object? displayMode = null,
    Object? color = null,
    Object? fontSize = null,
  }) {
    return _then(_value.copyWith(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      latex: null == latex
          ? _value.latex
          : latex // ignore: cast_nullable_to_non_nullable
              as String,
      displayMode: null == displayMode
          ? _value.displayMode
          : displayMode // ignore: cast_nullable_to_non_nullable
              as bool,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      fontSize: null == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MathDataImplCopyWith<$Res>
    implements $MathDataCopyWith<$Res> {
  factory _$$MathDataImplCopyWith(
          _$MathDataImpl value, $Res Function(_$MathDataImpl) then) =
      __$$MathDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double x,
      double y,
      double width,
      double height,
      String latex,
      bool displayMode,
      int color,
      double fontSize});
}

/// @nodoc
class __$$MathDataImplCopyWithImpl<$Res>
    extends _$MathDataCopyWithImpl<$Res, _$MathDataImpl>
    implements _$$MathDataImplCopyWith<$Res> {
  __$$MathDataImplCopyWithImpl(
      _$MathDataImpl _value, $Res Function(_$MathDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of MathData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
    Object? latex = null,
    Object? displayMode = null,
    Object? color = null,
    Object? fontSize = null,
  }) {
    return _then(_$MathDataImpl(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      latex: null == latex
          ? _value.latex
          : latex // ignore: cast_nullable_to_non_nullable
              as String,
      displayMode: null == displayMode
          ? _value.displayMode
          : displayMode // ignore: cast_nullable_to_non_nullable
              as bool,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      fontSize: null == fontSize
          ? _value.fontSize
          : fontSize // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MathDataImpl implements _MathData {
  const _$MathDataImpl(
      {required this.x,
      required this.y,
      required this.width,
      required this.height,
      required this.latex,
      this.displayMode = true,
      this.color = 0xFF000000,
      this.fontSize = 24.0});

  factory _$MathDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$MathDataImplFromJson(json);

  @override
  final double x;
  @override
  final double y;
  @override
  final double width;
  @override
  final double height;
  @override
  final String latex;
  @override
  @JsonKey()
  final bool displayMode;
  @override
  @JsonKey()
  final int color;
  @override
  @JsonKey()
  final double fontSize;

  @override
  String toString() {
    return 'MathData(x: $x, y: $y, width: $width, height: $height, latex: $latex, displayMode: $displayMode, color: $color, fontSize: $fontSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MathDataImpl &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height) &&
            (identical(other.latex, latex) || other.latex == latex) &&
            (identical(other.displayMode, displayMode) ||
                other.displayMode == displayMode) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.fontSize, fontSize) ||
                other.fontSize == fontSize));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType, x, y, width, height, latex, displayMode, color, fontSize);

  /// Create a copy of MathData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MathDataImplCopyWith<_$MathDataImpl> get copyWith =>
      __$$MathDataImplCopyWithImpl<_$MathDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MathDataImplToJson(
      this,
    );
  }
}

abstract class _MathData implements MathData {
  const factory _MathData(
      {required final double x,
      required final double y,
      required final double width,
      required final double height,
      required final String latex,
      final bool displayMode,
      final int color,
      final double fontSize}) = _$MathDataImpl;

  factory _MathData.fromJson(Map<String, dynamic> json) =
      _$MathDataImpl.fromJson;

  @override
  double get x;
  @override
  double get y;
  @override
  double get width;
  @override
  double get height;
  @override
  String get latex;
  @override
  bool get displayMode;
  @override
  int get color;
  @override
  double get fontSize;

  /// Create a copy of MathData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MathDataImplCopyWith<_$MathDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ImageData _$ImageDataFromJson(Map<String, dynamic> json) {
  return _ImageData.fromJson(json);
}

/// @nodoc
mixin _$ImageData {
  double get x => throw _privateConstructorUsedError;
  double get y => throw _privateConstructorUsedError;
  double get width => throw _privateConstructorUsedError;
  double get height => throw _privateConstructorUsedError;
  String get assetPath =>
      throw _privateConstructorUsedError; // path relativo in assets/images/
  double get rotation => throw _privateConstructorUsedError; // radianti
  double get opacity => throw _privateConstructorUsedError;
  bool get locked => throw _privateConstructorUsedError;
  bool get flipHorizontal => throw _privateConstructorUsedError;
  String? get comment => throw _privateConstructorUsedError;

  /// Serializes this ImageData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ImageData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ImageDataCopyWith<ImageData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ImageDataCopyWith<$Res> {
  factory $ImageDataCopyWith(ImageData value, $Res Function(ImageData) then) =
      _$ImageDataCopyWithImpl<$Res, ImageData>;
  @useResult
  $Res call(
      {double x,
      double y,
      double width,
      double height,
      String assetPath,
      double rotation,
      double opacity,
      bool locked,
      bool flipHorizontal,
      String? comment});
}

/// @nodoc
class _$ImageDataCopyWithImpl<$Res, $Val extends ImageData>
    implements $ImageDataCopyWith<$Res> {
  _$ImageDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ImageData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
    Object? assetPath = null,
    Object? rotation = null,
    Object? opacity = null,
    Object? locked = null,
    Object? flipHorizontal = null,
    Object? comment = freezed,
  }) {
    return _then(_value.copyWith(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      assetPath: null == assetPath
          ? _value.assetPath
          : assetPath // ignore: cast_nullable_to_non_nullable
              as String,
      rotation: null == rotation
          ? _value.rotation
          : rotation // ignore: cast_nullable_to_non_nullable
              as double,
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      locked: null == locked
          ? _value.locked
          : locked // ignore: cast_nullable_to_non_nullable
              as bool,
      flipHorizontal: null == flipHorizontal
          ? _value.flipHorizontal
          : flipHorizontal // ignore: cast_nullable_to_non_nullable
              as bool,
      comment: freezed == comment
          ? _value.comment
          : comment // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ImageDataImplCopyWith<$Res>
    implements $ImageDataCopyWith<$Res> {
  factory _$$ImageDataImplCopyWith(
          _$ImageDataImpl value, $Res Function(_$ImageDataImpl) then) =
      __$$ImageDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double x,
      double y,
      double width,
      double height,
      String assetPath,
      double rotation,
      double opacity,
      bool locked,
      bool flipHorizontal,
      String? comment});
}

/// @nodoc
class __$$ImageDataImplCopyWithImpl<$Res>
    extends _$ImageDataCopyWithImpl<$Res, _$ImageDataImpl>
    implements _$$ImageDataImplCopyWith<$Res> {
  __$$ImageDataImplCopyWithImpl(
      _$ImageDataImpl _value, $Res Function(_$ImageDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of ImageData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
    Object? assetPath = null,
    Object? rotation = null,
    Object? opacity = null,
    Object? locked = null,
    Object? flipHorizontal = null,
    Object? comment = freezed,
  }) {
    return _then(_$ImageDataImpl(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      assetPath: null == assetPath
          ? _value.assetPath
          : assetPath // ignore: cast_nullable_to_non_nullable
              as String,
      rotation: null == rotation
          ? _value.rotation
          : rotation // ignore: cast_nullable_to_non_nullable
              as double,
      opacity: null == opacity
          ? _value.opacity
          : opacity // ignore: cast_nullable_to_non_nullable
              as double,
      locked: null == locked
          ? _value.locked
          : locked // ignore: cast_nullable_to_non_nullable
              as bool,
      flipHorizontal: null == flipHorizontal
          ? _value.flipHorizontal
          : flipHorizontal // ignore: cast_nullable_to_non_nullable
              as bool,
      comment: freezed == comment
          ? _value.comment
          : comment // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ImageDataImpl implements _ImageData {
  const _$ImageDataImpl(
      {required this.x,
      required this.y,
      required this.width,
      required this.height,
      required this.assetPath,
      this.rotation = 0.0,
      this.opacity = 1.0,
      this.locked = false,
      this.flipHorizontal = false,
      this.comment});

  factory _$ImageDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ImageDataImplFromJson(json);

  @override
  final double x;
  @override
  final double y;
  @override
  final double width;
  @override
  final double height;
  @override
  final String assetPath;
// path relativo in assets/images/
  @override
  @JsonKey()
  final double rotation;
// radianti
  @override
  @JsonKey()
  final double opacity;
  @override
  @JsonKey()
  final bool locked;
  @override
  @JsonKey()
  final bool flipHorizontal;
  @override
  final String? comment;

  @override
  String toString() {
    return 'ImageData(x: $x, y: $y, width: $width, height: $height, assetPath: $assetPath, rotation: $rotation, opacity: $opacity, locked: $locked, flipHorizontal: $flipHorizontal, comment: $comment)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImageDataImpl &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height) &&
            (identical(other.assetPath, assetPath) ||
                other.assetPath == assetPath) &&
            (identical(other.rotation, rotation) ||
                other.rotation == rotation) &&
            (identical(other.opacity, opacity) || other.opacity == opacity) &&
            (identical(other.locked, locked) || other.locked == locked) &&
            (identical(other.flipHorizontal, flipHorizontal) ||
                other.flipHorizontal == flipHorizontal) &&
            (identical(other.comment, comment) || other.comment == comment));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, x, y, width, height, assetPath,
      rotation, opacity, locked, flipHorizontal, comment);

  /// Create a copy of ImageData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ImageDataImplCopyWith<_$ImageDataImpl> get copyWith =>
      __$$ImageDataImplCopyWithImpl<_$ImageDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ImageDataImplToJson(
      this,
    );
  }
}

abstract class _ImageData implements ImageData {
  const factory _ImageData(
      {required final double x,
      required final double y,
      required final double width,
      required final double height,
      required final String assetPath,
      final double rotation,
      final double opacity,
      final bool locked,
      final bool flipHorizontal,
      final String? comment}) = _$ImageDataImpl;

  factory _ImageData.fromJson(Map<String, dynamic> json) =
      _$ImageDataImpl.fromJson;

  @override
  double get x;
  @override
  double get y;
  @override
  double get width;
  @override
  double get height;
  @override
  String get assetPath; // path relativo in assets/images/
  @override
  double get rotation; // radianti
  @override
  double get opacity;
  @override
  bool get locked;
  @override
  bool get flipHorizontal;
  @override
  String? get comment;

  /// Create a copy of ImageData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ImageDataImplCopyWith<_$ImageDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ShapeData _$ShapeDataFromJson(Map<String, dynamic> json) {
  return _ShapeData.fromJson(json);
}

/// @nodoc
mixin _$ShapeData {
  String get shapeType =>
      throw _privateConstructorUsedError; // rectangle, circle, line, arrow, triangle
  double get x1 => throw _privateConstructorUsedError;
  double get y1 => throw _privateConstructorUsedError;
  double get x2 => throw _privateConstructorUsedError;
  double get y2 => throw _privateConstructorUsedError;
  int get strokeColor => throw _privateConstructorUsedError;
  double get strokeWidth =>
      throw _privateConstructorUsedError; // Set when this shape was auto-recognized from a held highlighter
// stroke, so the renderer paints it with the same translucent
// multiply blend as highlighter ink instead of an opaque stroke.
  bool get isHighlighter => throw _privateConstructorUsedError;
  int? get fillColor => throw _privateConstructorUsedError;
  double get rotation =>
      throw _privateConstructorUsedError; // For oblique (non-cardinal) triangles: explicit absolute-page-space
// vertices [apexX, apexY, base1X, base1Y, base2X, base2Y]. When
// present the renderer draws this path directly; when empty it falls
// back to the canonical bbox-relative path with `rotation` applied.
// Cardinal triangles leave this empty (the bbox + rotation already
// describes them exactly via the cardinal-special-case render path).
// Stored on resize via affine bbox-to-bbox vertex remap.
  List<double> get vertices => throw _privateConstructorUsedError;

  /// Serializes this ShapeData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ShapeData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ShapeDataCopyWith<ShapeData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ShapeDataCopyWith<$Res> {
  factory $ShapeDataCopyWith(ShapeData value, $Res Function(ShapeData) then) =
      _$ShapeDataCopyWithImpl<$Res, ShapeData>;
  @useResult
  $Res call(
      {String shapeType,
      double x1,
      double y1,
      double x2,
      double y2,
      int strokeColor,
      double strokeWidth,
      bool isHighlighter,
      int? fillColor,
      double rotation,
      List<double> vertices});
}

/// @nodoc
class _$ShapeDataCopyWithImpl<$Res, $Val extends ShapeData>
    implements $ShapeDataCopyWith<$Res> {
  _$ShapeDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ShapeData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? shapeType = null,
    Object? x1 = null,
    Object? y1 = null,
    Object? x2 = null,
    Object? y2 = null,
    Object? strokeColor = null,
    Object? strokeWidth = null,
    Object? isHighlighter = null,
    Object? fillColor = freezed,
    Object? rotation = null,
    Object? vertices = null,
  }) {
    return _then(_value.copyWith(
      shapeType: null == shapeType
          ? _value.shapeType
          : shapeType // ignore: cast_nullable_to_non_nullable
              as String,
      x1: null == x1
          ? _value.x1
          : x1 // ignore: cast_nullable_to_non_nullable
              as double,
      y1: null == y1
          ? _value.y1
          : y1 // ignore: cast_nullable_to_non_nullable
              as double,
      x2: null == x2
          ? _value.x2
          : x2 // ignore: cast_nullable_to_non_nullable
              as double,
      y2: null == y2
          ? _value.y2
          : y2 // ignore: cast_nullable_to_non_nullable
              as double,
      strokeColor: null == strokeColor
          ? _value.strokeColor
          : strokeColor // ignore: cast_nullable_to_non_nullable
              as int,
      strokeWidth: null == strokeWidth
          ? _value.strokeWidth
          : strokeWidth // ignore: cast_nullable_to_non_nullable
              as double,
      isHighlighter: null == isHighlighter
          ? _value.isHighlighter
          : isHighlighter // ignore: cast_nullable_to_non_nullable
              as bool,
      fillColor: freezed == fillColor
          ? _value.fillColor
          : fillColor // ignore: cast_nullable_to_non_nullable
              as int?,
      rotation: null == rotation
          ? _value.rotation
          : rotation // ignore: cast_nullable_to_non_nullable
              as double,
      vertices: null == vertices
          ? _value.vertices
          : vertices // ignore: cast_nullable_to_non_nullable
              as List<double>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ShapeDataImplCopyWith<$Res>
    implements $ShapeDataCopyWith<$Res> {
  factory _$$ShapeDataImplCopyWith(
          _$ShapeDataImpl value, $Res Function(_$ShapeDataImpl) then) =
      __$$ShapeDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String shapeType,
      double x1,
      double y1,
      double x2,
      double y2,
      int strokeColor,
      double strokeWidth,
      bool isHighlighter,
      int? fillColor,
      double rotation,
      List<double> vertices});
}

/// @nodoc
class __$$ShapeDataImplCopyWithImpl<$Res>
    extends _$ShapeDataCopyWithImpl<$Res, _$ShapeDataImpl>
    implements _$$ShapeDataImplCopyWith<$Res> {
  __$$ShapeDataImplCopyWithImpl(
      _$ShapeDataImpl _value, $Res Function(_$ShapeDataImpl) _then)
      : super(_value, _then);

  /// Create a copy of ShapeData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? shapeType = null,
    Object? x1 = null,
    Object? y1 = null,
    Object? x2 = null,
    Object? y2 = null,
    Object? strokeColor = null,
    Object? strokeWidth = null,
    Object? isHighlighter = null,
    Object? fillColor = freezed,
    Object? rotation = null,
    Object? vertices = null,
  }) {
    return _then(_$ShapeDataImpl(
      shapeType: null == shapeType
          ? _value.shapeType
          : shapeType // ignore: cast_nullable_to_non_nullable
              as String,
      x1: null == x1
          ? _value.x1
          : x1 // ignore: cast_nullable_to_non_nullable
              as double,
      y1: null == y1
          ? _value.y1
          : y1 // ignore: cast_nullable_to_non_nullable
              as double,
      x2: null == x2
          ? _value.x2
          : x2 // ignore: cast_nullable_to_non_nullable
              as double,
      y2: null == y2
          ? _value.y2
          : y2 // ignore: cast_nullable_to_non_nullable
              as double,
      strokeColor: null == strokeColor
          ? _value.strokeColor
          : strokeColor // ignore: cast_nullable_to_non_nullable
              as int,
      strokeWidth: null == strokeWidth
          ? _value.strokeWidth
          : strokeWidth // ignore: cast_nullable_to_non_nullable
              as double,
      isHighlighter: null == isHighlighter
          ? _value.isHighlighter
          : isHighlighter // ignore: cast_nullable_to_non_nullable
              as bool,
      fillColor: freezed == fillColor
          ? _value.fillColor
          : fillColor // ignore: cast_nullable_to_non_nullable
              as int?,
      rotation: null == rotation
          ? _value.rotation
          : rotation // ignore: cast_nullable_to_non_nullable
              as double,
      vertices: null == vertices
          ? _value._vertices
          : vertices // ignore: cast_nullable_to_non_nullable
              as List<double>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ShapeDataImpl implements _ShapeData {
  const _$ShapeDataImpl(
      {required this.shapeType,
      required this.x1,
      required this.y1,
      required this.x2,
      required this.y2,
      this.strokeColor = 0xFF000000,
      this.strokeWidth = 2.0,
      this.isHighlighter = false,
      this.fillColor,
      this.rotation = 0.0,
      final List<double> vertices = const <double>[]})
      : _vertices = vertices;

  factory _$ShapeDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$ShapeDataImplFromJson(json);

  @override
  final String shapeType;
// rectangle, circle, line, arrow, triangle
  @override
  final double x1;
  @override
  final double y1;
  @override
  final double x2;
  @override
  final double y2;
  @override
  @JsonKey()
  final int strokeColor;
  @override
  @JsonKey()
  final double strokeWidth;
// Set when this shape was auto-recognized from a held highlighter
// stroke, so the renderer paints it with the same translucent
// multiply blend as highlighter ink instead of an opaque stroke.
  @override
  @JsonKey()
  final bool isHighlighter;
  @override
  final int? fillColor;
  @override
  @JsonKey()
  final double rotation;
// For oblique (non-cardinal) triangles: explicit absolute-page-space
// vertices [apexX, apexY, base1X, base1Y, base2X, base2Y]. When
// present the renderer draws this path directly; when empty it falls
// back to the canonical bbox-relative path with `rotation` applied.
// Cardinal triangles leave this empty (the bbox + rotation already
// describes them exactly via the cardinal-special-case render path).
// Stored on resize via affine bbox-to-bbox vertex remap.
  final List<double> _vertices;
// For oblique (non-cardinal) triangles: explicit absolute-page-space
// vertices [apexX, apexY, base1X, base1Y, base2X, base2Y]. When
// present the renderer draws this path directly; when empty it falls
// back to the canonical bbox-relative path with `rotation` applied.
// Cardinal triangles leave this empty (the bbox + rotation already
// describes them exactly via the cardinal-special-case render path).
// Stored on resize via affine bbox-to-bbox vertex remap.
  @override
  @JsonKey()
  List<double> get vertices {
    if (_vertices is EqualUnmodifiableListView) return _vertices;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_vertices);
  }

  @override
  String toString() {
    return 'ShapeData(shapeType: $shapeType, x1: $x1, y1: $y1, x2: $x2, y2: $y2, strokeColor: $strokeColor, strokeWidth: $strokeWidth, isHighlighter: $isHighlighter, fillColor: $fillColor, rotation: $rotation, vertices: $vertices)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ShapeDataImpl &&
            (identical(other.shapeType, shapeType) ||
                other.shapeType == shapeType) &&
            (identical(other.x1, x1) || other.x1 == x1) &&
            (identical(other.y1, y1) || other.y1 == y1) &&
            (identical(other.x2, x2) || other.x2 == x2) &&
            (identical(other.y2, y2) || other.y2 == y2) &&
            (identical(other.strokeColor, strokeColor) ||
                other.strokeColor == strokeColor) &&
            (identical(other.strokeWidth, strokeWidth) ||
                other.strokeWidth == strokeWidth) &&
            (identical(other.isHighlighter, isHighlighter) ||
                other.isHighlighter == isHighlighter) &&
            (identical(other.fillColor, fillColor) ||
                other.fillColor == fillColor) &&
            (identical(other.rotation, rotation) ||
                other.rotation == rotation) &&
            const DeepCollectionEquality().equals(other._vertices, _vertices));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      shapeType,
      x1,
      y1,
      x2,
      y2,
      strokeColor,
      strokeWidth,
      isHighlighter,
      fillColor,
      rotation,
      const DeepCollectionEquality().hash(_vertices));

  /// Create a copy of ShapeData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ShapeDataImplCopyWith<_$ShapeDataImpl> get copyWith =>
      __$$ShapeDataImplCopyWithImpl<_$ShapeDataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ShapeDataImplToJson(
      this,
    );
  }
}

abstract class _ShapeData implements ShapeData {
  const factory _ShapeData(
      {required final String shapeType,
      required final double x1,
      required final double y1,
      required final double x2,
      required final double y2,
      final int strokeColor,
      final double strokeWidth,
      final bool isHighlighter,
      final int? fillColor,
      final double rotation,
      final List<double> vertices}) = _$ShapeDataImpl;

  factory _ShapeData.fromJson(Map<String, dynamic> json) =
      _$ShapeDataImpl.fromJson;

  @override
  String get shapeType; // rectangle, circle, line, arrow, triangle
  @override
  double get x1;
  @override
  double get y1;
  @override
  double get x2;
  @override
  double get y2;
  @override
  int get strokeColor;
  @override
  double
      get strokeWidth; // Set when this shape was auto-recognized from a held highlighter
// stroke, so the renderer paints it with the same translucent
// multiply blend as highlighter ink instead of an opaque stroke.
  @override
  bool get isHighlighter;
  @override
  int? get fillColor;
  @override
  double
      get rotation; // For oblique (non-cardinal) triangles: explicit absolute-page-space
// vertices [apexX, apexY, base1X, base1Y, base2X, base2Y]. When
// present the renderer draws this path directly; when empty it falls
// back to the canonical bbox-relative path with `rotation` applied.
// Cardinal triangles leave this empty (the bbox + rotation already
// describes them exactly via the cardinal-special-case render path).
// Stored on resize via affine bbox-to-bbox vertex remap.
  @override
  List<double> get vertices;

  /// Create a copy of ShapeData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ShapeDataImplCopyWith<_$ShapeDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PdfTextLayer _$PdfTextLayerFromJson(Map<String, dynamic> json) {
  return _PdfTextLayer.fromJson(json);
}

/// @nodoc
mixin _$PdfTextLayer {
  /// The `assetPath` of the PDF-page image this text overlays (ties the
  /// layer back to its raster for debugging / future re-mapping).
  String get sourceAssetPath => throw _privateConstructorUsedError;
  String get source => throw _privateConstructorUsedError; // 'embedded' | 'ocr'
  double? get confidence =>
      throw _privateConstructorUsedError; // null for embedded; mean confidence for OCR
  List<PdfTextRun> get runs => throw _privateConstructorUsedError;

  /// Serializes this PdfTextLayer to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PdfTextLayer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PdfTextLayerCopyWith<PdfTextLayer> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PdfTextLayerCopyWith<$Res> {
  factory $PdfTextLayerCopyWith(
          PdfTextLayer value, $Res Function(PdfTextLayer) then) =
      _$PdfTextLayerCopyWithImpl<$Res, PdfTextLayer>;
  @useResult
  $Res call(
      {String sourceAssetPath,
      String source,
      double? confidence,
      List<PdfTextRun> runs});
}

/// @nodoc
class _$PdfTextLayerCopyWithImpl<$Res, $Val extends PdfTextLayer>
    implements $PdfTextLayerCopyWith<$Res> {
  _$PdfTextLayerCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PdfTextLayer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sourceAssetPath = null,
    Object? source = null,
    Object? confidence = freezed,
    Object? runs = null,
  }) {
    return _then(_value.copyWith(
      sourceAssetPath: null == sourceAssetPath
          ? _value.sourceAssetPath
          : sourceAssetPath // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as String,
      confidence: freezed == confidence
          ? _value.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double?,
      runs: null == runs
          ? _value.runs
          : runs // ignore: cast_nullable_to_non_nullable
              as List<PdfTextRun>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PdfTextLayerImplCopyWith<$Res>
    implements $PdfTextLayerCopyWith<$Res> {
  factory _$$PdfTextLayerImplCopyWith(
          _$PdfTextLayerImpl value, $Res Function(_$PdfTextLayerImpl) then) =
      __$$PdfTextLayerImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String sourceAssetPath,
      String source,
      double? confidence,
      List<PdfTextRun> runs});
}

/// @nodoc
class __$$PdfTextLayerImplCopyWithImpl<$Res>
    extends _$PdfTextLayerCopyWithImpl<$Res, _$PdfTextLayerImpl>
    implements _$$PdfTextLayerImplCopyWith<$Res> {
  __$$PdfTextLayerImplCopyWithImpl(
      _$PdfTextLayerImpl _value, $Res Function(_$PdfTextLayerImpl) _then)
      : super(_value, _then);

  /// Create a copy of PdfTextLayer
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sourceAssetPath = null,
    Object? source = null,
    Object? confidence = freezed,
    Object? runs = null,
  }) {
    return _then(_$PdfTextLayerImpl(
      sourceAssetPath: null == sourceAssetPath
          ? _value.sourceAssetPath
          : sourceAssetPath // ignore: cast_nullable_to_non_nullable
              as String,
      source: null == source
          ? _value.source
          : source // ignore: cast_nullable_to_non_nullable
              as String,
      confidence: freezed == confidence
          ? _value.confidence
          : confidence // ignore: cast_nullable_to_non_nullable
              as double?,
      runs: null == runs
          ? _value._runs
          : runs // ignore: cast_nullable_to_non_nullable
              as List<PdfTextRun>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PdfTextLayerImpl implements _PdfTextLayer {
  const _$PdfTextLayerImpl(
      {required this.sourceAssetPath,
      this.source = 'embedded',
      this.confidence,
      final List<PdfTextRun> runs = const <PdfTextRun>[]})
      : _runs = runs;

  factory _$PdfTextLayerImpl.fromJson(Map<String, dynamic> json) =>
      _$$PdfTextLayerImplFromJson(json);

  /// The `assetPath` of the PDF-page image this text overlays (ties the
  /// layer back to its raster for debugging / future re-mapping).
  @override
  final String sourceAssetPath;
  @override
  @JsonKey()
  final String source;
// 'embedded' | 'ocr'
  @override
  final double? confidence;
// null for embedded; mean confidence for OCR
  final List<PdfTextRun> _runs;
// null for embedded; mean confidence for OCR
  @override
  @JsonKey()
  List<PdfTextRun> get runs {
    if (_runs is EqualUnmodifiableListView) return _runs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_runs);
  }

  @override
  String toString() {
    return 'PdfTextLayer(sourceAssetPath: $sourceAssetPath, source: $source, confidence: $confidence, runs: $runs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PdfTextLayerImpl &&
            (identical(other.sourceAssetPath, sourceAssetPath) ||
                other.sourceAssetPath == sourceAssetPath) &&
            (identical(other.source, source) || other.source == source) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            const DeepCollectionEquality().equals(other._runs, _runs));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, sourceAssetPath, source,
      confidence, const DeepCollectionEquality().hash(_runs));

  /// Create a copy of PdfTextLayer
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PdfTextLayerImplCopyWith<_$PdfTextLayerImpl> get copyWith =>
      __$$PdfTextLayerImplCopyWithImpl<_$PdfTextLayerImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PdfTextLayerImplToJson(
      this,
    );
  }
}

abstract class _PdfTextLayer implements PdfTextLayer {
  const factory _PdfTextLayer(
      {required final String sourceAssetPath,
      final String source,
      final double? confidence,
      final List<PdfTextRun> runs}) = _$PdfTextLayerImpl;

  factory _PdfTextLayer.fromJson(Map<String, dynamic> json) =
      _$PdfTextLayerImpl.fromJson;

  /// The `assetPath` of the PDF-page image this text overlays (ties the
  /// layer back to its raster for debugging / future re-mapping).
  @override
  String get sourceAssetPath;
  @override
  String get source; // 'embedded' | 'ocr'
  @override
  double? get confidence; // null for embedded; mean confidence for OCR
  @override
  List<PdfTextRun> get runs;

  /// Create a copy of PdfTextLayer
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PdfTextLayerImplCopyWith<_$PdfTextLayerImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PdfTextRun _$PdfTextRunFromJson(Map<String, dynamic> json) {
  return _PdfTextRun.fromJson(json);
}

/// @nodoc
mixin _$PdfTextRun {
  String get text => throw _privateConstructorUsedError;
  double get x => throw _privateConstructorUsedError;
  double get y => throw _privateConstructorUsedError;
  double get width => throw _privateConstructorUsedError;
  double get height => throw _privateConstructorUsedError;
  List<PdfCharBox> get chars => throw _privateConstructorUsedError;

  /// Serializes this PdfTextRun to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PdfTextRun
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PdfTextRunCopyWith<PdfTextRun> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PdfTextRunCopyWith<$Res> {
  factory $PdfTextRunCopyWith(
          PdfTextRun value, $Res Function(PdfTextRun) then) =
      _$PdfTextRunCopyWithImpl<$Res, PdfTextRun>;
  @useResult
  $Res call(
      {String text,
      double x,
      double y,
      double width,
      double height,
      List<PdfCharBox> chars});
}

/// @nodoc
class _$PdfTextRunCopyWithImpl<$Res, $Val extends PdfTextRun>
    implements $PdfTextRunCopyWith<$Res> {
  _$PdfTextRunCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PdfTextRun
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? text = null,
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
    Object? chars = null,
  }) {
    return _then(_value.copyWith(
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      chars: null == chars
          ? _value.chars
          : chars // ignore: cast_nullable_to_non_nullable
              as List<PdfCharBox>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PdfTextRunImplCopyWith<$Res>
    implements $PdfTextRunCopyWith<$Res> {
  factory _$$PdfTextRunImplCopyWith(
          _$PdfTextRunImpl value, $Res Function(_$PdfTextRunImpl) then) =
      __$$PdfTextRunImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String text,
      double x,
      double y,
      double width,
      double height,
      List<PdfCharBox> chars});
}

/// @nodoc
class __$$PdfTextRunImplCopyWithImpl<$Res>
    extends _$PdfTextRunCopyWithImpl<$Res, _$PdfTextRunImpl>
    implements _$$PdfTextRunImplCopyWith<$Res> {
  __$$PdfTextRunImplCopyWithImpl(
      _$PdfTextRunImpl _value, $Res Function(_$PdfTextRunImpl) _then)
      : super(_value, _then);

  /// Create a copy of PdfTextRun
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? text = null,
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
    Object? chars = null,
  }) {
    return _then(_$PdfTextRunImpl(
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
      chars: null == chars
          ? _value._chars
          : chars // ignore: cast_nullable_to_non_nullable
              as List<PdfCharBox>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PdfTextRunImpl implements _PdfTextRun {
  const _$PdfTextRunImpl(
      {required this.text,
      required this.x,
      required this.y,
      required this.width,
      required this.height,
      final List<PdfCharBox> chars = const <PdfCharBox>[]})
      : _chars = chars;

  factory _$PdfTextRunImpl.fromJson(Map<String, dynamic> json) =>
      _$$PdfTextRunImplFromJson(json);

  @override
  final String text;
  @override
  final double x;
  @override
  final double y;
  @override
  final double width;
  @override
  final double height;
  final List<PdfCharBox> _chars;
  @override
  @JsonKey()
  List<PdfCharBox> get chars {
    if (_chars is EqualUnmodifiableListView) return _chars;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_chars);
  }

  @override
  String toString() {
    return 'PdfTextRun(text: $text, x: $x, y: $y, width: $width, height: $height, chars: $chars)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PdfTextRunImpl &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height) &&
            const DeepCollectionEquality().equals(other._chars, _chars));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, text, x, y, width, height,
      const DeepCollectionEquality().hash(_chars));

  /// Create a copy of PdfTextRun
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PdfTextRunImplCopyWith<_$PdfTextRunImpl> get copyWith =>
      __$$PdfTextRunImplCopyWithImpl<_$PdfTextRunImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PdfTextRunImplToJson(
      this,
    );
  }
}

abstract class _PdfTextRun implements PdfTextRun {
  const factory _PdfTextRun(
      {required final String text,
      required final double x,
      required final double y,
      required final double width,
      required final double height,
      final List<PdfCharBox> chars}) = _$PdfTextRunImpl;

  factory _PdfTextRun.fromJson(Map<String, dynamic> json) =
      _$PdfTextRunImpl.fromJson;

  @override
  String get text;
  @override
  double get x;
  @override
  double get y;
  @override
  double get width;
  @override
  double get height;
  @override
  List<PdfCharBox> get chars;

  /// Create a copy of PdfTextRun
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PdfTextRunImplCopyWith<_$PdfTextRunImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PdfCharBox _$PdfCharBoxFromJson(Map<String, dynamic> json) {
  return _PdfCharBox.fromJson(json);
}

/// @nodoc
mixin _$PdfCharBox {
  double get x => throw _privateConstructorUsedError;
  double get y => throw _privateConstructorUsedError;
  double get width => throw _privateConstructorUsedError;
  double get height => throw _privateConstructorUsedError;

  /// Serializes this PdfCharBox to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of PdfCharBox
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PdfCharBoxCopyWith<PdfCharBox> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PdfCharBoxCopyWith<$Res> {
  factory $PdfCharBoxCopyWith(
          PdfCharBox value, $Res Function(PdfCharBox) then) =
      _$PdfCharBoxCopyWithImpl<$Res, PdfCharBox>;
  @useResult
  $Res call({double x, double y, double width, double height});
}

/// @nodoc
class _$PdfCharBoxCopyWithImpl<$Res, $Val extends PdfCharBox>
    implements $PdfCharBoxCopyWith<$Res> {
  _$PdfCharBoxCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PdfCharBox
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
  }) {
    return _then(_value.copyWith(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PdfCharBoxImplCopyWith<$Res>
    implements $PdfCharBoxCopyWith<$Res> {
  factory _$$PdfCharBoxImplCopyWith(
          _$PdfCharBoxImpl value, $Res Function(_$PdfCharBoxImpl) then) =
      __$$PdfCharBoxImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double x, double y, double width, double height});
}

/// @nodoc
class __$$PdfCharBoxImplCopyWithImpl<$Res>
    extends _$PdfCharBoxCopyWithImpl<$Res, _$PdfCharBoxImpl>
    implements _$$PdfCharBoxImplCopyWith<$Res> {
  __$$PdfCharBoxImplCopyWithImpl(
      _$PdfCharBoxImpl _value, $Res Function(_$PdfCharBoxImpl) _then)
      : super(_value, _then);

  /// Create a copy of PdfCharBox
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? x = null,
    Object? y = null,
    Object? width = null,
    Object? height = null,
  }) {
    return _then(_$PdfCharBoxImpl(
      x: null == x
          ? _value.x
          : x // ignore: cast_nullable_to_non_nullable
              as double,
      y: null == y
          ? _value.y
          : y // ignore: cast_nullable_to_non_nullable
              as double,
      width: null == width
          ? _value.width
          : width // ignore: cast_nullable_to_non_nullable
              as double,
      height: null == height
          ? _value.height
          : height // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PdfCharBoxImpl implements _PdfCharBox {
  const _$PdfCharBoxImpl(
      {required this.x,
      required this.y,
      required this.width,
      required this.height});

  factory _$PdfCharBoxImpl.fromJson(Map<String, dynamic> json) =>
      _$$PdfCharBoxImplFromJson(json);

  @override
  final double x;
  @override
  final double y;
  @override
  final double width;
  @override
  final double height;

  @override
  String toString() {
    return 'PdfCharBox(x: $x, y: $y, width: $width, height: $height)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PdfCharBoxImpl &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.width, width) || other.width == width) &&
            (identical(other.height, height) || other.height == height));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, x, y, width, height);

  /// Create a copy of PdfCharBox
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PdfCharBoxImplCopyWith<_$PdfCharBoxImpl> get copyWith =>
      __$$PdfCharBoxImplCopyWithImpl<_$PdfCharBoxImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PdfCharBoxImplToJson(
      this,
    );
  }
}

abstract class _PdfCharBox implements PdfCharBox {
  const factory _PdfCharBox(
      {required final double x,
      required final double y,
      required final double width,
      required final double height}) = _$PdfCharBoxImpl;

  factory _PdfCharBox.fromJson(Map<String, dynamic> json) =
      _$PdfCharBoxImpl.fromJson;

  @override
  double get x;
  @override
  double get y;
  @override
  double get width;
  @override
  double get height;

  /// Create a copy of PdfCharBox
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PdfCharBoxImplCopyWith<_$PdfCharBoxImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SyncMetadata _$SyncMetadataFromJson(Map<String, dynamic> json) {
  return _SyncMetadata.fromJson(json);
}

/// @nodoc
mixin _$SyncMetadata {
  String get notebookId => throw _privateConstructorUsedError;
  String get remotePath => throw _privateConstructorUsedError;
  String? get localPath => throw _privateConstructorUsedError;
  String? get etag => throw _privateConstructorUsedError;
  DateTime? get lastSynced => throw _privateConstructorUsedError;
  String get status =>
      throw _privateConstructorUsedError; // synced, modified, conflict, new
  List<String> get dirtyPages => throw _privateConstructorUsedError;

  /// Serializes this SyncMetadata to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SyncMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SyncMetadataCopyWith<SyncMetadata> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SyncMetadataCopyWith<$Res> {
  factory $SyncMetadataCopyWith(
          SyncMetadata value, $Res Function(SyncMetadata) then) =
      _$SyncMetadataCopyWithImpl<$Res, SyncMetadata>;
  @useResult
  $Res call(
      {String notebookId,
      String remotePath,
      String? localPath,
      String? etag,
      DateTime? lastSynced,
      String status,
      List<String> dirtyPages});
}

/// @nodoc
class _$SyncMetadataCopyWithImpl<$Res, $Val extends SyncMetadata>
    implements $SyncMetadataCopyWith<$Res> {
  _$SyncMetadataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SyncMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? notebookId = null,
    Object? remotePath = null,
    Object? localPath = freezed,
    Object? etag = freezed,
    Object? lastSynced = freezed,
    Object? status = null,
    Object? dirtyPages = null,
  }) {
    return _then(_value.copyWith(
      notebookId: null == notebookId
          ? _value.notebookId
          : notebookId // ignore: cast_nullable_to_non_nullable
              as String,
      remotePath: null == remotePath
          ? _value.remotePath
          : remotePath // ignore: cast_nullable_to_non_nullable
              as String,
      localPath: freezed == localPath
          ? _value.localPath
          : localPath // ignore: cast_nullable_to_non_nullable
              as String?,
      etag: freezed == etag
          ? _value.etag
          : etag // ignore: cast_nullable_to_non_nullable
              as String?,
      lastSynced: freezed == lastSynced
          ? _value.lastSynced
          : lastSynced // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      dirtyPages: null == dirtyPages
          ? _value.dirtyPages
          : dirtyPages // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SyncMetadataImplCopyWith<$Res>
    implements $SyncMetadataCopyWith<$Res> {
  factory _$$SyncMetadataImplCopyWith(
          _$SyncMetadataImpl value, $Res Function(_$SyncMetadataImpl) then) =
      __$$SyncMetadataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String notebookId,
      String remotePath,
      String? localPath,
      String? etag,
      DateTime? lastSynced,
      String status,
      List<String> dirtyPages});
}

/// @nodoc
class __$$SyncMetadataImplCopyWithImpl<$Res>
    extends _$SyncMetadataCopyWithImpl<$Res, _$SyncMetadataImpl>
    implements _$$SyncMetadataImplCopyWith<$Res> {
  __$$SyncMetadataImplCopyWithImpl(
      _$SyncMetadataImpl _value, $Res Function(_$SyncMetadataImpl) _then)
      : super(_value, _then);

  /// Create a copy of SyncMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? notebookId = null,
    Object? remotePath = null,
    Object? localPath = freezed,
    Object? etag = freezed,
    Object? lastSynced = freezed,
    Object? status = null,
    Object? dirtyPages = null,
  }) {
    return _then(_$SyncMetadataImpl(
      notebookId: null == notebookId
          ? _value.notebookId
          : notebookId // ignore: cast_nullable_to_non_nullable
              as String,
      remotePath: null == remotePath
          ? _value.remotePath
          : remotePath // ignore: cast_nullable_to_non_nullable
              as String,
      localPath: freezed == localPath
          ? _value.localPath
          : localPath // ignore: cast_nullable_to_non_nullable
              as String?,
      etag: freezed == etag
          ? _value.etag
          : etag // ignore: cast_nullable_to_non_nullable
              as String?,
      lastSynced: freezed == lastSynced
          ? _value.lastSynced
          : lastSynced // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      status: null == status
          ? _value.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      dirtyPages: null == dirtyPages
          ? _value._dirtyPages
          : dirtyPages // ignore: cast_nullable_to_non_nullable
              as List<String>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$SyncMetadataImpl implements _SyncMetadata {
  const _$SyncMetadataImpl(
      {required this.notebookId,
      required this.remotePath,
      this.localPath,
      this.etag,
      this.lastSynced,
      this.status = 'synced',
      final List<String> dirtyPages = const []})
      : _dirtyPages = dirtyPages;

  factory _$SyncMetadataImpl.fromJson(Map<String, dynamic> json) =>
      _$$SyncMetadataImplFromJson(json);

  @override
  final String notebookId;
  @override
  final String remotePath;
  @override
  final String? localPath;
  @override
  final String? etag;
  @override
  final DateTime? lastSynced;
  @override
  @JsonKey()
  final String status;
// synced, modified, conflict, new
  final List<String> _dirtyPages;
// synced, modified, conflict, new
  @override
  @JsonKey()
  List<String> get dirtyPages {
    if (_dirtyPages is EqualUnmodifiableListView) return _dirtyPages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_dirtyPages);
  }

  @override
  String toString() {
    return 'SyncMetadata(notebookId: $notebookId, remotePath: $remotePath, localPath: $localPath, etag: $etag, lastSynced: $lastSynced, status: $status, dirtyPages: $dirtyPages)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SyncMetadataImpl &&
            (identical(other.notebookId, notebookId) ||
                other.notebookId == notebookId) &&
            (identical(other.remotePath, remotePath) ||
                other.remotePath == remotePath) &&
            (identical(other.localPath, localPath) ||
                other.localPath == localPath) &&
            (identical(other.etag, etag) || other.etag == etag) &&
            (identical(other.lastSynced, lastSynced) ||
                other.lastSynced == lastSynced) &&
            (identical(other.status, status) || other.status == status) &&
            const DeepCollectionEquality()
                .equals(other._dirtyPages, _dirtyPages));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      notebookId,
      remotePath,
      localPath,
      etag,
      lastSynced,
      status,
      const DeepCollectionEquality().hash(_dirtyPages));

  /// Create a copy of SyncMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SyncMetadataImplCopyWith<_$SyncMetadataImpl> get copyWith =>
      __$$SyncMetadataImplCopyWithImpl<_$SyncMetadataImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SyncMetadataImplToJson(
      this,
    );
  }
}

abstract class _SyncMetadata implements SyncMetadata {
  const factory _SyncMetadata(
      {required final String notebookId,
      required final String remotePath,
      final String? localPath,
      final String? etag,
      final DateTime? lastSynced,
      final String status,
      final List<String> dirtyPages}) = _$SyncMetadataImpl;

  factory _SyncMetadata.fromJson(Map<String, dynamic> json) =
      _$SyncMetadataImpl.fromJson;

  @override
  String get notebookId;
  @override
  String get remotePath;
  @override
  String? get localPath;
  @override
  String? get etag;
  @override
  DateTime? get lastSynced;
  @override
  String get status; // synced, modified, conflict, new
  @override
  List<String> get dirtyPages;

  /// Create a copy of SyncMetadata
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SyncMetadataImplCopyWith<_$SyncMetadataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
