// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get csPdfTextCopied => 'テキストをコピーしました';

  @override
  String csCopyFailed(String error) {
    return 'コピーに失敗しました：$error';
  }

  @override
  String get csCopy => 'コピー';

  @override
  String get csSyncInProgress => '同期中です…';

  @override
  String get csSaved => '保存しました';

  @override
  String csErrorGeneric(String error) {
    return 'エラー：$error';
  }

  @override
  String get csSelectionCopied => '選択範囲をコピーしました';

  @override
  String get csSelectionCut => '選択範囲を切り取りました';

  @override
  String get csShortcutsTitle => 'キーボードショートカット';

  @override
  String get csShortcutGroupGeneral => '一般';

  @override
  String get csSaveNow => '今すぐ保存';

  @override
  String get csShortcutUndo => '元に戻す';

  @override
  String get csShortcutRedo => 'やり直す';

  @override
  String get csSelectAll => 'すべて選択';

  @override
  String get csShortcutResetZoom => 'ズームをリセットする';

  @override
  String get csShortcutDeselect => '選択解除／キャンセル';

  @override
  String get csShortcutThisGuide => 'ショートカット一覧';

  @override
  String get csShortcutGroupClipboard => 'クリップボード';

  @override
  String get csShortcutCopySelection => '選択範囲をコピー';

  @override
  String get csShortcutCutSelection => '選択範囲を切り取る';

  @override
  String get csPaste => '貼り付け';

  @override
  String get csShortcutDuplicateSelection => '選択範囲を複製';

  @override
  String get csShortcutKeyDeleteBackspace => 'Del / バックスペース';

  @override
  String get csShortcutDeleteElementOrSelection => '要素または選択範囲を削除する';

  @override
  String get csShortcutGroupTools => 'ツール';

  @override
  String get csToolPen => 'ペン';

  @override
  String get csToolBrush => 'ブラシ';

  @override
  String get csToolEraser => '消しゴム';

  @override
  String get csToolLasso => 'なげなわ';

  @override
  String get csToolHand => '手のひら（移動）';

  @override
  String get csToolText => 'テキスト';

  @override
  String get csToolShape => '図形';

  @override
  String get csClose => '閉じる';

  @override
  String get csUnsavedChangesTitle => '未保存の変更';

  @override
  String get csLocalSaveFailed => 'この端末に保存できません。自動で再試行しています。アプリを閉じないでください。';

  @override
  String get csLocalSaveFailedNoSpace =>
      'この端末の空き容量が不足しているため、最新の変更を保存できません。空き容量を確保すると、保存を自動で再試行します。';

  @override
  String get csUnsavedLocalBody => '最新の変更がこの端末に保存されていません。今閉じると変更が失われます。';

  @override
  String csPreviewBanner(String name) {
    return '「$name」のプレビューです。ライブラリに未追加のため、ここでの変更は保存されません。';
  }

  @override
  String csPreviewBannerOwned(String name) {
    return '「$name」のプレビューです。ライブラリにコピーがあります。ここでの変更は保存されません。';
  }

  @override
  String get csPreviewAdd => 'ライブラリに追加';

  @override
  String get csPreviewAddCopy => 'コピーとして追加';

  @override
  String get csPreviewOpenMine => '自分のコピーを開く';

  @override
  String libOpenAfterClose(String name) {
    return '現在のノートブックを閉じると「$name」が開きます。';
  }

  @override
  String get csRetrySave => '再試行';

  @override
  String get csDiscard => '破棄';

  @override
  String get csCancel => 'キャンセル';

  @override
  String get csSave => '保存';

  @override
  String get csOpeningLink => 'リンクを開いています…';

  @override
  String get csCannotOpenLink => 'リンクを開けません';

  @override
  String get csCameraUnavailable => 'この端末ではカメラを利用できません';

  @override
  String get csPhotoCaptureFailed => '写真を撮影できませんでした';

  @override
  String get csPdfRasterizing => 'PDFを画像に変換中…';

  @override
  String csPdfImportProgress(int done, int total) {
    return 'PDFをインポート中：$done/$total';
  }

  @override
  String get csPdfReadFailed => 'PDFを読み込めません。ページが見つかりませんでした。';

  @override
  String csPdfImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
    );
    return 'PDFをインポートしました（$_temp0）';
  }

  @override
  String get csNoNotebookOpen => 'ノートブックが開いていません';

  @override
  String get csNoPages => 'ページがありません';

  @override
  String get csRetrySync => '同期を再試行';

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページを白紙に置き換えました',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'ページの削除';

  @override
  String csMissingDownloadingTitle(int page) {
    return '$pageページをダウンロード中…';
  }

  @override
  String get csMissingDownloadingBody =>
      'このページをサーバーからダウンロードしています。完了するとここに表示されます。';

  @override
  String csMissingOfflineTitle(int page) {
    return '$pageページは未ダウンロードです';
  }

  @override
  String get csMissingOfflineBody =>
      'このページは端末に保存されておらず、サーバーからも応答がありません。再接続後に自動でダウンロードして表示します。';

  @override
  String csMissingGoneTitle(int page) {
    return '$pageページがありません';
  }

  @override
  String get csMissingGoneBody =>
      'このページのファイルが端末にもサーバーにもありません。別の端末でページを表示できる場合は、そちらで開いてください。再アップロードされると、ここにも表示されます。';

  @override
  String get csMissingNoServerBody =>
      'このページのファイルがこの端末にありません。このノートブックはサーバーと同期していません。';

  @override
  String get csMissingPreviousPage => '前のページへ';

  @override
  String get csMissingLastResort => 'ほかの端末にもページが残っていない場合のみ実行してください。';

  @override
  String get csMissingReplaceAction => '白紙のページに置き換える';

  @override
  String csMissingReplaceAll(int count) {
    return 'すべて白紙に置き換える（$countページ）';
  }

  @override
  String csMissingReplaceConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページを白紙に置き換えますか？',
    );
    return '$_temp0';
  }

  @override
  String csMissingReplaceConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '白紙への置き換えは、同期しているすべての端末に反映されます。元のページが別の端末に残っている場合も上書きされます。',
    );
    return '$_temp0';
  }

  @override
  String get csMissingDeleteConfirmTitle => 'ページを削除しますか？';

  @override
  String get csMissingDeleteConfirmBody => 'ページは、同期されたすべての端末のノートブックから削除されます。';

  @override
  String csSyncProgressCount(int done, int total) {
    return '$done/$total を同期中';
  }

  @override
  String get csSyncing => '同期中…';

  @override
  String csShapeRecognizedLabel(String shape) {
    return '図形：$shape';
  }

  @override
  String get csConfirmShapeSemantics => '認識した図形を確認';

  @override
  String get csConfirm => '確認';

  @override
  String get csCancelShapeSemantics => '認識した図形をキャンセル';

  @override
  String csTapToPlaceSymbol(String name) {
    return 'タップして「$name」を配置';
  }

  @override
  String get csCancelSymbolInsertSemantics => 'シンボルの挿入をキャンセルする';

  @override
  String get csTapToPlaceCopy => 'タップしてコピーを配置します';

  @override
  String get csCancelPasteSemantics => '貼り付けをキャンセル';

  @override
  String get csNewPage => '新しいページ';

  @override
  String get csImageCopied => '画像をコピーしました';

  @override
  String get csImageCut => '画像を切り取りました';

  @override
  String get csImageCommentTitle => '画像のコメント';

  @override
  String get csAddCommentHint => 'コメントを追加…';

  @override
  String get csRemove => '削除する';

  @override
  String get csCut => '切り取り';

  @override
  String get csDuplicate => '複製';

  @override
  String get csSelectionDuplicated => '選択範囲が複製されました';

  @override
  String get csChangeColor => '色を変更する';

  @override
  String get csThickness => '線の太さ';

  @override
  String get csDelete => '削除';

  @override
  String get csMore => 'その他';

  @override
  String get csPresentationMode => 'プレゼンテーションモード';

  @override
  String get csPresentationModeSub => 'ツールを隠して全画面表示にし、ページを見せやすくします';

  @override
  String get csLaserSub => 'ページに書き込まずに指し示します';

  @override
  String get csRecognizeHandwriting => '手書きを認識する';

  @override
  String get csRecognizeHandwritingSub => '手書き文字を端末上で認識し、検索できるテキストに変換します';

  @override
  String get csRecognizeInProgress => '認識中…';

  @override
  String get csRecognizeNothing => 'テキストが認識されませんでした。';

  @override
  String csRecognizeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count行を認識しました',
    );
    return '$_temp0。';
  }

  @override
  String csRecognizeFailed(String error) {
    return '認識失敗：$error';
  }

  @override
  String get csShareLink => 'リンク経由で共有';

  @override
  String get csShareLinkSub => 'PDFをNextcloudにアップロードし、公開リンクを作成します';

  @override
  String get csShareLinkInProgress => 'リンクを作成中…';

  @override
  String get csShareLinkTitle => '公開リンク';

  @override
  String get csShareLinkBody =>
      'リンクを知っている人は誰でもPDFを閲覧できます。リンクはNextcloudで無効にできます。';

  @override
  String get csShareLinkCopied => 'リンクがクリップボードにコピーされました。';

  @override
  String csShareLinkFailed(String error) {
    return '共有に失敗しました：$error';
  }

  @override
  String get csCopyLink => 'リンクをコピー';

  @override
  String get csShare => '共有';

  @override
  String get csRevokeLink => 'リンクを無効にする';

  @override
  String get csRevokeLinkDone => 'リンクを無効にしました。';

  @override
  String get csShareLinkUpdate => '共有PDFを更新する';

  @override
  String get csShareLinkUpdated => 'PDFを更新しました。';

  @override
  String get csChangeSelectionColor => '選択範囲の色を変更';

  @override
  String get csSelectionThickness => '選択した線の太さ';

  @override
  String csWidthPx(String width) {
    return '$width px';
  }

  @override
  String get csFlipHorizontal => '水平方向に反転';

  @override
  String get csFlipVertical => '垂直方向に反転';

  @override
  String get csCopyAsImage => '画像としてコピー';

  @override
  String get csPasteInAnotherNotebook => '別のノートブックに貼り付け…';

  @override
  String get csKeyDelete => 'Del';

  @override
  String get csCreateSymbol => 'シンボルの作成';

  @override
  String get csSelect => '選択';

  @override
  String get csImportFile => 'ファイルをインポート…';

  @override
  String get csTakePhoto => '写真を撮る';

  @override
  String get csInsertText => 'テキストの挿入';

  @override
  String csInsertSymbolCount(int count) {
    return 'シンボルを挿入（$count）';
  }

  @override
  String get csClearPage => 'ページをクリアする';

  @override
  String get csExportPng => 'PNG をエクスポート';

  @override
  String get csExportPdf => 'PDFをエクスポート';

  @override
  String get csClearPageConfirmBody => 'このページ上のすべての要素が削除されます。続行しますか？';

  @override
  String get csClear => 'クリア';

  @override
  String get csCreateSymbolTitle => '再利用可能なシンボルを作成する';

  @override
  String get csSymbolNameLabel => 'シンボル名';

  @override
  String get csLibraryLabel => 'ライブラリ：';

  @override
  String get csNoLibraryNotice => '既存のライブラリはありません。 「シンボル」ライブラリが作成されます。';

  @override
  String get csCreate => '作成';

  @override
  String csSymbolCreated(String name) {
    return 'シンボル「$name」が作成されました。';
  }

  @override
  String csSaveFileDialogTitle(String fileName) {
    return '$fileNameを保存';
  }

  @override
  String get csExportCurrentPagePng => '現在のページ (PNG)';

  @override
  String get csExportCurrentChapter => '現在の章';

  @override
  String get csExportEntireNotebook => 'ノートブック全体';

  @override
  String csExportingPages(int count) {
    return '$countページをエクスポートしています…';
  }

  @override
  String csChooseFolderForImages(int count) {
    return '$count枚の画像の保存先フォルダを選んでください';
  }

  @override
  String csPngExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページをPNGでエクスポートしました',
    );
    return '$_temp0';
  }

  @override
  String csExportError(String error) {
    return 'エクスポートエラー：$error';
  }

  @override
  String get csExportCurrentPage => '現在のページ';

  @override
  String csGeneratingPdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '$countページ',
    );
    return 'PDF（$_temp0）を生成中…';
  }

  @override
  String csPdfExportError(String error) {
    return 'PDFエクスポートエラー：$error';
  }

  @override
  String csPdfExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページをPDFでエクスポートしました',
    );
    return '$_temp0';
  }

  @override
  String get csChapterSeparatorEyebrow => '章';

  @override
  String get csSelectionCopiedAsImage => '選択範囲を画像としてコピー';

  @override
  String csCopyImageError(String error) {
    return '画像のコピーに失敗しました：$error';
  }

  @override
  String get csExport => 'エクスポート';

  @override
  String csPageNumber(int number) {
    return '$numberページ';
  }

  @override
  String csPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
    );
    return '$_temp0';
  }

  @override
  String get csExportChapterTitle => '章をエクスポート';

  @override
  String get csExportNotebookTitle => 'ノートブック全体をエクスポートする';

  @override
  String get csChapterSeparatorQuestion => '各章の前に区切りページを挿入しますか？';

  @override
  String get csYesWithSeparators => '区切りページを入れる';

  @override
  String get csNoPagesOnly => 'ページのみ';

  @override
  String csTotalPages(int count) {
    return '総ページ数：$count';
  }

  @override
  String csFromPage(int page) {
    return '開始ページ：$page';
  }

  @override
  String csToPage(int page) {
    return '終了ページ：$page';
  }

  @override
  String csWillExportPages(int count, int start, int end) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページがエクスポートされます ($start–$end)',
      one: '$countページがエクスポートされます ($start–$end)',
    );
    return '$_temp0';
  }

  @override
  String csChapterLabelWithCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '$countページ',
    );
    return '$title（$_temp0）';
  }

  @override
  String get csGoToPage => 'ページに移動';

  @override
  String get csDuplicatePage => 'ページを複製';

  @override
  String get csNewPageAfter => 'この後に新しいページを追加';

  @override
  String get csDeletePageConfirmTitle => 'ページを削除しますか？';

  @override
  String csDeletePageConfirmBody(int number) {
    return 'ページ $number とそのすべてのコンテンツが削除されます。';
  }

  @override
  String get csExportAsPdf => 'PDFとしてエクスポート';

  @override
  String get csExportAsPng => 'PNGとしてエクスポート';

  @override
  String get csExportAsNcnote => '.abelnote形式でエクスポート';

  @override
  String get csExportNcnoteSubtitle => 'ベクター情報を保持する標準形式（バックアップや移行用）';

  @override
  String get csGeneratingNcnote => '.abelnote を生成中…';

  @override
  String csNcnoteExported(String size) {
    return '.abelnote がエクスポートされました ($size KB)';
  }

  @override
  String csNcnoteExportError(String error) {
    return '.abelnote エクスポートエラー：$error';
  }

  @override
  String get csImageOrPdf => '画像またはPDF';

  @override
  String get csChangePaperType => '用紙の種類を変更する';

  @override
  String get csPenToMonitor => 'ペン→モニター';

  @override
  String get csPenToMonitorSubtitle => 'ペンを単一画面に制限する';

  @override
  String get csPaperType => '用紙の種類';

  @override
  String get csPaperBlank => '無地';

  @override
  String get csPaperLinedNarrow => '横罫（狭い）';

  @override
  String get csPaperLinedWide => '横罫（広い）';

  @override
  String get csPaperGrid => '方眼';

  @override
  String get csPaperDotted => 'ドット方眼';

  @override
  String get csPaperCornell => 'コーネル式';

  @override
  String get csPaperIsometric => '等角方眼';

  @override
  String get csPaperMusic => '五線譜';

  @override
  String get csPaperApplyTo => '適用先';

  @override
  String get csPaperThisPage => 'このページ';

  @override
  String get csPaperAllPages => 'すべてのページ';

  @override
  String get csLineSpacing => '間隔';

  @override
  String csLineSpacingMm(String value) {
    return '$value mm';
  }

  @override
  String get csMapPenToMonitor => 'ペンを使うモニターを選択';

  @override
  String csPenMappedTo(String monitor) {
    return 'ペンの入力先を$monitorに設定しました';
  }

  @override
  String get csAllMonitors => 'すべてのモニター';

  @override
  String get csAllMonitorsSubtitle => '設定をリセットして、デスクトップ全体でペンを使います';

  @override
  String get csPenReset => 'ペンの入力先をリセットしました';

  @override
  String get csShapeLine => '直線';

  @override
  String get csShapeCircle => '円';

  @override
  String get csShapeRectangle => '長方形';

  @override
  String get csShapeTriangle => '三角形';

  @override
  String get csShapeArrow => '矢印';

  @override
  String get csInvalidRangeError => '有効なページ範囲を入力してください（例：1〜10）。';

  @override
  String get csImportPdfTitle => 'PDFをインポート';

  @override
  String csAllPagesWithCount(int count) {
    return 'すべてのページ ($count)';
  }

  @override
  String get csAllPages => 'すべてのページ';

  @override
  String get csCustomRange => 'カスタム範囲';

  @override
  String get csFromLabel => '開始ページ';

  @override
  String get csToLabel => '終了ページ';

  @override
  String get csImport => 'インポート';

  @override
  String libErrorGeneric(String error) {
    return 'エラー：$error';
  }

  @override
  String libErrorOpen(String error) {
    return '開けませんでした：$error';
  }

  @override
  String get libImportCannotReadFile => 'ファイルを読み取れません';

  @override
  String get libImportInProgress => 'インポート中…';

  @override
  String get libServiceUnavailable => 'サービスが利用できません';

  @override
  String libImportedTitleSuffix(String title) {
    return '$title（インポート済み）';
  }

  @override
  String libImportSuccess(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
    );
    return '「$title」をインポートしました（$_temp0）';
  }

  @override
  String get libImportCorruptedFile =>
      'このファイルは有効な AbelNotes ノートブックではありません。不完全または破損している可能性があります。';

  @override
  String get libExport => 'エクスポート';

  @override
  String get libImportOneNoteUnreadable =>
      'AbelNotes はこの OneNote ファイルを読み取れません。インポーターがまだサポートしていない形式が使用されているか、破損している可能性があります。';

  @override
  String libErrorImport(String error) {
    return 'インポートエラー：$error';
  }

  @override
  String libErrorCreate(String error) {
    return '作成エラー：$error';
  }

  @override
  String get libSketchDefaultTitle => 'スケッチ';

  @override
  String libErrorCreateSketch(String error) {
    return 'スケッチ作成エラー：$error';
  }

  @override
  String get libRemoveFromFavorites => 'お気に入りから削除';

  @override
  String get libAddToFavorites => 'お気に入りに追加';

  @override
  String get libRename => '名前を変更';

  @override
  String get libChangeCover => '表紙を変更';

  @override
  String get libCoverColor => '色';

  @override
  String get libCoverPattern => 'パターン';

  @override
  String get libCoverApply => '適用';

  @override
  String get libCoverStyleAuto => '自動（用紙の種類に合わせる）';

  @override
  String get libCoverStylePlain => '無地';

  @override
  String get libCoverStylePinstripe => 'ピンストライプ';

  @override
  String get libCoverStyleDiagonal => '斜めストライプ';

  @override
  String get libCoverStylePolka => '水玉模様';

  @override
  String get libCoverStyleGingham => 'ギンガムチェック';

  @override
  String get libCoverStyleWaves => '波';

  @override
  String get libCoverStyleLabel => 'ラベル';

  @override
  String get libCoverStyleTwoTone => 'ツートンカラー';

  @override
  String get libCoverStyleSheen => '光沢';

  @override
  String get libMoveToFolder => 'フォルダに移動';

  @override
  String get libNoFolder => 'フォルダなし';

  @override
  String get libNewFolder => '新しいフォルダ';

  @override
  String get libRenameFolder => 'フォルダの名前を変更する';

  @override
  String get libFolderNameHint => 'フォルダ名';

  @override
  String get libAllNotebooks => 'すべて';

  @override
  String get libDeleteFolder => 'フォルダの削除';

  @override
  String libDeleteFolderTitle(String name) {
    return 'フォルダ「$name」を削除しますか？';
  }

  @override
  String get libDeleteFolderBody =>
      'フォルダ内のノートブックは削除されず、フォルダに属さない状態でライブラリに残ります。';

  @override
  String get libDelete => '削除';

  @override
  String get libDeleteNotebookTitle => 'このノートブックを削除しますか？';

  @override
  String get libDeleteNotebookBody => 'ゴミ箱に移動されます。 [設定] > [ストレージ] から復元できます。';

  @override
  String get libCancel => 'キャンセル';

  @override
  String get libRenameNotebookTitle => 'ノートブックの名前を変更する';

  @override
  String get libSave => '保存';

  @override
  String get libSortTitle => '並べ替え';

  @override
  String get libAppName => 'AbelNotes';

  @override
  String get libSearchHintShort => '検索…';

  @override
  String get libSearchHintNotebooks => 'ノートブックを検索…';

  @override
  String get libSettingsTooltip => '設定';

  @override
  String get libMoreTooltip => 'その他';

  @override
  String get libViewAsList => 'リストビュー';

  @override
  String get libViewAsGrid => 'グリッドビュー';

  @override
  String libSortWithLabel(String sortLabel) {
    return '並べ替え：$sortLabel';
  }

  @override
  String get libImportNcnoteMenu => 'インポート…';

  @override
  String get libYourNotebooks => 'ノートブック';

  @override
  String libItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件',
    );
    return '$_temp0';
  }

  @override
  String get libNewNotebook => '新しいノートブック';

  @override
  String get libSketches => 'スケッチ';

  @override
  String get libInfiniteSpace => '無限キャンバス';

  @override
  String get libShowAll => 'すべて表示';

  @override
  String get libShowLess => '表示を減らす';

  @override
  String get libNewSketch => '新しいスケッチ';

  @override
  String get libNew => '新規';

  @override
  String libPagesAbbrev(int count) {
    return '$countページ';
  }

  @override
  String libPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '$countページ',
    );
    return '$_temp0';
  }

  @override
  String get libFooterWebdav => 'WebDAV';

  @override
  String get libFooterLocalFirst => 'ローカルファーストのアプリ';

  @override
  String get libSyncingWithServer => 'サーバーと同期中…';

  @override
  String libDownloadingProgress(int done, int total) {
    return 'ノートブックをダウンロード中：$done/$total';
  }

  @override
  String get libLoadingNotebooks => 'ノートブックを読み込み中…';

  @override
  String get libLoadingNotebooksFromServer => 'サーバーからノートブックを読み込み中…';

  @override
  String get libTimeNow => 'たった今';

  @override
  String libTimeMinutesAgo(int count) {
    return '$count分前';
  }

  @override
  String libTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count時間前',
      one: '$count時間前',
    );
    return '$_temp0';
  }

  @override
  String libTimeDaysAgo(int count) {
    return '$count日前';
  }

  @override
  String libTimeWeeksAgo(int count) {
    return '$count週間前';
  }

  @override
  String libTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countか月前',
    );
    return '$_temp0';
  }

  @override
  String libTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count年前',
    );
    return '$_temp0';
  }

  @override
  String get libNotebookTitleLabel => 'タイトル';

  @override
  String get libCoverLabel => '表紙';

  @override
  String get libPaperLabel => '用紙';

  @override
  String get libPaperBlank => '無地';

  @override
  String get libPaperLined => '横罫';

  @override
  String get libPaperGrid => '方眼';

  @override
  String get libPaperDotted => 'ドット方眼';

  @override
  String get pageSizeLabel => 'ページサイズ';

  @override
  String get pageSizeLetter => 'レター';

  @override
  String get pageSizeLegal => 'リーガル';

  @override
  String get pageSizeSquare => '正方形';

  @override
  String get pageSizePortrait => '縦向き';

  @override
  String get pageSizeLandscape => '横向き';

  @override
  String get pageSizeCustom => 'カスタム';

  @override
  String get pageSizeWidthMm => '幅(mm)';

  @override
  String get pageSizeHeightMm => '高さ(mm)';

  @override
  String get pageSizeRange => '50～600mm';

  @override
  String get pageSizeApply => '適用';

  @override
  String pageSizeCustomMm(String width, String height) {
    return '$width × $height mm';
  }

  @override
  String get libCreate => '作成';

  @override
  String get setSectionGeneral => '一般';

  @override
  String get setSectionInput => 'ペンと入力';

  @override
  String get setSectionSync => '同期';

  @override
  String get setSectionStorage => 'ストレージ';

  @override
  String get setSectionShortcuts => 'ショートカット';

  @override
  String get setSectionAdvanced => '詳細設定';

  @override
  String get setSectionAbout => 'アプリについて';

  @override
  String get setBackToLibrary => 'ライブラリ';

  @override
  String get setSettingsTitle => '設定';

  @override
  String get setThemeLabel => 'テーマ';

  @override
  String get setThemeLight => 'ライト';

  @override
  String get setThemePaper => 'ペーパー';

  @override
  String get setThemeDark => 'ダーク';

  @override
  String get setLanguage => '言語';

  @override
  String get setLanguageSub => 'アプリの表示言語';

  @override
  String get setLanguageItalian => 'Italiano';

  @override
  String get setFavoritesFirst => 'お気に入りを先頭に表示';

  @override
  String get setFavoritesFirstSub => 'お気に入りのノートブックをライブラリの上部に表示します';

  @override
  String get setStylusOnly => 'ペンでのみ描画';

  @override
  String get setStylusOnlySub => '指での描画を無効にします。2本指での拡大・縮小や移動は引き続き使えます。';

  @override
  String get setPressureThickness => '筆圧で線の太さを変える';

  @override
  String get setPressureThicknessSub => 'ペンにかける力に応じて線の太さを変えます。';

  @override
  String get setSpeedThickness => '描く速さで線の太さを変える';

  @override
  String get setSpeedThicknessSub => '速く書くとストロークが細くなります';

  @override
  String get setStrokeContinuation => '線の途切れを補正';

  @override
  String get setStrokeContinuationSub =>
      'センサーが一瞬入力を見失ったときに線をつなぎます（例：小文字の i の点）。';

  @override
  String get setPencilDoubleTap => 'Apple Pencilのダブルタップ';

  @override
  String get setPencilDoubleTapSub => 'Apple Pencil をダブルタップしてペンと消しゴムを切り替えます';

  @override
  String get setFillShapes => '図形を塗りつぶす';

  @override
  String get setFillShapesSub => '認識した円・長方形・三角形を、ペンの色で薄く塗りつぶします。';

  @override
  String get setTapUndo => '指のタップで取り消す';

  @override
  String get setTapUndoSub => '2本指でタップして元に戻し、3本指でタップしてやり直します。';

  @override
  String get setPenButton => 'ペンのサイドボタン';

  @override
  String get setPenButtonSub => 'ボタンを押している間のペンの動作（S Pen の唯一のボタン）';

  @override
  String get setPenButton2 => '2つ目のサイドボタン';

  @override
  String get setPenButton2Sub => 'ボタンが2つあるペンで、ペン先から遠い方';

  @override
  String get setPenButtonNone => 'なし';

  @override
  String get setSyncConnectedDesc => 'WebDAVサーバーに接続しています。ノートブックを各端末で同期できます。';

  @override
  String get setSyncLocalOnlyDesc =>
      'ノートブックはこの端末だけに保存されます。WebDAVサーバーに接続すると、ほかの端末でも使えます。';

  @override
  String get setSyncWebdav => 'WebDAV';

  @override
  String get setSyncLocalOnly => 'この端末のみ';

  @override
  String setSyncAccountInfo(String host, String username) {
    return '$host · $username';
  }

  @override
  String get setSyncNoServer => 'サーバーが接続されていません';

  @override
  String get setDisconnect => '切断';

  @override
  String get setConnect => '接続';

  @override
  String get setDisconnectTitle => 'サーバーを切断しますか？';

  @override
  String get setDisconnectBody =>
      'すでにダウンロードされているノートブックはこの端末上に残ります。再接続するまで同期は停止します。';

  @override
  String get setCheckCert => 'サーバー証明書を確認';

  @override
  String get setCertCheckFailed => 'サーバーの証明書を検証できません。';

  @override
  String get setCertUnchanged => '証明書は最後の接続以来変更されていません。';

  @override
  String get setCertChangedTitle => '新しい証明書が検出されました';

  @override
  String setCertChangedBody(String oldFingerprint, String newFingerprint) {
    return 'サーバー証明書のフィンガープリントが、保存済みのものと異なります。ご自身で証明書を更新した場合は、新しい証明書を承認すると同期を続けられます。心当たりがない場合はキャンセルし、ネットワークを確認してから再試行してください。\n\n保存済み：$oldFingerprint\n現在：$newFingerprint';
  }

  @override
  String get setCertConfirmNew => '新しい証明書を承認';

  @override
  String get setCancel => 'キャンセル';

  @override
  String get setShortcutPen => 'ペン';

  @override
  String get setShortcutUndo => '元に戻す';

  @override
  String get setShortcutBrush => 'ブラシ';

  @override
  String get setShortcutRedo => 'やり直す';

  @override
  String get setShortcutEraser => '消しゴム';

  @override
  String get setShortcutSelectAll => 'すべて選択';

  @override
  String get setShortcutLasso => 'なげなわ';

  @override
  String get setShortcutCopy => 'コピー';

  @override
  String get setShortcutHand => '手のひら';

  @override
  String get setShortcutCut => '切り取り';

  @override
  String get setShortcutText => 'テキスト';

  @override
  String get setShortcutPaste => '貼り付け';

  @override
  String get setShortcutShape => '図形';

  @override
  String get setShortcutDuplicate => '複製';

  @override
  String get setShortcutChangePage => 'ページを切り替え';

  @override
  String get setShortcutSave => '保存';

  @override
  String get setShortcutFit => '画面に合わせる';

  @override
  String get setShortcutCheatSheet => 'ショートカット一覧';

  @override
  String get setKeyboardShortcutsTitle => 'キーボードショートカット';

  @override
  String get setClearCache => 'キャッシュを削除';

  @override
  String get setClearCacheSub => '一時ファイルだけを削除します。';

  @override
  String get setClear => 'クリア';

  @override
  String get setTrash => 'ゴミ箱';

  @override
  String get setTrashSub => '削除したノートブックを復元';

  @override
  String get setOpenTrash => 'ゴミ箱を開く';

  @override
  String get setClearCacheDone => 'キャッシュがクリアされました。';

  @override
  String get setExportLibrary => 'ライブラリのエクスポート';

  @override
  String get setExportLibrarySub => 'すべてのノートブックを1つのZIPファイルに保存します。';

  @override
  String get setExport => 'エクスポート';

  @override
  String get setExportLibraryEmpty => 'エクスポートするノートブックがありません。';

  @override
  String setExportLibraryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊のノートブックをエクスポートしました',
    );
    return '$_temp0。';
  }

  @override
  String setExportLibraryFailed(String error) {
    return 'エクスポートに失敗しました：$error';
  }

  @override
  String setExportLibraryProgress(int done, int total) {
    return '$done/$total をエクスポート中…';
  }

  @override
  String get setExportLibraryCancelled => 'エクスポートがキャンセルされました。';

  @override
  String setTrashPurgeTitle(String title) {
    return '「$title」を完全に削除しますか？';
  }

  @override
  String get setTrashPurgeBody => '削除後は復元できません。';

  @override
  String get setTrashPurge => '完全に削除';

  @override
  String get setTrashEmptyTitle => 'ゴミ箱を空にしますか？';

  @override
  String get setTrashEmptyBody => 'ゴミ箱内のすべてのノートブックは完全に削除されます。';

  @override
  String get setTrashEmpty => 'ゴミ箱を空にする';

  @override
  String get setTrashEmptyState => 'ゴミ箱が空です。';

  @override
  String get setTrashRestore => '復元';

  @override
  String get setAdvancedIntro =>
      '同期が止まってしまったノートブックを復旧するためのツールです。ライブラリで「強制同期」を実行しても同期に失敗する場合にだけ使ってください。';

  @override
  String get setForceReloadTitle => 'サーバーからノートブックを強制的に再読み込み';

  @override
  String get setForceReloadDesc =>
      'サーバーの差分フォルダからノートブック全体を再ダウンロードし、この端末のコピーを上書きします。ページ数がおかしい場合や、ノートブックを開けない場合に使えます。サーバー上のデータは失われません。';

  @override
  String setErrorGeneric(String error) {
    return 'エラー：$error';
  }

  @override
  String setPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '$countページ',
    );
    return '$_temp0';
  }

  @override
  String get setReload => '再読み込み';

  @override
  String get setCloseNotebookFirst => 'サーバーから再読み込みする前に、ノートブックを閉じてください。';

  @override
  String setReloadConfirmTitle(String title) {
    return '「$title」を再読み込みしますか？';
  }

  @override
  String get setReloadConfirmBody =>
      'サーバーの差分フォルダからメタデータ、文書、ページ、画像などの素材を再ダウンロードし、この端末のコピーを置き換えます。\n\nまだ同期していない変更は失われます。続行しますか？';

  @override
  String setReloadInProgress(String title) {
    return '「$title」を再読み込み中…';
  }

  @override
  String get setNotConnectedWebdav => 'WebDAV サーバーに接続されていません。';

  @override
  String setReloadDone(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '「$title」を再読み込みしました（$countページ）',
    );
    return '$_temp0。';
  }

  @override
  String setReloadFailed(String error) {
    return '再読み込みに失敗しました：$error';
  }

  @override
  String get setAboutTagline => 'ローカルファーストの手書きアプリ。';

  @override
  String get setAboutOffline => 'オフラインでも動作します。 WebDAV 同期はオプションです。';

  @override
  String setAboutVersion(String version, String commit) {
    return 'バージョン $version · ビルド $commit';
  }

  @override
  String get setReportProblem => '問題を報告する';

  @override
  String get setReportProblemSub => '報告に添付できるよう、エラーログをクリップボードにコピーします。';

  @override
  String get setCopyLog => 'ログのコピー';

  @override
  String get setReportProblemEmpty => 'エラーの記録はありません。';

  @override
  String get setCopyLogDone => 'ログがクリップボードにコピーされました。';

  @override
  String get setDetailedLog => '詳細ログ';

  @override
  String get setDetailedLogSub =>
      '同期とペンの詳細も記録するため、コピーしたログで問題を説明しやすくなります。必要ないときはオフにしてください。';

  @override
  String get setContribute => '認識精度の向上に協力';

  @override
  String get setContributeSub =>
      'contribute.abelnotes.appで数式や回路記号を書くと、認識精度の向上に協力できます。アプリからノートが送信されることはありません。サンプルは、そのページで送信を選んだ場合にだけ送信されます。';

  @override
  String get setContributeOpen => 'ページを開く';

  @override
  String get onbTagline =>
      '手書きノートやスケッチを、自分のサーバーに同期できます。使い始める方法を選んでください。あとから変更できます。';

  @override
  String get onbTryNowSubtitle => 'ノートブックはこの端末に保存されます。アカウントやサーバーの準備は不要です。';

  @override
  String get onbManagedServerTitle => 'AbelNotesの管理サーバー';

  @override
  String get driveSignInFailed => 'Googleへのサインインが完了しませんでした。変更は行われていません。';

  @override
  String get driveSignInCancelled => 'サインインがキャンセルされました。';

  @override
  String get driveNotConfigured => 'このビルドには Google 認証情報がないため、ドライブ同期は利用できません。';

  @override
  String get driveNoKeyring =>
      'このシステムには安全なストレージがないため、Google アカウントを安全に保管できません。ここではドライブ同期は利用できません。';

  @override
  String get driveConnectedTitle => 'Google Driveに接続しました';

  @override
  String get setSyncDriveTitle => 'Google Drive';

  @override
  String get setSyncDriveConnected => 'ノートブックは Google Drive を通じて同期されます。';

  @override
  String get setSyncDriveNotConnected => '接続されていません。';

  @override
  String get setSyncDriveDesktopOnly => '現在はパソコンでのみ利用できます。';

  @override
  String get setDriveDisconnectTitle => 'Google Drive を切断しますか？';

  @override
  String get setDriveDisconnectBody =>
      'すでにドライブ内にあるノートブックはそこに残ります。このアプリは同期を停止するだけです。この端末上のノートブックはそのままです。';

  @override
  String get setDriveDisconnectConfirm => '切断';

  @override
  String get setSyncOneBackendNote =>
      'ノートブックは一度に1つの場所（自分のサーバーまたはGoogle Drive）に同期されます。';

  @override
  String get setSyncSwitchTitle => '同期先をGoogle Driveに切り替えますか？';

  @override
  String get setSyncSwitchBody =>
      'ノートブックはこの端末上に残り、Google Drive にアップロードされます。サーバー上にすでに存在するコピーはそのまま残りますが、それ以降は更新の受信が停止されます。何も削除されません。';

  @override
  String get setSyncSwitchConfirm => 'Google Driveに切り替える';

  @override
  String get setSyncInactiveNote => '設定済みですが、現在は別の保存先に同期しています。';

  @override
  String libPendingNewDrive(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊のノートブックがまだGoogle Driveにありません：$names',
      one: '「$names」はまだGoogle Driveにありません',
    );
    return '$_temp0';
  }

  @override
  String libPendingNewServer(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊のノートブックがまだサーバーにありません：$names',
      one: '「$names」はまだサーバーにありません',
    );
    return '$_temp0';
  }

  @override
  String libPendingChanges(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊のノートブックの変更はまだアップロードされていません：$names',
      one: '「$names」の変更はまだアップロードされていません',
    );
    return '$_temp0';
  }

  @override
  String get libPendingUploadsHint =>
      'アップロードが終わるまでもノートブックはこの端末に保存されています。しばらくアプリを開いたままにしてください。';

  @override
  String get libDeleteRemotePending =>
      'この端末から削除しました。クラウドからの削除に失敗したため、自動で再試行します。';

  @override
  String libPendingRemoteDeletes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊のノートブックはこの端末で削除済みですが、クラウドからはまだ削除されていません',
    );
    return '$_temp0';
  }

  @override
  String get libPendingRemoteDeletesHint =>
      'クラウドからの削除が終わるまでは、ほかの端末に表示されることがあります。再接続後に削除を再試行します。';

  @override
  String get libServerUnreachable => 'サーバーに到達できません';

  @override
  String get libServerUnreachableHint => '変更はこの端末に残り、接続が回復するとすぐにアップロードされます。';

  @override
  String get libStorageFullDrive => 'Google Driveの空き容量が不足しています';

  @override
  String get libStorageFullServer => 'サーバーの容量が不足しています';

  @override
  String get libStorageFullBody =>
      'ノートブックはこの端末に保存されていますが、空き容量を確保するまでアップロードできません。Google Driveの保存容量はGmailやGoogle フォトと共用です。';

  @override
  String get libStorageFullBodyServer =>
      'ノートブックはこの端末に保存されていますが、サーバーの空き容量を確保するまでアップロードできません。';

  @override
  String get libLocalOnlyTitle => 'この端末のみ';

  @override
  String get libLocalOnlyBody =>
      'ノートブックはこの端末だけに保存されます。サーバーやGoogle Driveに接続すると、ほかの端末でも使えます。接続はあとから設定できます。';

  @override
  String get libLocalOnlyBodyWeb =>
      'ノートブックはこのブラウザー内に保存されます。残しておきたいノートブックはエクスポートするか、Google Driveに接続してほかの端末でも使えるようにしてください。Safariでは、アプリをホーム画面に追加していない場合、数日間使っていないサイトのデータが削除されることがあります。';

  @override
  String get libKeepOnDevice => 'この端末のみに保存しておく';

  @override
  String get libResumeSync => 'このノートブックを再度同期する';

  @override
  String get libLocalOnlyBadge => 'この端末のみ';

  @override
  String get libKeepOnDeviceTitle => 'このノートブックをこの端末だけに保存しますか？';

  @override
  String get libKeepOnDeviceBody =>
      'アップロードを停止し、ほかの端末には更新が届かなくなります。この端末では引き続き編集できます。';

  @override
  String get libKeepOnDeviceRemoveCopy => 'すでにアップロードされているコピーも削除します';

  @override
  String get libKeepOnDeviceConfirm => 'この端末にのみ保存';

  @override
  String get libLocalOnlyDone => 'この端末だけに保存する設定にしました。';

  @override
  String get syncLocalOnlyTooltip => 'この端末にのみ保存されます';

  @override
  String get libFreeSpace => 'この端末の空き容量を増やす';

  @override
  String get libKeepOnThisDevice => 'この端末にダウンロードする';

  @override
  String get libFreeSpaceTitle => 'このノートブックをこの端末から削除しますか？';

  @override
  String get libFreeSpaceBody =>
      'ノートブックは同期先とほかの端末に残ります。この端末では、タップすると再ダウンロードできるカードとして表示されます。再ダウンロードするまではオフラインで開けず、ノートブックの内容も検索対象になりません。';

  @override
  String get libFreeSpaceConfirm => '空き容量を増やす';

  @override
  String libFreeSpaceDone(String size) {
    return 'この端末から削除し、$sizeの空き容量を確保しました。';
  }

  @override
  String get libFreeSpaceNotSynced =>
      'このノートブックには、同期先にまだアップロードしていない変更があります。アップロードが完了すると、この端末から削除できます。';

  @override
  String get libFreeSpaceOpenNotebook => '先にノートブックを閉じてください。';

  @override
  String get libKeepOnThisDeviceDone => 'この端末に再度ダウンロードされます。';

  @override
  String get syncNotOnDeviceTooltip => '同期先に保存済み・この端末には未ダウンロード';

  @override
  String get onbSyncQuestion => 'ノートの同期';

  @override
  String get onbDriveShort => 'Google Drive';

  @override
  String get onbNextcloudShort => 'Nextcloud / WebDAV';

  @override
  String get onbStartWithoutSync => '同期せずに始める';

  @override
  String get onbDriveUnavailable => 'このビルドでは使用できません';

  @override
  String get onbLicenseNote =>
      'アプリを開くとAGPL-3.0ライセンスに同意したものとみなされます。「AbelNotes」はプロジェクトの商標です。';

  @override
  String logConnectionError(String error) {
    return '接続エラー：$error';
  }

  @override
  String get logCertificateChanged =>
      '前回の接続後にサーバー証明書が変更されています。ご自身で更新した場合は、「設定」>「同期」で新しいフィンガープリントを確認し、承認してください。';

  @override
  String get logCertConfirmTitle => 'サーバーの接続先を確認';

  @override
  String get logCertConfirmBody =>
      'このサーバーへの初回接続です。続行する前に、以下のフィンガープリントを、サーバー側でコマンドラインなどから確認した値と照合してください。';

  @override
  String get logCertConfirmTrust => '信頼して続行';

  @override
  String get logBackTooltip => '戻る';

  @override
  String get logTitle => 'Nextcloudに接続';

  @override
  String get logSubtitle =>
      'お使いのWebDAV／Nextcloudサーバー（VPS、自宅サーバー、LAN内など）に接続します。第三者のクラウドは経由しません。';

  @override
  String get logServerUrlLabel => 'サーバーURL';

  @override
  String get logServerUrlHint => 'https://cloud.example.com';

  @override
  String get logServerUrlRequired => 'サーバーのURLを入力してください';

  @override
  String get logServerUrlInvalid => 'http:// または https:// で始まる必要があります';

  @override
  String get logUsernameLabel => 'ユーザー名';

  @override
  String get logUsernameRequired => 'ユーザー名が必要です';

  @override
  String get logPasswordLabel => 'パスワード/アプリパスワード';

  @override
  String get logPasswordRequired => 'パスワードが必要です';

  @override
  String get logAppPasswordHint => '推奨：Nextcloud 設定から生成されたアプリパスワード。';

  @override
  String get logServerTypeNextcloud => 'Nextcloud / ownCloud';

  @override
  String get logServerTypeWebdav => 'その他 WebDAV';

  @override
  String get logServerUrlHintWebdav => 'https://dav.example.com/folder';

  @override
  String get logWebdavExperimental =>
      '汎用 WebDAV バックエンド（Synology、Seafile、rcloneなど）は実験的なものであり、完全にテストされているのは Nextcloud のみです。ノートブックのバックアップを保管してください。';

  @override
  String get logWebdavUrlHint =>
      'パスを含む完全なWebDAV URLを入力してください（例：Synology https://nas:5006/home、Seafile https://server/seafdav）。汎用WebDAVではリンク共有を利用できません。';

  @override
  String get logConnectButton => '接続';

  @override
  String get chromeBackToLibraryTooltip => 'ライブラリに戻る';

  @override
  String get chromeLibrary => 'ライブラリ';

  @override
  String get chromeUnsaved => '未保存';

  @override
  String get chromeMouseDrawsTooltip => 'マウスで描画します。クリックすると選択に切り替わります。';

  @override
  String get chromeMouseSelectsTooltip => 'マウスで選択します。クリックすると描画に切り替わります。';

  @override
  String get chromeTouchDrawsTooltip => '指で描画します。タップすると画面移動に切り替わります。';

  @override
  String get chromeTouchPansTooltip => '指で画面を移動します。タップすると描画に切り替わります。';

  @override
  String get chromeUndo => '元に戻す';

  @override
  String get chromeRedo => 'やり直す';

  @override
  String get chromeAllPages => 'すべてのページ';

  @override
  String chromePageIndicator(String current, int total) {
    return '$current / $total';
  }

  @override
  String get chromeAddPage => 'ページを追加';

  @override
  String get chromeSymbols => 'シンボル';

  @override
  String get chromeExport => 'エクスポート';

  @override
  String get chromeMore => 'その他';

  @override
  String get chromeToolPen => 'ペン・P';

  @override
  String get chromeToolHighlighter => '蛍光ペン';

  @override
  String get chromeToolEraser => '消しゴム · E';

  @override
  String get chromeToolLasso => 'なげなわ · L';

  @override
  String get chromeToolText => 'テキスト・T';

  @override
  String get chromeToolLaser => 'レーザー';

  @override
  String get chromeToolPan => '手のひら · H';

  @override
  String get chromeDragToMoveBar => 'ドラッグしてツールバーを移動します';

  @override
  String get chromeHoldForOptions => '長押しするか右クリックしてオプションを表示します';

  @override
  String chromeQuickPen(int n) {
    return 'クイックペン $n';
  }

  @override
  String get chromeAutoShape => '図形認識';

  @override
  String get chromeLabelPen => 'ペン';

  @override
  String get chromeLabelBallpoint => 'ボールペン';

  @override
  String get chromeLabelBrush => 'ブラシ';

  @override
  String get chromeLabelCalligraphy => 'カリグラフィー';

  @override
  String get chromeLabelEraser => '消しゴム';

  @override
  String get chromeLabelLasso => 'なげなわ';

  @override
  String get chromeLabelText => 'テキスト';

  @override
  String get chromeLabelShape => '図形';

  @override
  String get chromeLabelImage => '画像';

  @override
  String get chromeLabelPan => '手のひら';

  @override
  String get chromeColorSection => '色';

  @override
  String get chromeColorEditHint => '色を長押しして変更します';

  @override
  String get chromeThicknessSection => '線の太さ';

  @override
  String chromeThicknessPx(String value) {
    return '$value px';
  }

  @override
  String get chromePreview => 'プレビュー';

  @override
  String get chromeModeSection => 'モード';

  @override
  String get chromeEraserPerArea => '部分消し';

  @override
  String get chromeEraserPerStroke => '線ごとに消す';

  @override
  String get chromeSizeSection => 'サイズ';

  @override
  String get chromePresetOverwrite => '現在の設定で上書き';

  @override
  String get chromePresetReset => '初期設定に戻す';

  @override
  String get chromeNoPages => 'ページがありません';

  @override
  String get chromeHidePageBar => 'ページバーを非表示にする';

  @override
  String get chromeShowPageBar => 'ページバーを表示する';

  @override
  String chromePrevPageTooltip(int number) {
    return '前のページ（$numberページ）。タップして戻ります';
  }

  @override
  String chromePageOfChapterTooltip(int number, int globalNumber) {
    return '章の$numberページ目（ノートブックの$globalNumberページ目）';
  }

  @override
  String chromePageTooltip(int number) {
    return '$numberページ';
  }

  @override
  String get chromeHexLabel => '16進数';

  @override
  String get chromeCancel => 'キャンセル';

  @override
  String get chromeApply => '適用';

  @override
  String get pmCreateChapterFirst => '先に章を1つ以上作成してください。';

  @override
  String pmDeletePagesConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページを削除しますか？',
      one: '1ページ削除しますか？',
    );
    return '$_temp0';
  }

  @override
  String get pmActionCannotBeUndone => 'この操作は元に戻すことができません。';

  @override
  String get pmCancel => 'キャンセル';

  @override
  String get pmDelete => '削除';

  @override
  String pmSelectedCount(int count) {
    return '$countページを選択中';
  }

  @override
  String get pmGoToPageTooltip => 'ページに移動…';

  @override
  String get pmAddPage => 'ページを追加';

  @override
  String get pmClose => '閉じる';

  @override
  String get pmNewChapter => '新しい章';

  @override
  String get pmChapterNameHint => '章名';

  @override
  String pmPageDeleted(int number) {
    return '$numberページが削除されました';
  }

  @override
  String get pmUndo => '元に戻す';

  @override
  String get pmAssignChapter => '章の割り当て';

  @override
  String get pmRename => '名前を変更';

  @override
  String get pmRenameChapter => '章の名前を変更';

  @override
  String get pmDeleteChapter => '章の削除';

  @override
  String pmDeleteChapterConfirm(String title) {
    return '「$title」を削除しますか？ページは削除されず、章に属さない状態で残ります。';
  }

  @override
  String get pmGoToPage => 'ページに移動';

  @override
  String pmPageRangeHint(int max) {
    return '1–$max';
  }

  @override
  String get pmGo => '移動';

  @override
  String get pmOk => 'OK';

  @override
  String get pmInsertBefore => '前に挿入';

  @override
  String get pmInsertAfter => '後に挿入';

  @override
  String get pmDuplicate => '複製';

  @override
  String get pmMoveTo => 'ページに移動…';

  @override
  String get pmMove => '移動';

  @override
  String get pmMoveToPage => 'ページに移動';

  @override
  String get pmChapterEllipsis => '章…';

  @override
  String get pmCorruptAssetTooltip =>
      'サーバー上の画像データが途中で欠けています。元のPDFを再インポートして復旧してください';

  @override
  String get pmLoadingImageTooltip => 'サーバーから画像を読み込み中…';

  @override
  String get tedInsertTextTitle => 'テキストの挿入';

  @override
  String get tedEditTextTitle => 'テキストを編集する';

  @override
  String get tedBoldTooltip => '太字 (Ctrl+B)';

  @override
  String get tedItalicTooltip => '斜体 (Ctrl+I)';

  @override
  String get tedUnderlineTooltip => '下線 (Ctrl+U)';

  @override
  String get tedStrikethroughTooltip => '取り消し線';

  @override
  String get tedAlignLeft => '左揃え';

  @override
  String get tedAlignCenter => '中央揃え';

  @override
  String get tedAlignRight => '右揃え';

  @override
  String get tedWriteHereHint => 'ここに書いてください…';

  @override
  String get tedCancel => 'キャンセル';

  @override
  String get tedInsert => '挿入';

  @override
  String get cropTitle => '画像のトリミング';

  @override
  String get cropCancel => 'キャンセル';

  @override
  String get cropConfirm => 'トリミング';

  @override
  String get imgFontSmaller => '文字を小さく';

  @override
  String get imgFontLarger => '文字を大きく';

  @override
  String get imgCrop => 'トリミング';

  @override
  String get imgCopy => 'コピー';

  @override
  String get imgUnlock => 'ロックを解除する';

  @override
  String get imgLock => 'ロック';

  @override
  String get imgDelete => '削除';

  @override
  String get imgDeselect => '選択を解除します';

  @override
  String get imgMoreActions => 'その他の操作';

  @override
  String get imgBringToFront => '最前面へ移動';

  @override
  String get imgSendToBack => '最背面へ移動';

  @override
  String get imgComment => 'コメント';

  @override
  String get imgFlipHChecked => '左右反転 ✓';

  @override
  String get imgFlipH => '左右反転';

  @override
  String get imgCut => '切り取り';

  @override
  String get syncOkTooltip => '同期済み';

  @override
  String get syncPendingTooltip => '同期中…';

  @override
  String get syncOfflineTooltip => 'オフライン';

  @override
  String get syncConflictTooltip => '競合あり';

  @override
  String get confDecideLater => '後で決める';

  @override
  String confTitlePageDeletedElsewhere(int pageNumber) {
    return '$pageNumberページは別の端末で削除されました';
  }

  @override
  String confTitleConflictPage(int pageNumber) {
    return '競合：ページ $pageNumber';
  }

  @override
  String get confDeletionExplainer =>
      'このページを編集しましたが、別の端末によって削除されました。保持しますか、それとも削除しますか？';

  @override
  String get confKeepPage => 'ページを残す';

  @override
  String get confLocalYours => 'この端末の内容';

  @override
  String get confRemoteOtherDevice => 'ほかの端末の内容';

  @override
  String get confKeepAllLocal => 'すべてこの端末の内容を採用';

  @override
  String get confAcceptAllRemote => 'すべてほかの端末の内容を採用';

  @override
  String confProgressIndicator(int current, int total, num decided) {
    String _temp0 = intl.Intl.pluralLogic(
      decided,
      locale: localeName,
      other: '$decided件を選択済み',
    );
    return '$current / $total（$_temp0）';
  }

  @override
  String get confApplyChoices => '選択内容を適用';

  @override
  String confDecidedProgress(int decided, num total) {
    return '$decided/$total件を選択済み';
  }

  @override
  String get confJumpToConflict => '競合箇所へ移動';

  @override
  String confJumpDecidedCount(int decided, int total) {
    return '$decided/$total件を選択済み';
  }

  @override
  String confJumpItemPage(int pageNumber) {
    return '$pageNumberページ';
  }

  @override
  String confJumpItemPageWithChapter(int pageNumber, String chapterName) {
    return '$pageNumberページ · $chapterName';
  }

  @override
  String get confDismissDialogTitle => 'キャンセルしますか？';

  @override
  String get confDismissDialogBody => 'まだ適用していない選択内容は失われます。この端末の内容は保持されます。';

  @override
  String get confContinue => '続ける';

  @override
  String get confCancel => 'キャンセル';

  @override
  String get confModifiedJustNow => 'たった今';

  @override
  String confModifiedMinutesAgo(int minutes) {
    return '$minutes分前';
  }

  @override
  String confModifiedHoursAgo(num hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours時間前',
      one: '$hours時間前',
    );
    return '$_temp0';
  }

  @override
  String get confDeletePage => 'ページを削除する';

  @override
  String get confAsOnOtherDevice => 'ほかの端末の削除を反映';

  @override
  String get symNewLibraryTitle => '新しいライブラリ';

  @override
  String get symNewLibraryHint => 'ライブラリ名を入力してください';

  @override
  String get symRenameLibraryTitle => 'ライブラリの名前を変更する';

  @override
  String get symNewNameHint => '新しい名前';

  @override
  String get symDeleteLibraryTitle => 'ライブラリの削除';

  @override
  String symDeleteLibraryConfirm(String name) {
    return '「$name」とそのすべてのシンボルを削除しますか？';
  }

  @override
  String get symCancel => 'キャンセル';

  @override
  String get symDelete => '削除';

  @override
  String get symRenameSymbolTitle => 'シンボルの名前を変更';

  @override
  String get symPanelTitle => 'シンボルライブラリ';

  @override
  String get symNoLibraries => 'ライブラリなし';

  @override
  String get symNew => '新規';

  @override
  String get symSelectLibrary => 'ライブラリを選択してください';

  @override
  String get symNoSymbolsHint => 'シンボルがありません\nなげなわで要素を選択して✚を押してください';

  @override
  String get symLassoSaveHint => 'なげなわで要素を選び、✚を押すと、選択中のライブラリに保存できます';

  @override
  String get symRename => '名前を変更';

  @override
  String get symInsert => '挿入';

  @override
  String get symOk => 'OK';

  @override
  String get rcbBannerTitle => '別の端末からの変更';

  @override
  String get rcbSeeDetails => '詳細を見る';

  @override
  String get rcbDismiss => '閉じる';

  @override
  String get rcbIncomingChanges => '受信した変更';

  @override
  String get rcbTapPageHint => 'ページをタップすると変更を適用し、そのページに移動します';

  @override
  String rcbNewImagesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '新しい画像$count枚',
    );
    return '$_temp0';
  }

  @override
  String get rcbKeepMine => 'この端末の内容を保持';

  @override
  String get rcbApplyAll => 'すべて適用';

  @override
  String get rcbBadgeNew => '新規';

  @override
  String get rcbBadgeModified => '変更あり';

  @override
  String rcbPageTitle(int pageNumber) {
    return '$pageNumberページ';
  }

  @override
  String get rcbContentUpdated => 'コンテンツが更新されました';

  @override
  String rcbSummaryModifiedPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページが変更されました',
      one: '$countページが変更されました',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryNewPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '新規$countページ',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryImages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '画像$count枚',
    );
    return '$_temp0';
  }

  @override
  String get rcbChangesDetected => '変更を検出しました';

  @override
  String get nbUntitled => '無題';

  @override
  String get nbDefaultChapterTitle => '第1章';

  @override
  String get nbOpeningNotebook => 'ノートブックを開いています…';

  @override
  String get nbNoLocalCopyOffline =>
      'このノートブックのローカルコピーはなく、ダウンロードするためのサーバーに接続されていません。';

  @override
  String nbOpenFailed(String error) {
    return '開けませんでした：$error';
  }

  @override
  String get nbSortModifiedDesc => '更新日時（新しい順）';

  @override
  String get nbSortModifiedAsc => '更新日時（古い順）';

  @override
  String get nbSortTitleAsc => 'タイトルA→Z';

  @override
  String get nbSortTitleDesc => 'タイトルZ→A';

  @override
  String get nbSortCreatedDesc => '作成日時（新しい順）';

  @override
  String get nbSortCreatedAsc => '作成日時（古い順）';

  @override
  String get nbSortColorGroup => '表紙の色';

  @override
  String cvFormatTooNew(int fileVersion, int supportedVersion) {
    return 'このノートブックは新しい形式（v$fileVersion、対応：v$supportedVersion）で保存されています。開くにはAbelNotesを更新してください。';
  }

  @override
  String get setLanguageSystem => '端末の設定に従う';

  @override
  String get setLanguageEnglish => 'English';

  @override
  String get setLanguageSpanish => 'Español';

  @override
  String get onbAppName => 'AbelNotes';

  @override
  String get setAboutAppName => 'AbelNotes';

  @override
  String get chromeLabelHighlighter => '蛍光ペン';

  @override
  String get chromeLabelLaser => 'レーザー';

  @override
  String get importSourceTitle => 'ライブラリにインポートする';

  @override
  String get importSourceNcnote => '.abelnoteノートブック';

  @override
  String get importSourceObsidian => 'Obsidianの保管庫';

  @override
  String get importSourceObsidianHint => 'Markdown ファイルのフォルダ';

  @override
  String get importSourceNotion => 'Notionのエクスポート';

  @override
  String get importSourceNotionHint => '.zip ファイル（Markdown および CSV）';

  @override
  String get importPhaseScanning => '取り込むファイルを確認中…';

  @override
  String importPhaseParsing(int current, int total) {
    return 'ファイルを読み込み中：$current/$total';
  }

  @override
  String importPhasePaginating(int current, int total) {
    return '章のページをレイアウト中：$current/$total';
  }

  @override
  String get importPhasePackaging => 'ノートブックを作成中…';

  @override
  String get importCancel => 'キャンセル';

  @override
  String get importCancelled => 'インポートをキャンセルしました';

  @override
  String importReportTitle(int count) {
    return 'インポート時の警告：$count件';
  }

  @override
  String get importReportCopy => 'コピー';

  @override
  String get importReportClose => '閉じる';

  @override
  String get importSourceOneNote => 'OneNote ファイル';

  @override
  String get importSourceOneNoteHint => '.one セクションまたは .onetoc2 ノートブック';

  @override
  String get importSourceSamsung => 'Samsung Notesファイル';

  @override
  String get importSourceSamsungHint => '.sdocx メモ（Samsung Notes：ファイルとして保存）';

  @override
  String get libImportInviteTitle => 'ほかのアプリにノートがありますか？';

  @override
  String get libImportInviteBody => '元のノートを残したまま、ここに取り込めます。';

  @override
  String get libImportInviteLater => 'あとで';

  @override
  String get setOpenSourceLicenses => 'オープンソースライセンス';

  @override
  String get setOpenSourceLicensesSub => 'アプリにバンドルされているサードパーティ製コンポーネント';

  @override
  String get csBackToContent => 'コンテンツに戻る';

  @override
  String get setLanguageGerman => 'Deutsch';

  @override
  String get setLanguageFrench => 'Français';

  @override
  String get setLanguagePortuguese => 'Português';

  @override
  String get setLanguageJapanese => '日本語';

  @override
  String get setLanguageChinese => '中文';

  @override
  String get qlTrashDeletedNow => 'たった今削除されました';

  @override
  String qlTrashDeletedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count分前に削除されました',
      one: '$count分前に削除されました',
    );
    return '$_temp0';
  }

  @override
  String qlTrashDeletedHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count時間前に削除されました',
      one: '$count時間前に削除されました',
    );
    return '$_temp0';
  }

  @override
  String qlTrashDeletedDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日前に削除しました',
    );
    return '$_temp0';
  }

  @override
  String get qlAdvancedLocalOnly =>
      'これらの回復ツールは、サーバーまたは Google Drive が接続されている場合にのみ適用されます。';

  @override
  String get qlNameRequired => '名前を入力してください';

  @override
  String get qlDuplicate => '複製';

  @override
  String qlDuplicateTitle(String title) {
    return '$title（コピー）';
  }

  @override
  String get qlDuplicated => 'ノートブックが複製されました';

  @override
  String get qlDuplicateNoLocalCopy =>
      'このノートブックはこの端末に保存されていません。一度開いてダウンロードしてから複製してください。';

  @override
  String get qlDeleteOrphanBody =>
      'このノートブックのコピーはこの端末には残っていないため、復元するものはありません。ライブラリから削除されます。';

  @override
  String get qlDeletedNoTrash => '削除しました。この端末にコピーがなかったため、ゴミ箱には移動していません。';

  @override
  String get qlDeleteNeedsCopy =>
      'このノートブックはこの端末上にないため、ダウンロードしてゴミ箱に保存できませんでした。何も削除されませんでした。オンラインのときにもう一度試してください。';

  @override
  String get qlOpenCorrupt => 'このノートブックのデータは破損しているため、開くことができません。';

  @override
  String qlSearchNoResults(String query) {
    return '「$query」に一致するノートブックはありません。';
  }

  @override
  String get qcMouseSelectHint =>
      '現在、ペンツールを選んでいても、マウスは選択に使われます。マウスで描くには描画を有効にしてください。';

  @override
  String get qcMouseDrawEnable => 'マウスで描く';

  @override
  String qiIssueRemoteImage(String arg) {
    return 'リモート画像がダウンロードされていません：$arg';
  }

  @override
  String qiIssueImageNotFound(String arg) {
    return '画像が見つかりません：$arg';
  }

  @override
  String qiIssueImageUnreadable(String arg) {
    return '画像を読み取れませんでした：$arg';
  }

  @override
  String qiIssueAttachmentUnsupported(String arg) {
    return 'サポートされていない添付ファイル（画像のみ）：$arg';
  }

  @override
  String qiIssueAttachmentTooLarge(String arg) {
    return '添付ファイルが大きすぎるため、スキップされました：$arg';
  }

  @override
  String qiIssueEmbedUnsupported(String arg) {
    return '埋め込みファイルはインポートされていません（画像とメモのみ）：$arg';
  }

  @override
  String qiIssueNoteEmbedNotFound(String arg) {
    return '埋め込まれたメモが見つかりません：$arg';
  }

  @override
  String qiIssueNoteEmbedSkipped(String arg) {
    return '埋め込まれたメモが展開されていません（循環またはネストが深すぎる）：$arg';
  }

  @override
  String get qiIssueFileUnreadable => 'ファイルを読み取れませんでした';

  @override
  String qiIssueFileTooLarge(int count) {
    return 'ファイルが大きすぎるためスキップしました（$count MB）';
  }

  @override
  String get qiIssueEncodingFallback => '有効なUTF-8ではなかったため、Latin-1として読み込みました';

  @override
  String get qiIssueCsvUnreadable => 'テーブルを読み取れませんでした';

  @override
  String qiIssueZipEntryTooLarge(int count) {
    return 'アーカイブ内のファイルが大きすぎるためスキップしました（$count MB）';
  }

  @override
  String qiIssueZipTotalTooLarge(int count) {
    return 'アーカイブコンテンツが $count MB を超えているため、残りのファイルはスキップされました';
  }

  @override
  String qiIssueHiddenFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '隠しフォルダ内の$count件のメモがスキップされました',
      one: '隠しフォルダ内の1件のメモがスキップされました',
    );
    return '$_temp0';
  }

  @override
  String qiIssueTooManyChapters(int count) {
    return '$count章：サブフォルダを個別にインポートすることを検討してください';
  }

  @override
  String qiIssuePagesTruncated(int count) {
    return 'ノートは$countページまで取り込み、それ以降は省略しました';
  }

  @override
  String qiIssueOneNoteSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '未対応の要素$count個をスキップしました',
    );
    return '$_temp0';
  }

  @override
  String get qiErrNoMarkdown => '選択したフォルダに Markdown (.md) ファイルがありません';

  @override
  String get qiErrNoNotionContent =>
      'ZIPファイルに.mdまたは.csvファイルが含まれていません。Notionで「Markdown & CSV」形式を選んでエクスポートしてください。';

  @override
  String get qiErrNothingImportable => 'インポート可能なものが見つかりませんでした';

  @override
  String get qiErrZipUnreadable => 'zip ファイルが破損しているか、有効なアーカイブではありません';

  @override
  String get qiErrNoOneNotePages => 'このファイルにはインポート可能なページがありません';

  @override
  String get qiErrUnexpected => '予期せぬエラー';

  @override
  String qiOneNoteSection(int n) {
    return 'セクション $n';
  }

  @override
  String get qiOneNotePage => 'ページ';

  @override
  String get qiPdfNotPdf => 'このファイルは有効な PDF ではありません';

  @override
  String get qiPdfCorrupt => 'この PDF は破損しているか不完全であるため、読み取ることができません';

  @override
  String get qiPdfEmpty => 'この PDF にはページがありません';

  @override
  String get qiPdfUnsupported => 'この PDF はサポートされていない保護または機能を使用しています';

  @override
  String get qiPdfPasswordCancelled => 'インポートがキャンセルされました：パスワードが指定されていません';

  @override
  String get qiPdfImportFailed => 'PDFをインポートできませんでした';

  @override
  String get qiPdfPasswordTitle => 'パスワードで保護されたPDF';

  @override
  String get qiPdfPasswordBody => 'この PDF をインポートするにはパスワードを入力してください。';

  @override
  String get qiPdfPasswordHint => 'パスワード';

  @override
  String get qiPdfPasswordWrong => 'パスワードが間違っています。もう一度お試しください';

  @override
  String get qiPdfPasswordOpen => '開く';

  @override
  String qiPdfPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'PDFには$countページがあります。',
      one: 'PDFは1ページあります。',
    );
    return '$_temp0';
  }

  @override
  String qiPdfStartOutOfRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'PDFには$countページあります。開始ページが範囲外です。',
    );
    return '$_temp0';
  }

  @override
  String get qsReauthBanner =>
      'サーバーはサインインを受け付けなくなりました。変更内容はこの端末上で安全に保存され、再度サインインすると同期されます。';

  @override
  String get qsDriveReauthBanner =>
      'Google Driveへの再サインインが必要です。変更はこの端末に保存されており、再サインイン後すぐに同期されます。';

  @override
  String get qsBrowserStorageFull =>
      'このブラウザーの保存容量が不足しています。ページを再読み込みすると最新の変更が失われる可能性があります。ノートブックをエクスポートするか、空き容量を確保してください。';

  @override
  String get qsReauthAction => '再サインイン';

  @override
  String qsDeletedElsewhere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊のノートブックが別の端末で削除されました。この端末のコピーだけが残っています。',
    );
    return '$_temp0';
  }

  @override
  String get qsDeletedElsewhereHint =>
      'ノートブックを長押しし、[このノートブックを再度同期する] を選択してアップロードし直します。';

  @override
  String get qsRefreshTooltip => 'サーバーから更新する';

  @override
  String get qsResumeSyncPending => 'サーバーに接続できません。接続が回復すると、このノートブックをアップロードします。';

  @override
  String get qsResumeSyncUploaded => 'アップロードされました。このノートブックは再び同期されます。';

  @override
  String get qsNoServerConnected => 'サーバーが接続されていません。';

  @override
  String get qsLoginWrongCredentials => 'サーバーはユーザー名またはパスワードを拒否しました。';

  @override
  String get qsLoginNotAServer =>
      'このアドレスには Nextcloud または WebDAV サーバーが見つかりません。 URLを確認してください。';

  @override
  String get qsLoginUnreachable => 'サーバーにアクセスできません。アドレスと接続を確認してください。';

  @override
  String get qsLoginThrottled => '接続を試した回数が多すぎます。しばらく待ってから再試行してください。';

  @override
  String get qsLoginServerError => 'サーバーがエラーを返しました。後でもう一度試してください。';

  @override
  String get quPenNoMonitor => 'アクティブなモニターが見つかりません。';

  @override
  String get quPenNoDevice => 'ペン入力デバイスが見つかりません。';

  @override
  String get quPenBadGeometry => '画面の配置やサイズを正しく取得できません。';

  @override
  String quPenToolMissing(String tool) {
    return '$tool が見つかりません。';
  }

  @override
  String quPenToolFailed(String tool) {
    return '$toolの実行に失敗しました。';
  }

  @override
  String get quDiffStrokes => 'ストローク';

  @override
  String get quDiffImages => '画像';

  @override
  String get quDiffShapes => '図形';

  @override
  String get quDiffTexts => 'テキスト';

  @override
  String get quDefaultChapter => '第1章';

  @override
  String qtNeedsOpenToUpload(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count冊のノートブックが、ほかの端末でも変更されています',
    );
    return '$_temp0';
  }

  @override
  String get qtNeedsOpenToUploadHint => 'ノートブックを開くと、変更を統合してアップロードできます。';

  @override
  String get qtResumeSyncNeedsOpen =>
      'このノートブックの同期を再開しました。ノートブックを開き、別の端末での変更を統合してください。';

  @override
  String libImportSuccessMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のノートブックをインポートしました',
    );
    return '$_temp0';
  }

  @override
  String get pgtTitlePages => 'ページ';

  @override
  String pgtEyebrow(String notebook, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '1ページ',
    );
    return '$notebook · $_temp0';
  }

  @override
  String get pgtSelect => '選択';

  @override
  String get pgtSelectPages => 'ページを選択';

  @override
  String get pgtAll => 'すべて';

  @override
  String get pgtNone => 'なし';

  @override
  String get pgtDone => '完了';

  @override
  String get pgtNoChapter => '章なし';

  @override
  String get pgtCopy => 'コピー';

  @override
  String get pgtMove => '移動';

  @override
  String get pgtTagMoving => '移動中';

  @override
  String get pgtHintPlaceMove =>
      'ページをタップするとその後に、左端をタップするとその前に配置できます。確定するまで変更は行われません。';

  @override
  String get pgtHintPlaceCopy => 'ページをタップするとその後に、左端をタップするとその前に貼り付けられます。';

  @override
  String get pgtMoveHere => 'ここに移動';

  @override
  String get pgtPasteHere => 'ここに貼り付け';

  @override
  String get pgtMoveShort => '移動';

  @override
  String get pgtPasteShort => '貼り付け';

  @override
  String pgtPasteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '1ページ',
    );
    return '$_temp0を貼り付け';
  }

  @override
  String pgtPasteCountShort(int count) {
    return '$countを貼り付け';
  }

  @override
  String get pgtThisNotebook => 'このノートブック';

  @override
  String get pgtAnotherNotebook => '別のノートブック…';

  @override
  String pgtMoveToNb(String notebook) {
    return '$notebook に移動';
  }

  @override
  String pgtPasteIntoNb(String notebook) {
    return '$notebookに貼り付け';
  }

  @override
  String get pgtPosStart => '先頭';

  @override
  String pgtPosAfter(int page) {
    return '$pageページの後';
  }

  @override
  String get pgtPosEnd => '末尾';

  @override
  String pgtPosChapterEnd(String chapter) {
    return '$chapterの末尾';
  }

  @override
  String get pgtChapterMenuHead => 'ページを割り当てる章';

  @override
  String pgtTrayMoving(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ · 移動中',
      one: '1ページ · 移動中',
    );
    return '$_temp0';
  }

  @override
  String pgtTrayCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ · コピー済み',
    );
    return '$_temp0';
  }

  @override
  String get pgtSavedShort => '保存済み';

  @override
  String get pgtSavedLong => 'この端末に保存済みです。アプリを閉じても保持されます。';

  @override
  String pgtFrom(String notebook) {
    return '$notebookより';
  }

  @override
  String pgtFromChapter(String notebook, String chapter) {
    return '移動元：$notebook › $chapter';
  }

  @override
  String pgtFromSeveral(String notebook) {
    return '移動元：$notebook › 複数の章';
  }

  @override
  String pgtSourceDeleted(String notebook) {
    return '$notebook は削除されました。これらのページはコピーになりました';
  }

  @override
  String get pgtTrayOptions => 'ページトレイのオプション';

  @override
  String get pgtCancelMove => '移動をキャンセル';

  @override
  String get pgtCancelMoveHint => '元のページはまだ移動していません';

  @override
  String get pgtClearTray => 'トレイを空にする';

  @override
  String get pgtChooseWhere => 'ページ一覧で挿入先を選ぶ';

  @override
  String get pgtChooseWhereHint => 'トレイのページを配置できる状態で、このノートブックのページ一覧を開きます';

  @override
  String pgtOpenSource(String notebook) {
    return '$notebook を開く';
  }

  @override
  String get pgtOpenSourceHint => 'コピー元・移動元のノートブック';

  @override
  String get pgtUndo => '元に戻す';

  @override
  String get pgtShow => '表示する';

  @override
  String pgtChooserTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページの移動先を選択',
    );
    return '$_temp0';
  }

  @override
  String get pgtRecent => '最近使ったノートブック';

  @override
  String get pgtChooserEmpty => 'この端末には他のノートブックはありません。';

  @override
  String get pgtBrowseLibrary => 'ライブラリを参照する';

  @override
  String pgtNbPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '1ページ',
    );
    return '$_temp0';
  }

  @override
  String pgtNbChapters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count章',
      one: '1章',
    );
    return '$_temp0';
  }

  @override
  String pgtNbPagesChapters(String pages, String chapters) {
    return '$pages · $chapters';
  }

  @override
  String pgtLibHintMove(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '1ページ',
    );
    return '$_temp0を移動するノートブックを選択してください。カバーをタップするか、その…メニューを使用します。';
  }

  @override
  String pgtLibHintPaste(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '1ページ',
    );
    return '$_temp0を貼り付けるノートブックを選択してください。カバーをタップするか、その…メニューを使用します。';
  }

  @override
  String pgtBadgeMoving(int count) {
    return '$countページを移動中';
  }

  @override
  String pgtCardMoveHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページ',
      one: '1ページ',
    );
    return '$_temp0をここに移動';
  }

  @override
  String pgtCardPasteHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページをここに貼り付け',
    );
    return '$_temp0';
  }

  @override
  String get pgtWhereStart => '先頭';

  @override
  String pgtWhereAfter(int page) {
    return '$pageページの後';
  }

  @override
  String get pgtWhereEnd => '末尾';

  @override
  String pgtWhereChapterEnd(String chapter) {
    return '$chapterの末尾';
  }

  @override
  String pgtToastCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページをコピーしました。貼り付けるノートブックを開いてください。',
      one: '1ページコピーしました。貼り付けるノートブックを開いてください。',
    );
    return '$_temp0';
  }

  @override
  String pgtToastCopiedSkipped(int count, int skipped) {
    return '$countページをコピーしました。未読み込みの$skippedページはスキップしました。';
  }

  @override
  String pgtToastMoveReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページを移動する準備ができています。確認するまで何も変わりません。',
      one: '1ページを移動する準備ができました。確認するまで何も変わりません。',
    );
    return '$_temp0';
  }

  @override
  String pgtToastMoveReadySkipped(int count, int skipped) {
    return '$countページの移動準備ができました。未読み込みの$skippedページはスキップしました。確定するまで変更は行われません。';
  }

  @override
  String pgtToastMoveCancelled(int count, String notebook) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '移動がキャンセルされました。$countページは$notebookに残ります。',
      one: '移動がキャンセルされました。$notebookに1ページが残ります。',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastTrayCleared => 'トレイがクリアされました';

  @override
  String pgtToastPasted(int count, String notebook, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '「$notebook」の$whereに$countページを貼り付けました',
    );
    return '$_temp0';
  }

  @override
  String pgtToastMoved(int count, String notebook, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '「$notebook」の$whereに$countページを移動しました',
    );
    return '$_temp0';
  }

  @override
  String pgtToastDuplicated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countページを複製しました',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastUndone => '元に戻しました';

  @override
  String pgtToastTooMany(int max) {
    return 'トレイに入れられるのは$maxページまでです。選択するページ数を減らしてください。';
  }

  @override
  String get pgtToastNothing =>
      'これらのページはまだ準備ができていません（まだ読み込み中です）。しばらくしてからもう一度試してください。';

  @override
  String get pgtToastTrayNotSaved => 'この端末にトレイを保存できませんでした。アプリを閉じると失われます。';

  @override
  String get pgtToastPagesGone => 'それらのページはこのノートブックにはもうありません。';

  @override
  String get pgtToastTrayDamaged => '保存されたトレイは不完全で、何も貼り付けられていません。';

  @override
  String get pgtToastDestFailed => '貼り付けるページを保存できませんでした。変更は行われていません。';

  @override
  String get pgtToastDestUnavailable => 'そのノートブックは現在編集できません。変更は行われていません。';

  @override
  String pgtToastSourceFailed(String notebook) {
    return 'ページが追加されましたが、$notebook から削除できませんでした。これらは両方のノートブックにあります。トレイはコピーになりました。';
  }

  @override
  String pgtToastMoveResumed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '中断された移動によって残された$countページの移動が完了しました。',
      one: '中断した移動で残った1ページの移動が完了しました。',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastUndoFailed => '元に戻せませんでした。両方のノートを確認してください。';

  @override
  String get csTapUndone => '元に戻しました';

  @override
  String get csTapRedone => 'やり直しました';

  @override
  String get setSectionModules => 'モジュール';

  @override
  String get setModulesIntro =>
      '必要に応じて有効にできる機能です。無効な機能はメモリを使いません。その機能を使って作成したページもそのまま残ります。';

  @override
  String get modStatusReady => '準備完了';

  @override
  String get modStatusLoading => '読み込み中…';

  @override
  String get modStatusUnavailable => 'モデルがインストールされていません';

  @override
  String get modStatusDisabled => 'オフ';

  @override
  String modMeta(String version, String license) {
    return 'バージョン $version · ライセンス $license';
  }

  @override
  String modAssetLicense(String license) {
    return 'モデル：$license';
  }

  @override
  String get modBeta => 'ベータ版';

  @override
  String get modBetaHint => 'テスト中は無料';

  @override
  String get modOnDevice => '端末上で動作する小さなモデル。何も送信されません。';

  @override
  String get modCircuitsName => '回路認識';

  @override
  String get modCircuitsDesc =>
      '選択した手描き回路を認識し、整った回路記号と配線で描き直します。誤認識がある場合があるため、結果を確認してください。';

  @override
  String get modMathInkName => '数式認識';

  @override
  String get modMathInkDesc =>
      '選択した手書きの数式を認識し、編集可能な LaTeX に変換します。結果を確認してください。一部の記号が間違っている可能性があります。';

  @override
  String get csRecognizeMathFailed => '数式を認識できませんでした';

  @override
  String get mathEditTitle => '数式を編集する';

  @override
  String get mathEditHint => 'LaTeX ソース';

  @override
  String get mathEditInvalid => '数式が正しくありません';

  @override
  String get csRecognizeCircuit => '回路を認識する';

  @override
  String get csRecognizeCircuitFailed => '回路を認識できませんでした';

  @override
  String get csRecognizeBusy => '認識中…';

  @override
  String get csRecognizeModelMissing => '認識モデルが読み込まれていません';

  @override
  String get csRecognizeNoInk => '選択範囲に手書きの線がありません';

  @override
  String get csRecognizeError => '認識に失敗しました';

  @override
  String get csRecognizeImageMissing => '画像がまだ読み込まれていません';

  @override
  String get csRecognize => '認識';

  @override
  String get csRecognizedAsFormula => '数式として認識しました';

  @override
  String get csRecognizedAsCircuit => '回路として認識しました';

  @override
  String get csRecognizeChange => '変更';

  @override
  String get csRecognizeAs => '認識の種類';

  @override
  String get csRecognizeAsFormula => '数式';

  @override
  String get csRecognizeAsCircuit => '回路';

  @override
  String get csRecognizeAsText => 'テキスト';

  @override
  String get csRecognizeTextNotConverted => '手書き文字は検索できますが、入力テキストには変換されません';

  @override
  String get csRecognizeDrawing => '図のようです：認識するものはありません';

  @override
  String csRecognizeModuleOff(String module) {
    return '$moduleはオフです：設定 > モジュールでオンにしてください';
  }

  @override
  String get imgConvertToInk => 'インクに変換';

  @override
  String get csPhotoInkBusy => '手書き文字を読み取り中…';

  @override
  String get csPhotoInkFailed => 'この画像に手書き文字が見つかりません';

  @override
  String get csInsertPhotoInk => 'ノートの写真をインクに';

  @override
  String shareImportTitle(String name) {
    return '$name をインポート';
  }

  @override
  String shareImportTitleMany(int count) {
    return '$count個のファイルをインポート';
  }

  @override
  String get shareImportNewNotebookHint => 'PDFの各ページをノートブックの1ページとして取り込みます';

  @override
  String get shareImportAddTo => 'ノートブックに追加する';

  @override
  String get shareImportDefaultTitle => 'インポート済み';

  @override
  String shareImportWhere(String notebook) {
    return '「$notebook」の追加先';
  }

  @override
  String shareImportEndOf(String chapter) {
    return '「$chapter」の終わりに';
  }

  @override
  String get shareImportNewChapterHint => '最終章の後';

  @override
  String get shareImportAtEnd => 'ノートブックの末尾';

  @override
  String get csOpenBeside => '横に開く';

  @override
  String get csOpenBesideSub => '書きながら別のノートを読む';

  @override
  String get csCloseBeside => '横に開いたノートブックを閉じる';

  @override
  String get refPickTitle => '横に開くノート';

  @override
  String get refNoOthers => '他にノートはありません。';

  @override
  String get refLoadFailed => 'このノートブックを開けませんでした。この端末上にない場合は、オンラインにする必要があります。';

  @override
  String get refZoomIn => 'ズームイン';

  @override
  String get refZoomOut => 'ズームアウト';

  @override
  String get winMirrorBanner => '読み取り専用：このノートブックは別のウィンドウでも開いています。自動で更新されます。';

  @override
  String get winOpenElsewhere =>
      'このノートブックは別のウィンドウで開いています。そちらで閉じてからもう一度お試しください。';

  @override
  String get winOpenNewWindow => '新しいウィンドウで開く';

  @override
  String get libDropHint => 'ドロップしてインポート';

  @override
  String get libDropUnsupported =>
      'これらのファイルはインポートできません。 PDF、画像、ノートブック、OneNote、Notion、または Obsidian フォルダを試してください。';

  @override
  String get csDropHint => 'ここにドロップして挿入します';

  @override
  String get csDropUnsupported => 'ここには画像と PDF のみを挿入できます。';

  @override
  String get donScreenTitle => '提供するサンプル';

  @override
  String get donScreenIntro =>
      'サンプルが書いた内容と合っていない場合は、タップして修正するか破棄してください。「送信」を押すまでは、このブラウザーから何も送信されません。AbelNotesアプリから手書きデータが送信されることはなく、このページからだけ送信されます。';

  @override
  String get donPrivacy => 'プライバシーポリシー';

  @override
  String get donSentHeader => '提供済みのサンプル';

  @override
  String donAcceptedTotal(int count) {
    return '採用されたサンプル：$count件';
  }

  @override
  String get donKeepCode => '受付コードを保管してください。コードがないと、提供したデータの検索・確認・削除ができません。';

  @override
  String donConsentGiven(String date) {
    return '$dateに同意しました。';
  }

  @override
  String donConsentGivenRepublish(String date) {
    return '$dateにデータセットでの公開を含めて同意しました。';
  }

  @override
  String get donWithdraw => '同意を撤回';

  @override
  String donWithdrawn(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '同意を撤回し、$count件の提供データを削除しました。',
      zero: '同意を撤回しました。',
    );
    return '$_temp0';
  }

  @override
  String donWithdrawFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '同意は撤回しましたが、$count件の提供データをまだ削除できていません。それぞれの「削除」ボタンで再試行してください。',
    );
    return '$_temp0';
  }

  @override
  String get donWithdrawTitle => '同意を撤回しますか？';

  @override
  String get donWithdrawBody =>
      'ここに表示されている提供データをすべて保存先から削除し、今後の学習には使用しません。すでに学習済みのモデルには反映されません。次回送信時には、あらためて同意を確認します。';

  @override
  String donQueueSummary(int toReview, int reviewed) {
    return '未確認：$toReview · 確認済み：$reviewed';
  }

  @override
  String donSendCount(int count) {
    return '送信 ($count)';
  }

  @override
  String donSent(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countサンプルを送信しました',
      one: '1サンプルを送信しました',
    );
    return '$_temp0';
  }

  @override
  String get donDeleteTitle => '提供したサンプルを削除しますか？';

  @override
  String get donDeleteBody =>
      '提供したサンプルを保管先から削除し、今後の学習には使用しません。すでに学習済みのモデルには反映されません。';

  @override
  String get donDelete => '削除';

  @override
  String get donDeleted => '提供したサンプルを削除しました';

  @override
  String donParts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個の部品',
    );
    return '$_temp0';
  }

  @override
  String get donReviewed => '確認済み';

  @override
  String get donToReviewShort => '未確認';

  @override
  String donStatusAccepted(int count) {
    return '$count件を採用';
  }

  @override
  String get donStatusRejected => '不採用';

  @override
  String get donStatusInReview => '審査中';

  @override
  String donSamples(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countサンプル',
      one: '1サンプル',
    );
    return '$_temp0';
  }

  @override
  String get donCopyCode => 'コードをコピーする';

  @override
  String get donCodeCopied => 'コードをコピーしました';

  @override
  String get donErrOffline => 'サーバーに到達できませんでした。後でもう一度試してください。';

  @override
  String get donErrBusy => '現在送信数が多すぎます。 1分後にもう一度試してください。';

  @override
  String get donErrFull => '今日の制限に達しました。明日もう一度試してください。';

  @override
  String get donErrRefused => 'サーバーがサンプルを拒否しました。';

  @override
  String get donErrNotFound => '提供したサンプルが見つかりません。';

  @override
  String get donErrServer => 'サーバーエラー。後でもう一度試してください。';

  @override
  String get donConsentTitle => '送信する前に';

  @override
  String get donConsentWhat =>
      '送信される内容：各サンプルのペンの軌跡（位置、相対時刻、筆圧）と、書かれた内容（回路部品または数式）です。アカウント情報、名前、端末の識別情報や、ノート内のデータは含まれません。';

  @override
  String get donConsentWhy =>
      'AbelNotesは、提供されたサンプルを端末上で動く認識モデルの学習とテストに使います。最後のチェック項目を選ばない限り、サンプルは公開されません。署名や名前など、自分や他人を特定できる情報は書かないでください。';

  @override
  String get donConsentReceipt =>
      '送信ごとに受付コードを発行し、このブラウザーに保存します。このコードを使うと、提供したデータをいつでも削除できます。ここで同意を撤回すると、表示されている提供データをすべて削除します。';

  @override
  String get donConsentController =>
      'このデータの責任者、データの保管期間、およびあなたの権利：プライバシーポリシーをご覧ください。';

  @override
  String get donConsentTrain => 'AbelNotesが、これらのサンプルを認識モデルの学習に使用することに同意します。';

  @override
  String get donConsentAge => '私は16歳以上で、居住地域で有効に同意できる年齢に達しています（インドでは18歳以上）。';

  @override
  String get donConsentRepublish => 'サンプルをデータセットとして公開することにも同意します（任意）。';

  @override
  String get donConsentRepublishNote =>
      'データセットの公開後は、ほかの人が取得したコピーを回収できません。同意を撤回しても、停止できるのは今後の公開だけです。';

  @override
  String get donReviewTitle => 'サンプルを確認';

  @override
  String get donReset => 'リセット';

  @override
  String get donNoParts => '部品がありません。サンプルを破棄するか、ドラッグして部品を囲み、追加してください。';

  @override
  String get donReviewHint =>
      '部品をタップして修正・削除できます。認識されなかった部品は、ドラッグして囲むと追加できます。ピンチ操作やスクロールで拡大・縮小できます。';

  @override
  String get donDiscard => '破棄';

  @override
  String get donMarkReviewed => '内容を確認しました';

  @override
  String get donPickSymbol => 'この部品の種類は？';

  @override
  String get donRemovePart => 'この部品を削除';

  @override
  String get donFitView => 'ビューに合わせる';

  @override
  String get symResistor => '抵抗器';

  @override
  String get symCapacitor => 'コンデンサ';

  @override
  String get symCapacitorPolarized => '有極性コンデンサ';

  @override
  String get symInductor => 'インダクタ';

  @override
  String get symDiode => 'ダイオード';

  @override
  String get symVoltageDc => '直流電圧源';

  @override
  String get symVoltageAc => '交流電圧源';

  @override
  String get symBattery => 'バッテリー';

  @override
  String get symCurrentSource => '電流源';

  @override
  String get symBjt => 'BJTトランジスタ';

  @override
  String get symFet => 'FETトランジスタ';

  @override
  String get symOpamp => 'オペアンプ';

  @override
  String get symIc => '集積回路';

  @override
  String get symTransformer => '変圧器';

  @override
  String get symSwitch => 'スイッチ';

  @override
  String get symGnd => 'グラウンド（GND）';

  @override
  String get symVss => '電源レール (VCC/VSS)';

  @override
  String get symJunction => '接続点';

  @override
  String get symCrossover => '交差（接続なし）';

  @override
  String get symTerminal => '端子';

  @override
  String get symArrow => '矢印';

  @override
  String get symText => 'テキスト';

  @override
  String get donEmptyGuided => 'まだサンプルはありません。いくつかの数式や記号を書くと、それらがここに表示されます。';

  @override
  String get donFormulaHintGuided =>
      'お題の数式を書いたサンプルです。別の内容を書いた場合は、LaTeXを修正するかサンプルを破棄してください。';

  @override
  String get donLatexLabel => 'LaTeX';

  @override
  String get donLatexEmpty => 'LaTeXはまだありません';

  @override
  String get donLatexTooLong => '1000文字以内で入力してください';

  @override
  String get donLatexNotAscii =>
      'ASCII文字で入力してください。アクセント付きの文字や記号はLaTeXコマンドで記述してください。';

  @override
  String get donLatexInvalid => 'LaTeX が無効です：中かっことコマンドを確認してください';

  @override
  String get donGuidedTitle => '手書きサンプルを提供';

  @override
  String get donGuidedIntro =>
      '表示された数式や記号を、普段ノートに書くように手書きしてください。あなたの筆跡を認識モデルが学ぶためのサンプルになります。AbelNotesアプリから手書きデータが送信されることはありません。サンプルの提供はこのページからだけ行われ、内容を確認して「送信」を押すまではブラウザー内に保存されます。';

  @override
  String get donGuidedFormulas => '数式';

  @override
  String get donGuidedCircuits => '回路記号';

  @override
  String get donGuidedWriteFormula => 'この数式を書いてください';

  @override
  String get donGuidedDrawSymbol => '回路記号だけを描き、端子につながる線は短めにしてください';

  @override
  String get donGuidedWriteText => 'このラベルを書いてください';

  @override
  String get donGuidedPadHint => 'ペン・指・マウスでここに書いてください';

  @override
  String get donGuidedUndo => 'ストロークを元に戻す';

  @override
  String get donGuidedClear => 'クリア';

  @override
  String get donGuidedSkip => 'スキップ';

  @override
  String get donGuidedNext => '次へ';

  @override
  String donGuidedReview(int count) {
    return '確認して送信（$count件）';
  }

  @override
  String get donGuidedFull => '未送信のサンプルが上限に達しました。先に一部のサンプルを送信するか、破棄してください。';

  @override
  String get donGuidedTabTitle => 'サンプル提供 · AbelNotes';

  @override
  String get srchSection => 'ノート内';

  @override
  String srchHitsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ノート内で$count件一致',
    );
    return '$_temp0';
  }

  @override
  String srchPageN(int page) {
    return '$pageページ';
  }

  @override
  String srchShowMore(int count) {
    return 'さらに$count件表示';
  }

  @override
  String get srchIndexing => 'ノートをインデックス中…';

  @override
  String srchNoMatch(String query) {
    return '「$query」を含むノートはありません。';
  }

  @override
  String get findHint => 'ノートブック内を検索…';

  @override
  String get findInNotebook => 'ノートブック内を検索';

  @override
  String get findInNotebookSub => '入力テキスト、数式、PDF';

  @override
  String findCount(int current, int total) {
    return '$current / $total';
  }

  @override
  String get findNone => '一致なし';

  @override
  String get findPrevious => '前の一致（Shift+Enter）';

  @override
  String get findNext => '次の一致（Enter）';

  @override
  String get findClose => '閉じる（Esc）';
}
