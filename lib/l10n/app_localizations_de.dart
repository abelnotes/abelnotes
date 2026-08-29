// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get csPdfTextCopied => 'Text kopiert';

  @override
  String csCopyFailed(String error) {
    return 'Kopieren fehlgeschlagen: $error';
  }

  @override
  String get csCopy => 'Kopieren';

  @override
  String get csSyncInProgress => 'Synchronisierung läuft…';

  @override
  String get csSaved => 'Gespeichert!';

  @override
  String csErrorGeneric(String error) {
    return 'Fehler: $error';
  }

  @override
  String get csSelectionCopied => 'Auswahl kopiert';

  @override
  String get csSelectionCut => 'Auswahl ausgeschnitten';

  @override
  String get csShortcutsTitle => 'Tastenkürzel';

  @override
  String get csShortcutGroupGeneral => 'Allgemein';

  @override
  String get csSaveNow => 'Jetzt speichern';

  @override
  String get csShortcutUndo => 'Rückgängig';

  @override
  String get csShortcutRedo => 'Wiederholen';

  @override
  String get csSelectAll => 'Alles auswählen';

  @override
  String get csShortcutResetZoom => 'Zoom zurücksetzen';

  @override
  String get csShortcutDeselect => 'Auswahl aufheben / abbrechen';

  @override
  String get csShortcutThisGuide => 'Diese Übersicht';

  @override
  String get csShortcutGroupClipboard => 'Zwischenablage';

  @override
  String get csShortcutCopySelection => 'Auswahl kopieren';

  @override
  String get csShortcutCutSelection => 'Auswahl ausschneiden';

  @override
  String get csPaste => 'Einfügen';

  @override
  String get csShortcutDuplicateSelection => 'Auswahl duplizieren';

  @override
  String get csShortcutKeyDeleteBackspace => 'Entf / Rücktaste';

  @override
  String get csShortcutDeleteElementOrSelection =>
      'Element oder Auswahl löschen';

  @override
  String get csShortcutGroupTools => 'Werkzeuge';

  @override
  String get csToolPen => 'Stift';

  @override
  String get csToolBrush => 'Pinsel';

  @override
  String get csToolEraser => 'Radierer';

  @override
  String get csToolLasso => 'Lasso';

  @override
  String get csToolHand => 'Hand / Verschieben';

  @override
  String get csToolText => 'Text';

  @override
  String get csToolShape => 'Form';

  @override
  String get csClose => 'Schließen';

  @override
  String get csUnsavedChangesTitle => 'Nicht gespeicherte Änderungen';

  @override
  String get csUnsavedChangesBody => 'Vor dem Verlassen speichern?';

  @override
  String get csDiscard => 'Verwerfen';

  @override
  String get csCancel => 'Abbrechen';

  @override
  String get csSave => 'Speichern';

  @override
  String get csOpeningLink => 'Link wird geöffnet…';

  @override
  String get csCannotOpenLink => 'Der Link kann nicht geöffnet werden';

  @override
  String get csCameraUnavailable =>
      'Auf diesem Gerät ist keine Kamera verfügbar';

  @override
  String get csPhotoCaptureFailed => 'Das Foto konnte nicht aufgenommen werden';

  @override
  String get csPdfRasterizing => 'PDF wird gerastert…';

  @override
  String csPdfImportProgress(int done, int total) {
    return 'PDF wird importiert: $done/$total';
  }

  @override
  String get csPdfReadFailed =>
      'PDF kann nicht gelesen werden: keine Seiten gefunden';

  @override
  String csPdfImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return 'PDF importiert: $_temp0';
  }

  @override
  String csPdfImportError(String error) {
    return 'Fehler beim PDF-Import: $error';
  }

  @override
  String get csNoNotebookOpen => 'Kein Notizbuch geöffnet';

  @override
  String get csMissingPageDataTitle => 'Fehlende Seitendaten';

  @override
  String get csNoPages => 'Keine Seiten';

  @override
  String csMissingPagesBodyMany(int count) {
    return 'Diese Seite und $count weitere konnten nicht vom Server geladen werden. Die Dateien sind möglicherweise bei einer unvollständigen Synchronisierung verloren gegangen.';
  }

  @override
  String get csMissingPageBodyOne =>
      'Die Datei dieser Seite konnte nicht vom Server geladen werden. Sie ist möglicherweise bei einer unvollständigen Synchronisierung verloren gegangen.';

  @override
  String get csRetrySync => 'Synchronisierung wiederholen';

  @override
  String get csRestoreAsBlankPage => 'Als leere Seite wiederherstellen';

  @override
  String csRestoreAllMissing(int count) {
    return 'Alle wiederherstellen ($count)';
  }

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten als leer wiederhergestellt',
      one: '$count Seite als leer wiederhergestellt',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'Seite löschen';

  @override
  String csSyncProgressCount(int done, int total) {
    return 'Synchronisierung $done/$total';
  }

  @override
  String get csSyncing => 'Synchronisierung…';

  @override
  String csShapeRecognizedLabel(String shape) {
    return 'Form: $shape';
  }

  @override
  String get csConfirmShapeSemantics => 'Erkannte Form bestätigen';

  @override
  String get csConfirm => 'Bestätigen';

  @override
  String get csCancelShapeSemantics => 'Erkannte Form verwerfen';

  @override
  String csTapToPlaceSymbol(String name) {
    return 'Zum Platzieren tippen: $name';
  }

  @override
  String get csCancelSymbolInsertSemantics => 'Einfügen des Symbols abbrechen';

  @override
  String get csTapToPlaceCopy => 'Zum Platzieren der Kopie tippen';

  @override
  String get csCancelPasteSemantics => 'Einfügen abbrechen';

  @override
  String get csNewPage => 'Neue Seite';

  @override
  String get csImageCopied => 'Bild kopiert';

  @override
  String get csImageCut => 'Bild ausgeschnitten';

  @override
  String get csImageCommentTitle => 'Bildkommentar';

  @override
  String get csAddCommentHint => 'Kommentar hinzufügen...';

  @override
  String get csRemove => 'Entfernen';

  @override
  String get csCut => 'Ausschneiden';

  @override
  String get csDuplicate => 'Duplizieren';

  @override
  String get csSelectionDuplicated => 'Auswahl dupliziert';

  @override
  String get csChangeColor => 'Farbe ändern';

  @override
  String get csThickness => 'Stärke';

  @override
  String get csDelete => 'Löschen';

  @override
  String get csMore => 'Mehr';

  @override
  String get csPresentationMode => 'Präsentationsmodus';

  @override
  String get csPresentationModeSub =>
      'Vollbild, ohne Werkzeuge — ideal zum Zeigen von Seiten';

  @override
  String get csRecognizeHandwriting => 'Handschrift erkennen';

  @override
  String get csRecognizeHandwritingSub =>
      'Wandelt Tinte in durchsuchbaren Text um (auf dem Gerät)';

  @override
  String get csRecognizeInProgress => 'Erkennung läuft…';

  @override
  String get csRecognizeNothing => 'Kein Text erkannt.';

  @override
  String csRecognizeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Zeilen erkannt',
      one: '$count Zeile erkannt',
    );
    return '$_temp0.';
  }

  @override
  String csRecognizeFailed(String error) {
    return 'Erkennung fehlgeschlagen: $error';
  }

  @override
  String get csShareLink => 'Per Link teilen';

  @override
  String get csShareLinkSub =>
      'Lädt ein PDF in deine Nextcloud hoch und erzeugt einen öffentlichen Link';

  @override
  String get csShareLinkInProgress => 'Link wird erstellt…';

  @override
  String get csShareLinkTitle => 'Öffentlicher Link';

  @override
  String get csShareLinkBody =>
      'Wer diesen Link hat, kann das PDF ansehen. Über deine Nextcloud widerrufbar.';

  @override
  String get csShareLinkCopied => 'Link in die Zwischenablage kopiert.';

  @override
  String csShareLinkFailed(String error) {
    return 'Teilen fehlgeschlagen: $error';
  }

  @override
  String get csCopyLink => 'Link kopieren';

  @override
  String get csShare => 'Teilen';

  @override
  String get csRevokeLink => 'Link widerrufen';

  @override
  String get csRevokeLinkDone => 'Link widerrufen.';

  @override
  String get csShareLinkUpdate => 'Geteiltes PDF aktualisieren';

  @override
  String get csShareLinkUpdated => 'PDF aktualisiert.';

  @override
  String get csChangeSelectionColor => 'Farbe der Auswahl ändern';

  @override
  String get csSelectionThickness => 'Stärke der Auswahl';

  @override
  String csWidthPx(String width) {
    return '$width px';
  }

  @override
  String get csFlipHorizontal => 'Horizontal spiegeln';

  @override
  String get csFlipVertical => 'Vertikal spiegeln';

  @override
  String get csCopyAsImage => 'Als Bild kopieren';

  @override
  String get csPasteInAnotherNotebook => 'In ein anderes Notizbuch einfügen…';

  @override
  String get csKeyDelete => 'Entf';

  @override
  String get csCreateSymbol => 'Symbol erstellen';

  @override
  String get csSelect => 'Auswählen';

  @override
  String get csImportFile => 'Datei importieren…';

  @override
  String get csTakePhoto => 'Foto aufnehmen';

  @override
  String get csInsertText => 'Text einfügen';

  @override
  String csInsertSymbolCount(int count) {
    return 'Symbol einfügen ($count)';
  }

  @override
  String get csClearPage => 'Seite leeren';

  @override
  String get csExportPng => 'PNG exportieren';

  @override
  String get csExportPdf => 'PDF exportieren';

  @override
  String get csClearPageConfirmBody =>
      'Alle Elemente auf dieser Seite werden gelöscht. Fortfahren?';

  @override
  String get csClear => 'Leeren';

  @override
  String get csCreateSymbolTitle => 'Wiederverwendbares Symbol erstellen';

  @override
  String get csSymbolNameLabel => 'Symbolname';

  @override
  String get csLibraryLabel => 'Bibliothek:';

  @override
  String get csNoLibraryNotice =>
      'Keine Bibliothek vorhanden. Es wird eine Bibliothek „Symbole“ erstellt.';

  @override
  String get csCreate => 'Erstellen';

  @override
  String csSymbolCreated(String name) {
    return 'Symbol „$name“ erstellt!';
  }

  @override
  String csSaveFileDialogTitle(String fileName) {
    return '$fileName speichern';
  }

  @override
  String get csExportCurrentPagePng => 'Aktuelle Seite (PNG)';

  @override
  String get csExportCurrentChapter => 'Aktuelles Kapitel';

  @override
  String get csExportEntireNotebook => 'Gesamtes Notizbuch';

  @override
  String csExportingPages(int count) {
    return '$count Seiten werden exportiert...';
  }

  @override
  String csChooseFolderForImages(int count) {
    return 'Ordner für die $count Bilder wählen';
  }

  @override
  String csPngExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return 'PNG exportiert ($_temp0)';
  }

  @override
  String csExportError(String error) {
    return 'Fehler beim Export: $error';
  }

  @override
  String get csExportCurrentPage => 'Aktuelle Seite';

  @override
  String csGeneratingPdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return 'PDF wird erstellt ($_temp0)...';
  }

  @override
  String csPdfExportError(String error) {
    return 'Fehler beim PDF-Export: $error';
  }

  @override
  String csPdfExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return 'PDF exportiert: $_temp0';
  }

  @override
  String get csChapterSeparatorEyebrow => 'KAPITEL';

  @override
  String get csSelectionCopiedAsImage => 'Auswahl als Bild kopiert';

  @override
  String csCopyImageError(String error) {
    return 'Fehler beim Kopieren des Bildes: $error';
  }

  @override
  String get csExport => 'Exportieren';

  @override
  String csPageNumber(int number) {
    return 'Seite $number';
  }

  @override
  String csPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return '$_temp0';
  }

  @override
  String get csExportChapterTitle => 'Kapitel exportieren';

  @override
  String get csExportNotebookTitle => 'Gesamtes Notizbuch exportieren';

  @override
  String get csChapterSeparatorQuestion =>
      'Vor jedem Kapitel eine Trennseite einfügen?';

  @override
  String get csYesWithSeparators => 'Ja, mit Trennseiten';

  @override
  String get csNoPagesOnly => 'Nein, nur die Seiten';

  @override
  String csTotalPages(int count) {
    return 'Seiten insgesamt: $count';
  }

  @override
  String csFromPage(int page) {
    return 'Von Seite: $page';
  }

  @override
  String csToPage(int page) {
    return 'Bis Seite: $page';
  }

  @override
  String csWillExportPages(int count, int start, int end) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten werden exportiert ($start–$end)',
      one: '$count Seite wird exportiert ($start–$end)',
    );
    return '$_temp0';
  }

  @override
  String csChapterLabelWithCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return '$title ($_temp0)';
  }

  @override
  String get csGoToPage => 'Zu Seite springen';

  @override
  String get csDuplicatePage => 'Seite duplizieren';

  @override
  String get csNewPageAfter => 'Neue Seite danach';

  @override
  String get csDeletePageConfirmTitle => 'Seite löschen?';

  @override
  String csDeletePageConfirmBody(int number) {
    return 'Seite $number und ihr gesamter Inhalt werden gelöscht.';
  }

  @override
  String get csExportAsPdf => 'Als PDF exportieren';

  @override
  String get csExportAsPng => 'Als PNG exportieren';

  @override
  String get csExportAsNcnote => 'Als .abelnote exportieren (nativ)';

  @override
  String get csExportNcnoteSubtitle =>
      'Natives Format, volle Vektorqualität (für Backup oder Übertragung)';

  @override
  String get csGeneratingNcnote => '.abelnote wird erstellt…';

  @override
  String csNcnoteExported(String size) {
    return '.abelnote exportiert ($size KB)';
  }

  @override
  String csNcnoteExportError(String error) {
    return 'Fehler beim .abelnote-Export: $error';
  }

  @override
  String get csImageOrPdf => 'Bild oder PDF';

  @override
  String get csChangePaperType => 'Papierart ändern';

  @override
  String get csPenToMonitor => 'Stift → Monitor';

  @override
  String get csPenToMonitorSubtitle =>
      'Den Stift auf einen einzelnen Bildschirm beschränken';

  @override
  String get csPaperType => 'Papierart';

  @override
  String get csPaperBlank => 'Blanko';

  @override
  String get csPaperLinedNarrow => 'Enge Linien';

  @override
  String get csPaperLinedWide => 'Weite Linien';

  @override
  String get csPaperGrid => 'Karo';

  @override
  String get csPaperDotted => 'Punktraster';

  @override
  String get csPaperCornell => 'Cornell';

  @override
  String get csPaperIsometric => 'Isometrisch';

  @override
  String get csPaperMusic => 'Notenlinien';

  @override
  String get csMapPenToMonitor => 'Stift einem Monitor zuordnen';

  @override
  String csPenMappedTo(String monitor) {
    return 'Stift zugeordnet zu $monitor';
  }

  @override
  String get csAllMonitors => 'Alle Monitore';

  @override
  String get csAllMonitorsSubtitle =>
      'Zurücksetzen (Stift über den ganzen Desktop)';

  @override
  String get csPenReset => 'Stift zurückgesetzt';

  @override
  String get csShapeLine => 'Linie';

  @override
  String get csShapeCircle => 'Kreis';

  @override
  String get csShapeRectangle => 'Rechteck';

  @override
  String get csShapeTriangle => 'Dreieck';

  @override
  String get csShapeArrow => 'Pfeil';

  @override
  String get csInvalidRangeError =>
      'Gib einen gültigen Bereich ein (z. B. 1–10).';

  @override
  String csPdfStartOutOfRange(int count) {
    return 'Das PDF hat etwa $count Seiten. Der Startwert liegt außerhalb des Bereichs.';
  }

  @override
  String get csImportPdfTitle => 'PDF importieren';

  @override
  String csPdfEstimatedPages(int count) {
    return 'Das PDF hat etwa $count Seiten.';
  }

  @override
  String csAllPagesWithCount(int count) {
    return 'Alle Seiten ($count)';
  }

  @override
  String get csAllPages => 'Alle Seiten';

  @override
  String get csCustomRange => 'Eigener Bereich';

  @override
  String get csFromLabel => 'Von';

  @override
  String get csToLabel => 'Bis';

  @override
  String get csImport => 'Importieren';

  @override
  String libErrorGeneric(String error) {
    return 'Fehler: $error';
  }

  @override
  String libErrorOpen(String error) {
    return 'Fehler beim Öffnen: $error';
  }

  @override
  String get libImportCannotReadFile => 'Die Datei kann nicht gelesen werden';

  @override
  String get libImportInProgress => 'Import läuft…';

  @override
  String get libServiceUnavailable => 'Dienst nicht verfügbar';

  @override
  String libImportedTitleSuffix(String title) {
    return '$title (importiert)';
  }

  @override
  String libImportSuccess(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return 'Importiert: „$title“ ($_temp0)';
  }

  @override
  String get libImportCorruptedFile =>
      'Diese Datei ist kein gültiges AbelNotes-Notizbuch — sie ist möglicherweise unvollständig oder beschädigt.';

  @override
  String get libExport => 'Exportieren';

  @override
  String get libImportOneNoteUnreadable =>
      'AbelNotes kann diese OneNote-Datei nicht lesen — sie verwendet möglicherweise ein noch nicht unterstütztes Format oder ist beschädigt.';

  @override
  String libErrorImport(String error) {
    return 'Fehler beim Import: $error';
  }

  @override
  String libErrorCreate(String error) {
    return 'Fehler beim Erstellen: $error';
  }

  @override
  String get libSketchDefaultTitle => 'Skizze';

  @override
  String libErrorCreateSketch(String error) {
    return 'Fehler beim Erstellen der Skizze: $error';
  }

  @override
  String get libRemoveFromFavorites => 'Aus Favoriten entfernen';

  @override
  String get libAddToFavorites => 'Zu Favoriten hinzufügen';

  @override
  String get libRename => 'Umbenennen';

  @override
  String get libChangeCover => 'Einband ändern';

  @override
  String get libMoveToFolder => 'In Ordner verschieben';

  @override
  String get libNoFolder => 'Kein Ordner';

  @override
  String get libNewFolder => 'Neuer Ordner';

  @override
  String get libRenameFolder => 'Ordner umbenennen';

  @override
  String get libFolderNameHint => 'Ordnername';

  @override
  String get libAllNotebooks => 'Alle';

  @override
  String get libDeleteFolder => 'Ordner löschen';

  @override
  String libDeleteFolderTitle(String name) {
    return 'Ordner „$name“ löschen?';
  }

  @override
  String get libDeleteFolderBody =>
      'Die enthaltenen Notizbücher werden nicht gelöscht — sie bleiben ohne Ordner in der Bibliothek.';

  @override
  String get libDelete => 'Löschen';

  @override
  String get libDeleteNotebookTitle => 'Dieses Notizbuch löschen?';

  @override
  String get libDeleteNotebookBody =>
      'Es wird in den Papierkorb verschoben. Du kannst es unter Einstellungen > Speicher wiederherstellen.';

  @override
  String get libCancel => 'Abbrechen';

  @override
  String get libRenameNotebookTitle => 'Notizbuch umbenennen';

  @override
  String get libSave => 'Speichern';

  @override
  String get libSortTitle => 'Sortierung';

  @override
  String get libAppName => 'AbelNotes';

  @override
  String get libSearchHintShort => 'Suchen…';

  @override
  String get libSearchHintNotebooks => 'Notizbücher suchen…';

  @override
  String get libImport => 'Importieren';

  @override
  String get libImportTooltip => 'Eine .abelnote-Datei importieren';

  @override
  String get libSettingsTooltip => 'Einstellungen';

  @override
  String get libMoreTooltip => 'Mehr';

  @override
  String get libViewAsList => 'Listenansicht';

  @override
  String get libViewAsGrid => 'Rasteransicht';

  @override
  String libSortWithLabel(String sortLabel) {
    return 'Sortierung: $sortLabel';
  }

  @override
  String get libImportNcnoteMenu => 'Importieren…';

  @override
  String get libYourNotebooks => 'Deine Notizbücher';

  @override
  String libItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente',
      one: '$count Element',
    );
    return '$_temp0';
  }

  @override
  String get libNewNotebook => 'Neues Notizbuch';

  @override
  String get libSketches => 'Skizzen';

  @override
  String get libInfiniteSpace => 'unendliche Fläche';

  @override
  String get libNewSketch => 'Neue Skizze';

  @override
  String get libInfiniteCanvas => 'Unendliche Fläche';

  @override
  String get libNew => 'Neu';

  @override
  String libPagesAbbrev(int count) {
    return '$count S.';
  }

  @override
  String libPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return '$_temp0';
  }

  @override
  String get libFooterWebdav => 'WebDAV';

  @override
  String get libFooterLocalFirst => 'Local-First-App';

  @override
  String get libSyncingWithServer => 'Synchronisierung mit dem Server…';

  @override
  String libDownloadingProgress(int done, int total) {
    return '$done/$total Notizbücher werden geladen…';
  }

  @override
  String get libLoadingNotebooks => 'Notizbücher werden geladen…';

  @override
  String get libLoadingNotebooksFromServer =>
      'Notizbücher werden vom Server geladen…';

  @override
  String get libTimeNow => 'jetzt';

  @override
  String libTimeMinutesAgo(int count) {
    return 'vor $count Min.';
  }

  @override
  String libTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Stunden',
      one: 'vor $count Stunde',
    );
    return '$_temp0';
  }

  @override
  String libTimeDaysAgo(int count) {
    return 'vor $count T.';
  }

  @override
  String libTimeWeeksAgo(int count) {
    return 'vor $count Wo.';
  }

  @override
  String libTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Monaten',
      one: 'vor $count Monat',
    );
    return '$_temp0';
  }

  @override
  String libTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Jahren',
      one: 'vor $count Jahr',
    );
    return '$_temp0';
  }

  @override
  String get libNotebookTitleLabel => 'Titel';

  @override
  String get libCoverLabel => 'Einband';

  @override
  String get libPaperLabel => 'Papier';

  @override
  String get libPaperBlank => 'Blanko';

  @override
  String get libPaperLined => 'Liniert';

  @override
  String get libPaperGrid => 'Karo';

  @override
  String get libPaperDotted => 'Punktraster';

  @override
  String get libCreate => 'Erstellen';

  @override
  String get setSectionGeneral => 'Allgemein';

  @override
  String get setSectionInput => 'Stift & Eingabe';

  @override
  String get setSectionSync => 'Synchronisierung';

  @override
  String get setSectionStorage => 'Speicher';

  @override
  String get setSectionShortcuts => 'Tastenkürzel';

  @override
  String get setSectionAdvanced => 'Erweitert';

  @override
  String get setSectionAbout => 'Über';

  @override
  String get setBackToLibrary => 'Bibliothek';

  @override
  String get setSettingsTitle => 'Einstellungen';

  @override
  String get setThemeLabel => 'Design';

  @override
  String get setThemeLight => 'Hell';

  @override
  String get setThemePaper => 'Papier';

  @override
  String get setThemeDark => 'Dunkel';

  @override
  String get setLanguage => 'Sprache';

  @override
  String get setLanguageSub => 'Sprache der Benutzeroberfläche';

  @override
  String get setLanguageItalian => 'Italienisch';

  @override
  String get setFavoritesFirst => 'Favoriten zuerst';

  @override
  String get setFavoritesFirstSub =>
      'Favorisierte Notizbücher oben in der Bibliothek anzeigen';

  @override
  String get setStylusOnly => 'Nur Stift';

  @override
  String get setStylusOnlySub =>
      'Ignoriert Fingerberührungen beim Schreiben. Zoomen und Verschieben mit zwei Fingern funktionieren weiterhin.';

  @override
  String get setPalmRejection => 'Handballenerkennung';

  @override
  String get setPalmRejectionSub =>
      'Automatische Erkennung des aufliegenden Handballens';

  @override
  String get setPressureThickness => 'Druck → Stärke';

  @override
  String get setPressureThicknessSub => 'Strichstärke abhängig vom Stiftdruck';

  @override
  String get setTiltCalligraphy => 'Neigung → Kalligrafie';

  @override
  String get setTiltCalligraphySub =>
      'Die Neigung des Stifts verändert Breite und Winkel des Strichs';

  @override
  String get setStrokeContinuation => 'Strichfortsetzung';

  @override
  String get setStrokeContinuationSub =>
      'Gleicht kurze Aussetzer des Sensors aus (z. B. beim i-Punkt)';

  @override
  String get setSyncConnectedDesc =>
      'Mit einem WebDAV-Server verbunden. Notizbücher werden auf allen deinen Geräten synchronisiert.';

  @override
  String get setSyncLocalOnlyDesc =>
      'Nur-lokal-Modus: Notizbücher bleiben auf diesem Gerät. Verbinde einen WebDAV-Server, um von mehreren Geräten darauf zuzugreifen.';

  @override
  String get setSyncWebdav => 'WebDAV';

  @override
  String get setSyncLocalOnly => 'Nur lokal';

  @override
  String setSyncAccountInfo(String host, String username) {
    return '$host · $username';
  }

  @override
  String get setSyncNoServer => 'Kein Server verbunden';

  @override
  String get setDisconnect => 'Trennen';

  @override
  String get setConnect => 'Verbinden';

  @override
  String get setDisconnectTitle => 'Verbindung zum Server trennen?';

  @override
  String get setDisconnectBody =>
      'Bereits heruntergeladene Notizbücher bleiben auf diesem Gerät. Die Synchronisierung pausiert, bis du dich wieder verbindest.';

  @override
  String get setCheckCert => 'Serverzertifikat prüfen';

  @override
  String get setCertCheckFailed =>
      'Das Zertifikat des Servers kann nicht überprüft werden.';

  @override
  String get setCertUnchanged =>
      'Das Zertifikat hat sich seit der letzten Verbindung nicht geändert.';

  @override
  String get setCertChangedTitle => 'Neues Zertifikat erkannt';

  @override
  String setCertChangedBody(String oldFingerprint, String newFingerprint) {
    return 'Der Server zeigt einen anderen Fingerabdruck als den gespeicherten. Wenn du das Zertifikat selbst erneuert hast, bestätige, um weiter zu synchronisieren. Falls nicht, BRICH AB und überprüfe dein Netzwerk, bevor du es erneut versuchst.\n\nGespeicherter Fingerabdruck: $oldFingerprint\nAktueller Fingerabdruck: $newFingerprint';
  }

  @override
  String get setCertConfirmNew => 'Neues Zertifikat bestätigen';

  @override
  String get setCancel => 'Abbrechen';

  @override
  String get setShortcutPen => 'Stift';

  @override
  String get setShortcutUndo => 'Rückgängig';

  @override
  String get setShortcutBrush => 'Pinsel';

  @override
  String get setShortcutRedo => 'Wiederholen';

  @override
  String get setShortcutEraser => 'Radierer';

  @override
  String get setShortcutSelectAll => 'Alles auswählen';

  @override
  String get setShortcutLasso => 'Lasso';

  @override
  String get setShortcutCopy => 'Kopieren';

  @override
  String get setShortcutHand => 'Hand';

  @override
  String get setShortcutCut => 'Ausschneiden';

  @override
  String get setShortcutText => 'Text';

  @override
  String get setShortcutPaste => 'Einfügen';

  @override
  String get setShortcutShape => 'Form';

  @override
  String get setShortcutDuplicate => 'Duplizieren';

  @override
  String get setShortcutChangePage => 'Seite wechseln';

  @override
  String get setShortcutSave => 'Speichern';

  @override
  String get setShortcutFit => 'Einpassen';

  @override
  String get setShortcutCheatSheet => 'Kurzübersicht';

  @override
  String get setKeyboardShortcutsTitle => 'Tastenkürzel';

  @override
  String get setClearCache => 'Cache leeren';

  @override
  String get setClearCacheSub =>
      'Entfernt temporäre Dateien. Notizbücher bleiben unberührt.';

  @override
  String get setClear => 'Leeren';

  @override
  String get setTrash => 'Papierkorb';

  @override
  String get setTrashSub => 'Gelöschte Notizbücher, wiederherstellbar';

  @override
  String get setOpenTrash => 'Papierkorb öffnen';

  @override
  String get setClearCacheDone => 'Cache geleert.';

  @override
  String get setExportLibrary => 'Bibliothek exportieren';

  @override
  String get setExportLibrarySub =>
      'Speichert alle Notizbücher in einem einzigen ZIP-Archiv.';

  @override
  String get setExport => 'Exportieren';

  @override
  String get setExportLibraryEmpty => 'Keine Notizbücher zum Exportieren.';

  @override
  String get setExportLibraryInProgress => 'Export läuft…';

  @override
  String setExportLibraryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizbücher exportiert',
      one: '$count Notizbuch exportiert',
    );
    return '$_temp0.';
  }

  @override
  String setExportLibraryFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String setTrashPurgeTitle(String title) {
    return '„$title“ endgültig löschen?';
  }

  @override
  String get setTrashPurgeBody =>
      'Eine Wiederherstellung ist danach nicht mehr möglich.';

  @override
  String get setTrashPurge => 'Endgültig löschen';

  @override
  String get setTrashEmptyTitle => 'Papierkorb leeren?';

  @override
  String get setTrashEmptyBody =>
      'Alle Notizbücher im Papierkorb werden endgültig gelöscht.';

  @override
  String get setTrashEmpty => 'Papierkorb leeren';

  @override
  String get setTrashEmptyState => 'Der Papierkorb ist leer.';

  @override
  String setTrashDeletedAgo(String time) {
    return 'Gelöscht vor $time';
  }

  @override
  String get setTrashRestore => 'Wiederherstellen';

  @override
  String get setAdvancedIntro =>
      'Wiederherstellungswerkzeuge für die seltenen Fälle, in denen ein Notizbuch bei der Synchronisierung hängen bleibt. Nutze sie nur, wenn die Synchronisierung auch nach einem normalen „Sync erzwingen“ aus der Bibliothek weiter fehlschlägt.';

  @override
  String get setForceReloadTitle => 'Notizbuch vom Server neu laden';

  @override
  String get setForceReloadDesc =>
      'Lädt den gesamten Inhalt des Notizbuchs erneut aus dem Delta-Ordner des Servers und überschreibt die lokale Kopie. Nützlich, wenn die Seitenzahl falsch wirkt oder sich das Notizbuch nicht öffnen lässt. Auf dem Server gehen keine Daten verloren.';

  @override
  String setErrorGeneric(String error) {
    return 'Fehler: $error';
  }

  @override
  String setPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return '$_temp0';
  }

  @override
  String get setReload => 'Neu laden';

  @override
  String get setCloseNotebookFirst =>
      'Schließe das Notizbuch, bevor du es vom Server neu lädst.';

  @override
  String setReloadConfirmTitle(String title) {
    return '„$title“ neu laden?';
  }

  @override
  String get setReloadConfirmBody =>
      'Lädt Metadaten, Dokument, Seiten und Medien erneut aus dem Delta-Ordner des Servers. Die lokale Kopie wird ersetzt.\n\nNoch nicht synchronisierte lokale Änderungen gehen verloren. Fortfahren?';

  @override
  String setReloadInProgress(String title) {
    return '„$title“ wird neu geladen…';
  }

  @override
  String get setNotConnectedWebdav =>
      'Nicht mit einem WebDAV-Server verbunden.';

  @override
  String setReloadDone(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '$count Seite',
    );
    return '„$title“ neu geladen — $_temp0.';
  }

  @override
  String setReloadFailed(String error) {
    return 'Neu laden fehlgeschlagen: $error';
  }

  @override
  String get setAboutTagline => 'Eine Local-First-App für Handschrift.';

  @override
  String get setAboutOffline =>
      'Funktioniert offline; die WebDAV-Synchronisierung ist optional.';

  @override
  String setAboutVersion(String version, String commit) {
    return 'Version $version · Build $commit';
  }

  @override
  String get setReportProblem => 'Problem melden';

  @override
  String get setReportProblemSub =>
      'Kopiert das Fehlerprotokoll in die Zwischenablage, damit du es der Meldung anhängen kannst.';

  @override
  String get setCopyLog => 'Protokoll kopieren';

  @override
  String get setReportProblemEmpty => 'Keine Fehler protokolliert.';

  @override
  String get setCopyLogDone => 'Protokoll in die Zwischenablage kopiert.';

  @override
  String get onbTagline =>
      'Handschriftliche Notizen und freies Zeichnen, synchronisiert auf DEINEM Server. Wähle, wie du starten willst — änderbar ist es später jederzeit.';

  @override
  String get onbTryNowTitle => 'Gleich ausprobieren';

  @override
  String get onbTryNowSubtitle =>
      'Fang sofort an zu schreiben. Die Notizbücher bleiben auf diesem Gerät — kein Konto, kein Server.';

  @override
  String get onbConnectNextcloudTitle => 'Deine Nextcloud verbinden';

  @override
  String get onbConnectNextcloudSubtitle =>
      'Synchronisiere mit deinem eigenen WebDAV-/Nextcloud-Server und greife von allen Geräten darauf zu.';

  @override
  String get onbManagedServerTitle => 'Verwalteter AbelNotes-Server';

  @override
  String get onbManagedServerSubtitle =>
      'Kein eigener Server? Bald kannst du unseren nutzen, ganz ohne Einrichtung.';

  @override
  String get onbComingSoonBadge => 'Demnächst';

  @override
  String get onbDriveTitle => 'Mit Google Drive synchronisieren';

  @override
  String get onbDriveSubtitle =>
      'Nichts einzurichten: Deine Notizbücher werden über dein eigenes Google Drive synchronisiert.';

  @override
  String get driveSignInFailed =>
      'Die Google-Anmeldung wurde nicht abgeschlossen. Es wurde nichts geändert.';

  @override
  String get driveSignInCancelled => 'Anmeldung abgebrochen.';

  @override
  String get driveNotConfigured =>
      'Dieser Build enthält keine Google-Zugangsdaten, daher ist die Drive-Synchronisierung nicht verfügbar.';

  @override
  String get driveNoKeyring =>
      'Dieses System hat keinen sicheren Speicher, daher kann das Google-Konto nicht sicher abgelegt werden. Die Drive-Synchronisierung ist hier nicht verfügbar.';

  @override
  String get driveConnectedTitle => 'Google Drive verbunden';

  @override
  String get setSyncDriveTitle => 'Google Drive';

  @override
  String get setSyncDriveConnected =>
      'Notizbücher werden über dein Google Drive synchronisiert.';

  @override
  String get setSyncDriveNotConnected => 'Nicht verbunden.';

  @override
  String get setSyncDriveDesktopOnly => 'Vorerst nur am Computer verfügbar.';

  @override
  String get setDriveDisconnectTitle => 'Google Drive trennen?';

  @override
  String get setDriveDisconnectBody =>
      'Notizbücher, die bereits in deinem Drive liegen, bleiben dort — die App hört nur auf, sie zu synchronisieren. Die Notizbücher auf diesem Gerät bleiben unberührt.';

  @override
  String get setDriveDisconnectConfirm => 'Trennen';

  @override
  String get setSyncOneBackendNote =>
      'Notizbücher werden immer nur an einen Ort synchronisiert: deinen eigenen Server oder dein Google Drive.';

  @override
  String get setSyncSwitchTitle =>
      'Synchronisierung auf Google Drive umstellen?';

  @override
  String get setSyncSwitchBody =>
      'Deine Notizbücher bleiben auf diesem Gerät und werden in dein Google Drive hochgeladen. Die Kopien auf deinem Server bleiben, wo sie sind, erhalten aber ab dann keine Aktualisierungen mehr. Es wird nichts gelöscht.';

  @override
  String get setSyncSwitchConfirm => 'Auf Drive umstellen';

  @override
  String get setSyncInactiveNote =>
      'Eingerichtet, aber nicht in Verwendung: Die Synchronisierung läuft über das andere Ziel.';

  @override
  String libPendingUploadsDrive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizbücher noch nicht in Google Drive hochgeladen',
      one: '$count Notizbuch noch nicht in Google Drive hochgeladen',
    );
    return '$_temp0';
  }

  @override
  String libPendingUploadsServer(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizbücher noch nicht auf deinen Server hochgeladen',
      one: '$count Notizbuch noch nicht auf deinen Server hochgeladen',
    );
    return '$_temp0';
  }

  @override
  String get libPendingUploadsHint =>
      'Solange bleiben sie auf diesem Gerät. Lass die App einen Moment geöffnet.';

  @override
  String get libStorageFullDrive => 'Dein Google Drive ist voll';

  @override
  String get libStorageFullServer => 'Auf deinem Server ist kein Platz mehr';

  @override
  String get libStorageFullBody =>
      'Die Notizbücher bleiben auf diesem Gerät sicher, können aber erst hochgeladen werden, wenn du Platz schaffst. Google Drive teilt sich den Speicher mit Gmail und Fotos.';

  @override
  String get libStorageFullBodyServer =>
      'Die Notizbücher bleiben auf diesem Gerät sicher, können aber erst hochgeladen werden, wenn auf dem Server Platz frei wird.';

  @override
  String get libKeepOnDevice => 'Nur auf diesem Gerät behalten';

  @override
  String get libResumeSync => 'Dieses Notizbuch wieder synchronisieren';

  @override
  String get libLocalOnlyBadge => 'Nur hier';

  @override
  String get libKeepOnDeviceTitle =>
      'Dieses Notizbuch nur auf diesem Gerät behalten?';

  @override
  String get libKeepOnDeviceBody =>
      'Es wird nicht mehr hochgeladen, und andere Geräte erhalten es nicht mehr. Hier bleibt es voll nutzbar.';

  @override
  String get libKeepOnDeviceRemoveCopy =>
      'Auch die bereits hochgeladene Kopie löschen';

  @override
  String get libKeepOnDeviceConfirm => 'Nur hier behalten';

  @override
  String get libLocalOnlyDone => 'Nur auf diesem Gerät behalten.';

  @override
  String get libSyncResumedDone =>
      'Dieses Notizbuch wird wieder synchronisiert.';

  @override
  String get syncLocalOnlyTooltip => 'Nur auf diesem Gerät behalten';

  @override
  String get libFreeSpace => 'Speicherplatz auf diesem Gerät freigeben';

  @override
  String get libKeepOnThisDevice => 'Auf dieses Gerät laden';

  @override
  String get libFreeSpaceTitle =>
      'Dieses Notizbuch von diesem Gerät entfernen?';

  @override
  String get libFreeSpaceBody =>
      'Das Notizbuch bleibt auf dem Remote-Speicher und auf deinen anderen Geräten. Hier wird es zu einer Karte, die du antippen kannst, um es wieder zu laden. Bis dahin lässt es sich offline nicht öffnen, und die Suche durchsucht es nicht.';

  @override
  String get libFreeSpaceConfirm => 'Speicher freigeben';

  @override
  String libFreeSpaceDone(String size) {
    return 'Von diesem Gerät entfernt. $size freigegeben.';
  }

  @override
  String get libFreeSpaceNotSynced =>
      'Dieses Notizbuch enthält Änderungen, die der Remote-Speicher noch nicht hat. Sobald sie hochgeladen sind, ist es möglich.';

  @override
  String get libFreeSpaceOpenNotebook => 'Schließe zuerst das Notizbuch.';

  @override
  String get libKeepOnThisDeviceDone =>
      'Es wird wieder auf dieses Gerät geladen.';

  @override
  String get syncNotOnDeviceTooltip =>
      'Auf dem Remote-Speicher, nicht auf diesem Gerät';

  @override
  String get onbSyncQuestion => 'Notizen synchronisieren';

  @override
  String get onbSyncQuestionSub =>
      'Wähle, wo deine Notizbücher liegen. Das lässt sich später ändern.';

  @override
  String get onbDriveShort => 'Google Drive';

  @override
  String get onbNextcloudShort => 'Nextcloud / WebDAV';

  @override
  String get onbStartWithoutSync => 'Ohne Synchronisierung starten';

  @override
  String get onbDriveUnavailable => 'In diesem Build nicht verfügbar';

  @override
  String get onbLicenseNote =>
      'Mit dem Öffnen der App akzeptierst du die AGPL-3.0-Lizenz. „AbelNotes“ ist eine Marke des Projekts.';

  @override
  String get logConnectionFailed =>
      'Verbindung nicht möglich. Prüfe URL, Benutzername und Passwort.';

  @override
  String logConnectionError(String error) {
    return 'Verbindungsfehler: $error';
  }

  @override
  String get logCertificateChanged =>
      'Das Zertifikat des Servers hat sich seit der letzten Verbindung geändert. Wenn das von dir kam (z. B. Zertifikatserneuerung), bestätige den neuen Fingerabdruck unter Einstellungen > Synchronisierung.';

  @override
  String get logCertConfirmTitle => 'Identität des Servers prüfen';

  @override
  String get logCertConfirmBody =>
      'Erste Verbindung zu diesem Server. Vergleiche diesen Fingerabdruck mit dem deines Servers (z. B. über die Kommandozeile), bevor du fortfährst:';

  @override
  String get logCertConfirmTrust => 'Ich vertraue ihm, fortfahren';

  @override
  String get logBackTooltip => 'Zurück';

  @override
  String get logTitle => 'Deine Nextcloud verbinden';

  @override
  String get logSubtitle =>
      'Jeder WebDAV-/Nextcloud-Server (VPS, selbst gehostet, LAN). Keine Cloud von Dritten.';

  @override
  String get logServerUrlLabel => 'Server-URL';

  @override
  String get logServerUrlHint => 'https://cloud.example.com';

  @override
  String get logServerUrlRequired => 'Gib die Server-URL ein';

  @override
  String get logServerUrlInvalid => 'Muss mit http:// oder https:// beginnen';

  @override
  String get logUsernameLabel => 'Benutzername';

  @override
  String get logUsernameRequired => 'Benutzername erforderlich';

  @override
  String get logPasswordLabel => 'Passwort / App-Passwort';

  @override
  String get logPasswordRequired => 'Passwort erforderlich';

  @override
  String get logAppPasswordHint =>
      'Empfohlen: ein App-Passwort, erzeugt in den Nextcloud-Einstellungen.';

  @override
  String get logServerTypeNextcloud => 'Nextcloud / ownCloud';

  @override
  String get logServerTypeWebdav => 'Anderes WebDAV';

  @override
  String get logServerUrlHintWebdav => 'https://dav.example.com/ordner';

  @override
  String get logWebdavExperimental =>
      'Generische WebDAV-Backends (Synology, Seafile, rclone…) sind experimentell: Nur Nextcloud ist vollständig getestet. Halte Sicherungen deiner Notizbücher bereit.';

  @override
  String get logWebdavUrlHint =>
      'Vollständige WebDAV-URL samt Pfad — z. B. Synology https://nas:5006/home, Seafile https://server/seafdav. Das Teilen per Link ist bei generischem WebDAV nicht verfügbar.';

  @override
  String get logConnectButton => 'Verbinden';

  @override
  String get chromeBackToLibraryTooltip => 'Zurück zur Bibliothek';

  @override
  String get chromeLibrary => 'Bibliothek';

  @override
  String get chromeUnsaved => 'Nicht gespeichert';

  @override
  String get chromeMouseDrawsTooltip =>
      'Maus: zeichnet — tippen, um sie zum Auswählen zu verwenden';

  @override
  String get chromeMouseSelectsTooltip =>
      'Maus: Auswahl — tippen, um mit der Maus zu zeichnen';

  @override
  String get chromeTouchDrawsTooltip =>
      'Finger: zeichnet — tippen, um damit zu navigieren';

  @override
  String get chromeTouchPansTooltip =>
      'Finger: navigiert — tippen, um mit dem Finger zu zeichnen';

  @override
  String get chromeUndo => 'Rückgängig';

  @override
  String get chromeRedo => 'Wiederholen';

  @override
  String get chromeAllPages => 'Alle Seiten';

  @override
  String chromePageIndicator(String current, int total) {
    return '$current / $total';
  }

  @override
  String get chromeAddPage => 'Seite hinzufügen';

  @override
  String get chromeSymbols => 'Symbole';

  @override
  String get chromeExport => 'Exportieren';

  @override
  String get chromeMore => 'Mehr';

  @override
  String get chromeMoreEllipsis => 'Mehr…';

  @override
  String get chromeToolPen => 'Stift · P';

  @override
  String get chromeToolHighlighter => 'Textmarker';

  @override
  String get chromeToolEraser => 'Radierer · E';

  @override
  String get chromeToolLasso => 'Lasso · L';

  @override
  String get chromeToolText => 'Text · T';

  @override
  String get chromeToolLaser => 'Laser';

  @override
  String get chromeToolPan => 'Hand · H';

  @override
  String get chromeDragToMoveBar =>
      'Ziehen, um die Werkzeugleiste zu verschieben';

  @override
  String get chromeShapeGuessOn => 'Auto-Form · an';

  @override
  String get chromeShapeGuessOff => 'Auto-Form · aus';

  @override
  String get chromeLabelPen => 'Stift';

  @override
  String get chromeLabelBallpoint => 'Kugelschreiber';

  @override
  String get chromeLabelBrush => 'Pinsel';

  @override
  String get chromeLabelCalligraphy => 'Kalligrafie';

  @override
  String get chromeLabelEraser => 'Radierer';

  @override
  String get chromeLabelLasso => 'Lasso';

  @override
  String get chromeLabelText => 'Text';

  @override
  String get chromeLabelShape => 'Form';

  @override
  String get chromeLabelImage => 'Bild';

  @override
  String get chromeLabelPan => 'Hand';

  @override
  String get chromePresetsSection => 'Voreinstellungen';

  @override
  String get chromePresetHint => 'Lang drücken zum Speichern/Löschen';

  @override
  String get chromeColorSection => 'Farbe';

  @override
  String get chromeColorEditHint => 'Eine Farbe lang drücken, um sie zu ändern';

  @override
  String get chromeThicknessSection => 'Stärke';

  @override
  String chromeThicknessPx(String value) {
    return '$value px';
  }

  @override
  String get chromePreview => 'Vorschau';

  @override
  String get chromeModeSection => 'Modus';

  @override
  String get chromeEraserPerArea => 'Nach Fläche';

  @override
  String get chromeEraserPerStroke => 'Nach Strich';

  @override
  String get chromeSizeSection => 'Größe';

  @override
  String get chromeSizeSmall => 'S';

  @override
  String get chromeSizeMedium => 'M';

  @override
  String get chromeSizeLarge => 'L';

  @override
  String get chromePresetOverwrite => 'Mit aktueller überschreiben';

  @override
  String get chromePresetClearSlot => 'Platz leeren';

  @override
  String get chromeNoPages => 'Keine Seiten';

  @override
  String get chromeHidePageBar => 'Seitenleiste ausblenden';

  @override
  String get chromeShowPageBar => 'Seitenleiste einblenden';

  @override
  String chromePrevPageTooltip(int number) {
    return 'Vorherige Seite $number — tippen, um zurückzugehen';
  }

  @override
  String chromePageOfChapterTooltip(int number, int globalNumber) {
    return 'Seite $number des Kapitels · Seite $globalNumber des Notizbuchs';
  }

  @override
  String chromePageTooltip(int number) {
    return 'Seite $number';
  }

  @override
  String get chromeHexLabel => 'Hexadezimal';

  @override
  String get chromeCancel => 'Abbrechen';

  @override
  String get chromeApply => 'Anwenden';

  @override
  String get pmNone => 'Keines';

  @override
  String get pmCreateChapterFirst => 'Erstelle zuerst mindestens ein Kapitel.';

  @override
  String pmAssignChapterCount(int count) {
    return 'Kapitel zuweisen ($count S.)';
  }

  @override
  String pmDeletePagesConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten löschen?',
      one: '1 Seite löschen?',
    );
    return '$_temp0';
  }

  @override
  String get pmActionCannotBeUndone =>
      'Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get pmCancel => 'Abbrechen';

  @override
  String get pmDelete => 'Löschen';

  @override
  String pmPagesCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Seiten ausgeschnitten — öffne das Zielnotizbuch zum Einfügen.',
      one: '1 Seite ausgeschnitten — öffne das Zielnotizbuch zum Einfügen.',
    );
    return '$_temp0';
  }

  @override
  String pmPagesCutSkipped(int count, int skipped) {
    return '$count Seiten ausgeschnitten ($skipped noch nicht geladen, übersprungen) — öffne das Zielnotizbuch zum Einfügen.';
  }

  @override
  String pmSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get pmSelectAllButton => 'Alle';

  @override
  String get pmClearSelection => 'Auswahl aufheben';

  @override
  String pmPagesCount(int count) {
    return 'Seiten ($count)';
  }

  @override
  String pmPagesFilteredCount(int visible, int total) {
    return 'Seiten ($visible/$total)';
  }

  @override
  String get pmGoToPageTooltip => 'Zu Seite springen…';

  @override
  String get pmExitSelection => 'Auswahl beenden';

  @override
  String get pmSelectPages => 'Seiten auswählen';

  @override
  String get pmPastePages => 'Seiten einfügen';

  @override
  String pmPagesPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten eingefügt.',
      one: '1 Seite eingefügt.',
    );
    return '$_temp0';
  }

  @override
  String get pmAddPage => 'Seite hinzufügen';

  @override
  String get pmClose => 'Schließen';

  @override
  String get pmNewChapter => 'Neues Kapitel';

  @override
  String get pmChapterNameHint => 'Kapitelname';

  @override
  String pmPageDeleted(int number) {
    return 'Seite $number gelöscht';
  }

  @override
  String get pmUndo => 'Rückgängig';

  @override
  String get pmAssignChapter => 'Kapitel zuweisen';

  @override
  String get pmRename => 'Umbenennen';

  @override
  String get pmRenameChapter => 'Kapitel umbenennen';

  @override
  String get pmDeleteChapter => 'Kapitel löschen';

  @override
  String pmDeleteChapterConfirm(String title) {
    return '„$title“ löschen? Die enthaltenen Seiten bleiben erhalten, aber ohne Kapitel.';
  }

  @override
  String get pmGoToPage => 'Zu Seite springen';

  @override
  String pmPageRangeHint(int max) {
    return '1–$max';
  }

  @override
  String get pmGo => 'Los';

  @override
  String get pmOk => 'OK';

  @override
  String pmCountPagesShort(int count) {
    return '$count S.';
  }

  @override
  String get pmChapter => 'Kapitel';

  @override
  String get pmCut => 'Ausschneiden';

  @override
  String get pmInsertBefore => 'Davor einfügen';

  @override
  String get pmInsertAfter => 'Danach einfügen';

  @override
  String get pmDuplicate => 'Duplizieren';

  @override
  String get pmMoveTo => 'Auf Seite verschieben…';

  @override
  String get pmMove => 'Verschieben';

  @override
  String get pmMoveToPage => 'Auf Seite verschieben';

  @override
  String get pmChapterEllipsis => 'Kapitel…';

  @override
  String pmPageChapterLabel(int number, String chapter) {
    return '$number • $chapter';
  }

  @override
  String get pmCorruptAssetTooltip =>
      'Medium auf dem Server beschädigt (abgeschnitten) — importiere das ursprüngliche PDF erneut, um es wiederherzustellen';

  @override
  String get pmLoadingImageTooltip => 'Bild wird vom Server geladen…';

  @override
  String get tedInsertTextTitle => 'Text einfügen';

  @override
  String get tedEditTextTitle => 'Text bearbeiten';

  @override
  String get tedBoldTooltip => 'Fett (Strg+B)';

  @override
  String get tedItalicTooltip => 'Kursiv (Strg+I)';

  @override
  String get tedUnderlineTooltip => 'Unterstrichen (Strg+U)';

  @override
  String get tedStrikethroughTooltip => 'Durchgestrichen';

  @override
  String get tedAlignLeft => 'Links';

  @override
  String get tedAlignCenter => 'Zentriert';

  @override
  String get tedAlignRight => 'Rechts';

  @override
  String get tedWriteHereHint => 'Hier schreiben…';

  @override
  String get tedCancel => 'Abbrechen';

  @override
  String get tedInsert => 'Einfügen';

  @override
  String get cropTitle => 'Bild zuschneiden';

  @override
  String get cropCancel => 'Abbrechen';

  @override
  String get cropConfirm => 'Zuschneiden';

  @override
  String get imgFontSmaller => 'Kleinerer Text';

  @override
  String get imgFontLarger => 'Größerer Text';

  @override
  String get imgCrop => 'Zuschneiden';

  @override
  String get imgCopy => 'Kopieren';

  @override
  String get imgUnlock => 'Entsperren';

  @override
  String get imgLock => 'Sperren';

  @override
  String get imgDelete => 'Löschen';

  @override
  String get imgDeselect => 'Auswahl aufheben';

  @override
  String get imgMoreActions => 'Weitere Aktionen';

  @override
  String get imgBringToFront => 'In den Vordergrund';

  @override
  String get imgSendToBack => 'In den Hintergrund';

  @override
  String get imgComment => 'Kommentar';

  @override
  String get imgFlipHChecked => 'H spiegeln ✓';

  @override
  String get imgFlipH => 'H spiegeln';

  @override
  String get imgCut => 'Ausschneiden';

  @override
  String get syncOkTooltip => 'Synchronisiert';

  @override
  String get syncPendingTooltip => 'Synchronisierung…';

  @override
  String get syncOfflineTooltip => 'Offline';

  @override
  String get syncConflictTooltip => 'Konflikt';

  @override
  String get confDecideLater => 'Später entscheiden';

  @override
  String confTitlePageDeletedElsewhere(int pageNumber) {
    return 'Seite $pageNumber anderswo gelöscht';
  }

  @override
  String confTitleConflictPage(int pageNumber) {
    return 'Konflikt — Seite $pageNumber';
  }

  @override
  String get confDeletionExplainer =>
      'Du hast diese Seite bearbeitet, aber ein anderes Gerät hat sie gelöscht. Möchtest du sie behalten oder löschen?';

  @override
  String get confKeepPage => 'Seite behalten';

  @override
  String get confLocalYours => 'Lokal (deine)';

  @override
  String get confRemoteOtherDevice => 'Remote (anderes Gerät)';

  @override
  String get confKeepAllLocal => 'Alle lokalen behalten';

  @override
  String get confAcceptAllRemote => 'Alle Remote-Versionen übernehmen';

  @override
  String confProgressIndicator(int current, int total, num decided) {
    String _temp0 = intl.Intl.pluralLogic(
      decided,
      locale: localeName,
      other: '$decided entschieden',
      one: '$decided entschieden',
    );
    return '$current / $total  ($_temp0)';
  }

  @override
  String get confApplyChoices => 'Auswahl anwenden';

  @override
  String confDecidedProgress(int decided, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'entschieden',
      one: 'entschieden',
    );
    return '$decided/$total $_temp0';
  }

  @override
  String get confJumpToConflict => 'Zum Konflikt springen';

  @override
  String confJumpDecidedCount(int decided, int total) {
    return '$decided/$total entschieden';
  }

  @override
  String confJumpItemPage(int pageNumber) {
    return 'S. $pageNumber';
  }

  @override
  String confJumpItemPageWithChapter(int pageNumber, String chapterName) {
    return 'S. $pageNumber — $chapterName';
  }

  @override
  String get confDismissDialogTitle => 'Abbrechen?';

  @override
  String get confDismissDialogBody =>
      'Nicht angewendete Entscheidungen gehen verloren. Die lokale Version wird beibehalten.';

  @override
  String get confContinue => 'Weiter';

  @override
  String get confCancel => 'Abbrechen';

  @override
  String get confModifiedJustNow => 'Gerade eben';

  @override
  String confModifiedMinutesAgo(int minutes) {
    return 'vor $minutes Min.';
  }

  @override
  String confModifiedHoursAgo(num hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'vor $hours Stunden',
      one: 'vor $hours Stunde',
    );
    return '$_temp0';
  }

  @override
  String get confDeletePage => 'Seite löschen';

  @override
  String get confAsOnOtherDevice => 'Wie auf dem anderen Gerät';

  @override
  String get symNewLibraryTitle => 'Neue Bibliothek';

  @override
  String get symNewLibraryHint => 'Gib den Namen der Bibliothek ein';

  @override
  String get symRenameLibraryTitle => 'Bibliothek umbenennen';

  @override
  String get symNewNameHint => 'Neuer Name';

  @override
  String get symDeleteLibraryTitle => 'Bibliothek löschen';

  @override
  String symDeleteLibraryConfirm(String name) {
    return '„$name“ und alle enthaltenen Symbole löschen?';
  }

  @override
  String get symCancel => 'Abbrechen';

  @override
  String get symDelete => 'Löschen';

  @override
  String get symRenameSymbolTitle => 'Symbol umbenennen';

  @override
  String get symPanelTitle => 'Symbolbibliotheken';

  @override
  String get symNoLibraries => 'Keine Bibliotheken';

  @override
  String get symNew => 'Neu';

  @override
  String get symSelectLibrary => 'Bibliothek auswählen';

  @override
  String get symNoSymbolsHint =>
      'Keine Symbole\nWähle Elemente mit dem Lasso aus und drücke ✚';

  @override
  String get symLassoSaveHint =>
      'Elemente mit dem Lasso auswählen → ✚, um sie in der aktiven Bibliothek zu speichern';

  @override
  String get symRename => 'Umbenennen';

  @override
  String get symInsert => 'Einfügen';

  @override
  String get symOk => 'OK';

  @override
  String get rcbBannerTitle => 'Änderungen von einem anderen Gerät';

  @override
  String get rcbSeeDetails => 'Details ansehen';

  @override
  String get rcbDismiss => 'Ignorieren';

  @override
  String get rcbIncomingChanges => 'Eingehende Änderungen';

  @override
  String get rcbTapPageHint =>
      'Tippe auf eine Seite, um sie zu übernehmen und dorthin zu springen';

  @override
  String rcbNewImagesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue Bilder',
      one: '1 neues Bild',
    );
    return '$_temp0';
  }

  @override
  String get rcbKeepMine => 'Meine behalten';

  @override
  String get rcbApplyAll => 'Alle übernehmen';

  @override
  String get rcbBadgeNew => 'NEU';

  @override
  String get rcbBadgeModified => 'GEÄNDERT';

  @override
  String rcbPageTitle(int pageNumber) {
    return 'Seite $pageNumber';
  }

  @override
  String get rcbContentUpdated => 'Inhalt aktualisiert';

  @override
  String rcbSummaryModifiedPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten geändert',
      one: '$count Seite geändert',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryNewPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count neue',
      one: '$count neue',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryImages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bilder',
      one: '$count Bild',
    );
    return '$_temp0';
  }

  @override
  String get rcbChangesDetected => 'Änderungen erkannt';

  @override
  String get nbUntitled => 'Ohne Titel';

  @override
  String get nbDefaultChapterTitle => 'Kapitel 1';

  @override
  String get nbOpeningNotebook => 'Notizbuch wird geöffnet…';

  @override
  String get nbNoLocalCopyOffline =>
      'Es gibt keine lokale Kopie dieses Notizbuchs, und du bist mit keinem Server verbunden, um es herunterzuladen.';

  @override
  String nbOpenFailed(String error) {
    return 'Öffnen nicht möglich: $error';
  }

  @override
  String get nbSortModifiedDesc => 'Geändert (neueste zuerst)';

  @override
  String get nbSortModifiedAsc => 'Geändert (älteste zuerst)';

  @override
  String get nbSortTitleAsc => 'Titel A→Z';

  @override
  String get nbSortTitleDesc => 'Titel Z→A';

  @override
  String get nbSortCreatedDesc => 'Erstellt (neueste zuerst)';

  @override
  String get nbSortCreatedAsc => 'Erstellt (älteste zuerst)';

  @override
  String get nbSortColorGroup => 'Einbandfarbe';

  @override
  String cvFormatTooNew(int fileVersion, int supportedVersion) {
    return 'Dieses Notizbuch verwendet ein neueres Format (v$fileVersion, unterstützt: v$supportedVersion). Aktualisiere AbelNotes, um es zu öffnen.';
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
  String get chromeLabelHighlighter => 'Textmarker';

  @override
  String get chromeLabelLaser => 'Laser';

  @override
  String get importSourceTitle => 'In die Bibliothek importieren';

  @override
  String get importSourceNcnote => '.abelnote-Notizbuch';

  @override
  String get importSourceObsidian => 'Obsidian-Vault';

  @override
  String get importSourceObsidianHint => 'Ordner mit Markdown-Dateien';

  @override
  String get importSourceNotion => 'Notion-Export';

  @override
  String get importSourceNotionHint => '.zip-Datei (Markdown und CSV)';

  @override
  String get importPhaseScanning => 'Quelle wird analysiert…';

  @override
  String importPhaseParsing(int current, int total) {
    return 'Datei $current von $total wird gelesen';
  }

  @override
  String importPhasePaginating(int current, int total) {
    return 'Kapitel $current von $total wird gesetzt';
  }

  @override
  String get importPhasePackaging => 'Notizbuch wird erstellt…';

  @override
  String get importCancel => 'Abbrechen';

  @override
  String get importCancelled => 'Import abgebrochen';

  @override
  String importReportTitle(int count) {
    return '$count Warnungen beim Import';
  }

  @override
  String get importReportCopy => 'Kopieren';

  @override
  String get importReportClose => 'Schließen';

  @override
  String get importSourceOneNote => 'OneNote-Datei';

  @override
  String get importSourceOneNoteHint =>
      '.one-Abschnitt oder .onetoc2-Notizbuch';

  @override
  String get setOpenSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get setOpenSourceLicensesSub =>
      'In der App enthaltene Komponenten von Dritten';

  @override
  String get csBackToContent => 'Zurück zum Inhalt';

  @override
  String get setLanguageGerman => 'Deutsch';

  @override
  String get setLanguageFrench => 'Français';
}
