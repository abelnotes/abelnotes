// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get csPdfTextCopied => 'Text copied';

  @override
  String csCopyFailed(String error) {
    return 'Copy failed: $error';
  }

  @override
  String get csCopy => 'Copy';

  @override
  String get csSyncInProgress => 'Sync in progress…';

  @override
  String get csSaved => 'Saved!';

  @override
  String csErrorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String get csSelectionCopied => 'Selection copied';

  @override
  String get csSelectionCut => 'Selection cut';

  @override
  String get csShortcutsTitle => 'Keyboard shortcuts';

  @override
  String get csShortcutGroupGeneral => 'General';

  @override
  String get csSaveNow => 'Save now';

  @override
  String get csShortcutUndo => 'Undo';

  @override
  String get csShortcutRedo => 'Redo';

  @override
  String get csSelectAll => 'Select all';

  @override
  String get csShortcutResetZoom => 'Reset zoom';

  @override
  String get csShortcutDeselect => 'Deselect / cancel';

  @override
  String get csShortcutThisGuide => 'This guide';

  @override
  String get csShortcutGroupClipboard => 'Clipboard';

  @override
  String get csShortcutCopySelection => 'Copy selection';

  @override
  String get csShortcutCutSelection => 'Cut selection';

  @override
  String get csPaste => 'Paste';

  @override
  String get csShortcutDuplicateSelection => 'Duplicate selection';

  @override
  String get csShortcutKeyDeleteBackspace => 'Del / Backspace';

  @override
  String get csShortcutDeleteElementOrSelection =>
      'Delete element or selection';

  @override
  String get csShortcutGroupTools => 'Tools';

  @override
  String get csToolPen => 'Pen';

  @override
  String get csToolBrush => 'Brush';

  @override
  String get csToolEraser => 'Eraser';

  @override
  String get csToolLasso => 'Lasso';

  @override
  String get csToolHand => 'Hand / move';

  @override
  String get csToolText => 'Text';

  @override
  String get csToolShape => 'Shape';

  @override
  String get csClose => 'Close';

  @override
  String get csUnsavedChangesTitle => 'Unsaved changes';

  @override
  String get csUnsavedChangesBody => 'Do you want to save before leaving?';

  @override
  String get csDiscard => 'Discard';

  @override
  String get csCancel => 'Cancel';

  @override
  String get csSave => 'Save';

  @override
  String get csOpeningLink => 'Opening link…';

  @override
  String get csCannotOpenLink => 'Unable to open the link';

  @override
  String get csCameraUnavailable => 'Camera not available on this device';

  @override
  String get csPhotoCaptureFailed => 'Unable to take the photo';

  @override
  String get csPdfRasterizing => 'Rasterizing PDF…';

  @override
  String csPdfImportProgress(int done, int total) {
    return 'Importing PDF: $done/$total';
  }

  @override
  String get csPdfReadFailed => 'Unable to read the PDF: no pages found';

  @override
  String csPdfImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'PDF imported: $_temp0';
  }

  @override
  String csPdfImportError(String error) {
    return 'PDF import error: $error';
  }

  @override
  String get csNoNotebookOpen => 'No notebook open';

  @override
  String get csMissingPageDataTitle => 'Missing page data';

  @override
  String get csNoPages => 'No pages';

  @override
  String csMissingPagesBodyMany(int count) {
    return 'This page and $count others were not retrieved from the server. The files may have been lost during a partial sync.';
  }

  @override
  String get csMissingPageBodyOne =>
      'This page\'s file was not retrieved from the server. It may have been lost during a partial sync.';

  @override
  String get csRetrySync => 'Retry sync';

  @override
  String get csRestoreAsBlankPage => 'Restore as blank page';

  @override
  String csRestoreAllMissing(int count) {
    return 'Restore all ($count)';
  }

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages restored as blank',
      one: '$count page restored as blank',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'Delete page';

  @override
  String csSyncProgressCount(int done, int total) {
    return 'Syncing $done/$total';
  }

  @override
  String get csSyncing => 'Syncing…';

  @override
  String csShapeRecognizedLabel(String shape) {
    return 'Shape: $shape';
  }

  @override
  String get csConfirmShapeSemantics => 'Confirm recognized shape';

  @override
  String get csConfirm => 'Confirm';

  @override
  String get csCancelShapeSemantics => 'Cancel recognized shape';

  @override
  String csTapToPlaceSymbol(String name) {
    return 'Tap to place: $name';
  }

  @override
  String get csCancelSymbolInsertSemantics => 'Cancel symbol insertion';

  @override
  String get csTapToPlaceCopy => 'Tap to place the copy';

  @override
  String get csCancelPasteSemantics => 'Cancel paste';

  @override
  String get csNewPage => 'New page';

  @override
  String get csImageCopied => 'Image copied';

  @override
  String get csImageCut => 'Image cut';

  @override
  String get csImageCommentTitle => 'Image comment';

  @override
  String get csAddCommentHint => 'Add a comment...';

  @override
  String get csRemove => 'Remove';

  @override
  String get csCut => 'Cut';

  @override
  String get csDuplicate => 'Duplicate';

  @override
  String get csSelectionDuplicated => 'Selection duplicated';

  @override
  String get csChangeColor => 'Change color';

  @override
  String get csThickness => 'Thickness';

  @override
  String get csDelete => 'Delete';

  @override
  String get csMore => 'More';

  @override
  String get csPresentationMode => 'Presentation mode';

  @override
  String get csPresentationModeSub =>
      'Fullscreen, no tools — great for showing pages';

  @override
  String get csRecognizeHandwriting => 'Recognize handwriting';

  @override
  String get csRecognizeHandwritingSub =>
      'Turns ink into searchable text (on-device)';

  @override
  String get csRecognizeInProgress => 'Recognizing…';

  @override
  String get csRecognizeNothing => 'No text recognized.';

  @override
  String csRecognizeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines recognized',
      one: '$count line recognized',
    );
    return '$_temp0.';
  }

  @override
  String csRecognizeFailed(String error) {
    return 'Recognition failed: $error';
  }

  @override
  String get csShareLink => 'Share via link';

  @override
  String get csShareLinkSub =>
      'Uploads a PDF to your Nextcloud and creates a public link';

  @override
  String get csShareLinkInProgress => 'Creating link…';

  @override
  String get csShareLinkTitle => 'Public link';

  @override
  String get csShareLinkBody =>
      'Anyone with this link can view the PDF. Revocable from your Nextcloud.';

  @override
  String get csShareLinkCopied => 'Link copied to clipboard.';

  @override
  String csShareLinkFailed(String error) {
    return 'Sharing failed: $error';
  }

  @override
  String get csCopyLink => 'Copy link';

  @override
  String get csShare => 'Share';

  @override
  String get csRevokeLink => 'Revoke link';

  @override
  String get csRevokeLinkDone => 'Link revoked.';

  @override
  String get csShareLinkUpdate => 'Update shared PDF';

  @override
  String get csShareLinkUpdated => 'PDF updated.';

  @override
  String get csChangeSelectionColor => 'Change selection color';

  @override
  String get csSelectionThickness => 'Selection thickness';

  @override
  String csWidthPx(String width) {
    return '$width px';
  }

  @override
  String get csFlipHorizontal => 'Flip horizontally';

  @override
  String get csFlipVertical => 'Flip vertically';

  @override
  String get csCopyAsImage => 'Copy as image';

  @override
  String get csPasteInAnotherNotebook => 'Paste into another notebook…';

  @override
  String get csKeyDelete => 'Del';

  @override
  String get csCreateSymbol => 'Create symbol';

  @override
  String get csSelect => 'Select';

  @override
  String get csImportFile => 'Import file…';

  @override
  String get csTakePhoto => 'Take photo';

  @override
  String get csInsertText => 'Insert text';

  @override
  String csInsertSymbolCount(int count) {
    return 'Insert symbol ($count)';
  }

  @override
  String get csClearPage => 'Clear page';

  @override
  String get csExportPng => 'Export PNG';

  @override
  String get csExportPdf => 'Export PDF';

  @override
  String get csClearPageConfirmBody =>
      'All elements on this page will be deleted. Continue?';

  @override
  String get csClear => 'Clear';

  @override
  String get csCreateSymbolTitle => 'Create reusable symbol';

  @override
  String get csSymbolNameLabel => 'Symbol name';

  @override
  String get csLibraryLabel => 'Library:';

  @override
  String get csNoLibraryNotice =>
      'No existing library. A \"Symbols\" library will be created.';

  @override
  String get csCreate => 'Create';

  @override
  String csSymbolCreated(String name) {
    return 'Symbol \"$name\" created!';
  }

  @override
  String csSaveFileDialogTitle(String fileName) {
    return 'Save $fileName';
  }

  @override
  String get csExportCurrentPagePng => 'Current page (PNG)';

  @override
  String get csExportCurrentChapter => 'Current chapter';

  @override
  String get csExportEntireNotebook => 'Entire notebook';

  @override
  String csExportingPages(int count) {
    return 'Exporting $count pages...';
  }

  @override
  String csChooseFolderForImages(int count) {
    return 'Choose a folder for the $count images';
  }

  @override
  String csPngExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'PNG exported ($_temp0)';
  }

  @override
  String csExportError(String error) {
    return 'Export error: $error';
  }

  @override
  String get csExportCurrentPage => 'Current page';

  @override
  String csGeneratingPdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'Generating PDF ($_temp0)...';
  }

  @override
  String csPdfExportError(String error) {
    return 'PDF export error: $error';
  }

  @override
  String csPdfExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'PDF exported: $_temp0';
  }

  @override
  String get csChapterSeparatorEyebrow => 'CHAPTER';

  @override
  String get csSelectionCopiedAsImage => 'Selection copied as image';

  @override
  String csCopyImageError(String error) {
    return 'Image copy error: $error';
  }

  @override
  String get csExport => 'Export';

  @override
  String csPageNumber(int number) {
    return 'Page $number';
  }

  @override
  String csPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return '$_temp0';
  }

  @override
  String get csExportChapterTitle => 'Export chapter';

  @override
  String get csExportNotebookTitle => 'Export entire notebook';

  @override
  String get csChapterSeparatorQuestion =>
      'Insert a separator page before each chapter?';

  @override
  String get csYesWithSeparators => 'Yes, with separators';

  @override
  String get csNoPagesOnly => 'No, pages only';

  @override
  String csTotalPages(int count) {
    return 'Total pages: $count';
  }

  @override
  String csFromPage(int page) {
    return 'From page: $page';
  }

  @override
  String csToPage(int page) {
    return 'To page: $page';
  }

  @override
  String csWillExportPages(int count, int start, int end) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages will be exported ($start–$end)',
      one: '$count page will be exported ($start–$end)',
    );
    return '$_temp0';
  }

  @override
  String csChapterLabelWithCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return '$title ($_temp0)';
  }

  @override
  String get csGoToPage => 'Go to page';

  @override
  String get csDuplicatePage => 'Duplicate page';

  @override
  String get csNewPageAfter => 'New page after';

  @override
  String get csDeletePageConfirmTitle => 'Delete the page?';

  @override
  String csDeletePageConfirmBody(int number) {
    return 'Page $number and all its content will be deleted.';
  }

  @override
  String get csExportAsPdf => 'Export as PDF';

  @override
  String get csExportAsPng => 'Export as PNG';

  @override
  String get csExportAsNcnote => 'Export as .ncnote (native)';

  @override
  String get csExportNcnoteSubtitle =>
      'Native format, full vector quality (for backup or transfer)';

  @override
  String get csGeneratingNcnote => 'Generating .ncnote…';

  @override
  String csNcnoteExported(String size) {
    return '.ncnote exported ($size KB)';
  }

  @override
  String csNcnoteExportError(String error) {
    return '.ncnote export error: $error';
  }

  @override
  String get csImageOrPdf => 'Image or PDF';

  @override
  String get csChangePaperType => 'Change paper type';

  @override
  String get csPenToMonitor => 'Pen → Monitor';

  @override
  String get csPenToMonitorSubtitle => 'Restrict the pen to a single screen';

  @override
  String get csPaperType => 'Paper type';

  @override
  String get csPaperBlank => 'Blank';

  @override
  String get csPaperLinedNarrow => 'Narrow lines';

  @override
  String get csPaperLinedWide => 'Wide lines';

  @override
  String get csPaperGrid => 'Grid';

  @override
  String get csPaperDotted => 'Dotted';

  @override
  String get csPaperCornell => 'Cornell';

  @override
  String get csPaperIsometric => 'Isometric';

  @override
  String get csPaperMusic => 'Music staff';

  @override
  String get csMapPenToMonitor => 'Map pen to a monitor';

  @override
  String csPenMappedTo(String monitor) {
    return 'Pen mapped to $monitor';
  }

  @override
  String get csAllMonitors => 'All monitors';

  @override
  String get csAllMonitorsSubtitle => 'Reset (pen across the whole desktop)';

  @override
  String get csPenReset => 'Pen reset';

  @override
  String get csShapeLine => 'Line';

  @override
  String get csShapeCircle => 'Circle';

  @override
  String get csShapeRectangle => 'Rectangle';

  @override
  String get csShapeTriangle => 'Triangle';

  @override
  String get csShapeArrow => 'Arrow';

  @override
  String get csInvalidRangeError => 'Enter a valid range (e.g. 1–10).';

  @override
  String csPdfStartOutOfRange(int count) {
    return 'The PDF has about $count pages. Start is out of range.';
  }

  @override
  String get csImportPdfTitle => 'Import PDF';

  @override
  String csPdfEstimatedPages(int count) {
    return 'The PDF has about $count pages.';
  }

  @override
  String csAllPagesWithCount(int count) {
    return 'All pages ($count)';
  }

  @override
  String get csAllPages => 'All pages';

  @override
  String get csCustomRange => 'Custom range';

  @override
  String get csFromLabel => 'From';

  @override
  String get csToLabel => 'To';

  @override
  String get csImport => 'Import';

  @override
  String libErrorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String libErrorOpen(String error) {
    return 'Error opening: $error';
  }

  @override
  String get libImportCannotReadFile => 'Unable to read the file';

  @override
  String get libImportInProgress => 'Importing…';

  @override
  String get libServiceUnavailable => 'Service unavailable';

  @override
  String libImportedTitleSuffix(String title) {
    return '$title (imported)';
  }

  @override
  String libImportSuccess(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'Imported: \"$title\" ($_temp0)';
  }

  @override
  String libErrorImport(String error) {
    return 'Import error: $error';
  }

  @override
  String libErrorCreate(String error) {
    return 'Error creating: $error';
  }

  @override
  String get libSketchDefaultTitle => 'Sketch';

  @override
  String libErrorCreateSketch(String error) {
    return 'Error creating sketch: $error';
  }

  @override
  String get libRemoveFromFavorites => 'Remove from favorites';

  @override
  String get libAddToFavorites => 'Add to favorites';

  @override
  String get libRename => 'Rename';

  @override
  String get libChangeCover => 'Change cover';

  @override
  String get libMoveToFolder => 'Move to folder';

  @override
  String get libNoFolder => 'No folder';

  @override
  String get libNewFolder => 'New folder';

  @override
  String get libRenameFolder => 'Rename folder';

  @override
  String get libFolderNameHint => 'Folder name';

  @override
  String get libAllNotebooks => 'All';

  @override
  String get libDeleteFolder => 'Delete folder';

  @override
  String libDeleteFolderTitle(String name) {
    return 'Delete folder \"$name\"?';
  }

  @override
  String get libDeleteFolderBody =>
      'Notebooks inside it aren\'t deleted — they stay in the library with no folder.';

  @override
  String get libDelete => 'Delete';

  @override
  String get libDeleteNotebookTitle => 'Delete this notebook?';

  @override
  String get libDeleteNotebookBody =>
      'It will be moved to the trash. You can restore it from Settings > Storage.';

  @override
  String get libCancel => 'Cancel';

  @override
  String get libRenameNotebookTitle => 'Rename notebook';

  @override
  String get libSave => 'Save';

  @override
  String get libSortTitle => 'Sort';

  @override
  String get libAppName => 'AbelNotes';

  @override
  String get libSearchHintShort => 'Search…';

  @override
  String get libSearchHintNotebooks => 'Search notebooks…';

  @override
  String get libImport => 'Import';

  @override
  String get libImportTooltip => 'Import an .ncnote file';

  @override
  String get libSettingsTooltip => 'Settings';

  @override
  String get libMoreTooltip => 'More';

  @override
  String get libViewAsList => 'List view';

  @override
  String get libViewAsGrid => 'Grid view';

  @override
  String libSortWithLabel(String sortLabel) {
    return 'Sort: $sortLabel';
  }

  @override
  String get libImportNcnoteMenu => 'Import…';

  @override
  String get libYourNotebooks => 'Your notebooks';

  @override
  String libItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get libNewNotebook => 'New notebook';

  @override
  String get libSketches => 'Sketches';

  @override
  String get libInfiniteSpace => 'infinite space';

  @override
  String get libNewSketch => 'New sketch';

  @override
  String get libInfiniteCanvas => 'Infinite canvas';

  @override
  String get libNew => 'New';

  @override
  String libPagesAbbrev(int count) {
    return '$count pg.';
  }

  @override
  String libPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return '$_temp0';
  }

  @override
  String get libFooterWebdav => 'WebDAV';

  @override
  String get libFooterLocalFirst => 'Local-first app';

  @override
  String get libSyncingWithServer => 'Syncing with the server…';

  @override
  String libDownloadingProgress(int done, int total) {
    return 'Downloading $done/$total notebooks…';
  }

  @override
  String get libLoadingNotebooks => 'Loading notebooks…';

  @override
  String get libLoadingNotebooksFromServer =>
      'Loading notebooks from the server…';

  @override
  String get libTimeNow => 'now';

  @override
  String libTimeMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String libTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '$count hour ago',
    );
    return '$_temp0';
  }

  @override
  String libTimeDaysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String libTimeWeeksAgo(int count) {
    return '$count wk ago';
  }

  @override
  String libTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count months ago',
      one: '$count month ago',
    );
    return '$_temp0';
  }

  @override
  String libTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count years ago',
      one: '$count year ago',
    );
    return '$_temp0';
  }

  @override
  String get libNotebookTitleLabel => 'Title';

  @override
  String get libCoverLabel => 'Cover';

  @override
  String get libPaperLabel => 'Paper';

  @override
  String get libPaperBlank => 'Blank';

  @override
  String get libPaperLined => 'Lined';

  @override
  String get libPaperGrid => 'Grid';

  @override
  String get libPaperDotted => 'Dotted';

  @override
  String get libCreate => 'Create';

  @override
  String get setSectionGeneral => 'General';

  @override
  String get setSectionInput => 'Stylus & input';

  @override
  String get setSectionSync => 'Sync';

  @override
  String get setSectionStorage => 'Storage';

  @override
  String get setSectionShortcuts => 'Shortcuts';

  @override
  String get setSectionAdvanced => 'Advanced';

  @override
  String get setSectionAbout => 'About';

  @override
  String get setBackToLibrary => 'Library';

  @override
  String get setSettingsTitle => 'Settings';

  @override
  String get setThemeLabel => 'Theme';

  @override
  String get setThemeLight => 'Light';

  @override
  String get setThemePaper => 'Paper';

  @override
  String get setThemeDark => 'Dark';

  @override
  String get setLanguage => 'Language';

  @override
  String get setLanguageSub => 'Interface language';

  @override
  String get setLanguageItalian => 'Italian';

  @override
  String get setFavoritesFirst => 'Favorites first';

  @override
  String get setFavoritesFirstSub =>
      'Show favorite notebooks at the top of the library';

  @override
  String get setStylusOnly => 'Stylus only';

  @override
  String get setStylusOnlySub =>
      'Ignores finger touch while writing. Pinch and pan still work with two fingers.';

  @override
  String get setPalmRejection => 'Palm rejection';

  @override
  String get setPalmRejectionSub => 'Automatic detection of the resting palm';

  @override
  String get setPressureThickness => 'Pressure → thickness';

  @override
  String get setPressureThicknessSub =>
      'Stroke modulation based on stylus pressure';

  @override
  String get setTiltCalligraphy => 'Tilt → calligraphy';

  @override
  String get setTiltCalligraphySub =>
      'Stylus tilt changes stroke width and angle';

  @override
  String get setStrokeContinuation => 'Stroke continuation';

  @override
  String get setStrokeContinuationSub =>
      'Compensates for brief sensor interruptions (e.g. the dot of an i)';

  @override
  String get setSyncConnectedDesc =>
      'Connected to a WebDAV server. Notebooks sync across all your devices.';

  @override
  String get setSyncLocalOnlyDesc =>
      'Local-only mode: notebooks stay on this device. Connect a WebDAV server to access them from multiple devices.';

  @override
  String get setSyncWebdav => 'WebDAV';

  @override
  String get setSyncLocalOnly => 'Local only';

  @override
  String setSyncAccountInfo(String host, String username) {
    return '$host · $username';
  }

  @override
  String get setSyncNoServer => 'No server connected';

  @override
  String get setDisconnect => 'Disconnect';

  @override
  String get setConnect => 'Connect';

  @override
  String get setDisconnectTitle => 'Disconnect the server?';

  @override
  String get setDisconnectBody =>
      'Notebooks already downloaded stay on this device. Syncing stops until you reconnect.';

  @override
  String get setCheckCert => 'Verify server certificate';

  @override
  String get setCertCheckFailed =>
      'Unable to verify the server\'s certificate.';

  @override
  String get setCertUnchanged =>
      'The certificate hasn\'t changed since the last connection.';

  @override
  String get setCertChangedTitle => 'New certificate detected';

  @override
  String setCertChangedBody(String oldFingerprint, String newFingerprint) {
    return 'The server is presenting a fingerprint different from the one saved. If you renewed the certificate yourself, confirm to keep syncing. If you didn\'t, CANCEL and check your network before retrying.\n\nSaved fingerprint: $oldFingerprint\nCurrent fingerprint: $newFingerprint';
  }

  @override
  String get setCertConfirmNew => 'Confirm new certificate';

  @override
  String get setCancel => 'Cancel';

  @override
  String get setShortcutPen => 'Pen';

  @override
  String get setShortcutUndo => 'Undo';

  @override
  String get setShortcutBrush => 'Brush';

  @override
  String get setShortcutRedo => 'Redo';

  @override
  String get setShortcutEraser => 'Eraser';

  @override
  String get setShortcutSelectAll => 'Select all';

  @override
  String get setShortcutLasso => 'Lasso';

  @override
  String get setShortcutCopy => 'Copy';

  @override
  String get setShortcutHand => 'Hand';

  @override
  String get setShortcutCut => 'Cut';

  @override
  String get setShortcutText => 'Text';

  @override
  String get setShortcutPaste => 'Paste';

  @override
  String get setShortcutShape => 'Shape';

  @override
  String get setShortcutDuplicate => 'Duplicate';

  @override
  String get setShortcutChangePage => 'Change page';

  @override
  String get setShortcutSave => 'Save';

  @override
  String get setShortcutFit => 'Fit';

  @override
  String get setShortcutCheatSheet => 'Cheat sheet';

  @override
  String get setKeyboardShortcutsTitle => 'Keyboard shortcuts';

  @override
  String get setClearCache => 'Clear cache';

  @override
  String get setClearCacheSub =>
      'Removes temporary files. Notebooks are not touched.';

  @override
  String get setClear => 'Clear';

  @override
  String get setTrash => 'Trash';

  @override
  String get setTrashSub => 'Deleted notebooks, restorable';

  @override
  String get setOpenTrash => 'Open trash';

  @override
  String get setClearCacheDone => 'Cache cleared.';

  @override
  String get setExportLibrary => 'Export library';

  @override
  String get setExportLibrarySub =>
      'Saves every notebook into a single zip archive.';

  @override
  String get setExport => 'Export';

  @override
  String get setExportLibraryEmpty => 'No notebooks to export.';

  @override
  String get setExportLibraryInProgress => 'Exporting…';

  @override
  String setExportLibraryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exported $count notebooks',
      one: 'Exported $count notebook',
    );
    return '$_temp0.';
  }

  @override
  String setExportLibraryFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String setTrashPurgeTitle(String title) {
    return 'Permanently delete \"$title\"?';
  }

  @override
  String get setTrashPurgeBody => 'You won\'t be able to recover it.';

  @override
  String get setTrashPurge => 'Delete forever';

  @override
  String get setTrashEmptyTitle => 'Empty trash?';

  @override
  String get setTrashEmptyBody =>
      'Every notebook in the trash will be permanently deleted.';

  @override
  String get setTrashEmpty => 'Empty trash';

  @override
  String get setTrashEmptyState => 'Trash is empty.';

  @override
  String setTrashDeletedAgo(String time) {
    return 'Deleted $time ago';
  }

  @override
  String get setTrashRestore => 'Restore';

  @override
  String get setAdvancedIntro =>
      'Recovery tools for rare cases of a notebook stuck in sync. Use them only if sync keeps failing after a normal \"Force sync\" from the library.';

  @override
  String get setForceReloadTitle => 'Force reload notebook from server';

  @override
  String get setForceReloadDesc =>
      'Re-downloads the entire notebook content from the server\'s delta folder and overwrites the local copy. Useful if the page count looks wrong or the notebook won\'t open. No server-side data is lost.';

  @override
  String setErrorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String setPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return '$_temp0';
  }

  @override
  String get setReload => 'Reload';

  @override
  String get setCloseNotebookFirst =>
      'Close the notebook before reloading it from the server.';

  @override
  String setReloadConfirmTitle(String title) {
    return 'Reload \"$title\"?';
  }

  @override
  String get setReloadConfirmBody =>
      'Re-downloads metadata, document, pages and assets from the server\'s delta folder. The local copy is replaced.\n\nLocal changes not yet synced will be lost. Continue?';

  @override
  String setReloadInProgress(String title) {
    return 'Reloading \"$title\"…';
  }

  @override
  String get setNotConnectedWebdav => 'Not connected to a WebDAV server.';

  @override
  String setReloadDone(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return '\"$title\" reloaded — $_temp0.';
  }

  @override
  String setReloadFailed(String error) {
    return 'Reload failed: $error';
  }

  @override
  String get setAboutTagline => 'A local-first handwriting app.';

  @override
  String get setAboutOffline => 'Works offline; WebDAV sync is optional.';

  @override
  String setAboutVersion(String version, String commit) {
    return 'Version $version · build $commit';
  }

  @override
  String get setReportProblem => 'Report a problem';

  @override
  String get setReportProblemSub =>
      'Copies the error log to the clipboard to attach to your report.';

  @override
  String get setCopyLog => 'Copy log';

  @override
  String get setReportProblemEmpty => 'No errors logged.';

  @override
  String get setCopyLogDone => 'Log copied to clipboard.';

  @override
  String get onbTagline =>
      'Handwritten notes and freehand drawing, synced to YOUR server. Choose how to start — you can change later.';

  @override
  String get onbTryNowTitle => 'Try it now';

  @override
  String get onbTryNowSubtitle =>
      'Start writing now. Notebooks stay on this device — no account, no server.';

  @override
  String get onbConnectNextcloudTitle => 'Connect your Nextcloud';

  @override
  String get onbConnectNextcloudSubtitle =>
      'Sync to your personal WebDAV / Nextcloud server and access from all your devices.';

  @override
  String get onbManagedServerTitle => 'AbelNotes managed server';

  @override
  String get onbManagedServerSubtitle =>
      'Don\'t have a server? Soon you\'ll be able to use ours, with nothing to configure.';

  @override
  String get onbComingSoonBadge => 'Coming soon';

  @override
  String get onbLicenseNote =>
      'By opening the app you accept the AGPL-3.0 license. \"AbelNotes\" is a trademark of the project.';

  @override
  String get logConnectionFailed =>
      'Unable to connect. Check the URL, username and password.';

  @override
  String logConnectionError(String error) {
    return 'Connection error: $error';
  }

  @override
  String get logCertificateChanged =>
      'The server\'s certificate changed since the last connection. If that was you (e.g. certificate renewal), go to Settings > Sync to confirm the new fingerprint.';

  @override
  String get logCertConfirmTitle => 'Verify server identity';

  @override
  String get logCertConfirmBody =>
      'First connection to this server. Compare this fingerprint with your server\'s (e.g. from the command line) before continuing:';

  @override
  String get logCertConfirmTrust => 'I trust it, continue';

  @override
  String get logBackTooltip => 'Back';

  @override
  String get logTitle => 'Connect your Nextcloud';

  @override
  String get logSubtitle =>
      'Any WebDAV / Nextcloud server (VPS, self-hosted, LAN). No third-party cloud.';

  @override
  String get logServerUrlLabel => 'Server URL';

  @override
  String get logServerUrlHint => 'https://cloud.example.com';

  @override
  String get logServerUrlRequired => 'Enter the server URL';

  @override
  String get logServerUrlInvalid => 'Must start with http:// or https://';

  @override
  String get logUsernameLabel => 'Username';

  @override
  String get logUsernameRequired => 'Username required';

  @override
  String get logPasswordLabel => 'Password / App Password';

  @override
  String get logPasswordRequired => 'Password required';

  @override
  String get logAppPasswordHint =>
      'Recommended: an App Password generated from Nextcloud settings.';

  @override
  String get logServerTypeNextcloud => 'Nextcloud / ownCloud';

  @override
  String get logServerTypeWebdav => 'Other WebDAV';

  @override
  String get logServerUrlHintWebdav => 'https://dav.example.com/folder';

  @override
  String get logWebdavExperimental =>
      'Generic WebDAV backends (Synology, Seafile, rclone…) are experimental: only Nextcloud is fully tested. Keep backups of your notebooks.';

  @override
  String get logWebdavUrlHint =>
      'Full WebDAV URL, path included — e.g. Synology https://nas:5006/home, Seafile https://server/seafdav. Link sharing is unavailable on generic WebDAV.';

  @override
  String get logConnectButton => 'Connect';

  @override
  String get chromeBackToLibraryTooltip => 'Back to library';

  @override
  String get chromeLibrary => 'Library';

  @override
  String get chromeUnsaved => 'Unsaved';

  @override
  String get chromeMouseDrawsTooltip =>
      'Mouse: draws — tap to use it for selection';

  @override
  String get chromeMouseSelectsTooltip =>
      'Mouse: selection — tap to draw with the mouse';

  @override
  String get chromeTouchDrawsTooltip =>
      'Finger: draws — tap to use it for panning';

  @override
  String get chromeTouchPansTooltip =>
      'Finger: pans — tap to draw with your finger';

  @override
  String get chromeUndo => 'Undo';

  @override
  String get chromeRedo => 'Redo';

  @override
  String get chromeAllPages => 'All pages';

  @override
  String chromePageIndicator(String current, int total) {
    return '$current / $total';
  }

  @override
  String get chromeAddPage => 'Add page';

  @override
  String get chromeSymbols => 'Symbols';

  @override
  String get chromeExport => 'Export';

  @override
  String get chromeMore => 'More';

  @override
  String get chromeMoreEllipsis => 'More…';

  @override
  String get chromeToolPen => 'Pen · P';

  @override
  String get chromeToolHighlighter => 'Highlighter';

  @override
  String get chromeToolEraser => 'Eraser · E';

  @override
  String get chromeToolLasso => 'Lasso · L';

  @override
  String get chromeToolText => 'Text · T';

  @override
  String get chromeToolLaser => 'Laser';

  @override
  String get chromeToolPan => 'Hand · H';

  @override
  String get chromeDragToMoveBar => 'Drag to move the toolbar';

  @override
  String get chromeShapeGuessOn => 'Auto-shape · on';

  @override
  String get chromeShapeGuessOff => 'Auto-shape · off';

  @override
  String get chromeLabelPen => 'Pen';

  @override
  String get chromeLabelBallpoint => 'Ballpoint';

  @override
  String get chromeLabelBrush => 'Brush';

  @override
  String get chromeLabelCalligraphy => 'Calligraphy';

  @override
  String get chromeLabelEraser => 'Eraser';

  @override
  String get chromeLabelLasso => 'Lasso';

  @override
  String get chromeLabelText => 'Text';

  @override
  String get chromeLabelShape => 'Shape';

  @override
  String get chromeLabelImage => 'Image';

  @override
  String get chromeLabelPan => 'Hand';

  @override
  String get chromePresetsSection => 'Presets';

  @override
  String get chromePresetHint => 'Long-press to save/clear';

  @override
  String get chromeColorSection => 'Color';

  @override
  String get chromeColorEditHint => 'Long-press a color to change it';

  @override
  String get chromeThicknessSection => 'Thickness';

  @override
  String chromeThicknessPx(String value) {
    return '$value px';
  }

  @override
  String get chromePreview => 'Preview';

  @override
  String get chromeModeSection => 'Mode';

  @override
  String get chromeEraserPerArea => 'By area';

  @override
  String get chromeEraserPerStroke => 'By stroke';

  @override
  String get chromeSizeSection => 'Size';

  @override
  String get chromeSizeSmall => 'S';

  @override
  String get chromeSizeMedium => 'M';

  @override
  String get chromeSizeLarge => 'L';

  @override
  String get chromePresetOverwrite => 'Overwrite with current';

  @override
  String get chromePresetClearSlot => 'Clear slot';

  @override
  String get chromeNoPages => 'No pages';

  @override
  String get chromeHidePageBar => 'Hide the page bar';

  @override
  String get chromeShowPageBar => 'Show the page bar';

  @override
  String chromePrevPageTooltip(int number) {
    return 'Previous page $number — tap to go back';
  }

  @override
  String chromePageOfChapterTooltip(int number, int globalNumber) {
    return 'Page $number of the chapter · page $globalNumber of the notebook';
  }

  @override
  String chromePageTooltip(int number) {
    return 'Page $number';
  }

  @override
  String get chromeHexLabel => 'Hexadecimal';

  @override
  String get chromeCancel => 'Cancel';

  @override
  String get chromeApply => 'Apply';

  @override
  String get pmNone => 'None';

  @override
  String get pmCreateChapterFirst => 'Create at least one chapter first.';

  @override
  String pmAssignChapterCount(int count) {
    return 'Assign chapter ($count pp.)';
  }

  @override
  String pmDeletePagesConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count pages?',
      one: 'Delete 1 page?',
    );
    return '$_temp0';
  }

  @override
  String get pmActionCannotBeUndone => 'This action cannot be undone.';

  @override
  String get pmCancel => 'Cancel';

  @override
  String get pmDelete => 'Delete';

  @override
  String pmPagesCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages cut — open the destination notebook to paste.',
      one: '1 page cut — open the destination notebook to paste.',
    );
    return '$_temp0';
  }

  @override
  String pmPagesCutSkipped(int count, int skipped) {
    return '$count pages cut ($skipped not yet loaded, skipped) — open the destination notebook to paste.';
  }

  @override
  String pmSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get pmSelectAllButton => 'All';

  @override
  String get pmClearSelection => 'Clear selection';

  @override
  String pmPagesCount(int count) {
    return 'Pages ($count)';
  }

  @override
  String pmPagesFilteredCount(int visible, int total) {
    return 'Pages ($visible/$total)';
  }

  @override
  String get pmGoToPageTooltip => 'Go to page…';

  @override
  String get pmExitSelection => 'Exit selection';

  @override
  String get pmSelectPages => 'Select pages';

  @override
  String get pmPastePages => 'Paste pages';

  @override
  String pmPagesPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages pasted.',
      one: '1 page pasted.',
    );
    return '$_temp0';
  }

  @override
  String get pmAddPage => 'Add page';

  @override
  String get pmClose => 'Close';

  @override
  String get pmNewChapter => 'New chapter';

  @override
  String get pmChapterNameHint => 'Chapter name';

  @override
  String pmPageDeleted(int number) {
    return 'Page $number deleted';
  }

  @override
  String get pmUndo => 'Undo';

  @override
  String get pmAssignChapter => 'Assign chapter';

  @override
  String get pmRename => 'Rename';

  @override
  String get pmRenameChapter => 'Rename chapter';

  @override
  String get pmDeleteChapter => 'Delete chapter';

  @override
  String pmDeleteChapterConfirm(String title) {
    return 'Delete \"$title\"? Its pages will remain, but without a chapter.';
  }

  @override
  String get pmGoToPage => 'Go to page';

  @override
  String pmPageRangeHint(int max) {
    return '1–$max';
  }

  @override
  String get pmGo => 'Go';

  @override
  String get pmOk => 'OK';

  @override
  String pmCountPagesShort(int count) {
    return '$count pp.';
  }

  @override
  String get pmChapter => 'Chapter';

  @override
  String get pmCut => 'Cut';

  @override
  String get pmInsertBefore => 'Insert before';

  @override
  String get pmInsertAfter => 'Insert after';

  @override
  String get pmDuplicate => 'Duplicate';

  @override
  String get pmMoveTo => 'Move to page…';

  @override
  String get pmMove => 'Move';

  @override
  String get pmMoveToPage => 'Move to page';

  @override
  String get pmChapterEllipsis => 'Chapter…';

  @override
  String pmPageChapterLabel(int number, String chapter) {
    return '$number • $chapter';
  }

  @override
  String get pmCorruptAssetTooltip =>
      'Asset corrupted on the server (truncated) — re-import the original PDF to recover';

  @override
  String get pmLoadingImageTooltip => 'Loading image from the server…';

  @override
  String get tedInsertTextTitle => 'Insert text';

  @override
  String get tedEditTextTitle => 'Edit text';

  @override
  String get tedBoldTooltip => 'Bold (Ctrl+B)';

  @override
  String get tedItalicTooltip => 'Italic (Ctrl+I)';

  @override
  String get tedUnderlineTooltip => 'Underline (Ctrl+U)';

  @override
  String get tedStrikethroughTooltip => 'Strikethrough';

  @override
  String get tedAlignLeft => 'Left';

  @override
  String get tedAlignCenter => 'Center';

  @override
  String get tedAlignRight => 'Right';

  @override
  String get tedWriteHereHint => 'Write here…';

  @override
  String get tedCancel => 'Cancel';

  @override
  String get tedInsert => 'Insert';

  @override
  String get cropTitle => 'Crop image';

  @override
  String get cropCancel => 'Cancel';

  @override
  String get cropConfirm => 'Crop';

  @override
  String get imgFontSmaller => 'Smaller text';

  @override
  String get imgFontLarger => 'Larger text';

  @override
  String get imgCrop => 'Crop';

  @override
  String get imgCopy => 'Copy';

  @override
  String get imgUnlock => 'Unlock';

  @override
  String get imgLock => 'Lock';

  @override
  String get imgDelete => 'Delete';

  @override
  String get imgDeselect => 'Deselect';

  @override
  String get imgMoreActions => 'More actions';

  @override
  String get imgBringToFront => 'Bring to front';

  @override
  String get imgSendToBack => 'Send to back';

  @override
  String get imgComment => 'Comment';

  @override
  String get imgFlipHChecked => 'Flip H ✓';

  @override
  String get imgFlipH => 'Flip H';

  @override
  String get imgCut => 'Cut';

  @override
  String get syncOkTooltip => 'Synced';

  @override
  String get syncPendingTooltip => 'Syncing…';

  @override
  String get syncOfflineTooltip => 'Offline';

  @override
  String get syncConflictTooltip => 'Conflict';

  @override
  String get confDecideLater => 'Decide later';

  @override
  String confTitlePageDeletedElsewhere(int pageNumber) {
    return 'Page $pageNumber deleted elsewhere';
  }

  @override
  String confTitleConflictPage(int pageNumber) {
    return 'Conflict — Page $pageNumber';
  }

  @override
  String get confDeletionExplainer =>
      'You edited this page, but another device deleted it. Do you want to keep it or delete it?';

  @override
  String get confKeepPage => 'Keep the page';

  @override
  String get confLocalYours => 'Local (yours)';

  @override
  String get confRemoteOtherDevice => 'Remote (other device)';

  @override
  String get confKeepAllLocal => 'Keep all local';

  @override
  String get confAcceptAllRemote => 'Accept all remote';

  @override
  String confProgressIndicator(int current, int total, num decided) {
    String _temp0 = intl.Intl.pluralLogic(
      decided,
      locale: localeName,
      other: '$decided decided',
      one: '$decided decided',
    );
    return '$current / $total  ($_temp0)';
  }

  @override
  String get confApplyChoices => 'Apply choices';

  @override
  String confDecidedProgress(int decided, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'decided',
      one: 'decided',
    );
    return '$decided/$total $_temp0';
  }

  @override
  String get confJumpToConflict => 'Go to conflict';

  @override
  String confJumpDecidedCount(int decided, int total) {
    return '$decided/$total decided';
  }

  @override
  String confJumpItemPage(int pageNumber) {
    return 'Pg. $pageNumber';
  }

  @override
  String confJumpItemPageWithChapter(int pageNumber, String chapterName) {
    return 'Pg. $pageNumber — $chapterName';
  }

  @override
  String get confDismissDialogTitle => 'Cancel?';

  @override
  String get confDismissDialogBody =>
      'Unapplied choices will be lost. The local version will be kept.';

  @override
  String get confContinue => 'Continue';

  @override
  String get confCancel => 'Cancel';

  @override
  String get confModifiedJustNow => 'Just now';

  @override
  String confModifiedMinutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String confModifiedHoursAgo(num hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours ago',
      one: '$hours hour ago',
    );
    return '$_temp0';
  }

  @override
  String get confDeletePage => 'Delete the page';

  @override
  String get confAsOnOtherDevice => 'As on the other device';

  @override
  String get symNewLibraryTitle => 'New library';

  @override
  String get symNewLibraryHint => 'Enter the library name';

  @override
  String get symRenameLibraryTitle => 'Rename library';

  @override
  String get symNewNameHint => 'New name';

  @override
  String get symDeleteLibraryTitle => 'Delete library';

  @override
  String symDeleteLibraryConfirm(String name) {
    return 'Delete \"$name\" and all its symbols?';
  }

  @override
  String get symCancel => 'Cancel';

  @override
  String get symDelete => 'Delete';

  @override
  String get symRenameSymbolTitle => 'Rename symbol';

  @override
  String get symPanelTitle => 'Symbol libraries';

  @override
  String get symNoLibraries => 'No libraries';

  @override
  String get symNew => 'New';

  @override
  String get symSelectLibrary => 'Select a library';

  @override
  String get symNoSymbolsHint =>
      'No symbols\nSelect elements with the lasso and press ✚';

  @override
  String get symLassoSaveHint =>
      'Select elements with the lasso → ✚ to save into the active library';

  @override
  String get symRename => 'Rename';

  @override
  String get symInsert => 'Insert';

  @override
  String get symOk => 'OK';

  @override
  String get rcbBannerTitle => 'Changes from another device';

  @override
  String get rcbSeeDetails => 'View details';

  @override
  String get rcbDismiss => 'Dismiss';

  @override
  String get rcbIncomingChanges => 'Incoming changes';

  @override
  String get rcbTapPageHint => 'Tap a page to apply and jump there';

  @override
  String rcbNewImagesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new images',
      one: '1 new image',
    );
    return '$_temp0';
  }

  @override
  String get rcbKeepMine => 'Keep mine';

  @override
  String get rcbApplyAll => 'Apply all';

  @override
  String get rcbBadgeNew => 'NEW';

  @override
  String get rcbBadgeModified => 'MODIFIED';

  @override
  String rcbPageTitle(int pageNumber) {
    return 'Page $pageNumber';
  }

  @override
  String get rcbContentUpdated => 'Content updated';

  @override
  String rcbSummaryModifiedPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages modified',
      one: '$count page modified',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryNewPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new',
      one: '$count new',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryImages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count images',
      one: '$count image',
    );
    return '$_temp0';
  }

  @override
  String get rcbChangesDetected => 'Changes detected';

  @override
  String get nbUntitled => 'Untitled';

  @override
  String get nbDefaultChapterTitle => 'Chapter 1';

  @override
  String get nbOpeningNotebook => 'Opening notebook…';

  @override
  String get nbNoLocalCopyOffline =>
      'No local copy of this notebook, and you are not connected to a server to download it.';

  @override
  String nbOpenFailed(String error) {
    return 'Could not open: $error';
  }

  @override
  String get nbSortModifiedDesc => 'Modified (newest first)';

  @override
  String get nbSortModifiedAsc => 'Modified (oldest first)';

  @override
  String get nbSortTitleAsc => 'Title A→Z';

  @override
  String get nbSortTitleDesc => 'Title Z→A';

  @override
  String get nbSortCreatedDesc => 'Created (newest first)';

  @override
  String get nbSortCreatedAsc => 'Created (oldest first)';

  @override
  String get nbSortColorGroup => 'Cover color';

  @override
  String cvFormatTooNew(int fileVersion, int supportedVersion) {
    return 'This notebook uses a newer format (v$fileVersion, supported: v$supportedVersion). Update AbelNotes to open it.';
  }

  @override
  String get setLanguageSystem => 'System';

  @override
  String get setLanguageEnglish => 'English';

  @override
  String get setLanguageSpanish => 'Español';

  @override
  String get onbAppName => 'AbelNotes';

  @override
  String get setAboutAppName => 'AbelNotes';

  @override
  String get chromeLabelHighlighter => 'Highlighter';

  @override
  String get chromeLabelLaser => 'Laser';

  @override
  String get importSourceTitle => 'Import into library';

  @override
  String get importSourceNcnote => '.ncnote notebook';

  @override
  String get importSourceObsidian => 'Obsidian vault';

  @override
  String get importSourceObsidianHint => 'Folder of Markdown files';

  @override
  String get importSourceNotion => 'Notion export';

  @override
  String get importSourceNotionHint => '.zip file (Markdown & CSV)';

  @override
  String get importPhaseScanning => 'Scanning source…';

  @override
  String importPhaseParsing(int current, int total) {
    return 'Reading file $current of $total';
  }

  @override
  String importPhasePaginating(int current, int total) {
    return 'Laying out chapter $current of $total';
  }

  @override
  String get importPhasePackaging => 'Creating notebook…';

  @override
  String get importCancel => 'Cancel';

  @override
  String get importCancelled => 'Import cancelled';

  @override
  String importReportTitle(int count) {
    return '$count import warnings';
  }

  @override
  String get importReportCopy => 'Copy';

  @override
  String get importReportClose => 'Close';

  @override
  String get importSourceOneNote => 'OneNote file';

  @override
  String get importSourceOneNoteHint => '.one section or .onetoc2 notebook';

  @override
  String get setOpenSourceLicenses => 'Open-source licenses';

  @override
  String get setOpenSourceLicensesSub =>
      'Third-party components bundled with the app';

  @override
  String get csBackToContent => 'Back to content';
}
