// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get csPdfTextCopied => '文本已复制';

  @override
  String csCopyFailed(String error) {
    return '复制失败：$error';
  }

  @override
  String get csCopy => '复制';

  @override
  String get csSyncInProgress => '正在同步…';

  @override
  String get csSaved => '已保存！';

  @override
  String csErrorGeneric(String error) {
    return '错误：$error';
  }

  @override
  String get csSelectionCopied => '已复制所选内容';

  @override
  String get csSelectionCut => '已剪切所选内容';

  @override
  String get csShortcutsTitle => '键盘快捷键';

  @override
  String get csShortcutGroupGeneral => '常规';

  @override
  String get csSaveNow => '立即保存';

  @override
  String get csShortcutUndo => '撤销';

  @override
  String get csShortcutRedo => '重做';

  @override
  String get csSelectAll => '全选';

  @override
  String get csShortcutResetZoom => '重置缩放';

  @override
  String get csShortcutDeselect => '取消选择 / 取消';

  @override
  String get csShortcutThisGuide => '本指南';

  @override
  String get csShortcutGroupClipboard => '剪贴板';

  @override
  String get csShortcutCopySelection => '复制所选内容';

  @override
  String get csShortcutCutSelection => '剪切所选内容';

  @override
  String get csPaste => '粘贴';

  @override
  String get csShortcutDuplicateSelection => '复制一份所选内容';

  @override
  String get csShortcutKeyDeleteBackspace => 'Del / Backspace';

  @override
  String get csShortcutDeleteElementOrSelection => '删除元素或所选内容';

  @override
  String get csShortcutGroupTools => '工具';

  @override
  String get csToolPen => '钢笔';

  @override
  String get csToolBrush => '画笔';

  @override
  String get csToolEraser => '橡皮擦';

  @override
  String get csToolLasso => '套索';

  @override
  String get csToolHand => '抓手 / 移动';

  @override
  String get csToolText => '文本';

  @override
  String get csToolShape => '形状';

  @override
  String get csClose => '关闭';

  @override
  String get csUnsavedChangesTitle => '有未保存的更改';

  @override
  String get csUnsavedChangesBody => '离开前要保存吗？';

  @override
  String get csDiscard => '放弃';

  @override
  String get csCancel => '取消';

  @override
  String get csSave => '保存';

  @override
  String get csOpeningLink => '正在打开链接…';

  @override
  String get csCannotOpenLink => '无法打开该链接';

  @override
  String get csCameraUnavailable => '此设备没有可用的相机';

  @override
  String get csPhotoCaptureFailed => '无法拍照';

  @override
  String get csPdfRasterizing => '正在栅格化 PDF…';

  @override
  String csPdfImportProgress(int done, int total) {
    return '正在导入 PDF：$done/$total';
  }

  @override
  String get csPdfReadFailed => '无法读取该 PDF：未找到页面';

  @override
  String csPdfImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return 'PDF 已导入：$_temp0';
  }

  @override
  String csPdfImportError(String error) {
    return 'PDF 导入出错：$error';
  }

  @override
  String get csNoNotebookOpen => '没有打开的笔记本';

  @override
  String get csMissingPageDataTitle => '缺少页面数据';

  @override
  String get csNoPages => '没有页面';

  @override
  String csMissingPagesBodyMany(int count) {
    return '本页和另外 $count 页未能从服务器取回。这些文件可能在一次不完整的同步中丢失了。';
  }

  @override
  String get csMissingPageBodyOne => '本页的文件未能从服务器取回。它可能在一次不完整的同步中丢失了。';

  @override
  String get csRetrySync => '重新同步';

  @override
  String get csRestoreAsBlankPage => '恢复为空白页';

  @override
  String csRestoreAllMissing(int count) {
    return '全部恢复（$count）';
  }

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已将 $count 页恢复为空白页',
      one: '已将 $count 页恢复为空白页',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => '删除页面';

  @override
  String csSyncProgressCount(int done, int total) {
    return '正在同步 $done/$total';
  }

  @override
  String get csSyncing => '正在同步…';

  @override
  String csShapeRecognizedLabel(String shape) {
    return '形状：$shape';
  }

  @override
  String get csConfirmShapeSemantics => '确认识别出的形状';

  @override
  String get csConfirm => '确认';

  @override
  String get csCancelShapeSemantics => '取消识别出的形状';

  @override
  String csTapToPlaceSymbol(String name) {
    return '点按以放置：$name';
  }

  @override
  String get csCancelSymbolInsertSemantics => '取消插入符号';

  @override
  String get csTapToPlaceCopy => '点按以放置副本';

  @override
  String get csCancelPasteSemantics => '取消粘贴';

  @override
  String get csNewPage => '新建页面';

  @override
  String get csImageCopied => '图片已复制';

  @override
  String get csImageCut => '图片已剪切';

  @override
  String get csImageCommentTitle => '图片备注';

  @override
  String get csAddCommentHint => '添加备注...';

  @override
  String get csRemove => '移除';

  @override
  String get csCut => '剪切';

  @override
  String get csDuplicate => '复制一份';

  @override
  String get csSelectionDuplicated => '已复制所选内容';

  @override
  String get csChangeColor => '更改颜色';

  @override
  String get csThickness => '粗细';

  @override
  String get csDelete => '删除';

  @override
  String get csMore => '更多';

  @override
  String get csPresentationMode => '演示模式';

  @override
  String get csPresentationModeSub => '全屏、不显示工具 — 很适合展示页面';

  @override
  String get csRecognizeHandwriting => '识别手写内容';

  @override
  String get csRecognizeHandwritingSub => '把笔迹转成可搜索的文字（在本机完成）';

  @override
  String get csRecognizeInProgress => '正在识别…';

  @override
  String get csRecognizeNothing => '未识别到文字。';

  @override
  String csRecognizeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已识别 $count 行',
      one: '已识别 $count 行',
    );
    return '$_temp0。';
  }

  @override
  String csRecognizeFailed(String error) {
    return '识别失败：$error';
  }

  @override
  String get csShareLink => '通过链接分享';

  @override
  String get csShareLinkSub => '把 PDF 上传到你的 Nextcloud 并创建公开链接';

  @override
  String get csShareLinkInProgress => '正在创建链接…';

  @override
  String get csShareLinkTitle => '公开链接';

  @override
  String get csShareLinkBody => '拿到此链接的人都能查看该 PDF。你可以在 Nextcloud 中撤销。';

  @override
  String get csShareLinkCopied => '链接已复制到剪贴板。';

  @override
  String csShareLinkFailed(String error) {
    return '分享失败：$error';
  }

  @override
  String get csCopyLink => '复制链接';

  @override
  String get csShare => '分享';

  @override
  String get csRevokeLink => '撤销链接';

  @override
  String get csRevokeLinkDone => '链接已撤销。';

  @override
  String get csShareLinkUpdate => '更新已分享的 PDF';

  @override
  String get csShareLinkUpdated => 'PDF 已更新。';

  @override
  String get csChangeSelectionColor => '更改所选内容的颜色';

  @override
  String get csSelectionThickness => '所选内容的粗细';

  @override
  String csWidthPx(String width) {
    return '$width px';
  }

  @override
  String get csFlipHorizontal => '水平翻转';

  @override
  String get csFlipVertical => '垂直翻转';

  @override
  String get csCopyAsImage => '复制为图片';

  @override
  String get csPasteInAnotherNotebook => '粘贴到另一个笔记本…';

  @override
  String get csKeyDelete => 'Del';

  @override
  String get csCreateSymbol => '创建符号';

  @override
  String get csSelect => '选择';

  @override
  String get csImportFile => '导入文件…';

  @override
  String get csTakePhoto => '拍照';

  @override
  String get csInsertText => '插入文本';

  @override
  String csInsertSymbolCount(int count) {
    return '插入符号（$count）';
  }

  @override
  String get csClearPage => '清空页面';

  @override
  String get csExportPng => '导出 PNG';

  @override
  String get csExportPdf => '导出 PDF';

  @override
  String get csClearPageConfirmBody => '本页上的所有元素都会被删除。继续吗？';

  @override
  String get csClear => '清空';

  @override
  String get csCreateSymbolTitle => '创建可重复使用的符号';

  @override
  String get csSymbolNameLabel => '符号名称';

  @override
  String get csLibraryLabel => '库：';

  @override
  String get csNoLibraryNotice => '还没有库。将会创建一个“符号”库。';

  @override
  String get csCreate => '创建';

  @override
  String csSymbolCreated(String name) {
    return '符号“$name”已创建！';
  }

  @override
  String csSaveFileDialogTitle(String fileName) {
    return '保存 $fileName';
  }

  @override
  String get csExportCurrentPagePng => '当前页面（PNG）';

  @override
  String get csExportCurrentChapter => '当前章节';

  @override
  String get csExportEntireNotebook => '整个笔记本';

  @override
  String csExportingPages(int count) {
    return '正在导出 $count 页...';
  }

  @override
  String csChooseFolderForImages(int count) {
    return '为这 $count 张图片选择一个文件夹';
  }

  @override
  String csPngExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return 'PNG 已导出（$_temp0）';
  }

  @override
  String csExportError(String error) {
    return '导出出错：$error';
  }

  @override
  String get csExportCurrentPage => '当前页面';

  @override
  String csGeneratingPdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return '正在生成 PDF（$_temp0）...';
  }

  @override
  String csPdfExportError(String error) {
    return 'PDF 导出出错：$error';
  }

  @override
  String csPdfExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return 'PDF 已导出：$_temp0';
  }

  @override
  String get csChapterSeparatorEyebrow => '章节';

  @override
  String get csSelectionCopiedAsImage => '已把所选内容复制为图片';

  @override
  String csCopyImageError(String error) {
    return '复制图片出错：$error';
  }

  @override
  String get csExport => '导出';

  @override
  String csPageNumber(int number) {
    return '第 $number 页';
  }

  @override
  String csPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return '$_temp0';
  }

  @override
  String get csExportChapterTitle => '导出章节';

  @override
  String get csExportNotebookTitle => '导出整个笔记本';

  @override
  String get csChapterSeparatorQuestion => '在每个章节前插入一页分隔页吗？';

  @override
  String get csYesWithSeparators => '是，加分隔页';

  @override
  String get csNoPagesOnly => '不，只要页面';

  @override
  String csTotalPages(int count) {
    return '总页数：$count';
  }

  @override
  String csFromPage(int page) {
    return '起始页：$page';
  }

  @override
  String csToPage(int page) {
    return '结束页：$page';
  }

  @override
  String csWillExportPages(int count, int start, int end) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '将导出 $count 页（$start–$end）',
      one: '将导出 $count 页（$start–$end）',
    );
    return '$_temp0';
  }

  @override
  String csChapterLabelWithCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return '$title（$_temp0）';
  }

  @override
  String get csGoToPage => '跳转到页面';

  @override
  String get csDuplicatePage => '复制此页';

  @override
  String get csNewPageAfter => '在后面新建页面';

  @override
  String get csDeletePageConfirmTitle => '删除这一页吗？';

  @override
  String csDeletePageConfirmBody(int number) {
    return '第 $number 页及其全部内容都会被删除。';
  }

  @override
  String get csExportAsPdf => '导出为 PDF';

  @override
  String get csExportAsPng => '导出为 PNG';

  @override
  String get csExportAsNcnote => '导出为 .abelnote（原生格式）';

  @override
  String get csExportNcnoteSubtitle => '原生格式，保留完整矢量质量（用于备份或迁移）';

  @override
  String get csGeneratingNcnote => '正在生成 .abelnote…';

  @override
  String csNcnoteExported(String size) {
    return '.abelnote 已导出（$size KB）';
  }

  @override
  String csNcnoteExportError(String error) {
    return '.abelnote 导出出错：$error';
  }

  @override
  String get csImageOrPdf => '图片或 PDF';

  @override
  String get csChangePaperType => '更改纸张类型';

  @override
  String get csPenToMonitor => '笔 → 显示器';

  @override
  String get csPenToMonitorSubtitle => '把笔限制在单个屏幕上';

  @override
  String get csPaperType => '纸张类型';

  @override
  String get csPaperBlank => '空白';

  @override
  String get csPaperLinedNarrow => '窄行线';

  @override
  String get csPaperLinedWide => '宽行线';

  @override
  String get csPaperGrid => '方格';

  @override
  String get csPaperDotted => '点阵';

  @override
  String get csPaperCornell => '康奈尔笔记';

  @override
  String get csPaperIsometric => '等角网格';

  @override
  String get csPaperMusic => '五线谱';

  @override
  String get csMapPenToMonitor => '把笔映射到某个显示器';

  @override
  String csPenMappedTo(String monitor) {
    return '笔已映射到 $monitor';
  }

  @override
  String get csAllMonitors => '所有显示器';

  @override
  String get csAllMonitorsSubtitle => '重置（笔可用于整个桌面）';

  @override
  String get csPenReset => '笔已重置';

  @override
  String get csShapeLine => '直线';

  @override
  String get csShapeCircle => '圆形';

  @override
  String get csShapeRectangle => '矩形';

  @override
  String get csShapeTriangle => '三角形';

  @override
  String get csShapeArrow => '箭头';

  @override
  String get csInvalidRangeError => '请输入有效的范围（例如 1–10）。';

  @override
  String csPdfStartOutOfRange(int count) {
    return '该 PDF 大约有 $count 页。起始页超出范围。';
  }

  @override
  String get csImportPdfTitle => '导入 PDF';

  @override
  String csPdfEstimatedPages(int count) {
    return '该 PDF 大约有 $count 页。';
  }

  @override
  String csAllPagesWithCount(int count) {
    return '全部页面（$count）';
  }

  @override
  String get csAllPages => '全部页面';

  @override
  String get csCustomRange => '自定义范围';

  @override
  String get csFromLabel => '从';

  @override
  String get csToLabel => '到';

  @override
  String get csImport => '导入';

  @override
  String libErrorGeneric(String error) {
    return '错误：$error';
  }

  @override
  String libErrorOpen(String error) {
    return '打开时出错：$error';
  }

  @override
  String get libImportCannotReadFile => '无法读取该文件';

  @override
  String get libImportInProgress => '正在导入…';

  @override
  String get libServiceUnavailable => '服务不可用';

  @override
  String libImportedTitleSuffix(String title) {
    return '$title（已导入）';
  }

  @override
  String libImportSuccess(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return '已导入：“$title”（$_temp0）';
  }

  @override
  String get libImportCorruptedFile => '这个文件不是有效的 AbelNotes 笔记本 — 它可能不完整或已损坏。';

  @override
  String get libExport => '导出';

  @override
  String get libImportOneNoteUnreadable =>
      'AbelNotes 无法读取这个 OneNote 文件 — 它可能使用了导入器尚不支持的格式，或者已损坏。';

  @override
  String libErrorImport(String error) {
    return '导入出错：$error';
  }

  @override
  String libErrorCreate(String error) {
    return '创建时出错：$error';
  }

  @override
  String get libSketchDefaultTitle => '速写';

  @override
  String libErrorCreateSketch(String error) {
    return '创建速写时出错：$error';
  }

  @override
  String get libRemoveFromFavorites => '从收藏中移除';

  @override
  String get libAddToFavorites => '添加到收藏';

  @override
  String get libRename => '重命名';

  @override
  String get libChangeCover => '更换封面';

  @override
  String get libMoveToFolder => '移动到文件夹';

  @override
  String get libNoFolder => '不放入文件夹';

  @override
  String get libNewFolder => '新建文件夹';

  @override
  String get libRenameFolder => '重命名文件夹';

  @override
  String get libFolderNameHint => '文件夹名称';

  @override
  String get libAllNotebooks => '全部';

  @override
  String get libDeleteFolder => '删除文件夹';

  @override
  String libDeleteFolderTitle(String name) {
    return '删除文件夹“$name”吗？';
  }

  @override
  String get libDeleteFolderBody => '里面的笔记本不会被删除 — 它们会留在库中，只是不属于任何文件夹。';

  @override
  String get libDelete => '删除';

  @override
  String get libDeleteNotebookTitle => '删除这个笔记本吗？';

  @override
  String get libDeleteNotebookBody => '它会被移到回收站。你可以在“设置 > 存储”中恢复它。';

  @override
  String get libCancel => '取消';

  @override
  String get libRenameNotebookTitle => '重命名笔记本';

  @override
  String get libSave => '保存';

  @override
  String get libSortTitle => '排序';

  @override
  String get libAppName => 'AbelNotes';

  @override
  String get libSearchHintShort => '搜索…';

  @override
  String get libSearchHintNotebooks => '搜索笔记本…';

  @override
  String get libImport => '导入';

  @override
  String get libImportTooltip => '导入 .abelnote 文件';

  @override
  String get libSettingsTooltip => '设置';

  @override
  String get libMoreTooltip => '更多';

  @override
  String get libViewAsList => '列表视图';

  @override
  String get libViewAsGrid => '网格视图';

  @override
  String libSortWithLabel(String sortLabel) {
    return '排序：$sortLabel';
  }

  @override
  String get libImportNcnoteMenu => '导入…';

  @override
  String get libYourNotebooks => '你的笔记本';

  @override
  String libItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 项',
      one: '$count 项',
    );
    return '$_temp0';
  }

  @override
  String get libNewNotebook => '新建笔记本';

  @override
  String get libSketches => '速写';

  @override
  String get libInfiniteSpace => '无限空间';

  @override
  String get libNewSketch => '新建速写';

  @override
  String get libInfiniteCanvas => '无限画布';

  @override
  String get libNew => '新建';

  @override
  String libPagesAbbrev(int count) {
    return '$count 页';
  }

  @override
  String libPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return '$_temp0';
  }

  @override
  String get libFooterWebdav => 'WebDAV';

  @override
  String get libFooterLocalFirst => '本地优先的应用';

  @override
  String get libSyncingWithServer => '正在与服务器同步…';

  @override
  String libDownloadingProgress(int done, int total) {
    return '正在下载 $done/$total 个笔记本…';
  }

  @override
  String get libLoadingNotebooks => '正在加载笔记本…';

  @override
  String get libLoadingNotebooksFromServer => '正在从服务器加载笔记本…';

  @override
  String get libTimeNow => '刚刚';

  @override
  String libTimeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String libTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 小时前',
      one: '$count 小时前',
    );
    return '$_temp0';
  }

  @override
  String libTimeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String libTimeWeeksAgo(int count) {
    return '$count 周前';
  }

  @override
  String libTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 个月前',
      one: '$count 个月前',
    );
    return '$_temp0';
  }

  @override
  String libTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 年前',
      one: '$count 年前',
    );
    return '$_temp0';
  }

  @override
  String get libNotebookTitleLabel => '标题';

  @override
  String get libCoverLabel => '封面';

  @override
  String get libPaperLabel => '纸张';

  @override
  String get libPaperBlank => '空白';

  @override
  String get libPaperLined => '横线';

  @override
  String get libPaperGrid => '方格';

  @override
  String get libPaperDotted => '点阵';

  @override
  String get libCreate => '创建';

  @override
  String get setSectionGeneral => '常规';

  @override
  String get setSectionInput => '触控笔与输入';

  @override
  String get setSectionSync => '同步';

  @override
  String get setSectionStorage => '存储';

  @override
  String get setSectionShortcuts => '快捷键';

  @override
  String get setSectionAdvanced => '高级';

  @override
  String get setSectionAbout => '关于';

  @override
  String get setBackToLibrary => '笔记库';

  @override
  String get setSettingsTitle => '设置';

  @override
  String get setThemeLabel => '主题';

  @override
  String get setThemeLight => '浅色';

  @override
  String get setThemePaper => '纸张';

  @override
  String get setThemeDark => '深色';

  @override
  String get setLanguage => '语言';

  @override
  String get setLanguageSub => '界面语言';

  @override
  String get setLanguageItalian => '意大利语';

  @override
  String get setFavoritesFirst => '收藏优先';

  @override
  String get setFavoritesFirstSub => '把收藏的笔记本显示在笔记库顶部';

  @override
  String get setStylusOnly => '仅触控笔';

  @override
  String get setStylusOnlySub => '书写时忽略手指触摸。双指捏合和平移仍然可用。';

  @override
  String get setPalmRejection => '防误触';

  @override
  String get setPalmRejectionSub => '自动识别搁在屏幕上的手掌';

  @override
  String get setPressureThickness => '压感 → 粗细';

  @override
  String get setPressureThicknessSub => '根据触控笔压力调节笔画粗细';

  @override
  String get setTiltCalligraphy => '倾斜 → 书法效果';

  @override
  String get setTiltCalligraphySub => '笔的倾斜角度会改变笔画的宽度和角度';

  @override
  String get setStrokeContinuation => '笔画续接';

  @override
  String get setStrokeContinuationSub => '弥补传感器的短暂中断（例如写 i 上面那一点）';

  @override
  String get setSyncConnectedDesc => '已连接到 WebDAV 服务器。笔记本会在你的所有设备之间同步。';

  @override
  String get setSyncLocalOnlyDesc =>
      '仅本地模式：笔记本只保存在这台设备上。连接 WebDAV 服务器即可在多台设备上使用。';

  @override
  String get setSyncWebdav => 'WebDAV';

  @override
  String get setSyncLocalOnly => '仅本地';

  @override
  String setSyncAccountInfo(String host, String username) {
    return '$host · $username';
  }

  @override
  String get setSyncNoServer => '未连接服务器';

  @override
  String get setDisconnect => '断开连接';

  @override
  String get setConnect => '连接';

  @override
  String get setDisconnectTitle => '要断开服务器连接吗？';

  @override
  String get setDisconnectBody => '已下载的笔记本会留在这台设备上。在你重新连接之前，同步会停止。';

  @override
  String get setCheckCert => '验证服务器证书';

  @override
  String get setCertCheckFailed => '无法验证服务器的证书。';

  @override
  String get setCertUnchanged => '自上次连接以来证书没有变化。';

  @override
  String get setCertChangedTitle => '检测到新证书';

  @override
  String setCertChangedBody(String oldFingerprint, String newFingerprint) {
    return '服务器出示的指纹与已保存的不一致。如果证书是你自己更新的，请确认以继续同步。如果不是，请点“取消”，并在重试前检查你的网络。\n\n已保存的指纹：$oldFingerprint\n当前的指纹：$newFingerprint';
  }

  @override
  String get setCertConfirmNew => '确认使用新证书';

  @override
  String get setCancel => '取消';

  @override
  String get setShortcutPen => '钢笔';

  @override
  String get setShortcutUndo => '撤销';

  @override
  String get setShortcutBrush => '画笔';

  @override
  String get setShortcutRedo => '重做';

  @override
  String get setShortcutEraser => '橡皮擦';

  @override
  String get setShortcutSelectAll => '全选';

  @override
  String get setShortcutLasso => '套索';

  @override
  String get setShortcutCopy => '复制';

  @override
  String get setShortcutHand => '抓手';

  @override
  String get setShortcutCut => '剪切';

  @override
  String get setShortcutText => '文本';

  @override
  String get setShortcutPaste => '粘贴';

  @override
  String get setShortcutShape => '形状';

  @override
  String get setShortcutDuplicate => '复制一份';

  @override
  String get setShortcutChangePage => '切换页面';

  @override
  String get setShortcutSave => '保存';

  @override
  String get setShortcutFit => '适应窗口';

  @override
  String get setShortcutCheatSheet => '快捷键速查';

  @override
  String get setKeyboardShortcutsTitle => '键盘快捷键';

  @override
  String get setClearCache => '清理缓存';

  @override
  String get setClearCacheSub => '删除临时文件。不会动到你的笔记本。';

  @override
  String get setClear => '清理';

  @override
  String get setTrash => '回收站';

  @override
  String get setTrashSub => '已删除的笔记本，可以恢复';

  @override
  String get setOpenTrash => '打开回收站';

  @override
  String get setClearCacheDone => '缓存已清理。';

  @override
  String get setExportLibrary => '导出笔记库';

  @override
  String get setExportLibrarySub => '把所有笔记本保存到一个 zip 压缩包中。';

  @override
  String get setExport => '导出';

  @override
  String get setExportLibraryEmpty => '没有可导出的笔记本。';

  @override
  String get setExportLibraryInProgress => '正在导出…';

  @override
  String setExportLibraryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导出 $count 个笔记本',
      one: '已导出 $count 个笔记本',
    );
    return '$_temp0。';
  }

  @override
  String setExportLibraryFailed(String error) {
    return '导出失败：$error';
  }

  @override
  String setTrashPurgeTitle(String title) {
    return '要永久删除“$title”吗？';
  }

  @override
  String get setTrashPurgeBody => '删除后将无法恢复。';

  @override
  String get setTrashPurge => '永久删除';

  @override
  String get setTrashEmptyTitle => '要清空回收站吗？';

  @override
  String get setTrashEmptyBody => '回收站里的所有笔记本都会被永久删除。';

  @override
  String get setTrashEmpty => '清空回收站';

  @override
  String get setTrashEmptyState => '回收站是空的。';

  @override
  String setTrashDeletedAgo(String time) {
    return '$time前删除';
  }

  @override
  String get setTrashRestore => '恢复';

  @override
  String get setAdvancedIntro =>
      '用于笔记本同步卡住这类少见情况的修复工具。只有在笔记库里执行过普通的“强制同步”之后同步仍然失败时才使用。';

  @override
  String get setForceReloadTitle => '强制从服务器重新加载笔记本';

  @override
  String get setForceReloadDesc =>
      '从服务器的 delta 文件夹重新下载整个笔记本内容，并覆盖本地副本。如果页数看起来不对，或者笔记本打不开，可以用它。服务器上的数据不会丢失。';

  @override
  String setErrorGeneric(String error) {
    return '错误：$error';
  }

  @override
  String setPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return '$_temp0';
  }

  @override
  String get setReload => '重新加载';

  @override
  String get setCloseNotebookFirst => '请先关闭笔记本，再从服务器重新加载。';

  @override
  String setReloadConfirmTitle(String title) {
    return '要重新加载“$title”吗？';
  }

  @override
  String get setReloadConfirmBody =>
      '从服务器的 delta 文件夹重新下载元数据、文档、页面和资源。本地副本会被替换。\n\n尚未同步的本地更改会丢失。要继续吗？';

  @override
  String setReloadInProgress(String title) {
    return '正在重新加载“$title”…';
  }

  @override
  String get setNotConnectedWebdav => '未连接到 WebDAV 服务器。';

  @override
  String setReloadDone(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
      one: '$count 页',
    );
    return '“$title”已重新加载 — $_temp0。';
  }

  @override
  String setReloadFailed(String error) {
    return '重新加载失败：$error';
  }

  @override
  String get setAboutTagline => '一款本地优先的手写应用。';

  @override
  String get setAboutOffline => '可离线使用；WebDAV 同步是可选的。';

  @override
  String setAboutVersion(String version, String commit) {
    return '版本 $version · 构建 $commit';
  }

  @override
  String get setReportProblem => '反馈问题';

  @override
  String get setReportProblemSub => '把错误日志复制到剪贴板，方便附在你的反馈里。';

  @override
  String get setCopyLog => '复制日志';

  @override
  String get setReportProblemEmpty => '没有记录到错误。';

  @override
  String get setCopyLogDone => '日志已复制到剪贴板。';

  @override
  String get onbTagline => '手写笔记和自由绘图，同步到你自己的服务器。选择怎么开始 — 之后随时可以改。';

  @override
  String get onbTryNowTitle => '立即试用';

  @override
  String get onbTryNowSubtitle => '现在就开始写。笔记本只留在这台设备上 — 不用账号，也不用服务器。';

  @override
  String get onbConnectNextcloudTitle => '连接你的 Nextcloud';

  @override
  String get onbConnectNextcloudSubtitle =>
      '同步到你自己的 WebDAV / Nextcloud 服务器，在你的所有设备上都能用。';

  @override
  String get onbManagedServerTitle => 'AbelNotes 托管服务器';

  @override
  String get onbManagedServerSubtitle => '没有服务器？很快你就可以用我们的，完全不用配置。';

  @override
  String get onbComingSoonBadge => '即将推出';

  @override
  String get onbDriveTitle => '用 Google Drive 同步';

  @override
  String get onbDriveSubtitle => '无需配置：你的笔记本通过你自己的 Google Drive 同步。';

  @override
  String get driveSignInFailed => 'Google 登录没有完成。没有做任何更改。';

  @override
  String get driveSignInCancelled => '已取消登录。';

  @override
  String get driveNotConfigured => '此构建没有 Google 凭据，因此无法使用 Drive 同步。';

  @override
  String get driveNoKeyring => '此系统没有安全存储，无法妥善保存 Google 账号。这里无法使用 Drive 同步。';

  @override
  String get driveConnectedTitle => '已连接 Google Drive';

  @override
  String get setSyncDriveTitle => 'Google Drive';

  @override
  String get setSyncDriveConnected => '笔记本通过你的 Google Drive 同步。';

  @override
  String get setSyncDriveNotConnected => '未连接。';

  @override
  String get setSyncDriveDesktopOnly => '目前仅在电脑上可用。';

  @override
  String get setDriveDisconnectTitle => '要断开 Google Drive 吗？';

  @override
  String get setDriveDisconnectBody =>
      '已经在你 Drive 里的笔记本会留在那里 — 这个应用只是不再往里面同步。这台设备上的笔记本不受影响。';

  @override
  String get setDriveDisconnectConfirm => '断开连接';

  @override
  String get setSyncOneBackendNote =>
      '笔记本每次只同步到一个地方：你自己的服务器，或者你的 Google Drive。';

  @override
  String get setSyncSwitchTitle => '把同步改到 Google Drive 吗？';

  @override
  String get setSyncSwitchBody =>
      '你的笔记本会留在这台设备上，并上传到你的 Google Drive。已经在你服务器上的副本会保持原样，但从现在起不再收到更新。不会删除任何东西。';

  @override
  String get setSyncSwitchConfirm => '改用 Drive';

  @override
  String get setSyncInactiveNote => '已配置，但未在使用：同步正在发往另一个目标。';

  @override
  String libPendingUploadsDrive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '还有 $count 个笔记本待上传到 Google Drive',
      one: '还有 $count 个笔记本待上传到 Google Drive',
    );
    return '$_temp0';
  }

  @override
  String libPendingUploadsServer(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '还有 $count 个笔记本待上传到你的服务器',
      one: '还有 $count 个笔记本待上传到你的服务器',
    );
    return '$_temp0';
  }

  @override
  String get libPendingUploadsHint => '在此期间它们留在这台设备上。请让应用再开一会儿。';

  @override
  String get libStorageFullDrive => '你的 Google Drive 已满';

  @override
  String get libStorageFullServer => '你的服务器空间不足';

  @override
  String get libStorageFullBody =>
      '笔记本在这台设备上是安全的，但在你腾出空间之前无法上传。Google Drive 的空间与 Gmail 和相册共用。';

  @override
  String get libStorageFullBodyServer => '笔记本在这台设备上是安全的，但在服务器腾出空间之前无法上传。';

  @override
  String get libLocalOnlyTitle => '仅这台设备';

  @override
  String get libLocalOnlyBody =>
      '你的笔记本只留在这台设备上。连接你的服务器或 Google Drive，就能在任何地方使用 — 随时都可以连。';

  @override
  String get libKeepOnDevice => '只保留在这台设备上';

  @override
  String get libResumeSync => '重新同步这个笔记本';

  @override
  String get libLocalOnlyBadge => '仅这台设备';

  @override
  String get libKeepOnDeviceTitle => '把这个笔记本只保留在这台设备上吗？';

  @override
  String get libKeepOnDeviceBody => '它将不再上传，其他设备也不会再收到它。在这里它仍然完全可用。';

  @override
  String get libKeepOnDeviceRemoveCopy => '同时删除已经上传的副本';

  @override
  String get libKeepOnDeviceConfirm => '只留在这里';

  @override
  String get libLocalOnlyDone => '已只保留在这台设备上。';

  @override
  String get libSyncResumedDone => '这个笔记本会重新开始同步。';

  @override
  String get syncLocalOnlyTooltip => '只保留在这台设备上';

  @override
  String get libFreeSpace => '释放这台设备上的空间';

  @override
  String get libKeepOnThisDevice => '下载到这台设备';

  @override
  String get libFreeSpaceTitle => '要把这个笔记本从这台设备上移除吗？';

  @override
  String get libFreeSpaceBody =>
      '笔记本仍然保留在远端和你的其他设备上。在这里它会变成一张卡片，点一下就能重新下载。在那之前它无法离线打开，搜索也不会查它的内容。';

  @override
  String get libFreeSpaceConfirm => '释放空间';

  @override
  String libFreeSpaceDone(String size) {
    return '已从这台设备移除。释放了 $size。';
  }

  @override
  String get libFreeSpaceNotSynced => '这个笔记本有远端还没有的更改。等这些更改上传完就可以了。';

  @override
  String get libFreeSpaceOpenNotebook => '请先关闭笔记本。';

  @override
  String get libKeepOnThisDeviceDone => '它会重新下载到这台设备。';

  @override
  String get syncNotOnDeviceTooltip => '在远端，不在这台设备上';

  @override
  String get onbSyncQuestion => '同步你的笔记';

  @override
  String get onbSyncQuestionSub => '选择你的笔记本存放在哪里。之后可以更改。';

  @override
  String get onbDriveShort => 'Google Drive';

  @override
  String get onbNextcloudShort => 'Nextcloud / WebDAV';

  @override
  String get onbStartWithoutSync => '先不同步，直接开始';

  @override
  String get onbDriveUnavailable => '此构建中不可用';

  @override
  String get onbLicenseNote => '打开本应用即表示你接受 AGPL-3.0 许可证。“AbelNotes”是本项目的商标。';

  @override
  String get logConnectionFailed => '无法连接。请检查网址、用户名和密码。';

  @override
  String logConnectionError(String error) {
    return '连接出错：$error';
  }

  @override
  String get logCertificateChanged =>
      '服务器证书自上次连接以来发生了变化。如果是你自己改的（例如更新证书），请到“设置 > 同步”确认新的指纹。';

  @override
  String get logCertConfirmTitle => '验证服务器身份';

  @override
  String get logCertConfirmBody =>
      '这是第一次连接此服务器。在继续之前，请把这个指纹与你服务器上的（例如通过命令行获取）进行比对：';

  @override
  String get logCertConfirmTrust => '我信任它，继续';

  @override
  String get logBackTooltip => '返回';

  @override
  String get logTitle => '连接你的 Nextcloud';

  @override
  String get logSubtitle => '任何 WebDAV / Nextcloud 服务器（VPS、自建、局域网）。不经过第三方云。';

  @override
  String get logServerUrlLabel => '服务器网址';

  @override
  String get logServerUrlHint => 'https://cloud.example.com';

  @override
  String get logServerUrlRequired => '请输入服务器网址';

  @override
  String get logServerUrlInvalid => '必须以 http:// 或 https:// 开头';

  @override
  String get logUsernameLabel => '用户名';

  @override
  String get logUsernameRequired => '请填写用户名';

  @override
  String get logPasswordLabel => '密码 / 应用密码';

  @override
  String get logPasswordRequired => '请填写密码';

  @override
  String get logAppPasswordHint => '建议使用在 Nextcloud 设置中生成的应用密码。';

  @override
  String get logServerTypeNextcloud => 'Nextcloud / ownCloud';

  @override
  String get logServerTypeWebdav => '其他 WebDAV';

  @override
  String get logServerUrlHintWebdav => 'https://dav.example.com/folder';

  @override
  String get logWebdavExperimental =>
      '通用 WebDAV 后端（Synology、Seafile、rclone…）尚属实验性：只有 Nextcloud 经过完整测试。请为你的笔记本保留备份。';

  @override
  String get logWebdavUrlHint =>
      '完整的 WebDAV 网址，含路径 — 例如 Synology https://nas:5006/home、Seafile https://server/seafdav。通用 WebDAV 不支持链接分享。';

  @override
  String get logConnectButton => '连接';

  @override
  String get chromeBackToLibraryTooltip => '返回笔记库';

  @override
  String get chromeLibrary => '笔记库';

  @override
  String get chromeUnsaved => '未保存';

  @override
  String get chromeMouseDrawsTooltip => '鼠标：绘图 — 点一下改为用于选择';

  @override
  String get chromeMouseSelectsTooltip => '鼠标：选择 — 点一下改为用鼠标绘图';

  @override
  String get chromeTouchDrawsTooltip => '手指：绘图 — 点一下改为用于平移';

  @override
  String get chromeTouchPansTooltip => '手指：平移 — 点一下改为用手指绘图';

  @override
  String get chromeUndo => '撤销';

  @override
  String get chromeRedo => '重做';

  @override
  String get chromeAllPages => '全部页面';

  @override
  String chromePageIndicator(String current, int total) {
    return '$current / $total';
  }

  @override
  String get chromeAddPage => '添加页面';

  @override
  String get chromeSymbols => '符号';

  @override
  String get chromeExport => '导出';

  @override
  String get chromeMore => '更多';

  @override
  String get chromeMoreEllipsis => '更多…';

  @override
  String get chromeToolPen => '钢笔 · P';

  @override
  String get chromeToolHighlighter => '荧光笔';

  @override
  String get chromeToolEraser => '橡皮擦 · E';

  @override
  String get chromeToolLasso => '套索 · L';

  @override
  String get chromeToolText => '文本 · T';

  @override
  String get chromeToolLaser => '激光笔';

  @override
  String get chromeToolPan => '抓手 · H';

  @override
  String get chromeDragToMoveBar => '拖动可移动工具栏';

  @override
  String get chromeShapeGuessOn => '自动识别形状 · 开';

  @override
  String get chromeShapeGuessOff => '自动识别形状 · 关';

  @override
  String get chromeLabelPen => '钢笔';

  @override
  String get chromeLabelBallpoint => '圆珠笔';

  @override
  String get chromeLabelBrush => '画笔';

  @override
  String get chromeLabelCalligraphy => '书法笔';

  @override
  String get chromeLabelEraser => '橡皮擦';

  @override
  String get chromeLabelLasso => '套索';

  @override
  String get chromeLabelText => '文本';

  @override
  String get chromeLabelShape => '形状';

  @override
  String get chromeLabelImage => '图片';

  @override
  String get chromeLabelPan => '抓手';

  @override
  String get chromePresetsSection => '预设';

  @override
  String get chromePresetHint => '长按可保存/清除';

  @override
  String get chromeColorSection => '颜色';

  @override
  String get chromeColorEditHint => '长按某个颜色即可更改';

  @override
  String get chromeThicknessSection => '粗细';

  @override
  String chromeThicknessPx(String value) {
    return '$value px';
  }

  @override
  String get chromePreview => '预览';

  @override
  String get chromeModeSection => '模式';

  @override
  String get chromeEraserPerArea => '按区域';

  @override
  String get chromeEraserPerStroke => '按笔画';

  @override
  String get chromeSizeSection => '大小';

  @override
  String get chromeSizeSmall => '小';

  @override
  String get chromeSizeMedium => '中';

  @override
  String get chromeSizeLarge => '大';

  @override
  String get chromePresetOverwrite => '用当前设置覆盖';

  @override
  String get chromePresetClearSlot => '清除此位置';

  @override
  String get chromeNoPages => '没有页面';

  @override
  String get chromeHidePageBar => '隐藏页面栏';

  @override
  String get chromeShowPageBar => '显示页面栏';

  @override
  String chromePrevPageTooltip(int number) {
    return '上一页 第 $number 页 — 点一下返回';
  }

  @override
  String chromePageOfChapterTooltip(int number, int globalNumber) {
    return '本章第 $number 页 · 笔记本第 $globalNumber 页';
  }

  @override
  String chromePageTooltip(int number) {
    return '第 $number 页';
  }

  @override
  String get chromeHexLabel => '十六进制';

  @override
  String get chromeCancel => '取消';

  @override
  String get chromeApply => '应用';

  @override
  String get pmNone => '无';

  @override
  String get pmCreateChapterFirst => '请先创建至少一个章节。';

  @override
  String pmAssignChapterCount(int count) {
    return '指定章节（$count 页）';
  }

  @override
  String pmDeletePagesConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '要删除 $count 页吗？',
      one: '要删除 1 页吗？',
    );
    return '$_temp0';
  }

  @override
  String get pmActionCannotBeUndone => '此操作无法撤销。';

  @override
  String get pmCancel => '取消';

  @override
  String get pmDelete => '删除';

  @override
  String pmPagesCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已剪切 $count 页 — 打开目标笔记本即可粘贴。',
      one: '已剪切 1 页 — 打开目标笔记本即可粘贴。',
    );
    return '$_temp0';
  }

  @override
  String pmPagesCutSkipped(int count, int skipped) {
    return '已剪切 $count 页（$skipped 页尚未加载，已跳过）— 打开目标笔记本即可粘贴。';
  }

  @override
  String pmSelectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get pmSelectAllButton => '全部';

  @override
  String get pmClearSelection => '清除选择';

  @override
  String pmPagesCount(int count) {
    return '页面（$count）';
  }

  @override
  String pmPagesFilteredCount(int visible, int total) {
    return '页面（$visible/$total）';
  }

  @override
  String get pmGoToPageTooltip => '跳转到页面…';

  @override
  String get pmExitSelection => '退出选择';

  @override
  String get pmSelectPages => '选择页面';

  @override
  String get pmPastePages => '粘贴页面';

  @override
  String pmPagesPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已粘贴 $count 页。',
      one: '已粘贴 1 页。',
    );
    return '$_temp0';
  }

  @override
  String get pmAddPage => '添加页面';

  @override
  String get pmClose => '关闭';

  @override
  String get pmNewChapter => '新建章节';

  @override
  String get pmChapterNameHint => '章节名称';

  @override
  String pmPageDeleted(int number) {
    return '已删除第 $number 页';
  }

  @override
  String get pmUndo => '撤销';

  @override
  String get pmAssignChapter => '指定章节';

  @override
  String get pmRename => '重命名';

  @override
  String get pmRenameChapter => '重命名章节';

  @override
  String get pmDeleteChapter => '删除章节';

  @override
  String pmDeleteChapterConfirm(String title) {
    return '要删除“$title”吗？其中的页面会保留，但不再属于任何章节。';
  }

  @override
  String get pmGoToPage => '跳转到页面';

  @override
  String pmPageRangeHint(int max) {
    return '1–$max';
  }

  @override
  String get pmGo => '前往';

  @override
  String get pmOk => '好';

  @override
  String pmCountPagesShort(int count) {
    return '$count 页';
  }

  @override
  String get pmChapter => '章节';

  @override
  String get pmCut => '剪切';

  @override
  String get pmInsertBefore => '在前面插入';

  @override
  String get pmInsertAfter => '在后面插入';

  @override
  String get pmDuplicate => '复制一份';

  @override
  String get pmMoveTo => '移动到页面…';

  @override
  String get pmMove => '移动';

  @override
  String get pmMoveToPage => '移动到页面';

  @override
  String get pmChapterEllipsis => '章节…';

  @override
  String pmPageChapterLabel(int number, String chapter) {
    return '$number • $chapter';
  }

  @override
  String get pmCorruptAssetTooltip => '服务器上的资源已损坏（被截断）— 重新导入原始 PDF 即可恢复';

  @override
  String get pmLoadingImageTooltip => '正在从服务器加载图片…';

  @override
  String get tedInsertTextTitle => '插入文本';

  @override
  String get tedEditTextTitle => '编辑文本';

  @override
  String get tedBoldTooltip => '粗体（Ctrl+B）';

  @override
  String get tedItalicTooltip => '斜体（Ctrl+I）';

  @override
  String get tedUnderlineTooltip => '下划线（Ctrl+U）';

  @override
  String get tedStrikethroughTooltip => '删除线';

  @override
  String get tedAlignLeft => '左对齐';

  @override
  String get tedAlignCenter => '居中';

  @override
  String get tedAlignRight => '右对齐';

  @override
  String get tedWriteHereHint => '在这里输入…';

  @override
  String get tedCancel => '取消';

  @override
  String get tedInsert => '插入';

  @override
  String get cropTitle => '裁剪图片';

  @override
  String get cropCancel => '取消';

  @override
  String get cropConfirm => '裁剪';

  @override
  String get imgFontSmaller => '缩小文字';

  @override
  String get imgFontLarger => '放大文字';

  @override
  String get imgCrop => '裁剪';

  @override
  String get imgCopy => '复制';

  @override
  String get imgUnlock => '解锁';

  @override
  String get imgLock => '锁定';

  @override
  String get imgDelete => '删除';

  @override
  String get imgDeselect => '取消选择';

  @override
  String get imgMoreActions => '更多操作';

  @override
  String get imgBringToFront => '移到最前';

  @override
  String get imgSendToBack => '移到最后';

  @override
  String get imgComment => '备注';

  @override
  String get imgFlipHChecked => '水平翻转 ✓';

  @override
  String get imgFlipH => '水平翻转';

  @override
  String get imgCut => '剪切';

  @override
  String get syncOkTooltip => '已同步';

  @override
  String get syncPendingTooltip => '正在同步…';

  @override
  String get syncOfflineTooltip => '离线';

  @override
  String get syncConflictTooltip => '冲突';

  @override
  String get confDecideLater => '稍后再决定';

  @override
  String confTitlePageDeletedElsewhere(int pageNumber) {
    return '第 $pageNumber 页已在别处被删除';
  }

  @override
  String confTitleConflictPage(int pageNumber) {
    return '冲突 — 第 $pageNumber 页';
  }

  @override
  String get confDeletionExplainer => '你编辑了这一页，但另一台设备把它删除了。你想保留还是删除？';

  @override
  String get confKeepPage => '保留这一页';

  @override
  String get confLocalYours => '本地（你的）';

  @override
  String get confRemoteOtherDevice => '远端（其他设备）';

  @override
  String get confKeepAllLocal => '全部保留本地版本';

  @override
  String get confAcceptAllRemote => '全部采用远端版本';

  @override
  String confProgressIndicator(int current, int total, num decided) {
    String _temp0 = intl.Intl.pluralLogic(
      decided,
      locale: localeName,
      other: '已决定 $decided 项',
      one: '已决定 $decided 项',
    );
    return '$current / $total  （$_temp0）';
  }

  @override
  String get confApplyChoices => '应用这些选择';

  @override
  String confDecidedProgress(int decided, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '项',
      one: '项',
    );
    return '已决定 $decided/$total $_temp0';
  }

  @override
  String get confJumpToConflict => '跳到冲突处';

  @override
  String confJumpDecidedCount(int decided, int total) {
    return '已决定 $decided/$total';
  }

  @override
  String confJumpItemPage(int pageNumber) {
    return '第 $pageNumber 页';
  }

  @override
  String confJumpItemPageWithChapter(int pageNumber, String chapterName) {
    return '第 $pageNumber 页 — $chapterName';
  }

  @override
  String get confDismissDialogTitle => '要取消吗？';

  @override
  String get confDismissDialogBody => '未应用的选择会丢失。将保留本地版本。';

  @override
  String get confContinue => '继续';

  @override
  String get confCancel => '取消';

  @override
  String get confModifiedJustNow => '刚刚';

  @override
  String confModifiedMinutesAgo(int minutes) {
    return '$minutes 分钟前';
  }

  @override
  String confModifiedHoursAgo(num hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours 小时前',
      one: '$hours 小时前',
    );
    return '$_temp0';
  }

  @override
  String get confDeletePage => '删除这一页';

  @override
  String get confAsOnOtherDevice => '与另一台设备一致';

  @override
  String get symNewLibraryTitle => '新建库';

  @override
  String get symNewLibraryHint => '请输入库的名称';

  @override
  String get symRenameLibraryTitle => '重命名库';

  @override
  String get symNewNameHint => '新名称';

  @override
  String get symDeleteLibraryTitle => '删除库';

  @override
  String symDeleteLibraryConfirm(String name) {
    return '要删除“$name”及其中的所有符号吗？';
  }

  @override
  String get symCancel => '取消';

  @override
  String get symDelete => '删除';

  @override
  String get symRenameSymbolTitle => '重命名符号';

  @override
  String get symPanelTitle => '符号库';

  @override
  String get symNoLibraries => '还没有库';

  @override
  String get symNew => '新建';

  @override
  String get symSelectLibrary => '选择一个库';

  @override
  String get symNoSymbolsHint => '还没有符号\n用套索选中元素，然后按 ✚';

  @override
  String get symLassoSaveHint => '用套索选中元素 → 按 ✚ 保存到当前库';

  @override
  String get symRename => '重命名';

  @override
  String get symInsert => '插入';

  @override
  String get symOk => '好';

  @override
  String get rcbBannerTitle => '来自另一台设备的更改';

  @override
  String get rcbSeeDetails => '查看详情';

  @override
  String get rcbDismiss => '忽略';

  @override
  String get rcbIncomingChanges => '收到的更改';

  @override
  String get rcbTapPageHint => '点击某一页即可应用并跳转过去';

  @override
  String rcbNewImagesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 张新图片',
      one: '1 张新图片',
    );
    return '$_temp0';
  }

  @override
  String get rcbKeepMine => '保留我的';

  @override
  String get rcbApplyAll => '全部应用';

  @override
  String get rcbBadgeNew => '新增';

  @override
  String get rcbBadgeModified => '已修改';

  @override
  String rcbPageTitle(int pageNumber) {
    return '第 $pageNumber 页';
  }

  @override
  String get rcbContentUpdated => '内容已更新';

  @override
  String rcbSummaryModifiedPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页已修改',
      one: '$count 页已修改',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryNewPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '新增 $count 页',
      one: '新增 $count 页',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryImages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 张图片',
      one: '$count 张图片',
    );
    return '$_temp0';
  }

  @override
  String get rcbChangesDetected => '检测到更改';

  @override
  String get nbUntitled => '未命名';

  @override
  String get nbDefaultChapterTitle => '第 1 章';

  @override
  String get nbOpeningNotebook => '正在打开笔记本…';

  @override
  String get nbNoLocalCopyOffline => '本机没有这个笔记本的副本，而你也没有连接服务器来下载它。';

  @override
  String nbOpenFailed(String error) {
    return '无法打开：$error';
  }

  @override
  String get nbSortModifiedDesc => '修改时间（最新在前）';

  @override
  String get nbSortModifiedAsc => '修改时间（最早在前）';

  @override
  String get nbSortTitleAsc => '标题 A→Z';

  @override
  String get nbSortTitleDesc => '标题 Z→A';

  @override
  String get nbSortCreatedDesc => '创建时间（最新在前）';

  @override
  String get nbSortCreatedAsc => '创建时间（最早在前）';

  @override
  String get nbSortColorGroup => '封面颜色';

  @override
  String cvFormatTooNew(int fileVersion, int supportedVersion) {
    return '这个笔记本使用了更新的格式（v$fileVersion，当前支持：v$supportedVersion）。请升级 AbelNotes 后再打开。';
  }

  @override
  String get setLanguageSystem => '跟随系统';

  @override
  String get setLanguageEnglish => 'English';

  @override
  String get setLanguageSpanish => 'Español';

  @override
  String get onbAppName => 'AbelNotes';

  @override
  String get setAboutAppName => 'AbelNotes';

  @override
  String get chromeLabelHighlighter => '荧光笔';

  @override
  String get chromeLabelLaser => '激光笔';

  @override
  String get importSourceTitle => '导入到笔记库';

  @override
  String get importSourceNcnote => '.abelnote 笔记本';

  @override
  String get importSourceObsidian => 'Obsidian 仓库';

  @override
  String get importSourceObsidianHint => '存放 Markdown 文件的文件夹';

  @override
  String get importSourceNotion => 'Notion 导出文件';

  @override
  String get importSourceNotionHint => '.zip 文件（Markdown 和 CSV）';

  @override
  String get importPhaseScanning => '正在扫描来源…';

  @override
  String importPhaseParsing(int current, int total) {
    return '正在读取第 $current 个文件，共 $total 个';
  }

  @override
  String importPhasePaginating(int current, int total) {
    return '正在排版第 $current 章，共 $total 章';
  }

  @override
  String get importPhasePackaging => '正在创建笔记本…';

  @override
  String get importCancel => '取消';

  @override
  String get importCancelled => '已取消导入';

  @override
  String importReportTitle(int count) {
    return '导入时有 $count 条警告';
  }

  @override
  String get importReportCopy => '复制';

  @override
  String get importReportClose => '关闭';

  @override
  String get importSourceOneNote => 'OneNote 文件';

  @override
  String get importSourceOneNoteHint => '.one 分区或 .onetoc2 笔记本';

  @override
  String get setOpenSourceLicenses => '开源许可';

  @override
  String get setOpenSourceLicensesSub => '随应用一起分发的第三方组件';

  @override
  String get csBackToContent => '返回内容';

  @override
  String get setLanguageGerman => 'Deutsch';

  @override
  String get setLanguageFrench => 'Français';

  @override
  String get setLanguagePortuguese => 'Português';

  @override
  String get setLanguageChinese => '中文';
}
