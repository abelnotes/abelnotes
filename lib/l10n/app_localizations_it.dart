// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get csPdfTextCopied => 'Testo copiato';

  @override
  String csCopyFailed(String error) {
    return 'Copia non riuscita: $error';
  }

  @override
  String get csCopy => 'Copia';

  @override
  String get csSyncInProgress => 'Sincronizzazione in corso…';

  @override
  String get csSaved => 'Salvato!';

  @override
  String csErrorGeneric(String error) {
    return 'Errore: $error';
  }

  @override
  String get csSelectionCopied => 'Selezione copiata';

  @override
  String get csSelectionCut => 'Selezione tagliata';

  @override
  String get csShortcutsTitle => 'Scorciatoie tastiera';

  @override
  String get csShortcutGroupGeneral => 'Generale';

  @override
  String get csSaveNow => 'Salva ora';

  @override
  String get csShortcutUndo => 'Annulla';

  @override
  String get csShortcutRedo => 'Ripeti';

  @override
  String get csSelectAll => 'Seleziona tutto';

  @override
  String get csShortcutResetZoom => 'Azzera zoom';

  @override
  String get csShortcutDeselect => 'Deseleziona / annulla';

  @override
  String get csShortcutThisGuide => 'Questa guida';

  @override
  String get csShortcutGroupClipboard => 'Appunti';

  @override
  String get csShortcutCopySelection => 'Copia selezione';

  @override
  String get csShortcutCutSelection => 'Taglia selezione';

  @override
  String get csPaste => 'Incolla';

  @override
  String get csShortcutDuplicateSelection => 'Duplica selezione';

  @override
  String get csShortcutKeyDeleteBackspace => 'Canc / Backspace';

  @override
  String get csShortcutDeleteElementOrSelection =>
      'Elimina elemento o selezione';

  @override
  String get csShortcutGroupTools => 'Strumenti';

  @override
  String get csToolPen => 'Penna';

  @override
  String get csToolBrush => 'Pennello';

  @override
  String get csToolEraser => 'Gomma';

  @override
  String get csToolLasso => 'Lazo';

  @override
  String get csToolHand => 'Mano / sposta';

  @override
  String get csToolText => 'Testo';

  @override
  String get csToolShape => 'Forma';

  @override
  String get csClose => 'Chiudi';

  @override
  String get csUnsavedChangesTitle => 'Modifiche non salvate';

  @override
  String get csUnsavedChangesBody => 'Vuoi salvare prima di uscire?';

  @override
  String get csDiscard => 'Scarta';

  @override
  String get csCancel => 'Annulla';

  @override
  String get csSave => 'Salva';

  @override
  String get csOpeningLink => 'Apertura link…';

  @override
  String get csCannotOpenLink => 'Impossibile aprire il link';

  @override
  String get csCameraUnavailable =>
      'Fotocamera non disponibile su questo dispositivo';

  @override
  String get csPhotoCaptureFailed => 'Impossibile scattare la foto';

  @override
  String get csPdfRasterizing => 'Rasterizzazione PDF in corso…';

  @override
  String csPdfImportProgress(int done, int total) {
    return 'Importazione PDF: $done/$total';
  }

  @override
  String get csPdfReadFailed =>
      'Impossibile leggere il PDF: nessuna pagina trovata';

  @override
  String csPdfImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return 'PDF importato: $_temp0';
  }

  @override
  String csPdfImportError(String error) {
    return 'Errore importazione PDF: $error';
  }

  @override
  String get csNoNotebookOpen => 'Nessun taccuino aperto';

  @override
  String get csNoPages => 'Nessuna pagina';

  @override
  String get csRetrySync => 'Riprova sync';

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine sostituite con pagine vuote',
      one: '$count pagina sostituita con una vuota',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'Elimina pagina';

  @override
  String csMissingDownloadingTitle(int page) {
    return 'Scarico la pagina $page…';
  }

  @override
  String get csMissingDownloadingBody =>
      'Questa pagina non è ancora su questo dispositivo. È sul server: la sto scaricando e apparirà qui appena pronta.';

  @override
  String csMissingOfflineTitle(int page) {
    return 'Pagina $page non ancora scaricata';
  }

  @override
  String get csMissingOfflineBody =>
      'Questa pagina non è ancora su questo dispositivo e il server ora non risponde. Riprovo da solo: apparirà appena torna la connessione. Nel frattempo non viene modificato niente.';

  @override
  String csMissingGoneTitle(int page) {
    return 'Pagina $page mancante';
  }

  @override
  String get csMissingGoneBody =>
      'Il file di questa pagina non c\'è né su questo dispositivo né sul server. Se un altro dispositivo mostra ancora la pagina, aprila lì: verrà ricaricata sul server e tornerà anche qui.';

  @override
  String get csMissingNoServerBody =>
      'Il file di questa pagina non c\'è su questo dispositivo e il quaderno non è sincronizzato con un server.';

  @override
  String get csMissingPreviousPage => 'Pagina precedente';

  @override
  String get csMissingLastResort =>
      'Solo se sei sicuro che la pagina non esiste più da nessuna parte:';

  @override
  String get csMissingReplaceAction => 'Sostituisci con pagina vuota';

  @override
  String csMissingReplaceAll(int count) {
    return 'Sostituisci tutte ($count)';
  }

  @override
  String csMissingReplaceConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sostituire $count pagine con pagine vuote?',
      one: 'Sostituire la pagina con una vuota?',
    );
    return '$_temp0';
  }

  @override
  String csMissingReplaceConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Le pagine vuote vengono sincronizzate su tutti i dispositivi. Se gli originali esistono ancora su un altro dispositivo, verranno sovrascritti.',
      one:
          'La pagina vuota viene sincronizzata su tutti i dispositivi. Se l\'originale esiste ancora su un altro dispositivo, verrà sovrascritta.',
    );
    return '$_temp0';
  }

  @override
  String get csMissingDeleteConfirmTitle => 'Eliminare la pagina?';

  @override
  String get csMissingDeleteConfirmBody =>
      'La pagina viene tolta dal quaderno su tutti i dispositivi sincronizzati.';

  @override
  String csSyncProgressCount(int done, int total) {
    return 'Sincronizzazione $done/$total';
  }

  @override
  String get csSyncing => 'Sincronizzazione…';

  @override
  String csShapeRecognizedLabel(String shape) {
    return 'Forma: $shape';
  }

  @override
  String get csConfirmShapeSemantics => 'Conferma forma riconosciuta';

  @override
  String get csConfirm => 'Conferma';

  @override
  String get csCancelShapeSemantics => 'Annulla forma riconosciuta';

  @override
  String csTapToPlaceSymbol(String name) {
    return 'Tocca per posizionare: $name';
  }

  @override
  String get csCancelSymbolInsertSemantics => 'Annulla inserimento simbolo';

  @override
  String get csTapToPlaceCopy => 'Tocca per posizionare la copia';

  @override
  String get csCancelPasteSemantics => 'Annulla incolla';

  @override
  String get csNewPage => 'Nuova pagina';

  @override
  String get csImageCopied => 'Immagine copiata';

  @override
  String get csImageCut => 'Immagine tagliata';

  @override
  String get csImageCommentTitle => 'Commento immagine';

  @override
  String get csAddCommentHint => 'Aggiungi un commento...';

  @override
  String get csRemove => 'Rimuovi';

  @override
  String get csCut => 'Taglia';

  @override
  String get csDuplicate => 'Duplica';

  @override
  String get csSelectionDuplicated => 'Selezione duplicata';

  @override
  String get csChangeColor => 'Cambia colore';

  @override
  String get csThickness => 'Spessore';

  @override
  String get csDelete => 'Elimina';

  @override
  String get csMore => 'Altro';

  @override
  String get csPresentationMode => 'Modalità presentazione';

  @override
  String get csPresentationModeSub =>
      'Schermo intero, senza strumenti — ideale per mostrare le pagine';

  @override
  String get csRecognizeHandwriting => 'Riconosci calligrafia';

  @override
  String get csRecognizeHandwritingSub =>
      'Converte l\'inchiostro in testo cercabile (sul dispositivo)';

  @override
  String get csRecognizeInProgress => 'Riconoscimento in corso…';

  @override
  String get csRecognizeNothing => 'Nessun testo riconosciuto.';

  @override
  String csRecognizeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count righe riconosciute',
      one: '$count riga riconosciuta',
    );
    return '$_temp0.';
  }

  @override
  String csRecognizeFailed(String error) {
    return 'Riconoscimento fallito: $error';
  }

  @override
  String get csShareLink => 'Condividi con link';

  @override
  String get csShareLinkSub =>
      'Carica un PDF sul tuo Nextcloud e genera un link pubblico';

  @override
  String get csShareLinkInProgress => 'Creazione link in corso…';

  @override
  String get csShareLinkTitle => 'Link pubblico';

  @override
  String get csShareLinkBody =>
      'Chiunque abbia questo link può vedere il PDF. Revocabile dal tuo Nextcloud.';

  @override
  String get csShareLinkCopied => 'Link copiato negli appunti.';

  @override
  String csShareLinkFailed(String error) {
    return 'Condivisione fallita: $error';
  }

  @override
  String get csCopyLink => 'Copia link';

  @override
  String get csShare => 'Condividi';

  @override
  String get csRevokeLink => 'Revoca link';

  @override
  String get csRevokeLinkDone => 'Link revocato.';

  @override
  String get csShareLinkUpdate => 'Aggiorna PDF condiviso';

  @override
  String get csShareLinkUpdated => 'PDF aggiornato.';

  @override
  String get csChangeSelectionColor => 'Cambia colore selezione';

  @override
  String get csSelectionThickness => 'Spessore selezione';

  @override
  String csWidthPx(String width) {
    return '$width px';
  }

  @override
  String get csFlipHorizontal => 'Rifletti orizzontalmente';

  @override
  String get csFlipVertical => 'Rifletti verticalmente';

  @override
  String get csCopyAsImage => 'Copia come immagine';

  @override
  String get csPasteInAnotherNotebook => 'Incolla in un altro taccuino…';

  @override
  String get csKeyDelete => 'Canc';

  @override
  String get csCreateSymbol => 'Crea simbolo';

  @override
  String get csSelect => 'Seleziona';

  @override
  String get csImportFile => 'Importa file…';

  @override
  String get csTakePhoto => 'Scatta foto';

  @override
  String get csInsertText => 'Inserisci testo';

  @override
  String csInsertSymbolCount(int count) {
    return 'Inserisci simbolo ($count)';
  }

  @override
  String get csClearPage => 'Cancella pagina';

  @override
  String get csExportPng => 'Esporta PNG';

  @override
  String get csExportPdf => 'Esporta PDF';

  @override
  String get csClearPageConfirmBody =>
      'Tutti gli elementi di questa pagina saranno eliminati. Continuare?';

  @override
  String get csClear => 'Cancella';

  @override
  String get csCreateSymbolTitle => 'Crea simbolo riutilizzabile';

  @override
  String get csSymbolNameLabel => 'Nome simbolo';

  @override
  String get csLibraryLabel => 'Libreria:';

  @override
  String get csNoLibraryNotice =>
      'Nessuna libreria esistente. Verrà creata una libreria \"Simboli\".';

  @override
  String get csCreate => 'Crea';

  @override
  String csSymbolCreated(String name) {
    return 'Simbolo \"$name\" creato!';
  }

  @override
  String csSaveFileDialogTitle(String fileName) {
    return 'Salva $fileName';
  }

  @override
  String get csExportCurrentPagePng => 'Pagina corrente (PNG)';

  @override
  String get csExportCurrentChapter => 'Capitolo corrente';

  @override
  String get csExportEntireNotebook => 'Quaderno intero';

  @override
  String csExportingPages(int count) {
    return 'Esportazione $count pagine...';
  }

  @override
  String csChooseFolderForImages(int count) {
    return 'Scegli cartella per le $count immagini';
  }

  @override
  String csPngExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return 'PNG esportato ($_temp0)';
  }

  @override
  String csExportError(String error) {
    return 'Errore export: $error';
  }

  @override
  String get csExportCurrentPage => 'Pagina corrente';

  @override
  String csGeneratingPdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return 'Generazione PDF ($_temp0)...';
  }

  @override
  String csPdfExportError(String error) {
    return 'Errore export PDF: $error';
  }

  @override
  String csPdfExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return 'PDF esportato: $_temp0';
  }

  @override
  String get csChapterSeparatorEyebrow => 'CAPITOLO';

  @override
  String get csSelectionCopiedAsImage => 'Selezione copiata come immagine';

  @override
  String csCopyImageError(String error) {
    return 'Errore copia immagine: $error';
  }

  @override
  String get csExport => 'Esporta';

  @override
  String csPageNumber(int number) {
    return 'Pagina $number';
  }

  @override
  String csPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return '$_temp0';
  }

  @override
  String get csExportChapterTitle => 'Esporta capitolo';

  @override
  String get csExportNotebookTitle => 'Esporta quaderno intero';

  @override
  String get csChapterSeparatorQuestion =>
      'Inserire una pagina separatore prima di ogni capitolo?';

  @override
  String get csYesWithSeparators => 'Sì, con separatori';

  @override
  String get csNoPagesOnly => 'No, solo le pagine';

  @override
  String csTotalPages(int count) {
    return 'Pagine totali: $count';
  }

  @override
  String csFromPage(int page) {
    return 'Da pagina: $page';
  }

  @override
  String csToPage(int page) {
    return 'A pagina: $page';
  }

  @override
  String csWillExportPages(int count, int start, int end) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saranno esportate $count pagine ($start–$end)',
      one: 'Sarà esportata $count pagina ($start–$end)',
    );
    return '$_temp0';
  }

  @override
  String csChapterLabelWithCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return '$title ($_temp0)';
  }

  @override
  String get csGoToPage => 'Vai alla pagina';

  @override
  String get csDuplicatePage => 'Duplica pagina';

  @override
  String get csNewPageAfter => 'Nuova pagina dopo';

  @override
  String get csDeletePageConfirmTitle => 'Eliminare la pagina?';

  @override
  String csDeletePageConfirmBody(int number) {
    return 'La pagina $number e tutto il suo contenuto verranno eliminati.';
  }

  @override
  String get csExportAsPdf => 'Esporta come PDF';

  @override
  String get csExportAsPng => 'Esporta come PNG';

  @override
  String get csExportAsNcnote => 'Esporta come .abelnote (nativo)';

  @override
  String get csExportNcnoteSubtitle =>
      'Formato nativo, qualità vettoriale piena (per backup o trasferimento)';

  @override
  String get csGeneratingNcnote => 'Generazione .abelnote in corso…';

  @override
  String csNcnoteExported(String size) {
    return '.abelnote esportato ($size KB)';
  }

  @override
  String csNcnoteExportError(String error) {
    return 'Errore export .abelnote: $error';
  }

  @override
  String get csImageOrPdf => 'Immagine o PDF';

  @override
  String get csChangePaperType => 'Cambia tipo di carta';

  @override
  String get csPenToMonitor => 'Penna → Monitor';

  @override
  String get csPenToMonitorSubtitle => 'Limita la penna a un singolo schermo';

  @override
  String get csPaperType => 'Tipo di carta';

  @override
  String get csPaperBlank => 'Bianco';

  @override
  String get csPaperLinedNarrow => 'Righe strette';

  @override
  String get csPaperLinedWide => 'Righe larghe';

  @override
  String get csPaperGrid => 'Quadretti';

  @override
  String get csPaperDotted => 'Puntinato';

  @override
  String get csPaperCornell => 'Cornell';

  @override
  String get csPaperIsometric => 'Isometrico';

  @override
  String get csPaperMusic => 'Pentagramma';

  @override
  String get csMapPenToMonitor => 'Mappa penna su monitor';

  @override
  String csPenMappedTo(String monitor) {
    return 'Penna mappata su $monitor';
  }

  @override
  String get csAllMonitors => 'Tutti i monitor';

  @override
  String get csAllMonitorsSubtitle => 'Ripristina (penna su tutto il desktop)';

  @override
  String get csPenReset => 'Penna ripristinata';

  @override
  String get csShapeLine => 'Linea';

  @override
  String get csShapeCircle => 'Cerchio';

  @override
  String get csShapeRectangle => 'Rettangolo';

  @override
  String get csShapeTriangle => 'Triangolo';

  @override
  String get csShapeArrow => 'Freccia';

  @override
  String get csInvalidRangeError =>
      'Inserisci un intervallo valido (es. 1–10).';

  @override
  String csPdfStartOutOfRange(int count) {
    return 'Il PDF ha circa $count pagine. Inizio fuori range.';
  }

  @override
  String get csImportPdfTitle => 'Importa PDF';

  @override
  String csPdfEstimatedPages(int count) {
    return 'Il PDF ha circa $count pagine.';
  }

  @override
  String csAllPagesWithCount(int count) {
    return 'Tutte le pagine ($count)';
  }

  @override
  String get csAllPages => 'Tutte le pagine';

  @override
  String get csCustomRange => 'Intervallo personalizzato';

  @override
  String get csFromLabel => 'Da';

  @override
  String get csToLabel => 'A';

  @override
  String get csImport => 'Importa';

  @override
  String libErrorGeneric(String error) {
    return 'Errore: $error';
  }

  @override
  String libErrorOpen(String error) {
    return 'Errore apertura: $error';
  }

  @override
  String get libImportCannotReadFile => 'Impossibile leggere il file';

  @override
  String get libImportInProgress => 'Importazione in corso…';

  @override
  String get libServiceUnavailable => 'Servizio non disponibile';

  @override
  String libImportedTitleSuffix(String title) {
    return '$title (importato)';
  }

  @override
  String libImportSuccess(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return 'Importato: \"$title\" ($_temp0)';
  }

  @override
  String get libImportCorruptedFile =>
      'Questo file non è un taccuino AbelNotes valido: potrebbe essere incompleto o danneggiato.';

  @override
  String get libExport => 'Esporta';

  @override
  String get libImportOneNoteUnreadable =>
      'AbelNotes non riesce a leggere questo file OneNote: potrebbe usare un formato non ancora supportato, o essere danneggiato.';

  @override
  String libErrorImport(String error) {
    return 'Errore importazione: $error';
  }

  @override
  String libErrorCreate(String error) {
    return 'Errore creazione: $error';
  }

  @override
  String get libSketchDefaultTitle => 'Schizzo';

  @override
  String libErrorCreateSketch(String error) {
    return 'Errore creazione schizzo: $error';
  }

  @override
  String get libRemoveFromFavorites => 'Rimuovi dai preferiti';

  @override
  String get libAddToFavorites => 'Aggiungi ai preferiti';

  @override
  String get libRename => 'Rinomina';

  @override
  String get libChangeCover => 'Cambia copertina';

  @override
  String get libCoverColor => 'Colore';

  @override
  String get libCoverPattern => 'Motivo';

  @override
  String get libCoverApply => 'Applica';

  @override
  String get libCoverStyleAuto => 'Automatico (dal tipo di carta)';

  @override
  String get libCoverStylePlain => 'Tinta unita';

  @override
  String get libCoverStylePinstripe => 'Gessato';

  @override
  String get libCoverStyleDiagonal => 'Righe diagonali';

  @override
  String get libCoverStylePolka => 'Pois';

  @override
  String get libCoverStyleGingham => 'Quadretti vichy';

  @override
  String get libCoverStyleWaves => 'Onde';

  @override
  String get libCoverStyleLabel => 'Etichetta';

  @override
  String get libCoverStyleTwoTone => 'Bicolore';

  @override
  String get libCoverStyleSheen => 'Lucido';

  @override
  String get libMoveToFolder => 'Sposta in cartella';

  @override
  String get libNoFolder => 'Nessuna cartella';

  @override
  String get libNewFolder => 'Nuova cartella';

  @override
  String get libRenameFolder => 'Rinomina cartella';

  @override
  String get libFolderNameHint => 'Nome cartella';

  @override
  String get libAllNotebooks => 'Tutti';

  @override
  String get libDeleteFolder => 'Elimina cartella';

  @override
  String libDeleteFolderTitle(String name) {
    return 'Eliminare la cartella \"$name\"?';
  }

  @override
  String get libDeleteFolderBody =>
      'I taccuini al suo interno non vengono eliminati, restano nella libreria senza cartella.';

  @override
  String get libDelete => 'Elimina';

  @override
  String get libDeleteNotebookTitle => 'Eliminare il taccuino?';

  @override
  String get libDeleteNotebookBody =>
      'Verrà spostato nel cestino. Potrai ripristinarlo da Impostazioni > Spazio.';

  @override
  String get libCancel => 'Annulla';

  @override
  String get libRenameNotebookTitle => 'Rinomina taccuino';

  @override
  String get libSave => 'Salva';

  @override
  String get libSortTitle => 'Ordinamento';

  @override
  String get libAppName => 'AbelNotes';

  @override
  String get libSearchHintShort => 'Cerca…';

  @override
  String get libSearchHintNotebooks => 'Cerca taccuini…';

  @override
  String get libImport => 'Importa';

  @override
  String get libImportTooltip => 'Importa un file .abelnote';

  @override
  String get libSettingsTooltip => 'Impostazioni';

  @override
  String get libMoreTooltip => 'Altro';

  @override
  String get libViewAsList => 'Vista a lista';

  @override
  String get libViewAsGrid => 'Vista a griglia';

  @override
  String libSortWithLabel(String sortLabel) {
    return 'Ordinamento: $sortLabel';
  }

  @override
  String get libImportNcnoteMenu => 'Importa…';

  @override
  String get libYourNotebooks => 'I tuoi taccuini';

  @override
  String libItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi',
      one: '$count elemento',
    );
    return '$_temp0';
  }

  @override
  String get libNewNotebook => 'Nuovo taccuino';

  @override
  String get libSketches => 'Schizzi';

  @override
  String get libInfiniteSpace => 'spazio infinito';

  @override
  String get libShowAll => 'Mostra tutti';

  @override
  String get libShowLess => 'Mostra meno';

  @override
  String get libNewSketch => 'Nuovo schizzo';

  @override
  String get libInfiniteCanvas => 'Canvas infinito';

  @override
  String get libNew => 'Nuovo';

  @override
  String libPagesAbbrev(int count) {
    return '$count pag.';
  }

  @override
  String libPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return '$_temp0';
  }

  @override
  String get libFooterWebdav => 'WebDAV';

  @override
  String get libFooterLocalFirst => 'App locale-first';

  @override
  String get libSyncingWithServer => 'Sincronizzazione con il server…';

  @override
  String libDownloadingProgress(int done, int total) {
    return 'Scaricamento $done/$total taccuini…';
  }

  @override
  String get libLoadingNotebooks => 'Caricamento taccuini…';

  @override
  String get libLoadingNotebooksFromServer =>
      'Caricamento taccuini dal server…';

  @override
  String get libTimeNow => 'ora';

  @override
  String libTimeMinutesAgo(int count) {
    return '$count min fa';
  }

  @override
  String libTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ore fa',
      one: '$count ora fa',
    );
    return '$_temp0';
  }

  @override
  String libTimeDaysAgo(int count) {
    return '$count g fa';
  }

  @override
  String libTimeWeeksAgo(int count) {
    return '$count sett. fa';
  }

  @override
  String libTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mesi fa',
      one: '$count mese fa',
    );
    return '$_temp0';
  }

  @override
  String libTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count anni fa',
      one: '$count anno fa',
    );
    return '$_temp0';
  }

  @override
  String get libNotebookTitleLabel => 'Titolo';

  @override
  String get libCoverLabel => 'Copertina';

  @override
  String get libPaperLabel => 'Carta';

  @override
  String get libPaperBlank => 'Bianco';

  @override
  String get libPaperLined => 'Righe';

  @override
  String get libPaperGrid => 'Griglia';

  @override
  String get libPaperDotted => 'Puntinato';

  @override
  String get libCreate => 'Crea';

  @override
  String get setSectionGeneral => 'Generale';

  @override
  String get setSectionInput => 'Stylus e input';

  @override
  String get setSectionSync => 'Sincronia';

  @override
  String get setSectionStorage => 'Spazio';

  @override
  String get setSectionShortcuts => 'Scorciatoie';

  @override
  String get setSectionAdvanced => 'Avanzate';

  @override
  String get setSectionAbout => 'Informazioni';

  @override
  String get setBackToLibrary => 'Libreria';

  @override
  String get setSettingsTitle => 'Impostazioni';

  @override
  String get setThemeLabel => 'Tema';

  @override
  String get setThemeLight => 'Chiaro';

  @override
  String get setThemePaper => 'Carta';

  @override
  String get setThemeDark => 'Scuro';

  @override
  String get setLanguage => 'Lingua';

  @override
  String get setLanguageSub => 'Lingua dell\'interfaccia';

  @override
  String get setLanguageItalian => 'Italiano';

  @override
  String get setFavoritesFirst => 'Preferiti per primi';

  @override
  String get setFavoritesFirstSub =>
      'Mostra i taccuini preferiti in cima alla libreria';

  @override
  String get setStylusOnly => 'Solo stylus';

  @override
  String get setStylusOnlySub =>
      'Ignora il tocco del dito durante la scrittura. Pinch e pan continuano a funzionare con due dita.';

  @override
  String get setPressureThickness => 'Pressione → spessore';

  @override
  String get setPressureThicknessSub =>
      'Modulazione di tratto in base alla pressione dello stylus';

  @override
  String get setSpeedThickness => 'Velocità → spessore';

  @override
  String get setSpeedThicknessSub =>
      'Scrivere più veloce assottiglia il tratto';

  @override
  String get setStrokeContinuation => 'Continuazione tratto';

  @override
  String get setStrokeContinuationSub =>
      'Compensa brevi interruzioni del sensore (es. punto della i)';

  @override
  String get setFillShapes => 'Riempi le forme';

  @override
  String get setFillShapesSub =>
      'Cerchi, rettangoli e triangoli riconosciuti prendono una tinta leggera del colore dell\'inchiostro';

  @override
  String get setSyncConnectedDesc =>
      'Connesso a un server WebDAV. I taccuini si sincronizzano su tutti i tuoi dispositivi.';

  @override
  String get setSyncLocalOnlyDesc =>
      'Modalità solo-locale: i taccuini restano su questo dispositivo. Connetti un server WebDAV per accedervi da più dispositivi.';

  @override
  String get setSyncWebdav => 'WebDAV';

  @override
  String get setSyncLocalOnly => 'Solo locale';

  @override
  String setSyncAccountInfo(String host, String username) {
    return '$host · $username';
  }

  @override
  String get setSyncNoServer => 'Nessun server connesso';

  @override
  String get setDisconnect => 'Disconnetti';

  @override
  String get setConnect => 'Connetti';

  @override
  String get setDisconnectTitle => 'Disconnettere il server?';

  @override
  String get setDisconnectBody =>
      'I taccuini già scaricati restano su questo dispositivo. La sincronizzazione si interrompe finché non riconnetti.';

  @override
  String get setCheckCert => 'Verifica certificato server';

  @override
  String get setCertCheckFailed =>
      'Impossibile verificare il certificato del server.';

  @override
  String get setCertUnchanged =>
      'Il certificato non è cambiato dall\'ultima connessione.';

  @override
  String get setCertChangedTitle => 'Nuovo certificato rilevato';

  @override
  String setCertChangedBody(String oldFingerprint, String newFingerprint) {
    return 'Il server presenta un\'impronta diversa da quella salvata. Se hai rinnovato tu il certificato, conferma per continuare a sincronizzare. Se non sei stato tu, ANNULLA e controlla la tua rete prima di riprovare.\n\nImpronta salvata: $oldFingerprint\nImpronta attuale: $newFingerprint';
  }

  @override
  String get setCertConfirmNew => 'Conferma nuovo certificato';

  @override
  String get setCancel => 'Annulla';

  @override
  String get setShortcutPen => 'Penna';

  @override
  String get setShortcutUndo => 'Annulla';

  @override
  String get setShortcutBrush => 'Pennello';

  @override
  String get setShortcutRedo => 'Ripeti';

  @override
  String get setShortcutEraser => 'Gomma';

  @override
  String get setShortcutSelectAll => 'Seleziona tutto';

  @override
  String get setShortcutLasso => 'Lasso';

  @override
  String get setShortcutCopy => 'Copia';

  @override
  String get setShortcutHand => 'Mano';

  @override
  String get setShortcutCut => 'Taglia';

  @override
  String get setShortcutText => 'Testo';

  @override
  String get setShortcutPaste => 'Incolla';

  @override
  String get setShortcutShape => 'Forma';

  @override
  String get setShortcutDuplicate => 'Duplica';

  @override
  String get setShortcutChangePage => 'Cambia pagina';

  @override
  String get setShortcutSave => 'Salva';

  @override
  String get setShortcutFit => 'Adatta';

  @override
  String get setShortcutCheatSheet => 'Promemoria';

  @override
  String get setKeyboardShortcutsTitle => 'Scorciatoie da tastiera';

  @override
  String get setClearCache => 'Pulisci cache';

  @override
  String get setClearCacheSub =>
      'Rimuove i file temporanei. I taccuini non vengono toccati.';

  @override
  String get setClear => 'Pulisci';

  @override
  String get setTrash => 'Cestino';

  @override
  String get setTrashSub => 'Taccuini eliminati, ripristinabili';

  @override
  String get setOpenTrash => 'Apri cestino';

  @override
  String get setClearCacheDone => 'Cache pulita.';

  @override
  String get setExportLibrary => 'Esporta libreria';

  @override
  String get setExportLibrarySub =>
      'Salva tutti i taccuini in un unico archivio zip.';

  @override
  String get setExport => 'Esporta';

  @override
  String get setExportLibraryEmpty => 'Nessun taccuino da esportare.';

  @override
  String get setExportLibraryInProgress => 'Esportazione in corso…';

  @override
  String setExportLibraryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Esportati $count taccuini',
      one: 'Esportato $count taccuino',
    );
    return '$_temp0.';
  }

  @override
  String setExportLibraryFailed(String error) {
    return 'Esportazione fallita: $error';
  }

  @override
  String setTrashPurgeTitle(String title) {
    return 'Eliminare definitivamente \"$title\"?';
  }

  @override
  String get setTrashPurgeBody => 'Non potrai più recuperarlo.';

  @override
  String get setTrashPurge => 'Elimina definitivamente';

  @override
  String get setTrashEmptyTitle => 'Svuotare il cestino?';

  @override
  String get setTrashEmptyBody =>
      'Tutti i taccuini nel cestino verranno eliminati definitivamente.';

  @override
  String get setTrashEmpty => 'Svuota cestino';

  @override
  String get setTrashEmptyState => 'Il cestino è vuoto.';

  @override
  String get setTrashRestore => 'Ripristina';

  @override
  String get setAdvancedIntro =>
      'Strumenti di recupero per casi rari di taccuino bloccato in sincronia. Usali solo se il sync continua a fallire dopo un normale \"Forza sync\" dalla libreria.';

  @override
  String get setForceReloadTitle => 'Forza ricarica taccuino dal server';

  @override
  String get setForceReloadDesc =>
      'Riscarica tutto il contenuto del taccuino dalla cartella delta del server e sovrascrive la copia locale. Utile se il count pagine sembra sbagliato o il taccuino non si apre. Non perde dati lato server.';

  @override
  String setErrorGeneric(String error) {
    return 'Errore: $error';
  }

  @override
  String setPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return '$_temp0';
  }

  @override
  String get setReload => 'Ricarica';

  @override
  String get setCloseNotebookFirst =>
      'Chiudi il taccuino prima di ricaricarlo dal server.';

  @override
  String setReloadConfirmTitle(String title) {
    return 'Ricaricare \"$title\"?';
  }

  @override
  String get setReloadConfirmBody =>
      'Riscarica metadata, document, pagine e asset dalla cartella delta del server. La copia locale viene sostituita.\n\nModifiche locali non ancora sincronizzate verranno perse. Continuare?';

  @override
  String setReloadInProgress(String title) {
    return 'Ricarica \"$title\" in corso…';
  }

  @override
  String get setNotConnectedWebdav => 'Non connesso a un server WebDAV.';

  @override
  String setReloadDone(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '$count pagina',
    );
    return '\"$title\" ricaricato — $_temp0.';
  }

  @override
  String setReloadFailed(String error) {
    return 'Ricarica fallita: $error';
  }

  @override
  String get setAboutTagline => 'App di scrittura a mano, local-first.';

  @override
  String get setAboutOffline =>
      'Funziona offline; la sincronia con WebDAV è facoltativa.';

  @override
  String setAboutVersion(String version, String commit) {
    return 'Versione $version · build $commit';
  }

  @override
  String get setReportProblem => 'Segnala un problema';

  @override
  String get setReportProblemSub =>
      'Copia il log errori negli appunti da allegare alla segnalazione.';

  @override
  String get setCopyLog => 'Copia log';

  @override
  String get setReportProblemEmpty => 'Nessun errore registrato.';

  @override
  String get setCopyLogDone => 'Log copiato negli appunti.';

  @override
  String get onbTagline =>
      'Appunti e disegno a mano libera, sincronizzati sul TUO server. Scegli come iniziare — puoi cambiare in seguito.';

  @override
  String get onbTryNowTitle => 'Prova subito';

  @override
  String get onbTryNowSubtitle =>
      'Inizia a scrivere ora. I taccuini restano su questo dispositivo — nessun account, nessun server.';

  @override
  String get onbConnectNextcloudTitle => 'Connetti il tuo Nextcloud';

  @override
  String get onbConnectNextcloudSubtitle =>
      'Sincronizza sul tuo server WebDAV / Nextcloud personale e accedi da tutti i dispositivi.';

  @override
  String get onbManagedServerTitle => 'Server gestito AbelNotes';

  @override
  String get onbManagedServerSubtitle =>
      'Non hai un server? Presto potrai usare il nostro, senza configurare nulla.';

  @override
  String get onbComingSoonBadge => 'In arrivo';

  @override
  String get onbDriveTitle => 'Sincronizza con Google Drive';

  @override
  String get onbDriveSubtitle =>
      'Niente da configurare: i tuoi quaderni si sincronizzano nel tuo Google Drive.';

  @override
  String get driveSignInFailed =>
      'L\'accesso a Google non è andato a buon fine. Non è stato cambiato nulla.';

  @override
  String get driveSignInCancelled => 'Accesso annullato.';

  @override
  String get driveNotConfigured =>
      'Questa build non ha le credenziali Google, quindi la sincronizzazione con Drive non è disponibile.';

  @override
  String get driveNoKeyring =>
      'Questo sistema non ha un archivio sicuro, quindi l\'account Google non può essere conservato in sicurezza. Qui la sincronizzazione con Drive non è disponibile.';

  @override
  String get driveConnectedTitle => 'Google Drive collegato';

  @override
  String get setSyncDriveTitle => 'Google Drive';

  @override
  String get setSyncDriveConnected =>
      'I quaderni si sincronizzano nel tuo Google Drive.';

  @override
  String get setSyncDriveNotConnected => 'Non collegato.';

  @override
  String get setSyncDriveDesktopOnly => 'Per ora disponibile su computer.';

  @override
  String get setDriveDisconnectTitle => 'Scollegare Google Drive?';

  @override
  String get setDriveDisconnectBody =>
      'I quaderni già presenti nel tuo Drive restano dove sono: l\'app smette solo di sincronizzarli. I quaderni su questo dispositivo non vengono toccati.';

  @override
  String get setDriveDisconnectConfirm => 'Scollega';

  @override
  String get setSyncOneBackendNote =>
      'I quaderni si sincronizzano in un posto alla volta: il tuo server oppure il tuo Google Drive.';

  @override
  String get setSyncSwitchTitle =>
      'Spostare la sincronizzazione su Google Drive?';

  @override
  String get setSyncSwitchBody =>
      'I tuoi quaderni restano su questo dispositivo e vengono caricati sul tuo Google Drive. Le copie già presenti sul tuo server restano dove sono, ma da quel momento non ricevono più aggiornamenti. Non viene cancellato nulla.';

  @override
  String get setSyncSwitchConfirm => 'Sposta su Drive';

  @override
  String get setSyncInactiveNote =>
      'Configurato, ma non in uso: la sincronizzazione va sull\'altra destinazione.';

  @override
  String libPendingNewDrive(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count quaderni non sono ancora su Google Drive: $names',
      one: '«$names» non è ancora su Google Drive',
    );
    return '$_temp0';
  }

  @override
  String libPendingNewServer(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count quaderni non sono ancora sul tuo server: $names',
      one: '«$names» non è ancora sul tuo server',
    );
    return '$_temp0';
  }

  @override
  String libPendingChanges(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Modifiche a $count quaderni non ancora caricate: $names',
      one: 'Modifiche a «$names» non ancora caricate',
    );
    return '$_temp0';
  }

  @override
  String get libPendingUploadsHint =>
      'Intanto restano su questo dispositivo. Lascia l\'app aperta un momento.';

  @override
  String get libDeleteRemotePending =>
      'Eliminato qui. Rimozione dal cloud non riuscita: verrà ritentata in automatico.';

  @override
  String libPendingRemoteDeletes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count quaderni eliminati qui, ancora da togliere dal cloud',
      one: '$count quaderno eliminato qui, ancora da togliere dal cloud',
    );
    return '$_temp0';
  }

  @override
  String get libPendingRemoteDeletesHint =>
      'Finché non va via, gli altri dispositivi possono ancora vederlo. Nuovo tentativo appena la connessione torna.';

  @override
  String get libServerUnreachable => 'Server non raggiungibile';

  @override
  String get libServerUnreachableHint =>
      'Le modifiche restano su questo dispositivo e si caricano appena torna la connessione.';

  @override
  String get libStorageFullDrive => 'Il tuo Google Drive è pieno';

  @override
  String get libStorageFullServer => 'Il tuo server non ha più spazio';

  @override
  String get libStorageFullBody =>
      'I quaderni restano al sicuro su questo dispositivo, ma non possono essere caricati finché non liberi spazio. Lo spazio di Google Drive è condiviso con Gmail e Foto.';

  @override
  String get libStorageFullBodyServer =>
      'I quaderni restano al sicuro su questo dispositivo, ma non possono essere caricati finché non viene liberato spazio sul server.';

  @override
  String get libLocalOnlyTitle => 'Solo su questo dispositivo';

  @override
  String get libLocalOnlyBody =>
      'I tuoi taccuini restano su questo dispositivo. Collega il tuo server o Google Drive per averli su tutti i dispositivi — puoi farlo quando vuoi.';

  @override
  String get libLocalOnlyBodyWeb =>
      'I tuoi quaderni restano in questo browser. Esporta quelli che vuoi tenere, o collega Google Drive per averli ovunque. Safari può cancellare i dati dei siti non usati da qualche giorno, a meno che tu non aggiunga l\'app alla schermata Home.';

  @override
  String get libKeepOnDevice => 'Tieni solo su questo dispositivo';

  @override
  String get libResumeSync => 'Torna a sincronizzare questo quaderno';

  @override
  String get libLocalOnlyBadge => 'Solo qui';

  @override
  String get libKeepOnDeviceTitle => 'Tenere questo quaderno solo qui?';

  @override
  String get libKeepOnDeviceBody =>
      'Smette di essere caricato e gli altri dispositivi non lo riceveranno più. Su questo dispositivo resta pienamente utilizzabile.';

  @override
  String get libKeepOnDeviceRemoveCopy => 'Elimina anche la copia già caricata';

  @override
  String get libKeepOnDeviceConfirm => 'Tieni solo qui';

  @override
  String get libLocalOnlyDone => 'Tenuto solo su questo dispositivo.';

  @override
  String get libSyncResumedDone => 'Questo quaderno tornerà a sincronizzarsi.';

  @override
  String get syncLocalOnlyTooltip => 'Tenuto solo su questo dispositivo';

  @override
  String get libFreeSpace => 'Libera spazio su questo dispositivo';

  @override
  String get libKeepOnThisDevice => 'Scarica su questo dispositivo';

  @override
  String get libFreeSpaceTitle =>
      'Togliere questo quaderno da questo dispositivo?';

  @override
  String get libFreeSpaceBody =>
      'Il quaderno resta sul remoto e sugli altri dispositivi. Qui diventa una scheda da toccare per riscaricarlo. Fino ad allora non si apre offline e la ricerca non guarda al suo interno.';

  @override
  String get libFreeSpaceConfirm => 'Libera spazio';

  @override
  String libFreeSpaceDone(String size) {
    return 'Tolto da questo dispositivo. Liberati $size.';
  }

  @override
  String get libFreeSpaceNotSynced =>
      'Questo quaderno ha modifiche che il remoto non ha ancora. Sarà possibile una volta caricate.';

  @override
  String get libFreeSpaceOpenNotebook => 'Chiudi prima il quaderno.';

  @override
  String get libKeepOnThisDeviceDone =>
      'Verrà di nuovo scaricato su questo dispositivo.';

  @override
  String get syncNotOnDeviceTooltip => 'Sul remoto, non su questo dispositivo';

  @override
  String get onbSyncQuestion => 'Sincronizza i tuoi appunti';

  @override
  String get onbSyncQuestionSub =>
      'Scegli dove vivono i tuoi quaderni. Puoi cambiare in seguito.';

  @override
  String get onbDriveShort => 'Google Drive';

  @override
  String get onbNextcloudShort => 'Nextcloud / WebDAV';

  @override
  String get onbStartWithoutSync => 'Inizia senza sincronizzare';

  @override
  String get onbDriveUnavailable => 'Non disponibile in questa build';

  @override
  String get onbLicenseNote =>
      'Aprendo l\'app accetti la licenza AGPL-3.0. \"AbelNotes\" è un marchio del progetto.';

  @override
  String get logConnectionFailed =>
      'Impossibile connettersi. Verifica URL, username e password.';

  @override
  String logConnectionError(String error) {
    return 'Errore di connessione: $error';
  }

  @override
  String get logCertificateChanged =>
      'Il certificato del server è cambiato rispetto all\'ultima connessione. Se sei stato tu (es. rinnovo certificato), vai in Impostazioni > Sincronizzazione per confermare la nuova impronta.';

  @override
  String get logCertConfirmTitle => 'Verifica identità del server';

  @override
  String get logCertConfirmBody =>
      'Prima connessione a questo server. Confronta questa impronta con quella del tuo server (es. da riga di comando) prima di continuare:';

  @override
  String get logCertConfirmTrust => 'Mi fido, continua';

  @override
  String get logBackTooltip => 'Indietro';

  @override
  String get logTitle => 'Connetti il tuo Nextcloud';

  @override
  String get logSubtitle =>
      'Qualsiasi server WebDAV / Nextcloud (VPS, self-hosted, LAN). Nessun cloud di terze parti.';

  @override
  String get logServerUrlLabel => 'URL Server';

  @override
  String get logServerUrlHint => 'https://cloud.example.com';

  @override
  String get logServerUrlRequired => 'Inserisci l\'URL del server';

  @override
  String get logServerUrlInvalid => 'Deve iniziare con http:// o https://';

  @override
  String get logUsernameLabel => 'Nome utente';

  @override
  String get logUsernameRequired => 'Nome utente richiesto';

  @override
  String get logPasswordLabel => 'Password / App Password';

  @override
  String get logPasswordRequired => 'Password richiesta';

  @override
  String get logAppPasswordHint =>
      'Consigliato: una App Password generata dalle impostazioni di Nextcloud.';

  @override
  String get logServerTypeNextcloud => 'Nextcloud / ownCloud';

  @override
  String get logServerTypeWebdav => 'Altro WebDAV';

  @override
  String get logServerUrlHintWebdav => 'https://dav.example.com/cartella';

  @override
  String get logWebdavExperimental =>
      'I backend WebDAV generici (Synology, Seafile, rclone…) sono sperimentali: solo Nextcloud è testato a fondo. Tieni un backup dei tuoi quaderni.';

  @override
  String get logWebdavUrlHint =>
      'URL WebDAV completo, percorso incluso — es. Synology https://nas:5006/home, Seafile https://server/seafdav. La condivisione link non è disponibile su WebDAV generico.';

  @override
  String get logConnectButton => 'Connetti';

  @override
  String get chromeBackToLibraryTooltip => 'Torna alla libreria';

  @override
  String get chromeLibrary => 'Libreria';

  @override
  String get chromeUnsaved => 'Non salvato';

  @override
  String get chromeMouseDrawsTooltip =>
      'Mouse: disegna — tocca per usarlo come selezione';

  @override
  String get chromeMouseSelectsTooltip =>
      'Mouse: selezione — tocca per disegnare col mouse';

  @override
  String get chromeTouchDrawsTooltip =>
      'Dito: disegna — tocca per usarlo per navigare';

  @override
  String get chromeTouchPansTooltip =>
      'Dito: naviga — tocca per disegnare col dito';

  @override
  String get chromeUndo => 'Annulla';

  @override
  String get chromeRedo => 'Ripeti';

  @override
  String get chromeAllPages => 'Tutte le pagine';

  @override
  String chromePageIndicator(String current, int total) {
    return '$current / $total';
  }

  @override
  String get chromeAddPage => 'Aggiungi pagina';

  @override
  String get chromeSymbols => 'Simboli';

  @override
  String get chromeExport => 'Esporta';

  @override
  String get chromeMore => 'Altro';

  @override
  String get chromeMoreEllipsis => 'Altro…';

  @override
  String get chromeToolPen => 'Penna · P';

  @override
  String get chromeToolHighlighter => 'Evidenziatore';

  @override
  String get chromeToolEraser => 'Gomma · E';

  @override
  String get chromeToolLasso => 'Lasso · L';

  @override
  String get chromeToolText => 'Testo · T';

  @override
  String get chromeToolLaser => 'Laser';

  @override
  String get chromeToolPan => 'Mano · H';

  @override
  String get chromeDragToMoveBar => 'Trascina per spostare la barra';

  @override
  String get chromeShapeGuessOn => 'Auto-forma · attivo';

  @override
  String get chromeShapeGuessOff => 'Auto-forma · spento';

  @override
  String get chromeHoldForOptions =>
      'Tieni premuto o clic destro per le opzioni';

  @override
  String get chromeLabelPen => 'Penna';

  @override
  String get chromeLabelBallpoint => 'Penna a sfera';

  @override
  String get chromeLabelBrush => 'Pennello';

  @override
  String get chromeLabelCalligraphy => 'Calligrafia';

  @override
  String get chromeLabelEraser => 'Gomma';

  @override
  String get chromeLabelLasso => 'Lasso';

  @override
  String get chromeLabelText => 'Testo';

  @override
  String get chromeLabelShape => 'Forma';

  @override
  String get chromeLabelImage => 'Immagine';

  @override
  String get chromeLabelPan => 'Mano';

  @override
  String get chromePresetsSection => 'Pre-impostazioni';

  @override
  String get chromePresetHint => 'Tieni premuto per salvare/cancellare';

  @override
  String get chromeColorSection => 'Colore';

  @override
  String get chromeColorEditHint => 'Tieni premuto un colore per cambiarlo';

  @override
  String get chromeThicknessSection => 'Spessore';

  @override
  String chromeThicknessPx(String value) {
    return '$value px';
  }

  @override
  String get chromePreview => 'Anteprima';

  @override
  String get chromeModeSection => 'Modalità';

  @override
  String get chromeEraserPerArea => 'Per area';

  @override
  String get chromeEraserPerStroke => 'Per tratto';

  @override
  String get chromeSizeSection => 'Dimensione';

  @override
  String get chromeSizeSmall => 'S';

  @override
  String get chromeSizeMedium => 'M';

  @override
  String get chromeSizeLarge => 'L';

  @override
  String get chromePresetOverwrite => 'Sovrascrivi con corrente';

  @override
  String get chromePresetClearSlot => 'Svuota slot';

  @override
  String get chromeNoPages => 'Nessuna pagina';

  @override
  String get chromeHidePageBar => 'Nascondi la barra delle pagine';

  @override
  String get chromeShowPageBar => 'Mostra la barra delle pagine';

  @override
  String chromePrevPageTooltip(int number) {
    return 'Pagina precedente $number — tocca per tornare indietro';
  }

  @override
  String chromePageOfChapterTooltip(int number, int globalNumber) {
    return 'Pagina $number del capitolo · pagina $globalNumber del taccuino';
  }

  @override
  String chromePageTooltip(int number) {
    return 'Pagina $number';
  }

  @override
  String get chromeHexLabel => 'Esadecimale';

  @override
  String get chromeCancel => 'Annulla';

  @override
  String get chromeApply => 'Applica';

  @override
  String get pmNone => 'Nessuno';

  @override
  String get pmCreateChapterFirst => 'Crea prima almeno un capitolo.';

  @override
  String pmAssignChapterCount(int count) {
    return 'Assegna capitolo ($count pag.)';
  }

  @override
  String pmDeletePagesConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminare $count pagine?',
      one: 'Eliminare 1 pagina?',
    );
    return '$_temp0';
  }

  @override
  String get pmActionCannotBeUndone =>
      'Questa azione non può essere annullata.';

  @override
  String get pmCancel => 'Annulla';

  @override
  String get pmDelete => 'Elimina';

  @override
  String pmPagesCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count pagine tagliate — aprire il taccuino di destinazione per incollare.',
      one:
          '1 pagina tagliata — aprire il taccuino di destinazione per incollare.',
    );
    return '$_temp0';
  }

  @override
  String pmPagesCutSkipped(int count, int skipped) {
    return '$count pagine tagliate ($skipped non ancora caricate, saltate) — aprire il taccuino di destinazione per incollare.';
  }

  @override
  String pmSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selezionate',
      one: '1 selezionata',
    );
    return '$_temp0';
  }

  @override
  String get pmSelectAllButton => 'Tutte';

  @override
  String get pmClearSelection => 'Annulla selezione';

  @override
  String pmPagesCount(int count) {
    return 'Pagine ($count)';
  }

  @override
  String pmPagesFilteredCount(int visible, int total) {
    return 'Pagine ($visible/$total)';
  }

  @override
  String get pmGoToPageTooltip => 'Vai alla pagina…';

  @override
  String get pmExitSelection => 'Esci dalla selezione';

  @override
  String get pmSelectPages => 'Seleziona pagine';

  @override
  String get pmPastePages => 'Incolla pagine';

  @override
  String pmPagesPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine incollate.',
      one: '1 pagina incollata.',
    );
    return '$_temp0';
  }

  @override
  String get pmAddPage => 'Aggiungi pagina';

  @override
  String get pmClose => 'Chiudi';

  @override
  String get pmNewChapter => 'Nuovo capitolo';

  @override
  String get pmChapterNameHint => 'Nome capitolo';

  @override
  String pmPageDeleted(int number) {
    return 'Pagina $number eliminata';
  }

  @override
  String get pmUndo => 'Annulla';

  @override
  String get pmAssignChapter => 'Assegna capitolo';

  @override
  String get pmRename => 'Rinomina';

  @override
  String get pmRenameChapter => 'Rinomina capitolo';

  @override
  String get pmDeleteChapter => 'Elimina capitolo';

  @override
  String pmDeleteChapterConfirm(String title) {
    return 'Eliminare \"$title\"? Le pagine al suo interno resteranno ma senza capitolo.';
  }

  @override
  String get pmGoToPage => 'Vai alla pagina';

  @override
  String pmPageRangeHint(int max) {
    return '1–$max';
  }

  @override
  String get pmGo => 'Vai';

  @override
  String get pmOk => 'OK';

  @override
  String pmCountPagesShort(int count) {
    return '$count pag.';
  }

  @override
  String get pmChapter => 'Capitolo';

  @override
  String get pmCut => 'Taglia';

  @override
  String get pmInsertBefore => 'Inserisci prima';

  @override
  String get pmInsertAfter => 'Inserisci dopo';

  @override
  String get pmDuplicate => 'Duplica';

  @override
  String get pmMoveTo => 'Sposta a pagina…';

  @override
  String get pmMove => 'Sposta';

  @override
  String get pmMoveToPage => 'Sposta a pagina';

  @override
  String get pmChapterEllipsis => 'Capitolo…';

  @override
  String pmPageChapterLabel(int number, String chapter) {
    return '$number • $chapter';
  }

  @override
  String get pmCorruptAssetTooltip =>
      'Asset corrotto sul server (troncato) — ri-importa il PDF originale per recuperare';

  @override
  String get pmLoadingImageTooltip => 'Caricamento immagine dal server…';

  @override
  String get tedInsertTextTitle => 'Inserisci testo';

  @override
  String get tedEditTextTitle => 'Modifica testo';

  @override
  String get tedBoldTooltip => 'Grassetto (Ctrl+B)';

  @override
  String get tedItalicTooltip => 'Corsivo (Ctrl+I)';

  @override
  String get tedUnderlineTooltip => 'Sottolineato (Ctrl+U)';

  @override
  String get tedStrikethroughTooltip => 'Barrato';

  @override
  String get tedAlignLeft => 'Sinistra';

  @override
  String get tedAlignCenter => 'Centro';

  @override
  String get tedAlignRight => 'Destra';

  @override
  String get tedWriteHereHint => 'Scrivi qui…';

  @override
  String get tedCancel => 'Annulla';

  @override
  String get tedInsert => 'Inserisci';

  @override
  String get cropTitle => 'Ritaglia immagine';

  @override
  String get cropCancel => 'Annulla';

  @override
  String get cropConfirm => 'Ritaglia';

  @override
  String get imgFontSmaller => 'Testo più piccolo';

  @override
  String get imgFontLarger => 'Testo più grande';

  @override
  String get imgCrop => 'Ritaglia';

  @override
  String get imgCopy => 'Copia';

  @override
  String get imgUnlock => 'Sblocca';

  @override
  String get imgLock => 'Blocca';

  @override
  String get imgDelete => 'Elimina';

  @override
  String get imgDeselect => 'Deseleziona';

  @override
  String get imgMoreActions => 'Altre azioni';

  @override
  String get imgBringToFront => 'In primo piano';

  @override
  String get imgSendToBack => 'Dietro a tutto';

  @override
  String get imgComment => 'Commento';

  @override
  String get imgFlipHChecked => 'Rifletti H ✓';

  @override
  String get imgFlipH => 'Rifletti H';

  @override
  String get imgCut => 'Taglia';

  @override
  String get syncOkTooltip => 'Sincronizzato';

  @override
  String get syncPendingTooltip => 'In sincronia…';

  @override
  String get syncOfflineTooltip => 'Offline';

  @override
  String get syncConflictTooltip => 'Conflitto';

  @override
  String get confDecideLater => 'Decidi più tardi';

  @override
  String confTitlePageDeletedElsewhere(int pageNumber) {
    return 'Pagina $pageNumber eliminata altrove';
  }

  @override
  String confTitleConflictPage(int pageNumber) {
    return 'Conflitto — Pagina $pageNumber';
  }

  @override
  String get confDeletionExplainer =>
      'Hai modificato questa pagina, ma un altro dispositivo l\'ha eliminata. Vuoi mantenerla o eliminarla?';

  @override
  String get confKeepPage => 'Mantieni la pagina';

  @override
  String get confLocalYours => 'Locale (tuo)';

  @override
  String get confRemoteOtherDevice => 'Remoto (altro dispositivo)';

  @override
  String get confKeepAllLocal => 'Tieni tutti locali';

  @override
  String get confAcceptAllRemote => 'Accetta tutti remoti';

  @override
  String confProgressIndicator(int current, int total, num decided) {
    String _temp0 = intl.Intl.pluralLogic(
      decided,
      locale: localeName,
      other: '$decided decisi',
      one: '$decided deciso',
    );
    return '$current / $total  ($_temp0)';
  }

  @override
  String get confApplyChoices => 'Applica scelte';

  @override
  String confDecidedProgress(int decided, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'decisi',
      one: 'deciso',
    );
    return '$decided/$total $_temp0';
  }

  @override
  String get confJumpToConflict => 'Vai al conflitto';

  @override
  String confJumpDecidedCount(int decided, int total) {
    return '$decided/$total decisi';
  }

  @override
  String confJumpItemPage(int pageNumber) {
    return 'Pag. $pageNumber';
  }

  @override
  String confJumpItemPageWithChapter(int pageNumber, String chapterName) {
    return 'Pag. $pageNumber — $chapterName';
  }

  @override
  String get confDismissDialogTitle => 'Annullare?';

  @override
  String get confDismissDialogBody =>
      'Le scelte non applicate verranno perse. La versione locale verrà mantenuta.';

  @override
  String get confContinue => 'Continua';

  @override
  String get confCancel => 'Annulla';

  @override
  String get confModifiedJustNow => 'Adesso';

  @override
  String confModifiedMinutesAgo(int minutes) {
    return '$minutes min fa';
  }

  @override
  String confModifiedHoursAgo(num hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours ore fa',
      one: '$hours ora fa',
    );
    return '$_temp0';
  }

  @override
  String get confDeletePage => 'Elimina la pagina';

  @override
  String get confAsOnOtherDevice => 'Come sull\'altro dispositivo';

  @override
  String get symNewLibraryTitle => 'Nuova libreria';

  @override
  String get symNewLibraryHint => 'Inserisci il nome della libreria';

  @override
  String get symRenameLibraryTitle => 'Rinomina libreria';

  @override
  String get symNewNameHint => 'Nuovo nome';

  @override
  String get symDeleteLibraryTitle => 'Elimina libreria';

  @override
  String symDeleteLibraryConfirm(String name) {
    return 'Elimina \"$name\" e tutti i suoi simboli?';
  }

  @override
  String get symCancel => 'Annulla';

  @override
  String get symDelete => 'Elimina';

  @override
  String get symRenameSymbolTitle => 'Rinomina simbolo';

  @override
  String get symPanelTitle => 'Librerie simboli';

  @override
  String get symNoLibraries => 'Nessuna libreria';

  @override
  String get symNew => 'Nuova';

  @override
  String get symSelectLibrary => 'Seleziona una libreria';

  @override
  String get symNoSymbolsHint =>
      'Nessun simbolo\nSeleziona elementi con il lazo e premi ✚';

  @override
  String get symLassoSaveHint =>
      'Seleziona elementi con il lazo → ✚ per salvare nella libreria attiva';

  @override
  String get symRename => 'Rinomina';

  @override
  String get symInsert => 'Inserisci';

  @override
  String get symOk => 'OK';

  @override
  String get rcbBannerTitle => 'Modifiche da un altro dispositivo';

  @override
  String get rcbSeeDetails => 'Vedi dettagli';

  @override
  String get rcbDismiss => 'Ignora';

  @override
  String get rcbIncomingChanges => 'Modifiche in arrivo';

  @override
  String get rcbTapPageHint => 'Tocca una pagina per applicare e andare lì';

  @override
  String rcbNewImagesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuove immagini',
      one: '1 nuova immagine',
    );
    return '$_temp0';
  }

  @override
  String get rcbKeepMine => 'Mantieni i miei';

  @override
  String get rcbApplyAll => 'Applica tutto';

  @override
  String get rcbBadgeNew => 'NUOVA';

  @override
  String get rcbBadgeModified => 'MODIFICATA';

  @override
  String rcbPageTitle(int pageNumber) {
    return 'Pagina $pageNumber';
  }

  @override
  String get rcbContentUpdated => 'Contenuto aggiornato';

  @override
  String rcbSummaryModifiedPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pag. modificate',
      one: '$count pag. modificata',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryNewPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuove',
      one: '$count nuova',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryImages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count immagini',
      one: '$count immagine',
    );
    return '$_temp0';
  }

  @override
  String get rcbChangesDetected => 'Cambiamenti rilevati';

  @override
  String get nbUntitled => 'Senza titolo';

  @override
  String get nbDefaultChapterTitle => 'Capitolo 1';

  @override
  String get nbOpeningNotebook => 'Apertura taccuino…';

  @override
  String get nbNoLocalCopyOffline =>
      'Nessuna copia locale di questo taccuino, e non sei connesso a un server per scaricarlo.';

  @override
  String nbOpenFailed(String error) {
    return 'Impossibile aprire: $error';
  }

  @override
  String get nbSortModifiedDesc => 'Modificati (più recenti)';

  @override
  String get nbSortModifiedAsc => 'Modificati (meno recenti)';

  @override
  String get nbSortTitleAsc => 'Titolo A→Z';

  @override
  String get nbSortTitleDesc => 'Titolo Z→A';

  @override
  String get nbSortCreatedDesc => 'Creati (più recenti)';

  @override
  String get nbSortCreatedAsc => 'Creati (meno recenti)';

  @override
  String get nbSortColorGroup => 'Colore copertina';

  @override
  String cvFormatTooNew(int fileVersion, int supportedVersion) {
    return 'Questo taccuino usa un formato più recente (v$fileVersion, supportato: v$supportedVersion). Aggiorna AbelNotes per aprirlo.';
  }

  @override
  String get setLanguageSystem => 'Sistema';

  @override
  String get setLanguageEnglish => 'English';

  @override
  String get setLanguageSpanish => 'Español';

  @override
  String get onbAppName => 'AbelNotes';

  @override
  String get setAboutAppName => 'AbelNotes';

  @override
  String get chromeLabelHighlighter => 'Evidenziatore';

  @override
  String get chromeLabelLaser => 'Laser';

  @override
  String get importSourceTitle => 'Importa nella libreria';

  @override
  String get importSourceNcnote => 'Taccuino .abelnote';

  @override
  String get importSourceObsidian => 'Vault Obsidian';

  @override
  String get importSourceObsidianHint => 'Cartella con file Markdown';

  @override
  String get importSourceNotion => 'Export Notion';

  @override
  String get importSourceNotionHint => 'File .zip (Markdown e CSV)';

  @override
  String get importPhaseScanning => 'Analisi sorgente…';

  @override
  String importPhaseParsing(int current, int total) {
    return 'Lettura file $current di $total';
  }

  @override
  String importPhasePaginating(int current, int total) {
    return 'Impaginazione capitolo $current di $total';
  }

  @override
  String get importPhasePackaging => 'Creazione taccuino…';

  @override
  String get importCancel => 'Annulla';

  @override
  String get importCancelled => 'Importazione annullata';

  @override
  String importReportTitle(int count) {
    return '$count avvisi durante l\'import';
  }

  @override
  String get importReportCopy => 'Copia';

  @override
  String get importReportClose => 'Chiudi';

  @override
  String get importSourceOneNote => 'File OneNote';

  @override
  String get importSourceOneNoteHint => 'Sezione .one o taccuino .onetoc2';

  @override
  String get setOpenSourceLicenses => 'Licenze open source';

  @override
  String get setOpenSourceLicensesSub =>
      'Componenti di terze parti inclusi nell\'app';

  @override
  String get csBackToContent => 'Torna al contenuto';

  @override
  String get setLanguageGerman => 'Deutsch';

  @override
  String get setLanguageFrench => 'Français';

  @override
  String get setLanguagePortuguese => 'Português';

  @override
  String get setLanguageChinese => '中文';

  @override
  String get qlTrashDeletedNow => 'Eliminato adesso';

  @override
  String qlTrashDeletedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminato $count minuti fa',
      one: 'Eliminato $count minuto fa',
    );
    return '$_temp0';
  }

  @override
  String qlTrashDeletedHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminato $count ore fa',
      one: 'Eliminato $count ora fa',
    );
    return '$_temp0';
  }

  @override
  String qlTrashDeletedDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminato $count giorni fa',
      one: 'Eliminato $count giorno fa',
    );
    return '$_temp0';
  }

  @override
  String get qlAdvancedLocalOnly =>
      'Questi strumenti di recupero servono solo quando è collegato un server o Google Drive.';

  @override
  String get qlNameRequired => 'Inserisci un nome';

  @override
  String get qlDuplicate => 'Duplica';

  @override
  String qlDuplicateTitle(String title) {
    return '$title (copia)';
  }

  @override
  String get qlDuplicated => 'Taccuino duplicato';

  @override
  String get qlDuplicateNoLocalCopy =>
      'Questo taccuino non è su questo dispositivo. Aprilo una volta per scaricarlo, poi duplicalo.';

  @override
  String get qlDeleteOrphanBody =>
      'Su questo dispositivo non resta nessuna copia di questo taccuino, quindi non si potrà ripristinare. Verrà rimosso dalla libreria.';

  @override
  String get qlDeletedNoTrash =>
      'Rimosso. Su questo dispositivo non c\'era nessuna copia, quindi nulla è finito nel cestino.';

  @override
  String get qlOpenCorrupt =>
      'I dati di questo taccuino sono danneggiati e non si possono aprire.';

  @override
  String qlSearchNoResults(String query) {
    return 'Nessun taccuino corrisponde a “$query”.';
  }

  @override
  String get qcMouseSelectHint =>
      'Il mouse seleziona mentre è attiva una penna: per disegnare col mouse attivalo.';

  @override
  String get qcMouseDrawEnable => 'Disegna col mouse';

  @override
  String qiIssueRemoteImage(String arg) {
    return 'Immagine remota non scaricata: $arg';
  }

  @override
  String qiIssueImageNotFound(String arg) {
    return 'Immagine non trovata: $arg';
  }

  @override
  String qiIssueImageUnreadable(String arg) {
    return 'Immagine illeggibile: $arg';
  }

  @override
  String qiIssueAttachmentUnsupported(String arg) {
    return 'Allegato non supportato (solo immagini): $arg';
  }

  @override
  String qiIssueAttachmentTooLarge(String arg) {
    return 'Allegato troppo grande, saltato: $arg';
  }

  @override
  String qiIssueEmbedUnsupported(String arg) {
    return 'Incorporamento non importato (solo immagini e note): $arg';
  }

  @override
  String qiIssueNoteEmbedNotFound(String arg) {
    return 'Nota incorporata non trovata: $arg';
  }

  @override
  String qiIssueNoteEmbedSkipped(String arg) {
    return 'Nota incorporata non espansa (circolare o troppo annidata): $arg';
  }

  @override
  String get qiIssueFileUnreadable => 'File illeggibile';

  @override
  String qiIssueFileTooLarge(int count) {
    return 'File troppo grande ($count MB), saltato';
  }

  @override
  String get qiIssueEncodingFallback =>
      'Il testo non era UTF-8 valido: letto come Latin-1';

  @override
  String get qiIssueCsvUnreadable => 'Tabella illeggibile';

  @override
  String qiIssueZipEntryTooLarge(int count) {
    return 'Elemento dell\'archivio troppo grande ($count MB), saltato';
  }

  @override
  String qiIssueZipTotalTooLarge(int count) {
    return 'Il contenuto dell\'archivio supera $count MB: i file restanti sono stati saltati';
  }

  @override
  String qiIssueHiddenFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count note in cartelle nascoste sono state saltate',
      one: '1 nota in una cartella nascosta è stata saltata',
    );
    return '$_temp0';
  }

  @override
  String qiIssueTooManyChapters(int count) {
    return '$count capitoli: valuta di importare le sottocartelle separatamente';
  }

  @override
  String qiIssuePagesTruncated(int count) {
    return 'Nota troncata dopo $count pagine';
  }

  @override
  String qiIssueOneNoteSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi non supportati saltati',
      one: '1 elemento non supportato saltato',
    );
    return '$_temp0';
  }

  @override
  String get qiErrNoMarkdown =>
      'Nessun file Markdown (.md) nella cartella scelta';

  @override
  String get qiErrNoNotionContent =>
      'Lo zip non contiene file .md o .csv: serve un export Notion «Markdown e CSV»';

  @override
  String get qiErrNothingImportable => 'Nessun contenuto importabile';

  @override
  String get qiErrZipUnreadable =>
      'Il file zip è danneggiato o non è un archivio valido';

  @override
  String get qiErrNoOneNotePages => 'Nessuna pagina importabile in questo file';

  @override
  String get qiErrUnexpected => 'errore imprevisto';

  @override
  String qiOneNoteSection(int n) {
    return 'Sezione $n';
  }

  @override
  String get qiOneNotePage => 'Pagina';

  @override
  String get qiPdfNotPdf => 'Questo file non è un PDF valido';

  @override
  String get qiPdfCorrupt =>
      'Questo PDF è danneggiato o incompleto e non può essere letto';

  @override
  String get qiPdfEmpty => 'Questo PDF non contiene pagine';

  @override
  String get qiPdfUnsupported =>
      'Questo PDF usa una protezione o una funzione non supportata';

  @override
  String get qiPdfPasswordCancelled =>
      'Importazione annullata: password non fornita';

  @override
  String get qiPdfImportFailed => 'Impossibile importare il PDF';

  @override
  String get qiPdfPasswordTitle => 'PDF protetto da password';

  @override
  String get qiPdfPasswordBody =>
      'Inserisci la password per importare questo PDF.';

  @override
  String get qiPdfPasswordHint => 'Password';

  @override
  String get qiPdfPasswordWrong => 'Password errata, riprova';

  @override
  String get qiPdfPasswordOpen => 'Apri';

  @override
  String qiPdfPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Il PDF ha $count pagine.',
      one: 'Il PDF ha 1 pagina.',
    );
    return '$_temp0';
  }

  @override
  String qiPdfStartOutOfRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Il PDF ha $count pagine. Inizio fuori range.',
      one: 'Il PDF ha 1 pagina. Inizio fuori range.',
    );
    return '$_temp0';
  }

  @override
  String get qsReauthBanner =>
      'Il server non accetta più il tuo accesso. Le modifiche restano al sicuro su questo dispositivo e si sincronizzeranno dopo il nuovo accesso.';

  @override
  String get qsDriveReauthBanner =>
      'Google Drive chiede di accedere di nuovo. Le modifiche sono al sicuro su questo dispositivo e si sincronizzano appena accedi.';

  @override
  String get qsBrowserStorageFull =>
      'Il browser non ha più spazio per salvare: le ultime modifiche potrebbero andare perse ricaricando la pagina. Esporta i quaderni o libera spazio.';

  @override
  String get qsReauthAction => 'Accedi di nuovo';

  @override
  String qsDeletedElsewhere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count quaderni sono stati eliminati su un altro dispositivo. Le tue copie restano solo qui.',
      one:
          '$count quaderno è stato eliminato su un altro dispositivo. La tua copia resta solo qui.',
    );
    return '$_temp0';
  }

  @override
  String get qsDeletedElsewhereHint =>
      'Tieni premuto un quaderno e scegli \"Torna a sincronizzare questo quaderno\" per caricarlo di nuovo.';

  @override
  String get qsRefreshTooltip => 'Aggiorna dal server';

  @override
  String get qsResumeSyncPending =>
      'Server non raggiungibile. Questo quaderno verrà caricato appena torna disponibile.';

  @override
  String get qsResumeSyncUploaded =>
      'Caricato. Questo quaderno si sincronizza di nuovo.';

  @override
  String get qsNoServerConnected => 'Nessun server collegato.';

  @override
  String get qsLoginWrongCredentials =>
      'Il server ha rifiutato nome utente o password.';

  @override
  String get qsLoginNotAServer =>
      'Nessun server Nextcloud o WebDAV trovato a questo indirizzo. Controlla l\'URL.';

  @override
  String get qsLoginUnreachable =>
      'Impossibile raggiungere il server. Controlla l\'indirizzo e la connessione.';

  @override
  String get qsLoginThrottled =>
      'Troppi tentativi. Il server chiede di attendere un po\' prima di riprovare.';

  @override
  String get qsLoginServerError =>
      'Il server ha restituito un errore. Riprova più tardi.';

  @override
  String get quPenNoMonitor => 'Nessun monitor attivo rilevato.';

  @override
  String get quPenNoDevice => 'Nessun dispositivo penna trovato.';

  @override
  String get quPenBadGeometry => 'Geometria del desktop non valida.';

  @override
  String quPenToolMissing(String tool) {
    return '$tool non trovato.';
  }

  @override
  String quPenToolFailed(String tool) {
    return '$tool ha restituito un errore.';
  }

  @override
  String get quDiffStrokes => 'Tratti';

  @override
  String get quDiffImages => 'Immagini';

  @override
  String get quDiffShapes => 'Forme';

  @override
  String get quDiffTexts => 'Testi';

  @override
  String get quDefaultChapter => 'Capitolo 1';

  @override
  String qtNeedsOpenToUpload(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count quaderni sono cambiati anche su un altro dispositivo',
      one: '$count quaderno è cambiato anche su un altro dispositivo',
    );
    return '$_temp0';
  }

  @override
  String get qtNeedsOpenToUploadHint =>
      'Aprilo per unire e caricare le tue modifiche.';

  @override
  String get qtResumeSyncNeedsOpen =>
      'Il quaderno si sincronizza di nuovo. Aprilo per unire le modifiche fatte su un altro dispositivo.';

  @override
  String libImportSuccessMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Importati $count quaderni',
      one: 'Importato $count quaderno',
    );
    return '$_temp0';
  }

  @override
  String get pgtTitlePages => 'Pagine';

  @override
  String pgtEyebrow(String notebook, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '1 pagina',
    );
    return '$notebook · $_temp0';
  }

  @override
  String get pgtSelect => 'Seleziona';

  @override
  String get pgtSelectPages => 'Seleziona pagine';

  @override
  String get pgtAll => 'Tutte';

  @override
  String get pgtNone => 'Nessuna';

  @override
  String get pgtDone => 'Fine';

  @override
  String get pgtNoChapter => 'Nessun capitolo';

  @override
  String get pgtCopy => 'Copia';

  @override
  String get pgtMove => 'Sposta';

  @override
  String get pgtTagMoving => 'in spostamento';

  @override
  String get pgtHintPlaceMove =>
      'Tocca una pagina per metterle dopo di essa, o il suo bordo sinistro per metterle prima. Non cambia nulla finché non confermi.';

  @override
  String get pgtHintPlaceCopy =>
      'Tocca una pagina per incollare dopo di essa, o il suo bordo sinistro per incollare prima.';

  @override
  String get pgtMoveHere => 'Sposta qui';

  @override
  String get pgtPasteHere => 'Incolla qui';

  @override
  String get pgtMoveShort => 'Sposta';

  @override
  String get pgtPasteShort => 'Incolla';

  @override
  String pgtPasteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '1 pagina',
    );
    return 'Incolla $_temp0';
  }

  @override
  String pgtPasteCountShort(int count) {
    return 'Incolla $count';
  }

  @override
  String get pgtThisNotebook => 'Questo taccuino';

  @override
  String get pgtAnotherNotebook => 'Altro taccuino…';

  @override
  String pgtMoveToNb(String notebook) {
    return 'Sposta in $notebook';
  }

  @override
  String pgtPasteIntoNb(String notebook) {
    return 'Incolla in $notebook';
  }

  @override
  String get pgtPosStart => 'All\'inizio';

  @override
  String pgtPosAfter(int page) {
    return 'Dopo la pagina $page';
  }

  @override
  String get pgtPosEnd => 'In fondo';

  @override
  String pgtPosChapterEnd(String chapter) {
    return 'Fine di $chapter';
  }

  @override
  String get pgtChapterMenuHead => 'Capitolo per le pagine';

  @override
  String pgtTrayMoving(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine · in spostamento',
      one: '1 pagina · in spostamento',
    );
    return '$_temp0';
  }

  @override
  String pgtTrayCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine · copiate',
      one: '1 pagina · copiata',
    );
    return '$_temp0';
  }

  @override
  String get pgtSavedShort => 'Salvato';

  @override
  String get pgtSavedLong =>
      'Salvato su questo dispositivo. Resta anche dopo la chiusura dell\'app.';

  @override
  String pgtFrom(String notebook) {
    return 'da $notebook';
  }

  @override
  String pgtFromChapter(String notebook, String chapter) {
    return 'da $notebook › $chapter';
  }

  @override
  String pgtFromSeveral(String notebook) {
    return 'da $notebook › più capitoli';
  }

  @override
  String pgtSourceDeleted(String notebook) {
    return '$notebook è stato eliminato, queste pagine ora sono una copia';
  }

  @override
  String get pgtTrayOptions => 'Opzioni degli appunti';

  @override
  String get pgtCancelMove => 'Annulla spostamento';

  @override
  String get pgtCancelMoveHint => 'Le pagine non sono mai state rimosse';

  @override
  String get pgtClearTray => 'Svuota gli appunti';

  @override
  String get pgtChooseWhere => 'Scegli dove, in Pagine';

  @override
  String get pgtChooseWhereHint =>
      'Apre le pagine di questo taccuino, pronte per incollare gli appunti';

  @override
  String pgtOpenSource(String notebook) {
    return 'Apri $notebook';
  }

  @override
  String get pgtOpenSourceHint => 'Da dove vengono queste pagine';

  @override
  String get pgtUndo => 'Annulla';

  @override
  String get pgtShow => 'Mostra';

  @override
  String pgtChooserTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '1 pagina',
    );
    return 'Sposta $_temp0 in…';
  }

  @override
  String get pgtRecent => 'Recenti';

  @override
  String get pgtChooserEmpty =>
      'Non ci sono altri taccuini su questo dispositivo.';

  @override
  String get pgtBrowseLibrary => 'Sfoglia la libreria';

  @override
  String pgtNbPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '1 pagina',
    );
    return '$_temp0';
  }

  @override
  String pgtNbChapters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capitoli',
      one: '1 capitolo',
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
      other: '$count pagine',
      one: '1 pagina',
    );
    return 'Scegli un taccuino in cui spostare $_temp0. Tocca una copertina o usa il suo menu …';
  }

  @override
  String pgtLibHintPaste(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '1 pagina',
    );
    return 'Scegli un taccuino in cui incollare $_temp0. Tocca una copertina o usa il suo menu …';
  }

  @override
  String pgtBadgeMoving(int count) {
    return '$count in spostamento';
  }

  @override
  String pgtCardMoveHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '1 pagina',
    );
    return 'Sposta qui $_temp0';
  }

  @override
  String pgtCardPasteHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pagine',
      one: '1 pagina',
    );
    return 'Incolla qui $_temp0';
  }

  @override
  String pgtCardEndOfChapter(String chapter) {
    return 'In fondo a $chapter';
  }

  @override
  String get pgtCardAtEnd => 'In fondo';

  @override
  String get pgtWhereStart => 'all\'inizio';

  @override
  String pgtWhereAfter(int page) {
    return 'dopo la pagina $page';
  }

  @override
  String get pgtWhereEnd => 'in fondo';

  @override
  String pgtWhereChapterEnd(String chapter) {
    return 'in fondo a $chapter';
  }

  @override
  String pgtToastCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copiate $count pagine. Apri un taccuino per incollare.',
      one: 'Copiata 1 pagina. Apri un taccuino per incollare.',
    );
    return '$_temp0';
  }

  @override
  String pgtToastCopiedSkipped(int count, int skipped) {
    return 'Copiate $count pagine; $skipped non ancora caricate sono state saltate.';
  }

  @override
  String pgtToastMoveReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count pagine pronte da spostare. Non cambia nulla finché non confermi.',
      one: '1 pagina pronta da spostare. Non cambia nulla finché non confermi.',
    );
    return '$_temp0';
  }

  @override
  String pgtToastMoveReadySkipped(int count, int skipped) {
    return '$count pagine pronte da spostare; $skipped non ancora caricate sono state saltate. Non cambia nulla finché non confermi.';
  }

  @override
  String pgtToastMoveCancelled(int count, String notebook) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spostamento annullato. $count pagine restano in $notebook.',
      one: 'Spostamento annullato. 1 pagina resta in $notebook.',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastTrayCleared => 'Appunti svuotati';

  @override
  String pgtToastPasted(int count, String notebook, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Incollate $count pagine in $notebook, $where',
      one: 'Incollata 1 pagina in $notebook, $where',
    );
    return '$_temp0';
  }

  @override
  String pgtToastMoved(int count, String notebook, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Spostate $count pagine in $notebook, $where',
      one: 'Spostata 1 pagina in $notebook, $where',
    );
    return '$_temp0';
  }

  @override
  String pgtToastDuplicated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Duplicate $count pagine',
      one: 'Duplicata 1 pagina',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastUndone => 'Annullato';

  @override
  String pgtToastTooMany(int max) {
    return 'Negli appunti ci stanno al massimo $max pagine. Selezionane di meno.';
  }

  @override
  String get pgtToastNothing =>
      'Queste pagine non sono ancora pronte (in caricamento). Riprova tra un momento.';

  @override
  String get pgtToastTrayNotSaved =>
      'Impossibile salvare gli appunti su questo dispositivo. Andranno persi alla chiusura dell\'app.';

  @override
  String get pgtToastPagesGone =>
      'Queste pagine non sono più in questo taccuino.';

  @override
  String get pgtToastTrayDamaged =>
      'Gli appunti salvati sono incompleti, non è stato incollato nulla.';

  @override
  String get pgtToastDestFailed =>
      'Impossibile salvare le pagine incollate. Non è cambiato nulla.';

  @override
  String get pgtToastDestUnavailable =>
      'Questo taccuino non si può modificare ora. Non è cambiato nulla.';

  @override
  String pgtToastSourceFailed(String notebook) {
    return 'Le pagine sono state aggiunte, ma non si sono potute rimuovere da $notebook. Ora sono in entrambi i taccuini; le pagine negli appunti sono diventate una copia.';
  }

  @override
  String pgtToastMoveResumed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Completato lo spostamento di $count pagine rimasto a metà.',
      one: 'Completato lo spostamento di 1 pagina rimasto a metà.',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastUndoFailed =>
      'Impossibile annullare. Controlla i due taccuini.';
}
