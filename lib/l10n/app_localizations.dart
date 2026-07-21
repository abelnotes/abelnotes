import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('it')
  ];

  /// No description provided for @csPdfTextCopied.
  ///
  /// In it, this message translates to:
  /// **'Testo copiato'**
  String get csPdfTextCopied;

  /// No description provided for @csCopyFailed.
  ///
  /// In it, this message translates to:
  /// **'Copia non riuscita: {error}'**
  String csCopyFailed(String error);

  /// No description provided for @csCopy.
  ///
  /// In it, this message translates to:
  /// **'Copia'**
  String get csCopy;

  /// No description provided for @csSyncInProgress.
  ///
  /// In it, this message translates to:
  /// **'Sincronizzazione in corso…'**
  String get csSyncInProgress;

  /// No description provided for @csSaved.
  ///
  /// In it, this message translates to:
  /// **'Salvato!'**
  String get csSaved;

  /// No description provided for @csErrorGeneric.
  ///
  /// In it, this message translates to:
  /// **'Errore: {error}'**
  String csErrorGeneric(String error);

  /// No description provided for @csSelectionCopied.
  ///
  /// In it, this message translates to:
  /// **'Selezione copiata'**
  String get csSelectionCopied;

  /// No description provided for @csSelectionCut.
  ///
  /// In it, this message translates to:
  /// **'Selezione tagliata'**
  String get csSelectionCut;

  /// No description provided for @csShortcutsTitle.
  ///
  /// In it, this message translates to:
  /// **'Scorciatoie tastiera'**
  String get csShortcutsTitle;

  /// No description provided for @csShortcutGroupGeneral.
  ///
  /// In it, this message translates to:
  /// **'Generale'**
  String get csShortcutGroupGeneral;

  /// No description provided for @csSaveNow.
  ///
  /// In it, this message translates to:
  /// **'Salva ora'**
  String get csSaveNow;

  /// No description provided for @csShortcutUndo.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get csShortcutUndo;

  /// No description provided for @csShortcutRedo.
  ///
  /// In it, this message translates to:
  /// **'Ripeti'**
  String get csShortcutRedo;

  /// No description provided for @csSelectAll.
  ///
  /// In it, this message translates to:
  /// **'Seleziona tutto'**
  String get csSelectAll;

  /// No description provided for @csShortcutResetZoom.
  ///
  /// In it, this message translates to:
  /// **'Azzera zoom'**
  String get csShortcutResetZoom;

  /// No description provided for @csShortcutDeselect.
  ///
  /// In it, this message translates to:
  /// **'Deseleziona / annulla'**
  String get csShortcutDeselect;

  /// No description provided for @csShortcutThisGuide.
  ///
  /// In it, this message translates to:
  /// **'Questa guida'**
  String get csShortcutThisGuide;

  /// No description provided for @csShortcutGroupClipboard.
  ///
  /// In it, this message translates to:
  /// **'Appunti'**
  String get csShortcutGroupClipboard;

  /// No description provided for @csShortcutCopySelection.
  ///
  /// In it, this message translates to:
  /// **'Copia selezione'**
  String get csShortcutCopySelection;

  /// No description provided for @csShortcutCutSelection.
  ///
  /// In it, this message translates to:
  /// **'Taglia selezione'**
  String get csShortcutCutSelection;

  /// No description provided for @csPaste.
  ///
  /// In it, this message translates to:
  /// **'Incolla'**
  String get csPaste;

  /// No description provided for @csShortcutDuplicateSelection.
  ///
  /// In it, this message translates to:
  /// **'Duplica selezione'**
  String get csShortcutDuplicateSelection;

  /// No description provided for @csShortcutKeyDeleteBackspace.
  ///
  /// In it, this message translates to:
  /// **'Canc / Backspace'**
  String get csShortcutKeyDeleteBackspace;

  /// No description provided for @csShortcutDeleteElementOrSelection.
  ///
  /// In it, this message translates to:
  /// **'Elimina elemento o selezione'**
  String get csShortcutDeleteElementOrSelection;

  /// No description provided for @csShortcutGroupTools.
  ///
  /// In it, this message translates to:
  /// **'Strumenti'**
  String get csShortcutGroupTools;

  /// No description provided for @csToolPen.
  ///
  /// In it, this message translates to:
  /// **'Penna'**
  String get csToolPen;

  /// No description provided for @csToolBrush.
  ///
  /// In it, this message translates to:
  /// **'Pennello'**
  String get csToolBrush;

  /// No description provided for @csToolEraser.
  ///
  /// In it, this message translates to:
  /// **'Gomma'**
  String get csToolEraser;

  /// No description provided for @csToolLasso.
  ///
  /// In it, this message translates to:
  /// **'Lazo'**
  String get csToolLasso;

  /// No description provided for @csToolHand.
  ///
  /// In it, this message translates to:
  /// **'Mano / sposta'**
  String get csToolHand;

  /// No description provided for @csToolText.
  ///
  /// In it, this message translates to:
  /// **'Testo'**
  String get csToolText;

  /// No description provided for @csToolShape.
  ///
  /// In it, this message translates to:
  /// **'Forma'**
  String get csToolShape;

  /// No description provided for @csClose.
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get csClose;

  /// No description provided for @csUnsavedChangesTitle.
  ///
  /// In it, this message translates to:
  /// **'Modifiche non salvate'**
  String get csUnsavedChangesTitle;

  /// No description provided for @csUnsavedChangesBody.
  ///
  /// In it, this message translates to:
  /// **'Vuoi salvare prima di uscire?'**
  String get csUnsavedChangesBody;

  /// No description provided for @csDiscard.
  ///
  /// In it, this message translates to:
  /// **'Scarta'**
  String get csDiscard;

  /// No description provided for @csCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get csCancel;

  /// No description provided for @csSave.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get csSave;

  /// No description provided for @csOpeningLink.
  ///
  /// In it, this message translates to:
  /// **'Apertura link…'**
  String get csOpeningLink;

  /// No description provided for @csCannotOpenLink.
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire il link'**
  String get csCannotOpenLink;

  /// No description provided for @csCameraUnavailable.
  ///
  /// In it, this message translates to:
  /// **'Fotocamera non disponibile su questo dispositivo'**
  String get csCameraUnavailable;

  /// No description provided for @csPhotoCaptureFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile scattare la foto'**
  String get csPhotoCaptureFailed;

  /// No description provided for @csPdfRasterizing.
  ///
  /// In it, this message translates to:
  /// **'Rasterizzazione PDF in corso…'**
  String get csPdfRasterizing;

  /// No description provided for @csPdfImportProgress.
  ///
  /// In it, this message translates to:
  /// **'Importazione PDF: {done}/{total}'**
  String csPdfImportProgress(int done, int total);

  /// No description provided for @csPdfReadFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile leggere il PDF: nessuna pagina trovata'**
  String get csPdfReadFailed;

  /// No description provided for @csPdfImported.
  ///
  /// In it, this message translates to:
  /// **'PDF importato: {count, plural, one{{count} pagina} other{{count} pagine}}'**
  String csPdfImported(int count);

  /// No description provided for @csPdfImportError.
  ///
  /// In it, this message translates to:
  /// **'Errore importazione PDF: {error}'**
  String csPdfImportError(String error);

  /// No description provided for @csNoNotebookOpen.
  ///
  /// In it, this message translates to:
  /// **'Nessun notebook aperto'**
  String get csNoNotebookOpen;

  /// No description provided for @csMissingPageDataTitle.
  ///
  /// In it, this message translates to:
  /// **'Dati pagina mancanti'**
  String get csMissingPageDataTitle;

  /// No description provided for @csNoPages.
  ///
  /// In it, this message translates to:
  /// **'Nessuna pagina'**
  String get csNoPages;

  /// No description provided for @csMissingPagesBodyMany.
  ///
  /// In it, this message translates to:
  /// **'Questa pagina e altre {count} non sono state recuperate dal server. I file potrebbero essere andati persi durante una sincronizzazione parziale.'**
  String csMissingPagesBodyMany(int count);

  /// No description provided for @csMissingPageBodyOne.
  ///
  /// In it, this message translates to:
  /// **'Il file di questa pagina non è stato recuperato dal server. Potrebbe essere andato perso durante una sincronizzazione parziale.'**
  String get csMissingPageBodyOne;

  /// No description provided for @csRetrySync.
  ///
  /// In it, this message translates to:
  /// **'Riprova sync'**
  String get csRetrySync;

  /// No description provided for @csRestoreAsBlankPage.
  ///
  /// In it, this message translates to:
  /// **'Ripristina come pagina vuota'**
  String get csRestoreAsBlankPage;

  /// No description provided for @csRestoreAllMissing.
  ///
  /// In it, this message translates to:
  /// **'Ripristina tutte ({count})'**
  String csRestoreAllMissing(int count);

  /// No description provided for @csPagesRestoredBlank.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} pagina ripristinata come vuota} other{{count} pagine ripristinate come vuote}}'**
  String csPagesRestoredBlank(int count);

  /// No description provided for @csDeletePage.
  ///
  /// In it, this message translates to:
  /// **'Elimina pagina'**
  String get csDeletePage;

  /// No description provided for @csSyncProgressCount.
  ///
  /// In it, this message translates to:
  /// **'Sincronizzazione {done}/{total}'**
  String csSyncProgressCount(int done, int total);

  /// No description provided for @csSyncing.
  ///
  /// In it, this message translates to:
  /// **'Sincronizzazione…'**
  String get csSyncing;

  /// No description provided for @csShapeRecognizedLabel.
  ///
  /// In it, this message translates to:
  /// **'Forma: {shape}'**
  String csShapeRecognizedLabel(String shape);

  /// No description provided for @csConfirmShapeSemantics.
  ///
  /// In it, this message translates to:
  /// **'Conferma forma riconosciuta'**
  String get csConfirmShapeSemantics;

  /// No description provided for @csConfirm.
  ///
  /// In it, this message translates to:
  /// **'Conferma'**
  String get csConfirm;

  /// No description provided for @csCancelShapeSemantics.
  ///
  /// In it, this message translates to:
  /// **'Annulla forma riconosciuta'**
  String get csCancelShapeSemantics;

  /// No description provided for @csTapToPlaceSymbol.
  ///
  /// In it, this message translates to:
  /// **'Tocca per posizionare: {name}'**
  String csTapToPlaceSymbol(String name);

  /// No description provided for @csCancelSymbolInsertSemantics.
  ///
  /// In it, this message translates to:
  /// **'Annulla inserimento simbolo'**
  String get csCancelSymbolInsertSemantics;

  /// No description provided for @csTapToPlaceCopy.
  ///
  /// In it, this message translates to:
  /// **'Tocca per posizionare la copia'**
  String get csTapToPlaceCopy;

  /// No description provided for @csCancelPasteSemantics.
  ///
  /// In it, this message translates to:
  /// **'Annulla incolla'**
  String get csCancelPasteSemantics;

  /// No description provided for @csNewPage.
  ///
  /// In it, this message translates to:
  /// **'Nuova pagina'**
  String get csNewPage;

  /// No description provided for @csImageCopied.
  ///
  /// In it, this message translates to:
  /// **'Immagine copiata'**
  String get csImageCopied;

  /// No description provided for @csImageCut.
  ///
  /// In it, this message translates to:
  /// **'Immagine tagliata'**
  String get csImageCut;

  /// No description provided for @csImageCommentTitle.
  ///
  /// In it, this message translates to:
  /// **'Commento immagine'**
  String get csImageCommentTitle;

  /// No description provided for @csAddCommentHint.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi un commento...'**
  String get csAddCommentHint;

  /// No description provided for @csRemove.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi'**
  String get csRemove;

  /// No description provided for @csCut.
  ///
  /// In it, this message translates to:
  /// **'Taglia'**
  String get csCut;

  /// No description provided for @csDuplicate.
  ///
  /// In it, this message translates to:
  /// **'Duplica'**
  String get csDuplicate;

  /// No description provided for @csSelectionDuplicated.
  ///
  /// In it, this message translates to:
  /// **'Selezione duplicata'**
  String get csSelectionDuplicated;

  /// No description provided for @csChangeColor.
  ///
  /// In it, this message translates to:
  /// **'Cambia colore'**
  String get csChangeColor;

  /// No description provided for @csThickness.
  ///
  /// In it, this message translates to:
  /// **'Spessore'**
  String get csThickness;

  /// No description provided for @csDelete.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get csDelete;

  /// No description provided for @csMore.
  ///
  /// In it, this message translates to:
  /// **'Altro'**
  String get csMore;

  /// No description provided for @csPresentationMode.
  ///
  /// In it, this message translates to:
  /// **'Modalità presentazione'**
  String get csPresentationMode;

  /// No description provided for @csPresentationModeSub.
  ///
  /// In it, this message translates to:
  /// **'Schermo intero, senza strumenti — ideale per mostrare le pagine'**
  String get csPresentationModeSub;

  /// No description provided for @csRecognizeHandwriting.
  ///
  /// In it, this message translates to:
  /// **'Riconosci calligrafia'**
  String get csRecognizeHandwriting;

  /// No description provided for @csRecognizeHandwritingSub.
  ///
  /// In it, this message translates to:
  /// **'Converte l\'inchiostro in testo cercabile (sul dispositivo)'**
  String get csRecognizeHandwritingSub;

  /// No description provided for @csRecognizeInProgress.
  ///
  /// In it, this message translates to:
  /// **'Riconoscimento in corso…'**
  String get csRecognizeInProgress;

  /// No description provided for @csRecognizeNothing.
  ///
  /// In it, this message translates to:
  /// **'Nessun testo riconosciuto.'**
  String get csRecognizeNothing;

  /// No description provided for @csRecognizeDone.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} riga riconosciuta} other{{count} righe riconosciute}}.'**
  String csRecognizeDone(int count);

  /// No description provided for @csRecognizeFailed.
  ///
  /// In it, this message translates to:
  /// **'Riconoscimento fallito: {error}'**
  String csRecognizeFailed(String error);

  /// No description provided for @csShareLink.
  ///
  /// In it, this message translates to:
  /// **'Condividi con link'**
  String get csShareLink;

  /// No description provided for @csShareLinkSub.
  ///
  /// In it, this message translates to:
  /// **'Carica un PDF sul tuo Nextcloud e genera un link pubblico'**
  String get csShareLinkSub;

  /// No description provided for @csShareLinkInProgress.
  ///
  /// In it, this message translates to:
  /// **'Creazione link in corso…'**
  String get csShareLinkInProgress;

  /// No description provided for @csShareLinkTitle.
  ///
  /// In it, this message translates to:
  /// **'Link pubblico'**
  String get csShareLinkTitle;

  /// No description provided for @csShareLinkBody.
  ///
  /// In it, this message translates to:
  /// **'Chiunque abbia questo link può vedere il PDF. Revocabile dal tuo Nextcloud.'**
  String get csShareLinkBody;

  /// No description provided for @csShareLinkCopied.
  ///
  /// In it, this message translates to:
  /// **'Link copiato negli appunti.'**
  String get csShareLinkCopied;

  /// No description provided for @csShareLinkFailed.
  ///
  /// In it, this message translates to:
  /// **'Condivisione fallita: {error}'**
  String csShareLinkFailed(String error);

  /// No description provided for @csCopyLink.
  ///
  /// In it, this message translates to:
  /// **'Copia link'**
  String get csCopyLink;

  /// No description provided for @csShare.
  ///
  /// In it, this message translates to:
  /// **'Condividi'**
  String get csShare;

  /// No description provided for @csRevokeLink.
  ///
  /// In it, this message translates to:
  /// **'Revoca link'**
  String get csRevokeLink;

  /// No description provided for @csRevokeLinkDone.
  ///
  /// In it, this message translates to:
  /// **'Link revocato.'**
  String get csRevokeLinkDone;

  /// No description provided for @csShareLinkUpdate.
  ///
  /// In it, this message translates to:
  /// **'Aggiorna PDF condiviso'**
  String get csShareLinkUpdate;

  /// No description provided for @csShareLinkUpdated.
  ///
  /// In it, this message translates to:
  /// **'PDF aggiornato.'**
  String get csShareLinkUpdated;

  /// No description provided for @csChangeSelectionColor.
  ///
  /// In it, this message translates to:
  /// **'Cambia colore selezione'**
  String get csChangeSelectionColor;

  /// No description provided for @csSelectionThickness.
  ///
  /// In it, this message translates to:
  /// **'Spessore selezione'**
  String get csSelectionThickness;

  /// No description provided for @csWidthPx.
  ///
  /// In it, this message translates to:
  /// **'{width} px'**
  String csWidthPx(String width);

  /// No description provided for @csFlipHorizontal.
  ///
  /// In it, this message translates to:
  /// **'Rifletti orizzontalmente'**
  String get csFlipHorizontal;

  /// No description provided for @csFlipVertical.
  ///
  /// In it, this message translates to:
  /// **'Rifletti verticalmente'**
  String get csFlipVertical;

  /// No description provided for @csCopyAsImage.
  ///
  /// In it, this message translates to:
  /// **'Copia come immagine'**
  String get csCopyAsImage;

  /// No description provided for @csPasteInAnotherNotebook.
  ///
  /// In it, this message translates to:
  /// **'Incolla in un altro taccuino…'**
  String get csPasteInAnotherNotebook;

  /// No description provided for @csKeyDelete.
  ///
  /// In it, this message translates to:
  /// **'Canc'**
  String get csKeyDelete;

  /// No description provided for @csCreateSymbol.
  ///
  /// In it, this message translates to:
  /// **'Crea simbolo'**
  String get csCreateSymbol;

  /// No description provided for @csSelect.
  ///
  /// In it, this message translates to:
  /// **'Seleziona'**
  String get csSelect;

  /// No description provided for @csImportFile.
  ///
  /// In it, this message translates to:
  /// **'Importa file…'**
  String get csImportFile;

  /// No description provided for @csTakePhoto.
  ///
  /// In it, this message translates to:
  /// **'Scatta foto'**
  String get csTakePhoto;

  /// No description provided for @csInsertText.
  ///
  /// In it, this message translates to:
  /// **'Inserisci testo'**
  String get csInsertText;

  /// No description provided for @csInsertSymbolCount.
  ///
  /// In it, this message translates to:
  /// **'Inserisci simbolo ({count})'**
  String csInsertSymbolCount(int count);

  /// No description provided for @csClearPage.
  ///
  /// In it, this message translates to:
  /// **'Cancella pagina'**
  String get csClearPage;

  /// No description provided for @csExportPng.
  ///
  /// In it, this message translates to:
  /// **'Esporta PNG'**
  String get csExportPng;

  /// No description provided for @csExportPdf.
  ///
  /// In it, this message translates to:
  /// **'Esporta PDF'**
  String get csExportPdf;

  /// No description provided for @csClearPageConfirmBody.
  ///
  /// In it, this message translates to:
  /// **'Tutti gli elementi di questa pagina saranno eliminati. Continuare?'**
  String get csClearPageConfirmBody;

  /// No description provided for @csClear.
  ///
  /// In it, this message translates to:
  /// **'Cancella'**
  String get csClear;

  /// No description provided for @csCreateSymbolTitle.
  ///
  /// In it, this message translates to:
  /// **'Crea simbolo riutilizzabile'**
  String get csCreateSymbolTitle;

  /// No description provided for @csSymbolNameLabel.
  ///
  /// In it, this message translates to:
  /// **'Nome simbolo'**
  String get csSymbolNameLabel;

  /// No description provided for @csLibraryLabel.
  ///
  /// In it, this message translates to:
  /// **'Libreria:'**
  String get csLibraryLabel;

  /// No description provided for @csNoLibraryNotice.
  ///
  /// In it, this message translates to:
  /// **'Nessuna libreria esistente. Verrà creata una libreria \"Simboli\".'**
  String get csNoLibraryNotice;

  /// No description provided for @csCreate.
  ///
  /// In it, this message translates to:
  /// **'Crea'**
  String get csCreate;

  /// No description provided for @csSymbolCreated.
  ///
  /// In it, this message translates to:
  /// **'Simbolo \"{name}\" creato!'**
  String csSymbolCreated(String name);

  /// No description provided for @csSaveFileDialogTitle.
  ///
  /// In it, this message translates to:
  /// **'Salva {fileName}'**
  String csSaveFileDialogTitle(String fileName);

  /// No description provided for @csExportCurrentPagePng.
  ///
  /// In it, this message translates to:
  /// **'Pagina corrente (PNG)'**
  String get csExportCurrentPagePng;

  /// No description provided for @csExportCurrentChapter.
  ///
  /// In it, this message translates to:
  /// **'Capitolo corrente'**
  String get csExportCurrentChapter;

  /// No description provided for @csExportEntireNotebook.
  ///
  /// In it, this message translates to:
  /// **'Quaderno intero'**
  String get csExportEntireNotebook;

  /// No description provided for @csExportingPages.
  ///
  /// In it, this message translates to:
  /// **'Esportazione {count} pagine...'**
  String csExportingPages(int count);

  /// No description provided for @csChooseFolderForImages.
  ///
  /// In it, this message translates to:
  /// **'Scegli cartella per le {count} immagini'**
  String csChooseFolderForImages(int count);

  /// No description provided for @csPngExported.
  ///
  /// In it, this message translates to:
  /// **'PNG esportato ({count, plural, one{{count} pagina} other{{count} pagine}})'**
  String csPngExported(int count);

  /// No description provided for @csExportError.
  ///
  /// In it, this message translates to:
  /// **'Errore export: {error}'**
  String csExportError(String error);

  /// No description provided for @csExportCurrentPage.
  ///
  /// In it, this message translates to:
  /// **'Pagina corrente'**
  String get csExportCurrentPage;

  /// No description provided for @csGeneratingPdf.
  ///
  /// In it, this message translates to:
  /// **'Generazione PDF ({count, plural, one{{count} pagina} other{{count} pagine}})...'**
  String csGeneratingPdf(int count);

  /// No description provided for @csPdfExportError.
  ///
  /// In it, this message translates to:
  /// **'Errore export PDF: {error}'**
  String csPdfExportError(String error);

  /// No description provided for @csPdfExported.
  ///
  /// In it, this message translates to:
  /// **'PDF esportato: {count, plural, one{{count} pagina} other{{count} pagine}}'**
  String csPdfExported(int count);

  /// No description provided for @csChapterSeparatorEyebrow.
  ///
  /// In it, this message translates to:
  /// **'CAPITOLO'**
  String get csChapterSeparatorEyebrow;

  /// No description provided for @csSelectionCopiedAsImage.
  ///
  /// In it, this message translates to:
  /// **'Selezione copiata come immagine'**
  String get csSelectionCopiedAsImage;

  /// No description provided for @csCopyImageError.
  ///
  /// In it, this message translates to:
  /// **'Errore copia immagine: {error}'**
  String csCopyImageError(String error);

  /// No description provided for @csExport.
  ///
  /// In it, this message translates to:
  /// **'Esporta'**
  String get csExport;

  /// No description provided for @csPageNumber.
  ///
  /// In it, this message translates to:
  /// **'Pagina {number}'**
  String csPageNumber(int number);

  /// No description provided for @csPagesCount.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} pagina} other{{count} pagine}}'**
  String csPagesCount(int count);

  /// No description provided for @csExportChapterTitle.
  ///
  /// In it, this message translates to:
  /// **'Esporta capitolo'**
  String get csExportChapterTitle;

  /// No description provided for @csExportNotebookTitle.
  ///
  /// In it, this message translates to:
  /// **'Esporta quaderno intero'**
  String get csExportNotebookTitle;

  /// No description provided for @csChapterSeparatorQuestion.
  ///
  /// In it, this message translates to:
  /// **'Inserire una pagina separatore prima di ogni capitolo?'**
  String get csChapterSeparatorQuestion;

  /// No description provided for @csYesWithSeparators.
  ///
  /// In it, this message translates to:
  /// **'Sì, con separatori'**
  String get csYesWithSeparators;

  /// No description provided for @csNoPagesOnly.
  ///
  /// In it, this message translates to:
  /// **'No, solo le pagine'**
  String get csNoPagesOnly;

  /// No description provided for @csTotalPages.
  ///
  /// In it, this message translates to:
  /// **'Pagine totali: {count}'**
  String csTotalPages(int count);

  /// No description provided for @csFromPage.
  ///
  /// In it, this message translates to:
  /// **'Da pagina: {page}'**
  String csFromPage(int page);

  /// No description provided for @csToPage.
  ///
  /// In it, this message translates to:
  /// **'A pagina: {page}'**
  String csToPage(int page);

  /// No description provided for @csWillExportPages.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{Sarà esportata {count} pagina ({start}–{end})} other{Saranno esportate {count} pagine ({start}–{end})}}'**
  String csWillExportPages(int count, int start, int end);

  /// No description provided for @csChapterLabelWithCount.
  ///
  /// In it, this message translates to:
  /// **'{title} ({count, plural, one{{count} pagina} other{{count} pagine}})'**
  String csChapterLabelWithCount(String title, int count);

  /// No description provided for @csGoToPage.
  ///
  /// In it, this message translates to:
  /// **'Vai alla pagina'**
  String get csGoToPage;

  /// No description provided for @csDuplicatePage.
  ///
  /// In it, this message translates to:
  /// **'Duplica pagina'**
  String get csDuplicatePage;

  /// No description provided for @csNewPageAfter.
  ///
  /// In it, this message translates to:
  /// **'Nuova pagina dopo'**
  String get csNewPageAfter;

  /// No description provided for @csDeletePageConfirmTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare la pagina?'**
  String get csDeletePageConfirmTitle;

  /// No description provided for @csDeletePageConfirmBody.
  ///
  /// In it, this message translates to:
  /// **'La pagina {number} e tutto il suo contenuto verranno eliminati.'**
  String csDeletePageConfirmBody(int number);

  /// No description provided for @csExportAsPdf.
  ///
  /// In it, this message translates to:
  /// **'Esporta come PDF'**
  String get csExportAsPdf;

  /// No description provided for @csExportAsPng.
  ///
  /// In it, this message translates to:
  /// **'Esporta come PNG'**
  String get csExportAsPng;

  /// No description provided for @csExportAsNcnote.
  ///
  /// In it, this message translates to:
  /// **'Esporta come .ncnote (nativo)'**
  String get csExportAsNcnote;

  /// No description provided for @csExportNcnoteSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Formato nativo, qualità vettoriale piena (per backup o trasferimento)'**
  String get csExportNcnoteSubtitle;

  /// No description provided for @csGeneratingNcnote.
  ///
  /// In it, this message translates to:
  /// **'Generazione .ncnote in corso…'**
  String get csGeneratingNcnote;

  /// No description provided for @csNcnoteExported.
  ///
  /// In it, this message translates to:
  /// **'.ncnote esportato ({size} KB)'**
  String csNcnoteExported(String size);

  /// No description provided for @csNcnoteExportError.
  ///
  /// In it, this message translates to:
  /// **'Errore export .ncnote: {error}'**
  String csNcnoteExportError(String error);

  /// No description provided for @csImageOrPdf.
  ///
  /// In it, this message translates to:
  /// **'Immagine o PDF'**
  String get csImageOrPdf;

  /// No description provided for @csChangePaperType.
  ///
  /// In it, this message translates to:
  /// **'Cambia tipo di carta'**
  String get csChangePaperType;

  /// No description provided for @csPenToMonitor.
  ///
  /// In it, this message translates to:
  /// **'Penna → Monitor'**
  String get csPenToMonitor;

  /// No description provided for @csPenToMonitorSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Limita la penna a un singolo schermo'**
  String get csPenToMonitorSubtitle;

  /// No description provided for @csPaperType.
  ///
  /// In it, this message translates to:
  /// **'Tipo di carta'**
  String get csPaperType;

  /// No description provided for @csPaperBlank.
  ///
  /// In it, this message translates to:
  /// **'Bianco'**
  String get csPaperBlank;

  /// No description provided for @csPaperLinedNarrow.
  ///
  /// In it, this message translates to:
  /// **'Righe strette'**
  String get csPaperLinedNarrow;

  /// No description provided for @csPaperLinedWide.
  ///
  /// In it, this message translates to:
  /// **'Righe larghe'**
  String get csPaperLinedWide;

  /// No description provided for @csPaperGrid.
  ///
  /// In it, this message translates to:
  /// **'Quadretti'**
  String get csPaperGrid;

  /// No description provided for @csPaperDotted.
  ///
  /// In it, this message translates to:
  /// **'Puntinato'**
  String get csPaperDotted;

  /// No description provided for @csPaperCornell.
  ///
  /// In it, this message translates to:
  /// **'Cornell'**
  String get csPaperCornell;

  /// No description provided for @csPaperIsometric.
  ///
  /// In it, this message translates to:
  /// **'Isometrico'**
  String get csPaperIsometric;

  /// No description provided for @csPaperMusic.
  ///
  /// In it, this message translates to:
  /// **'Pentagramma'**
  String get csPaperMusic;

  /// No description provided for @csMapPenToMonitor.
  ///
  /// In it, this message translates to:
  /// **'Mappa penna su monitor'**
  String get csMapPenToMonitor;

  /// No description provided for @csPenMappedTo.
  ///
  /// In it, this message translates to:
  /// **'Penna mappata su {monitor}'**
  String csPenMappedTo(String monitor);

  /// No description provided for @csAllMonitors.
  ///
  /// In it, this message translates to:
  /// **'Tutti i monitor'**
  String get csAllMonitors;

  /// No description provided for @csAllMonitorsSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Ripristina (penna su tutto il desktop)'**
  String get csAllMonitorsSubtitle;

  /// No description provided for @csPenReset.
  ///
  /// In it, this message translates to:
  /// **'Penna ripristinata'**
  String get csPenReset;

  /// No description provided for @csShapeLine.
  ///
  /// In it, this message translates to:
  /// **'Linea'**
  String get csShapeLine;

  /// No description provided for @csShapeCircle.
  ///
  /// In it, this message translates to:
  /// **'Cerchio'**
  String get csShapeCircle;

  /// No description provided for @csShapeRectangle.
  ///
  /// In it, this message translates to:
  /// **'Rettangolo'**
  String get csShapeRectangle;

  /// No description provided for @csShapeTriangle.
  ///
  /// In it, this message translates to:
  /// **'Triangolo'**
  String get csShapeTriangle;

  /// No description provided for @csShapeArrow.
  ///
  /// In it, this message translates to:
  /// **'Freccia'**
  String get csShapeArrow;

  /// No description provided for @csInvalidRangeError.
  ///
  /// In it, this message translates to:
  /// **'Inserisci un intervallo valido (es. 1–10).'**
  String get csInvalidRangeError;

  /// No description provided for @csPdfStartOutOfRange.
  ///
  /// In it, this message translates to:
  /// **'Il PDF ha circa {count} pagine. Inizio fuori range.'**
  String csPdfStartOutOfRange(int count);

  /// No description provided for @csImportPdfTitle.
  ///
  /// In it, this message translates to:
  /// **'Importa PDF'**
  String get csImportPdfTitle;

  /// No description provided for @csPdfEstimatedPages.
  ///
  /// In it, this message translates to:
  /// **'Il PDF ha circa {count} pagine.'**
  String csPdfEstimatedPages(int count);

  /// No description provided for @csAllPagesWithCount.
  ///
  /// In it, this message translates to:
  /// **'Tutte le pagine ({count})'**
  String csAllPagesWithCount(int count);

  /// No description provided for @csAllPages.
  ///
  /// In it, this message translates to:
  /// **'Tutte le pagine'**
  String get csAllPages;

  /// No description provided for @csCustomRange.
  ///
  /// In it, this message translates to:
  /// **'Intervallo personalizzato'**
  String get csCustomRange;

  /// No description provided for @csFromLabel.
  ///
  /// In it, this message translates to:
  /// **'Da'**
  String get csFromLabel;

  /// No description provided for @csToLabel.
  ///
  /// In it, this message translates to:
  /// **'A'**
  String get csToLabel;

  /// No description provided for @csImport.
  ///
  /// In it, this message translates to:
  /// **'Importa'**
  String get csImport;

  /// No description provided for @libErrorGeneric.
  ///
  /// In it, this message translates to:
  /// **'Errore: {error}'**
  String libErrorGeneric(String error);

  /// No description provided for @libErrorOpen.
  ///
  /// In it, this message translates to:
  /// **'Errore apertura: {error}'**
  String libErrorOpen(String error);

  /// No description provided for @libImportCannotReadFile.
  ///
  /// In it, this message translates to:
  /// **'Impossibile leggere il file'**
  String get libImportCannotReadFile;

  /// No description provided for @libImportInProgress.
  ///
  /// In it, this message translates to:
  /// **'Importazione in corso…'**
  String get libImportInProgress;

  /// No description provided for @libServiceUnavailable.
  ///
  /// In it, this message translates to:
  /// **'Servizio non disponibile'**
  String get libServiceUnavailable;

  /// No description provided for @libImportedTitleSuffix.
  ///
  /// In it, this message translates to:
  /// **'{title} (importato)'**
  String libImportedTitleSuffix(String title);

  /// No description provided for @libImportSuccess.
  ///
  /// In it, this message translates to:
  /// **'Importato: \"{title}\" ({count, plural, one{{count} pagina} other{{count} pagine}})'**
  String libImportSuccess(String title, int count);

  /// No description provided for @libErrorImport.
  ///
  /// In it, this message translates to:
  /// **'Errore importazione: {error}'**
  String libErrorImport(String error);

  /// No description provided for @libErrorCreate.
  ///
  /// In it, this message translates to:
  /// **'Errore creazione: {error}'**
  String libErrorCreate(String error);

  /// No description provided for @libSketchDefaultTitle.
  ///
  /// In it, this message translates to:
  /// **'Schizzo'**
  String get libSketchDefaultTitle;

  /// No description provided for @libErrorCreateSketch.
  ///
  /// In it, this message translates to:
  /// **'Errore creazione schizzo: {error}'**
  String libErrorCreateSketch(String error);

  /// No description provided for @libRemoveFromFavorites.
  ///
  /// In it, this message translates to:
  /// **'Rimuovi dai preferiti'**
  String get libRemoveFromFavorites;

  /// No description provided for @libAddToFavorites.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi ai preferiti'**
  String get libAddToFavorites;

  /// No description provided for @libRename.
  ///
  /// In it, this message translates to:
  /// **'Rinomina'**
  String get libRename;

  /// No description provided for @libChangeCover.
  ///
  /// In it, this message translates to:
  /// **'Cambia copertina'**
  String get libChangeCover;

  /// No description provided for @libMoveToFolder.
  ///
  /// In it, this message translates to:
  /// **'Sposta in cartella'**
  String get libMoveToFolder;

  /// No description provided for @libNoFolder.
  ///
  /// In it, this message translates to:
  /// **'Nessuna cartella'**
  String get libNoFolder;

  /// No description provided for @libNewFolder.
  ///
  /// In it, this message translates to:
  /// **'Nuova cartella'**
  String get libNewFolder;

  /// No description provided for @libRenameFolder.
  ///
  /// In it, this message translates to:
  /// **'Rinomina cartella'**
  String get libRenameFolder;

  /// No description provided for @libFolderNameHint.
  ///
  /// In it, this message translates to:
  /// **'Nome cartella'**
  String get libFolderNameHint;

  /// No description provided for @libAllNotebooks.
  ///
  /// In it, this message translates to:
  /// **'Tutti'**
  String get libAllNotebooks;

  /// No description provided for @libDeleteFolder.
  ///
  /// In it, this message translates to:
  /// **'Elimina cartella'**
  String get libDeleteFolder;

  /// No description provided for @libDeleteFolderTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare la cartella \"{name}\"?'**
  String libDeleteFolderTitle(String name);

  /// No description provided for @libDeleteFolderBody.
  ///
  /// In it, this message translates to:
  /// **'I taccuini al suo interno non vengono eliminati, restano nella libreria senza cartella.'**
  String get libDeleteFolderBody;

  /// No description provided for @libDelete.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get libDelete;

  /// No description provided for @libDeleteNotebookTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare il taccuino?'**
  String get libDeleteNotebookTitle;

  /// No description provided for @libDeleteNotebookBody.
  ///
  /// In it, this message translates to:
  /// **'Verrà spostato nel cestino. Potrai ripristinarlo da Impostazioni > Spazio.'**
  String get libDeleteNotebookBody;

  /// No description provided for @libCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get libCancel;

  /// No description provided for @libRenameNotebookTitle.
  ///
  /// In it, this message translates to:
  /// **'Rinomina taccuino'**
  String get libRenameNotebookTitle;

  /// No description provided for @libSave.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get libSave;

  /// No description provided for @libSortTitle.
  ///
  /// In it, this message translates to:
  /// **'Ordinamento'**
  String get libSortTitle;

  /// No description provided for @libAppName.
  ///
  /// In it, this message translates to:
  /// **'AbelNotes'**
  String get libAppName;

  /// No description provided for @libSearchHintShort.
  ///
  /// In it, this message translates to:
  /// **'Cerca…'**
  String get libSearchHintShort;

  /// No description provided for @libSearchHintNotebooks.
  ///
  /// In it, this message translates to:
  /// **'Cerca taccuini…'**
  String get libSearchHintNotebooks;

  /// No description provided for @libImport.
  ///
  /// In it, this message translates to:
  /// **'Importa'**
  String get libImport;

  /// No description provided for @libImportTooltip.
  ///
  /// In it, this message translates to:
  /// **'Importa un file .ncnote'**
  String get libImportTooltip;

  /// No description provided for @libSettingsTooltip.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get libSettingsTooltip;

  /// No description provided for @libMoreTooltip.
  ///
  /// In it, this message translates to:
  /// **'Altro'**
  String get libMoreTooltip;

  /// No description provided for @libViewAsList.
  ///
  /// In it, this message translates to:
  /// **'Vista a lista'**
  String get libViewAsList;

  /// No description provided for @libViewAsGrid.
  ///
  /// In it, this message translates to:
  /// **'Vista a griglia'**
  String get libViewAsGrid;

  /// No description provided for @libSortWithLabel.
  ///
  /// In it, this message translates to:
  /// **'Ordinamento: {sortLabel}'**
  String libSortWithLabel(String sortLabel);

  /// No description provided for @libImportNcnoteMenu.
  ///
  /// In it, this message translates to:
  /// **'Importa…'**
  String get libImportNcnoteMenu;

  /// No description provided for @libYourNotebooks.
  ///
  /// In it, this message translates to:
  /// **'I tuoi taccuini'**
  String get libYourNotebooks;

  /// No description provided for @libItemsCount.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} elemento} other{{count} elementi}}'**
  String libItemsCount(int count);

  /// No description provided for @libNewNotebook.
  ///
  /// In it, this message translates to:
  /// **'Nuovo taccuino'**
  String get libNewNotebook;

  /// No description provided for @libSketches.
  ///
  /// In it, this message translates to:
  /// **'Schizzi'**
  String get libSketches;

  /// No description provided for @libInfiniteSpace.
  ///
  /// In it, this message translates to:
  /// **'spazio infinito'**
  String get libInfiniteSpace;

  /// No description provided for @libNewSketch.
  ///
  /// In it, this message translates to:
  /// **'Nuovo schizzo'**
  String get libNewSketch;

  /// No description provided for @libInfiniteCanvas.
  ///
  /// In it, this message translates to:
  /// **'Canvas infinito'**
  String get libInfiniteCanvas;

  /// No description provided for @libNew.
  ///
  /// In it, this message translates to:
  /// **'Nuovo'**
  String get libNew;

  /// No description provided for @libPagesAbbrev.
  ///
  /// In it, this message translates to:
  /// **'{count} pag.'**
  String libPagesAbbrev(int count);

  /// No description provided for @libPagesCount.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} pagina} other{{count} pagine}}'**
  String libPagesCount(int count);

  /// No description provided for @libFooterWebdav.
  ///
  /// In it, this message translates to:
  /// **'WebDAV'**
  String get libFooterWebdav;

  /// No description provided for @libFooterLocalFirst.
  ///
  /// In it, this message translates to:
  /// **'App locale-first'**
  String get libFooterLocalFirst;

  /// No description provided for @libSyncingWithServer.
  ///
  /// In it, this message translates to:
  /// **'Sincronizzazione con il server…'**
  String get libSyncingWithServer;

  /// No description provided for @libDownloadingProgress.
  ///
  /// In it, this message translates to:
  /// **'Scaricamento {done}/{total} taccuini…'**
  String libDownloadingProgress(int done, int total);

  /// No description provided for @libLoadingNotebooks.
  ///
  /// In it, this message translates to:
  /// **'Caricamento taccuini…'**
  String get libLoadingNotebooks;

  /// No description provided for @libLoadingNotebooksFromServer.
  ///
  /// In it, this message translates to:
  /// **'Caricamento taccuini dal server…'**
  String get libLoadingNotebooksFromServer;

  /// No description provided for @libTimeNow.
  ///
  /// In it, this message translates to:
  /// **'ora'**
  String get libTimeNow;

  /// No description provided for @libTimeMinutesAgo.
  ///
  /// In it, this message translates to:
  /// **'{count} min fa'**
  String libTimeMinutesAgo(int count);

  /// No description provided for @libTimeHoursAgo.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} ora fa} other{{count} ore fa}}'**
  String libTimeHoursAgo(int count);

  /// No description provided for @libTimeDaysAgo.
  ///
  /// In it, this message translates to:
  /// **'{count} g fa'**
  String libTimeDaysAgo(int count);

  /// No description provided for @libTimeWeeksAgo.
  ///
  /// In it, this message translates to:
  /// **'{count} sett. fa'**
  String libTimeWeeksAgo(int count);

  /// No description provided for @libTimeMonthsAgo.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} mese fa} other{{count} mesi fa}}'**
  String libTimeMonthsAgo(int count);

  /// No description provided for @libTimeYearsAgo.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} anno fa} other{{count} anni fa}}'**
  String libTimeYearsAgo(int count);

  /// No description provided for @libNotebookTitleLabel.
  ///
  /// In it, this message translates to:
  /// **'Titolo'**
  String get libNotebookTitleLabel;

  /// No description provided for @libCoverLabel.
  ///
  /// In it, this message translates to:
  /// **'Copertina'**
  String get libCoverLabel;

  /// No description provided for @libPaperLabel.
  ///
  /// In it, this message translates to:
  /// **'Carta'**
  String get libPaperLabel;

  /// No description provided for @libPaperBlank.
  ///
  /// In it, this message translates to:
  /// **'Bianco'**
  String get libPaperBlank;

  /// No description provided for @libPaperLined.
  ///
  /// In it, this message translates to:
  /// **'Righe'**
  String get libPaperLined;

  /// No description provided for @libPaperGrid.
  ///
  /// In it, this message translates to:
  /// **'Griglia'**
  String get libPaperGrid;

  /// No description provided for @libPaperDotted.
  ///
  /// In it, this message translates to:
  /// **'Puntinato'**
  String get libPaperDotted;

  /// No description provided for @libCreate.
  ///
  /// In it, this message translates to:
  /// **'Crea'**
  String get libCreate;

  /// No description provided for @setSectionGeneral.
  ///
  /// In it, this message translates to:
  /// **'Generale'**
  String get setSectionGeneral;

  /// No description provided for @setSectionInput.
  ///
  /// In it, this message translates to:
  /// **'Stylus & input'**
  String get setSectionInput;

  /// No description provided for @setSectionSync.
  ///
  /// In it, this message translates to:
  /// **'Sincronia'**
  String get setSectionSync;

  /// No description provided for @setSectionStorage.
  ///
  /// In it, this message translates to:
  /// **'Spazio'**
  String get setSectionStorage;

  /// No description provided for @setSectionShortcuts.
  ///
  /// In it, this message translates to:
  /// **'Scorciatoie'**
  String get setSectionShortcuts;

  /// No description provided for @setSectionAdvanced.
  ///
  /// In it, this message translates to:
  /// **'Avanzate'**
  String get setSectionAdvanced;

  /// No description provided for @setSectionAbout.
  ///
  /// In it, this message translates to:
  /// **'Informazioni'**
  String get setSectionAbout;

  /// No description provided for @setBackToLibrary.
  ///
  /// In it, this message translates to:
  /// **'Libreria'**
  String get setBackToLibrary;

  /// No description provided for @setSettingsTitle.
  ///
  /// In it, this message translates to:
  /// **'Impostazioni'**
  String get setSettingsTitle;

  /// No description provided for @setThemeLabel.
  ///
  /// In it, this message translates to:
  /// **'Tema'**
  String get setThemeLabel;

  /// No description provided for @setThemeLight.
  ///
  /// In it, this message translates to:
  /// **'Chiaro'**
  String get setThemeLight;

  /// No description provided for @setThemePaper.
  ///
  /// In it, this message translates to:
  /// **'Carta'**
  String get setThemePaper;

  /// No description provided for @setThemeDark.
  ///
  /// In it, this message translates to:
  /// **'Scuro'**
  String get setThemeDark;

  /// No description provided for @setLanguage.
  ///
  /// In it, this message translates to:
  /// **'Lingua'**
  String get setLanguage;

  /// No description provided for @setLanguageSub.
  ///
  /// In it, this message translates to:
  /// **'Lingua dell\'interfaccia'**
  String get setLanguageSub;

  /// No description provided for @setLanguageItalian.
  ///
  /// In it, this message translates to:
  /// **'Italiano'**
  String get setLanguageItalian;

  /// No description provided for @setFavoritesFirst.
  ///
  /// In it, this message translates to:
  /// **'Preferiti per primi'**
  String get setFavoritesFirst;

  /// No description provided for @setFavoritesFirstSub.
  ///
  /// In it, this message translates to:
  /// **'Mostra i taccuini preferiti in cima alla libreria'**
  String get setFavoritesFirstSub;

  /// No description provided for @setStylusOnly.
  ///
  /// In it, this message translates to:
  /// **'Solo stylus'**
  String get setStylusOnly;

  /// No description provided for @setStylusOnlySub.
  ///
  /// In it, this message translates to:
  /// **'Ignora il tocco del dito durante la scrittura. Pinch e pan continuano a funzionare con due dita.'**
  String get setStylusOnlySub;

  /// No description provided for @setPalmRejection.
  ///
  /// In it, this message translates to:
  /// **'Palm rejection'**
  String get setPalmRejection;

  /// No description provided for @setPalmRejectionSub.
  ///
  /// In it, this message translates to:
  /// **'Riconoscimento automatico del palmo appoggiato'**
  String get setPalmRejectionSub;

  /// No description provided for @setPressureThickness.
  ///
  /// In it, this message translates to:
  /// **'Pressione → spessore'**
  String get setPressureThickness;

  /// No description provided for @setPressureThicknessSub.
  ///
  /// In it, this message translates to:
  /// **'Modulazione di tratto in base alla pressione dello stylus'**
  String get setPressureThicknessSub;

  /// No description provided for @setTiltCalligraphy.
  ///
  /// In it, this message translates to:
  /// **'Tilt → calligrafia'**
  String get setTiltCalligraphy;

  /// No description provided for @setTiltCalligraphySub.
  ///
  /// In it, this message translates to:
  /// **'L\'inclinazione dello stylus altera larghezza e angolo del tratto'**
  String get setTiltCalligraphySub;

  /// No description provided for @setStrokeContinuation.
  ///
  /// In it, this message translates to:
  /// **'Continuazione tratto'**
  String get setStrokeContinuation;

  /// No description provided for @setStrokeContinuationSub.
  ///
  /// In it, this message translates to:
  /// **'Compensa brevi interruzioni del sensore (es. punto della i)'**
  String get setStrokeContinuationSub;

  /// No description provided for @setSyncConnectedDesc.
  ///
  /// In it, this message translates to:
  /// **'Connesso a un server WebDAV. I taccuini si sincronizzano su tutti i tuoi dispositivi.'**
  String get setSyncConnectedDesc;

  /// No description provided for @setSyncLocalOnlyDesc.
  ///
  /// In it, this message translates to:
  /// **'Modalità solo-locale: i taccuini restano su questo dispositivo. Connetti un server WebDAV per accedervi da più dispositivi.'**
  String get setSyncLocalOnlyDesc;

  /// No description provided for @setSyncWebdav.
  ///
  /// In it, this message translates to:
  /// **'WebDAV'**
  String get setSyncWebdav;

  /// No description provided for @setSyncLocalOnly.
  ///
  /// In it, this message translates to:
  /// **'Solo locale'**
  String get setSyncLocalOnly;

  /// No description provided for @setSyncAccountInfo.
  ///
  /// In it, this message translates to:
  /// **'{host} · {username}'**
  String setSyncAccountInfo(String host, String username);

  /// No description provided for @setSyncNoServer.
  ///
  /// In it, this message translates to:
  /// **'Nessun server connesso'**
  String get setSyncNoServer;

  /// No description provided for @setDisconnect.
  ///
  /// In it, this message translates to:
  /// **'Disconnetti'**
  String get setDisconnect;

  /// No description provided for @setConnect.
  ///
  /// In it, this message translates to:
  /// **'Connetti'**
  String get setConnect;

  /// No description provided for @setDisconnectTitle.
  ///
  /// In it, this message translates to:
  /// **'Disconnettere il server?'**
  String get setDisconnectTitle;

  /// No description provided for @setDisconnectBody.
  ///
  /// In it, this message translates to:
  /// **'I taccuini già scaricati restano su questo dispositivo. La sincronizzazione si interrompe finché non riconnetti.'**
  String get setDisconnectBody;

  /// No description provided for @setCheckCert.
  ///
  /// In it, this message translates to:
  /// **'Verifica certificato server'**
  String get setCheckCert;

  /// No description provided for @setCertCheckFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile verificare il certificato del server.'**
  String get setCertCheckFailed;

  /// No description provided for @setCertUnchanged.
  ///
  /// In it, this message translates to:
  /// **'Il certificato non è cambiato dall\'ultima connessione.'**
  String get setCertUnchanged;

  /// No description provided for @setCertChangedTitle.
  ///
  /// In it, this message translates to:
  /// **'Nuovo certificato rilevato'**
  String get setCertChangedTitle;

  /// No description provided for @setCertChangedBody.
  ///
  /// In it, this message translates to:
  /// **'Il server presenta un\'impronta diversa da quella salvata. Se hai rinnovato tu il certificato, conferma per continuare a sincronizzare. Se non sei stato tu, ANNULLA e controlla la tua rete prima di riprovare.\n\nImpronta salvata: {oldFingerprint}\nImpronta attuale: {newFingerprint}'**
  String setCertChangedBody(String oldFingerprint, String newFingerprint);

  /// No description provided for @setCertConfirmNew.
  ///
  /// In it, this message translates to:
  /// **'Conferma nuovo certificato'**
  String get setCertConfirmNew;

  /// No description provided for @setCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get setCancel;

  /// No description provided for @setShortcutPen.
  ///
  /// In it, this message translates to:
  /// **'Penna'**
  String get setShortcutPen;

  /// No description provided for @setShortcutUndo.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get setShortcutUndo;

  /// No description provided for @setShortcutBrush.
  ///
  /// In it, this message translates to:
  /// **'Pennello'**
  String get setShortcutBrush;

  /// No description provided for @setShortcutRedo.
  ///
  /// In it, this message translates to:
  /// **'Ripeti'**
  String get setShortcutRedo;

  /// No description provided for @setShortcutEraser.
  ///
  /// In it, this message translates to:
  /// **'Gomma'**
  String get setShortcutEraser;

  /// No description provided for @setShortcutSelectAll.
  ///
  /// In it, this message translates to:
  /// **'Seleziona tutto'**
  String get setShortcutSelectAll;

  /// No description provided for @setShortcutLasso.
  ///
  /// In it, this message translates to:
  /// **'Lasso'**
  String get setShortcutLasso;

  /// No description provided for @setShortcutCopy.
  ///
  /// In it, this message translates to:
  /// **'Copia'**
  String get setShortcutCopy;

  /// No description provided for @setShortcutHand.
  ///
  /// In it, this message translates to:
  /// **'Mano'**
  String get setShortcutHand;

  /// No description provided for @setShortcutCut.
  ///
  /// In it, this message translates to:
  /// **'Taglia'**
  String get setShortcutCut;

  /// No description provided for @setShortcutText.
  ///
  /// In it, this message translates to:
  /// **'Testo'**
  String get setShortcutText;

  /// No description provided for @setShortcutPaste.
  ///
  /// In it, this message translates to:
  /// **'Incolla'**
  String get setShortcutPaste;

  /// No description provided for @setShortcutShape.
  ///
  /// In it, this message translates to:
  /// **'Forma'**
  String get setShortcutShape;

  /// No description provided for @setShortcutDuplicate.
  ///
  /// In it, this message translates to:
  /// **'Duplica'**
  String get setShortcutDuplicate;

  /// No description provided for @setShortcutChangePage.
  ///
  /// In it, this message translates to:
  /// **'Cambia pagina'**
  String get setShortcutChangePage;

  /// No description provided for @setShortcutSave.
  ///
  /// In it, this message translates to:
  /// **'Salva'**
  String get setShortcutSave;

  /// No description provided for @setShortcutFit.
  ///
  /// In it, this message translates to:
  /// **'Adatta'**
  String get setShortcutFit;

  /// No description provided for @setShortcutCheatSheet.
  ///
  /// In it, this message translates to:
  /// **'Cheat sheet'**
  String get setShortcutCheatSheet;

  /// No description provided for @setKeyboardShortcutsTitle.
  ///
  /// In it, this message translates to:
  /// **'Scorciatoie da tastiera'**
  String get setKeyboardShortcutsTitle;

  /// No description provided for @setClearCache.
  ///
  /// In it, this message translates to:
  /// **'Pulisci cache'**
  String get setClearCache;

  /// No description provided for @setClearCacheSub.
  ///
  /// In it, this message translates to:
  /// **'Rimuove i file temporanei. I taccuini non vengono toccati.'**
  String get setClearCacheSub;

  /// No description provided for @setClear.
  ///
  /// In it, this message translates to:
  /// **'Pulisci'**
  String get setClear;

  /// No description provided for @setTrash.
  ///
  /// In it, this message translates to:
  /// **'Cestino'**
  String get setTrash;

  /// No description provided for @setTrashSub.
  ///
  /// In it, this message translates to:
  /// **'Taccuini eliminati, ripristinabili'**
  String get setTrashSub;

  /// No description provided for @setOpenTrash.
  ///
  /// In it, this message translates to:
  /// **'Apri cestino'**
  String get setOpenTrash;

  /// No description provided for @setClearCacheDone.
  ///
  /// In it, this message translates to:
  /// **'Cache pulita.'**
  String get setClearCacheDone;

  /// No description provided for @setExportLibrary.
  ///
  /// In it, this message translates to:
  /// **'Esporta libreria'**
  String get setExportLibrary;

  /// No description provided for @setExportLibrarySub.
  ///
  /// In it, this message translates to:
  /// **'Salva tutti i taccuini in un unico archivio zip.'**
  String get setExportLibrarySub;

  /// No description provided for @setExport.
  ///
  /// In it, this message translates to:
  /// **'Esporta'**
  String get setExport;

  /// No description provided for @setExportLibraryEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun taccuino da esportare.'**
  String get setExportLibraryEmpty;

  /// No description provided for @setExportLibraryInProgress.
  ///
  /// In it, this message translates to:
  /// **'Esportazione in corso…'**
  String get setExportLibraryInProgress;

  /// No description provided for @setExportLibraryDone.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{Esportato {count} taccuino} other{Esportati {count} taccuini}}.'**
  String setExportLibraryDone(int count);

  /// No description provided for @setExportLibraryFailed.
  ///
  /// In it, this message translates to:
  /// **'Esportazione fallita: {error}'**
  String setExportLibraryFailed(String error);

  /// No description provided for @setTrashPurgeTitle.
  ///
  /// In it, this message translates to:
  /// **'Eliminare definitivamente \"{title}\"?'**
  String setTrashPurgeTitle(String title);

  /// No description provided for @setTrashPurgeBody.
  ///
  /// In it, this message translates to:
  /// **'Non potrai più recuperarlo.'**
  String get setTrashPurgeBody;

  /// No description provided for @setTrashPurge.
  ///
  /// In it, this message translates to:
  /// **'Elimina definitivamente'**
  String get setTrashPurge;

  /// No description provided for @setTrashEmptyTitle.
  ///
  /// In it, this message translates to:
  /// **'Svuotare il cestino?'**
  String get setTrashEmptyTitle;

  /// No description provided for @setTrashEmptyBody.
  ///
  /// In it, this message translates to:
  /// **'Tutti i taccuini nel cestino verranno eliminati definitivamente.'**
  String get setTrashEmptyBody;

  /// No description provided for @setTrashEmpty.
  ///
  /// In it, this message translates to:
  /// **'Svuota cestino'**
  String get setTrashEmpty;

  /// No description provided for @setTrashEmptyState.
  ///
  /// In it, this message translates to:
  /// **'Il cestino è vuoto.'**
  String get setTrashEmptyState;

  /// No description provided for @setTrashDeletedAgo.
  ///
  /// In it, this message translates to:
  /// **'Eliminato {time} fa'**
  String setTrashDeletedAgo(String time);

  /// No description provided for @setTrashRestore.
  ///
  /// In it, this message translates to:
  /// **'Ripristina'**
  String get setTrashRestore;

  /// No description provided for @setAdvancedIntro.
  ///
  /// In it, this message translates to:
  /// **'Strumenti di recupero per casi rari di taccuino bloccato in sincronia. Usali solo se il sync continua a fallire dopo un normale \"Forza sync\" dalla libreria.'**
  String get setAdvancedIntro;

  /// No description provided for @setForceReloadTitle.
  ///
  /// In it, this message translates to:
  /// **'Forza ricarica taccuino dal server'**
  String get setForceReloadTitle;

  /// No description provided for @setForceReloadDesc.
  ///
  /// In it, this message translates to:
  /// **'Riscarica tutto il contenuto del taccuino dalla cartella delta del server e sovrascrive la copia locale. Utile se il count pagine sembra sbagliato o il taccuino non si apre. Non perde dati lato server.'**
  String get setForceReloadDesc;

  /// No description provided for @setErrorGeneric.
  ///
  /// In it, this message translates to:
  /// **'Errore: {error}'**
  String setErrorGeneric(String error);

  /// No description provided for @setPagesCount.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} pagina} other{{count} pagine}}'**
  String setPagesCount(int count);

  /// No description provided for @setReload.
  ///
  /// In it, this message translates to:
  /// **'Ricarica'**
  String get setReload;

  /// No description provided for @setCloseNotebookFirst.
  ///
  /// In it, this message translates to:
  /// **'Chiudi il taccuino prima di ricaricarlo dal server.'**
  String get setCloseNotebookFirst;

  /// No description provided for @setReloadConfirmTitle.
  ///
  /// In it, this message translates to:
  /// **'Ricaricare \"{title}\"?'**
  String setReloadConfirmTitle(String title);

  /// No description provided for @setReloadConfirmBody.
  ///
  /// In it, this message translates to:
  /// **'Riscarica metadata, document, pagine e asset dalla cartella delta del server. La copia locale viene sostituita.\n\nModifiche locali non ancora sincronizzate verranno perse. Continuare?'**
  String get setReloadConfirmBody;

  /// No description provided for @setReloadInProgress.
  ///
  /// In it, this message translates to:
  /// **'Ricarica \"{title}\" in corso…'**
  String setReloadInProgress(String title);

  /// No description provided for @setNotConnectedWebdav.
  ///
  /// In it, this message translates to:
  /// **'Non connesso a un server WebDAV.'**
  String get setNotConnectedWebdav;

  /// No description provided for @setReloadDone.
  ///
  /// In it, this message translates to:
  /// **'\"{title}\" ricaricato — {count, plural, one{{count} pagina} other{{count} pagine}}.'**
  String setReloadDone(String title, int count);

  /// No description provided for @setReloadFailed.
  ///
  /// In it, this message translates to:
  /// **'Ricarica fallita: {error}'**
  String setReloadFailed(String error);

  /// No description provided for @setAboutTagline.
  ///
  /// In it, this message translates to:
  /// **'App di scrittura a mano, local-first.'**
  String get setAboutTagline;

  /// No description provided for @setAboutOffline.
  ///
  /// In it, this message translates to:
  /// **'Funziona offline; la sincronia con WebDAV è facoltativa.'**
  String get setAboutOffline;

  /// No description provided for @setAboutVersion.
  ///
  /// In it, this message translates to:
  /// **'Versione {version} · build {commit}'**
  String setAboutVersion(String version, String commit);

  /// No description provided for @setReportProblem.
  ///
  /// In it, this message translates to:
  /// **'Segnala un problema'**
  String get setReportProblem;

  /// No description provided for @setReportProblemSub.
  ///
  /// In it, this message translates to:
  /// **'Copia il log errori negli appunti da allegare alla segnalazione.'**
  String get setReportProblemSub;

  /// No description provided for @setCopyLog.
  ///
  /// In it, this message translates to:
  /// **'Copia log'**
  String get setCopyLog;

  /// No description provided for @setReportProblemEmpty.
  ///
  /// In it, this message translates to:
  /// **'Nessun errore registrato.'**
  String get setReportProblemEmpty;

  /// No description provided for @setCopyLogDone.
  ///
  /// In it, this message translates to:
  /// **'Log copiato negli appunti.'**
  String get setCopyLogDone;

  /// No description provided for @onbTagline.
  ///
  /// In it, this message translates to:
  /// **'Appunti e disegno a mano libera, sincronizzati sul TUO server. Scegli come iniziare — puoi cambiare in seguito.'**
  String get onbTagline;

  /// No description provided for @onbTryNowTitle.
  ///
  /// In it, this message translates to:
  /// **'Prova subito'**
  String get onbTryNowTitle;

  /// No description provided for @onbTryNowSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Inizia a scrivere ora. I taccuini restano su questo dispositivo — nessun account, nessun server.'**
  String get onbTryNowSubtitle;

  /// No description provided for @onbConnectNextcloudTitle.
  ///
  /// In it, this message translates to:
  /// **'Connetti il tuo Nextcloud'**
  String get onbConnectNextcloudTitle;

  /// No description provided for @onbConnectNextcloudSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Sincronizza sul tuo server WebDAV / Nextcloud personale e accedi da tutti i dispositivi.'**
  String get onbConnectNextcloudSubtitle;

  /// No description provided for @onbManagedServerTitle.
  ///
  /// In it, this message translates to:
  /// **'Server gestito AbelNotes'**
  String get onbManagedServerTitle;

  /// No description provided for @onbManagedServerSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Non hai un server? Presto potrai usare il nostro, senza configurare nulla.'**
  String get onbManagedServerSubtitle;

  /// No description provided for @onbComingSoonBadge.
  ///
  /// In it, this message translates to:
  /// **'In arrivo'**
  String get onbComingSoonBadge;

  /// No description provided for @onbLicenseNote.
  ///
  /// In it, this message translates to:
  /// **'Aprendo l\'app accetti la licenza AGPL-3.0. \"AbelNotes\" è un marchio del progetto.'**
  String get onbLicenseNote;

  /// No description provided for @logConnectionFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile connettersi. Verifica URL, username e password.'**
  String get logConnectionFailed;

  /// No description provided for @logConnectionError.
  ///
  /// In it, this message translates to:
  /// **'Errore di connessione: {error}'**
  String logConnectionError(String error);

  /// No description provided for @logCertificateChanged.
  ///
  /// In it, this message translates to:
  /// **'Il certificato del server è cambiato rispetto all\'ultima connessione. Se sei stato tu (es. rinnovo certificato), vai in Impostazioni > Sincronizzazione per confermare la nuova impronta.'**
  String get logCertificateChanged;

  /// No description provided for @logCertConfirmTitle.
  ///
  /// In it, this message translates to:
  /// **'Verifica identità del server'**
  String get logCertConfirmTitle;

  /// No description provided for @logCertConfirmBody.
  ///
  /// In it, this message translates to:
  /// **'Prima connessione a questo server. Confronta questa impronta con quella del tuo server (es. da riga di comando) prima di continuare:'**
  String get logCertConfirmBody;

  /// No description provided for @logCertConfirmTrust.
  ///
  /// In it, this message translates to:
  /// **'Mi fido, continua'**
  String get logCertConfirmTrust;

  /// No description provided for @logBackTooltip.
  ///
  /// In it, this message translates to:
  /// **'Indietro'**
  String get logBackTooltip;

  /// No description provided for @logTitle.
  ///
  /// In it, this message translates to:
  /// **'Connetti il tuo Nextcloud'**
  String get logTitle;

  /// No description provided for @logSubtitle.
  ///
  /// In it, this message translates to:
  /// **'Qualsiasi server WebDAV / Nextcloud (VPS, self-hosted, LAN). Nessun cloud di terze parti.'**
  String get logSubtitle;

  /// No description provided for @logServerUrlLabel.
  ///
  /// In it, this message translates to:
  /// **'URL Server'**
  String get logServerUrlLabel;

  /// No description provided for @logServerUrlHint.
  ///
  /// In it, this message translates to:
  /// **'https://cloud.example.com'**
  String get logServerUrlHint;

  /// No description provided for @logServerUrlRequired.
  ///
  /// In it, this message translates to:
  /// **'Inserisci l\'URL del server'**
  String get logServerUrlRequired;

  /// No description provided for @logServerUrlInvalid.
  ///
  /// In it, this message translates to:
  /// **'Deve iniziare con http:// o https://'**
  String get logServerUrlInvalid;

  /// No description provided for @logUsernameLabel.
  ///
  /// In it, this message translates to:
  /// **'Username'**
  String get logUsernameLabel;

  /// No description provided for @logUsernameRequired.
  ///
  /// In it, this message translates to:
  /// **'Username richiesto'**
  String get logUsernameRequired;

  /// No description provided for @logPasswordLabel.
  ///
  /// In it, this message translates to:
  /// **'Password / App Password'**
  String get logPasswordLabel;

  /// No description provided for @logPasswordRequired.
  ///
  /// In it, this message translates to:
  /// **'Password richiesta'**
  String get logPasswordRequired;

  /// No description provided for @logAppPasswordHint.
  ///
  /// In it, this message translates to:
  /// **'Consigliato: una App Password generata dalle impostazioni di Nextcloud.'**
  String get logAppPasswordHint;

  /// No description provided for @logServerTypeNextcloud.
  ///
  /// In it, this message translates to:
  /// **'Nextcloud / ownCloud'**
  String get logServerTypeNextcloud;

  /// No description provided for @logServerTypeWebdav.
  ///
  /// In it, this message translates to:
  /// **'Altro WebDAV'**
  String get logServerTypeWebdav;

  /// No description provided for @logServerUrlHintWebdav.
  ///
  /// In it, this message translates to:
  /// **'https://dav.example.com/cartella'**
  String get logServerUrlHintWebdav;

  /// No description provided for @logWebdavExperimental.
  ///
  /// In it, this message translates to:
  /// **'I backend WebDAV generici (Synology, Seafile, rclone…) sono sperimentali: solo Nextcloud è testato a fondo. Tieni un backup dei tuoi quaderni.'**
  String get logWebdavExperimental;

  /// No description provided for @logWebdavUrlHint.
  ///
  /// In it, this message translates to:
  /// **'URL WebDAV completo, percorso incluso — es. Synology https://nas:5006/home, Seafile https://server/seafdav. La condivisione link non è disponibile su WebDAV generico.'**
  String get logWebdavUrlHint;

  /// No description provided for @logConnectButton.
  ///
  /// In it, this message translates to:
  /// **'Connetti'**
  String get logConnectButton;

  /// No description provided for @chromeBackToLibraryTooltip.
  ///
  /// In it, this message translates to:
  /// **'Torna alla libreria'**
  String get chromeBackToLibraryTooltip;

  /// No description provided for @chromeLibrary.
  ///
  /// In it, this message translates to:
  /// **'Libreria'**
  String get chromeLibrary;

  /// No description provided for @chromeUnsaved.
  ///
  /// In it, this message translates to:
  /// **'Non salvato'**
  String get chromeUnsaved;

  /// No description provided for @chromeMouseDrawsTooltip.
  ///
  /// In it, this message translates to:
  /// **'Mouse: disegna — tocca per usarlo come selezione'**
  String get chromeMouseDrawsTooltip;

  /// No description provided for @chromeMouseSelectsTooltip.
  ///
  /// In it, this message translates to:
  /// **'Mouse: selezione — tocca per disegnare col mouse'**
  String get chromeMouseSelectsTooltip;

  /// No description provided for @chromeTouchDrawsTooltip.
  ///
  /// In it, this message translates to:
  /// **'Dito: disegna — tocca per usarlo per navigare'**
  String get chromeTouchDrawsTooltip;

  /// No description provided for @chromeTouchPansTooltip.
  ///
  /// In it, this message translates to:
  /// **'Dito: naviga — tocca per disegnare col dito'**
  String get chromeTouchPansTooltip;

  /// No description provided for @chromeUndo.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get chromeUndo;

  /// No description provided for @chromeRedo.
  ///
  /// In it, this message translates to:
  /// **'Ripeti'**
  String get chromeRedo;

  /// No description provided for @chromeAllPages.
  ///
  /// In it, this message translates to:
  /// **'Tutte le pagine'**
  String get chromeAllPages;

  /// No description provided for @chromePageIndicator.
  ///
  /// In it, this message translates to:
  /// **'{current} / {total}'**
  String chromePageIndicator(String current, int total);

  /// No description provided for @chromeAddPage.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi pagina'**
  String get chromeAddPage;

  /// No description provided for @chromeSymbols.
  ///
  /// In it, this message translates to:
  /// **'Simboli'**
  String get chromeSymbols;

  /// No description provided for @chromeExport.
  ///
  /// In it, this message translates to:
  /// **'Esporta'**
  String get chromeExport;

  /// No description provided for @chromeMore.
  ///
  /// In it, this message translates to:
  /// **'Altro'**
  String get chromeMore;

  /// No description provided for @chromeMoreEllipsis.
  ///
  /// In it, this message translates to:
  /// **'Altro…'**
  String get chromeMoreEllipsis;

  /// No description provided for @chromeToolPen.
  ///
  /// In it, this message translates to:
  /// **'Penna · P'**
  String get chromeToolPen;

  /// No description provided for @chromeToolHighlighter.
  ///
  /// In it, this message translates to:
  /// **'Evidenziatore'**
  String get chromeToolHighlighter;

  /// No description provided for @chromeToolEraser.
  ///
  /// In it, this message translates to:
  /// **'Gomma · E'**
  String get chromeToolEraser;

  /// No description provided for @chromeToolLasso.
  ///
  /// In it, this message translates to:
  /// **'Lasso · L'**
  String get chromeToolLasso;

  /// No description provided for @chromeToolText.
  ///
  /// In it, this message translates to:
  /// **'Testo · T'**
  String get chromeToolText;

  /// No description provided for @chromeToolLaser.
  ///
  /// In it, this message translates to:
  /// **'Laser'**
  String get chromeToolLaser;

  /// No description provided for @chromeToolPan.
  ///
  /// In it, this message translates to:
  /// **'Mano · H'**
  String get chromeToolPan;

  /// No description provided for @chromeDragToMoveBar.
  ///
  /// In it, this message translates to:
  /// **'Trascina per spostare la barra'**
  String get chromeDragToMoveBar;

  /// No description provided for @chromeShapeGuessOn.
  ///
  /// In it, this message translates to:
  /// **'Auto-forma · attivo'**
  String get chromeShapeGuessOn;

  /// No description provided for @chromeShapeGuessOff.
  ///
  /// In it, this message translates to:
  /// **'Auto-forma · spento'**
  String get chromeShapeGuessOff;

  /// No description provided for @chromeLabelPen.
  ///
  /// In it, this message translates to:
  /// **'Penna'**
  String get chromeLabelPen;

  /// No description provided for @chromeLabelBallpoint.
  ///
  /// In it, this message translates to:
  /// **'Ballpoint'**
  String get chromeLabelBallpoint;

  /// No description provided for @chromeLabelBrush.
  ///
  /// In it, this message translates to:
  /// **'Pennello'**
  String get chromeLabelBrush;

  /// No description provided for @chromeLabelCalligraphy.
  ///
  /// In it, this message translates to:
  /// **'Calligrafia'**
  String get chromeLabelCalligraphy;

  /// No description provided for @chromeLabelEraser.
  ///
  /// In it, this message translates to:
  /// **'Gomma'**
  String get chromeLabelEraser;

  /// No description provided for @chromeLabelLasso.
  ///
  /// In it, this message translates to:
  /// **'Lasso'**
  String get chromeLabelLasso;

  /// No description provided for @chromeLabelText.
  ///
  /// In it, this message translates to:
  /// **'Testo'**
  String get chromeLabelText;

  /// No description provided for @chromeLabelShape.
  ///
  /// In it, this message translates to:
  /// **'Forma'**
  String get chromeLabelShape;

  /// No description provided for @chromeLabelImage.
  ///
  /// In it, this message translates to:
  /// **'Immagine'**
  String get chromeLabelImage;

  /// No description provided for @chromeLabelPan.
  ///
  /// In it, this message translates to:
  /// **'Mano'**
  String get chromeLabelPan;

  /// No description provided for @chromePresetsSection.
  ///
  /// In it, this message translates to:
  /// **'Pre-impostazioni'**
  String get chromePresetsSection;

  /// No description provided for @chromePresetHint.
  ///
  /// In it, this message translates to:
  /// **'Tieni premuto per salvare/cancellare'**
  String get chromePresetHint;

  /// No description provided for @chromeColorSection.
  ///
  /// In it, this message translates to:
  /// **'Colore'**
  String get chromeColorSection;

  /// No description provided for @chromeColorEditHint.
  ///
  /// In it, this message translates to:
  /// **'Tieni premuto un colore per cambiarlo'**
  String get chromeColorEditHint;

  /// No description provided for @chromeThicknessSection.
  ///
  /// In it, this message translates to:
  /// **'Spessore'**
  String get chromeThicknessSection;

  /// No description provided for @chromeThicknessPx.
  ///
  /// In it, this message translates to:
  /// **'{value} px'**
  String chromeThicknessPx(String value);

  /// No description provided for @chromePreview.
  ///
  /// In it, this message translates to:
  /// **'Anteprima'**
  String get chromePreview;

  /// No description provided for @chromeModeSection.
  ///
  /// In it, this message translates to:
  /// **'Modalità'**
  String get chromeModeSection;

  /// No description provided for @chromeEraserPerArea.
  ///
  /// In it, this message translates to:
  /// **'Per area'**
  String get chromeEraserPerArea;

  /// No description provided for @chromeEraserPerStroke.
  ///
  /// In it, this message translates to:
  /// **'Per tratto'**
  String get chromeEraserPerStroke;

  /// No description provided for @chromeSizeSection.
  ///
  /// In it, this message translates to:
  /// **'Dimensione'**
  String get chromeSizeSection;

  /// No description provided for @chromeSizeSmall.
  ///
  /// In it, this message translates to:
  /// **'S'**
  String get chromeSizeSmall;

  /// No description provided for @chromeSizeMedium.
  ///
  /// In it, this message translates to:
  /// **'M'**
  String get chromeSizeMedium;

  /// No description provided for @chromeSizeLarge.
  ///
  /// In it, this message translates to:
  /// **'L'**
  String get chromeSizeLarge;

  /// No description provided for @chromePresetOverwrite.
  ///
  /// In it, this message translates to:
  /// **'Sovrascrivi con corrente'**
  String get chromePresetOverwrite;

  /// No description provided for @chromePresetClearSlot.
  ///
  /// In it, this message translates to:
  /// **'Svuota slot'**
  String get chromePresetClearSlot;

  /// No description provided for @chromeNoPages.
  ///
  /// In it, this message translates to:
  /// **'Nessuna pagina'**
  String get chromeNoPages;

  /// No description provided for @chromeHidePageBar.
  ///
  /// In it, this message translates to:
  /// **'Nascondi la barra delle pagine'**
  String get chromeHidePageBar;

  /// No description provided for @chromeShowPageBar.
  ///
  /// In it, this message translates to:
  /// **'Mostra la barra delle pagine'**
  String get chromeShowPageBar;

  /// No description provided for @chromePrevPageTooltip.
  ///
  /// In it, this message translates to:
  /// **'Pagina precedente {number} — tocca per tornare indietro'**
  String chromePrevPageTooltip(int number);

  /// No description provided for @chromePageOfChapterTooltip.
  ///
  /// In it, this message translates to:
  /// **'Pagina {number} del capitolo · pagina {globalNumber} del taccuino'**
  String chromePageOfChapterTooltip(int number, int globalNumber);

  /// No description provided for @chromePageTooltip.
  ///
  /// In it, this message translates to:
  /// **'Pagina {number}'**
  String chromePageTooltip(int number);

  /// No description provided for @chromeHexLabel.
  ///
  /// In it, this message translates to:
  /// **'Esadecimale'**
  String get chromeHexLabel;

  /// No description provided for @chromeCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get chromeCancel;

  /// No description provided for @chromeApply.
  ///
  /// In it, this message translates to:
  /// **'Applica'**
  String get chromeApply;

  /// No description provided for @pmNone.
  ///
  /// In it, this message translates to:
  /// **'Nessuno'**
  String get pmNone;

  /// No description provided for @pmCreateChapterFirst.
  ///
  /// In it, this message translates to:
  /// **'Crea prima almeno un capitolo.'**
  String get pmCreateChapterFirst;

  /// No description provided for @pmAssignChapterCount.
  ///
  /// In it, this message translates to:
  /// **'Assegna capitolo ({count} pag.)'**
  String pmAssignChapterCount(int count);

  /// No description provided for @pmDeletePagesConfirm.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{Eliminare 1 pagina?} other{Eliminare {count} pagine?}}'**
  String pmDeletePagesConfirm(int count);

  /// No description provided for @pmActionCannotBeUndone.
  ///
  /// In it, this message translates to:
  /// **'Questa azione non può essere annullata.'**
  String get pmActionCannotBeUndone;

  /// No description provided for @pmCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get pmCancel;

  /// No description provided for @pmDelete.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get pmDelete;

  /// No description provided for @pmPagesCut.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{1 pagina tagliata — aprire il notebook di destinazione per incollare.} other{{count} pagine tagliate — aprire il notebook di destinazione per incollare.}}'**
  String pmPagesCut(int count);

  /// No description provided for @pmPagesCutSkipped.
  ///
  /// In it, this message translates to:
  /// **'{count} pagine tagliate ({skipped} non ancora caricate, saltate) — aprire il notebook di destinazione per incollare.'**
  String pmPagesCutSkipped(int count, int skipped);

  /// No description provided for @pmSelectedCount.
  ///
  /// In it, this message translates to:
  /// **'{count} selezionate'**
  String pmSelectedCount(int count);

  /// No description provided for @pmSelectAllButton.
  ///
  /// In it, this message translates to:
  /// **'Tutte'**
  String get pmSelectAllButton;

  /// No description provided for @pmClearSelection.
  ///
  /// In it, this message translates to:
  /// **'Annulla selezione'**
  String get pmClearSelection;

  /// No description provided for @pmPagesCount.
  ///
  /// In it, this message translates to:
  /// **'Pagine ({count})'**
  String pmPagesCount(int count);

  /// No description provided for @pmPagesFilteredCount.
  ///
  /// In it, this message translates to:
  /// **'Pagine ({visible}/{total})'**
  String pmPagesFilteredCount(int visible, int total);

  /// No description provided for @pmGoToPageTooltip.
  ///
  /// In it, this message translates to:
  /// **'Vai alla pagina…'**
  String get pmGoToPageTooltip;

  /// No description provided for @pmExitSelection.
  ///
  /// In it, this message translates to:
  /// **'Esci dalla selezione'**
  String get pmExitSelection;

  /// No description provided for @pmSelectPages.
  ///
  /// In it, this message translates to:
  /// **'Seleziona pagine'**
  String get pmSelectPages;

  /// No description provided for @pmPastePages.
  ///
  /// In it, this message translates to:
  /// **'Incolla pagine'**
  String get pmPastePages;

  /// No description provided for @pmPagesPasted.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{1 pagina incollata.} other{{count} pagine incollate.}}'**
  String pmPagesPasted(int count);

  /// No description provided for @pmAddPage.
  ///
  /// In it, this message translates to:
  /// **'Aggiungi pagina'**
  String get pmAddPage;

  /// No description provided for @pmClose.
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get pmClose;

  /// No description provided for @pmNewChapter.
  ///
  /// In it, this message translates to:
  /// **'Nuovo capitolo'**
  String get pmNewChapter;

  /// No description provided for @pmChapterNameHint.
  ///
  /// In it, this message translates to:
  /// **'Nome capitolo'**
  String get pmChapterNameHint;

  /// No description provided for @pmPageDeleted.
  ///
  /// In it, this message translates to:
  /// **'Pagina {number} eliminata'**
  String pmPageDeleted(int number);

  /// No description provided for @pmUndo.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get pmUndo;

  /// No description provided for @pmAssignChapter.
  ///
  /// In it, this message translates to:
  /// **'Assegna capitolo'**
  String get pmAssignChapter;

  /// No description provided for @pmRename.
  ///
  /// In it, this message translates to:
  /// **'Rinomina'**
  String get pmRename;

  /// No description provided for @pmRenameChapter.
  ///
  /// In it, this message translates to:
  /// **'Rinomina capitolo'**
  String get pmRenameChapter;

  /// No description provided for @pmDeleteChapter.
  ///
  /// In it, this message translates to:
  /// **'Elimina capitolo'**
  String get pmDeleteChapter;

  /// No description provided for @pmDeleteChapterConfirm.
  ///
  /// In it, this message translates to:
  /// **'Eliminare \"{title}\"? Le pagine al suo interno resteranno ma senza capitolo.'**
  String pmDeleteChapterConfirm(String title);

  /// No description provided for @pmGoToPage.
  ///
  /// In it, this message translates to:
  /// **'Vai alla pagina'**
  String get pmGoToPage;

  /// No description provided for @pmPageRangeHint.
  ///
  /// In it, this message translates to:
  /// **'1–{max}'**
  String pmPageRangeHint(int max);

  /// No description provided for @pmGo.
  ///
  /// In it, this message translates to:
  /// **'Vai'**
  String get pmGo;

  /// No description provided for @pmOk.
  ///
  /// In it, this message translates to:
  /// **'OK'**
  String get pmOk;

  /// No description provided for @pmCountPagesShort.
  ///
  /// In it, this message translates to:
  /// **'{count} pag.'**
  String pmCountPagesShort(int count);

  /// No description provided for @pmChapter.
  ///
  /// In it, this message translates to:
  /// **'Capitolo'**
  String get pmChapter;

  /// No description provided for @pmCut.
  ///
  /// In it, this message translates to:
  /// **'Taglia'**
  String get pmCut;

  /// No description provided for @pmInsertBefore.
  ///
  /// In it, this message translates to:
  /// **'Inserisci prima'**
  String get pmInsertBefore;

  /// No description provided for @pmInsertAfter.
  ///
  /// In it, this message translates to:
  /// **'Inserisci dopo'**
  String get pmInsertAfter;

  /// No description provided for @pmDuplicate.
  ///
  /// In it, this message translates to:
  /// **'Duplica'**
  String get pmDuplicate;

  /// No description provided for @pmMoveTo.
  ///
  /// In it, this message translates to:
  /// **'Sposta a pagina…'**
  String get pmMoveTo;

  /// No description provided for @pmMove.
  ///
  /// In it, this message translates to:
  /// **'Sposta'**
  String get pmMove;

  /// No description provided for @pmMoveToPage.
  ///
  /// In it, this message translates to:
  /// **'Sposta a pagina'**
  String get pmMoveToPage;

  /// No description provided for @pmChapterEllipsis.
  ///
  /// In it, this message translates to:
  /// **'Capitolo…'**
  String get pmChapterEllipsis;

  /// No description provided for @pmPageChapterLabel.
  ///
  /// In it, this message translates to:
  /// **'{number} • {chapter}'**
  String pmPageChapterLabel(int number, String chapter);

  /// No description provided for @pmCorruptAssetTooltip.
  ///
  /// In it, this message translates to:
  /// **'Asset corrotto sul server (troncato) — ri-importa il PDF originale per recuperare'**
  String get pmCorruptAssetTooltip;

  /// No description provided for @pmLoadingImageTooltip.
  ///
  /// In it, this message translates to:
  /// **'Caricamento immagine dal server…'**
  String get pmLoadingImageTooltip;

  /// No description provided for @tedInsertTextTitle.
  ///
  /// In it, this message translates to:
  /// **'Inserisci testo'**
  String get tedInsertTextTitle;

  /// No description provided for @tedEditTextTitle.
  ///
  /// In it, this message translates to:
  /// **'Modifica testo'**
  String get tedEditTextTitle;

  /// No description provided for @tedBoldTooltip.
  ///
  /// In it, this message translates to:
  /// **'Grassetto (Ctrl+B)'**
  String get tedBoldTooltip;

  /// No description provided for @tedItalicTooltip.
  ///
  /// In it, this message translates to:
  /// **'Corsivo (Ctrl+I)'**
  String get tedItalicTooltip;

  /// No description provided for @tedUnderlineTooltip.
  ///
  /// In it, this message translates to:
  /// **'Sottolineato (Ctrl+U)'**
  String get tedUnderlineTooltip;

  /// No description provided for @tedStrikethroughTooltip.
  ///
  /// In it, this message translates to:
  /// **'Barrato'**
  String get tedStrikethroughTooltip;

  /// No description provided for @tedAlignLeft.
  ///
  /// In it, this message translates to:
  /// **'Sinistra'**
  String get tedAlignLeft;

  /// No description provided for @tedAlignCenter.
  ///
  /// In it, this message translates to:
  /// **'Centro'**
  String get tedAlignCenter;

  /// No description provided for @tedAlignRight.
  ///
  /// In it, this message translates to:
  /// **'Destra'**
  String get tedAlignRight;

  /// No description provided for @tedWriteHereHint.
  ///
  /// In it, this message translates to:
  /// **'Scrivi qui…'**
  String get tedWriteHereHint;

  /// No description provided for @tedCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get tedCancel;

  /// No description provided for @tedInsert.
  ///
  /// In it, this message translates to:
  /// **'Inserisci'**
  String get tedInsert;

  /// No description provided for @cropTitle.
  ///
  /// In it, this message translates to:
  /// **'Ritaglia immagine'**
  String get cropTitle;

  /// No description provided for @cropCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get cropCancel;

  /// No description provided for @cropConfirm.
  ///
  /// In it, this message translates to:
  /// **'Ritaglia'**
  String get cropConfirm;

  /// No description provided for @imgFontSmaller.
  ///
  /// In it, this message translates to:
  /// **'Testo più piccolo'**
  String get imgFontSmaller;

  /// No description provided for @imgFontLarger.
  ///
  /// In it, this message translates to:
  /// **'Testo più grande'**
  String get imgFontLarger;

  /// No description provided for @imgCrop.
  ///
  /// In it, this message translates to:
  /// **'Ritaglia'**
  String get imgCrop;

  /// No description provided for @imgCopy.
  ///
  /// In it, this message translates to:
  /// **'Copia'**
  String get imgCopy;

  /// No description provided for @imgUnlock.
  ///
  /// In it, this message translates to:
  /// **'Sblocca'**
  String get imgUnlock;

  /// No description provided for @imgLock.
  ///
  /// In it, this message translates to:
  /// **'Blocca'**
  String get imgLock;

  /// No description provided for @imgDelete.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get imgDelete;

  /// No description provided for @imgDeselect.
  ///
  /// In it, this message translates to:
  /// **'Deseleziona'**
  String get imgDeselect;

  /// No description provided for @imgMoreActions.
  ///
  /// In it, this message translates to:
  /// **'Altre azioni'**
  String get imgMoreActions;

  /// No description provided for @imgBringToFront.
  ///
  /// In it, this message translates to:
  /// **'In primo piano'**
  String get imgBringToFront;

  /// No description provided for @imgSendToBack.
  ///
  /// In it, this message translates to:
  /// **'Dietro a tutto'**
  String get imgSendToBack;

  /// No description provided for @imgComment.
  ///
  /// In it, this message translates to:
  /// **'Commento'**
  String get imgComment;

  /// No description provided for @imgFlipHChecked.
  ///
  /// In it, this message translates to:
  /// **'Rifletti H ✓'**
  String get imgFlipHChecked;

  /// No description provided for @imgFlipH.
  ///
  /// In it, this message translates to:
  /// **'Rifletti H'**
  String get imgFlipH;

  /// No description provided for @imgCut.
  ///
  /// In it, this message translates to:
  /// **'Taglia'**
  String get imgCut;

  /// No description provided for @syncOkTooltip.
  ///
  /// In it, this message translates to:
  /// **'Sincronizzato'**
  String get syncOkTooltip;

  /// No description provided for @syncPendingTooltip.
  ///
  /// In it, this message translates to:
  /// **'In sincronia…'**
  String get syncPendingTooltip;

  /// No description provided for @syncOfflineTooltip.
  ///
  /// In it, this message translates to:
  /// **'Offline'**
  String get syncOfflineTooltip;

  /// No description provided for @syncConflictTooltip.
  ///
  /// In it, this message translates to:
  /// **'Conflitto'**
  String get syncConflictTooltip;

  /// No description provided for @confDecideLater.
  ///
  /// In it, this message translates to:
  /// **'Decidi più tardi'**
  String get confDecideLater;

  /// No description provided for @confTitlePageDeletedElsewhere.
  ///
  /// In it, this message translates to:
  /// **'Pagina {pageNumber} eliminata altrove'**
  String confTitlePageDeletedElsewhere(int pageNumber);

  /// No description provided for @confTitleConflictPage.
  ///
  /// In it, this message translates to:
  /// **'Conflitto — Pagina {pageNumber}'**
  String confTitleConflictPage(int pageNumber);

  /// No description provided for @confDeletionExplainer.
  ///
  /// In it, this message translates to:
  /// **'Hai modificato questa pagina, ma un altro dispositivo l\'ha eliminata. Vuoi mantenerla o eliminarla?'**
  String get confDeletionExplainer;

  /// No description provided for @confKeepPage.
  ///
  /// In it, this message translates to:
  /// **'Mantieni la pagina'**
  String get confKeepPage;

  /// No description provided for @confLocalYours.
  ///
  /// In it, this message translates to:
  /// **'Locale (tuo)'**
  String get confLocalYours;

  /// No description provided for @confRemoteOtherDevice.
  ///
  /// In it, this message translates to:
  /// **'Remoto (altro dispositivo)'**
  String get confRemoteOtherDevice;

  /// No description provided for @confKeepAllLocal.
  ///
  /// In it, this message translates to:
  /// **'Tieni tutti locali'**
  String get confKeepAllLocal;

  /// No description provided for @confAcceptAllRemote.
  ///
  /// In it, this message translates to:
  /// **'Accetta tutti remoti'**
  String get confAcceptAllRemote;

  /// No description provided for @confProgressIndicator.
  ///
  /// In it, this message translates to:
  /// **'{current} / {total}  ({decided, plural, one{{decided} deciso} other{{decided} decisi}})'**
  String confProgressIndicator(int current, int total, num decided);

  /// No description provided for @confApplyChoices.
  ///
  /// In it, this message translates to:
  /// **'Applica scelte'**
  String get confApplyChoices;

  /// No description provided for @confDecidedProgress.
  ///
  /// In it, this message translates to:
  /// **'{decided}/{total} {total, plural, one{deciso} other{decisi}}'**
  String confDecidedProgress(int decided, num total);

  /// No description provided for @confJumpToConflict.
  ///
  /// In it, this message translates to:
  /// **'Vai al conflitto'**
  String get confJumpToConflict;

  /// No description provided for @confJumpDecidedCount.
  ///
  /// In it, this message translates to:
  /// **'{decided}/{total} decisi'**
  String confJumpDecidedCount(int decided, int total);

  /// No description provided for @confJumpItemPage.
  ///
  /// In it, this message translates to:
  /// **'Pag. {pageNumber}'**
  String confJumpItemPage(int pageNumber);

  /// No description provided for @confJumpItemPageWithChapter.
  ///
  /// In it, this message translates to:
  /// **'Pag. {pageNumber} — {chapterName}'**
  String confJumpItemPageWithChapter(int pageNumber, String chapterName);

  /// No description provided for @confDismissDialogTitle.
  ///
  /// In it, this message translates to:
  /// **'Annullare?'**
  String get confDismissDialogTitle;

  /// No description provided for @confDismissDialogBody.
  ///
  /// In it, this message translates to:
  /// **'Le scelte non applicate verranno perse. La versione locale verrà mantenuta.'**
  String get confDismissDialogBody;

  /// No description provided for @confContinue.
  ///
  /// In it, this message translates to:
  /// **'Continua'**
  String get confContinue;

  /// No description provided for @confCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get confCancel;

  /// No description provided for @confModifiedJustNow.
  ///
  /// In it, this message translates to:
  /// **'Adesso'**
  String get confModifiedJustNow;

  /// No description provided for @confModifiedMinutesAgo.
  ///
  /// In it, this message translates to:
  /// **'{minutes} min fa'**
  String confModifiedMinutesAgo(int minutes);

  /// No description provided for @confModifiedHoursAgo.
  ///
  /// In it, this message translates to:
  /// **'{hours, plural, one{{hours} ora fa} other{{hours} ore fa}}'**
  String confModifiedHoursAgo(num hours);

  /// No description provided for @confDeletePage.
  ///
  /// In it, this message translates to:
  /// **'Elimina la pagina'**
  String get confDeletePage;

  /// No description provided for @confAsOnOtherDevice.
  ///
  /// In it, this message translates to:
  /// **'Come sull\'altro dispositivo'**
  String get confAsOnOtherDevice;

  /// No description provided for @symNewLibraryTitle.
  ///
  /// In it, this message translates to:
  /// **'Nuova libreria'**
  String get symNewLibraryTitle;

  /// No description provided for @symNewLibraryHint.
  ///
  /// In it, this message translates to:
  /// **'Inserisci il nome della libreria'**
  String get symNewLibraryHint;

  /// No description provided for @symRenameLibraryTitle.
  ///
  /// In it, this message translates to:
  /// **'Rinomina libreria'**
  String get symRenameLibraryTitle;

  /// No description provided for @symNewNameHint.
  ///
  /// In it, this message translates to:
  /// **'Nuovo nome'**
  String get symNewNameHint;

  /// No description provided for @symDeleteLibraryTitle.
  ///
  /// In it, this message translates to:
  /// **'Elimina libreria'**
  String get symDeleteLibraryTitle;

  /// No description provided for @symDeleteLibraryConfirm.
  ///
  /// In it, this message translates to:
  /// **'Elimina \"{name}\" e tutti i suoi simboli?'**
  String symDeleteLibraryConfirm(String name);

  /// No description provided for @symCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get symCancel;

  /// No description provided for @symDelete.
  ///
  /// In it, this message translates to:
  /// **'Elimina'**
  String get symDelete;

  /// No description provided for @symRenameSymbolTitle.
  ///
  /// In it, this message translates to:
  /// **'Rinomina simbolo'**
  String get symRenameSymbolTitle;

  /// No description provided for @symPanelTitle.
  ///
  /// In it, this message translates to:
  /// **'Librerie simboli'**
  String get symPanelTitle;

  /// No description provided for @symNoLibraries.
  ///
  /// In it, this message translates to:
  /// **'Nessuna libreria'**
  String get symNoLibraries;

  /// No description provided for @symNew.
  ///
  /// In it, this message translates to:
  /// **'Nuova'**
  String get symNew;

  /// No description provided for @symSelectLibrary.
  ///
  /// In it, this message translates to:
  /// **'Seleziona una libreria'**
  String get symSelectLibrary;

  /// No description provided for @symNoSymbolsHint.
  ///
  /// In it, this message translates to:
  /// **'Nessun simbolo\nSeleziona elementi con il lazo e premi ✚'**
  String get symNoSymbolsHint;

  /// No description provided for @symLassoSaveHint.
  ///
  /// In it, this message translates to:
  /// **'Seleziona elementi con il lazo → ✚ per salvare nella libreria attiva'**
  String get symLassoSaveHint;

  /// No description provided for @symRename.
  ///
  /// In it, this message translates to:
  /// **'Rinomina'**
  String get symRename;

  /// No description provided for @symInsert.
  ///
  /// In it, this message translates to:
  /// **'Inserisci'**
  String get symInsert;

  /// No description provided for @symOk.
  ///
  /// In it, this message translates to:
  /// **'OK'**
  String get symOk;

  /// No description provided for @rcbBannerTitle.
  ///
  /// In it, this message translates to:
  /// **'Modifiche da un altro dispositivo'**
  String get rcbBannerTitle;

  /// No description provided for @rcbSeeDetails.
  ///
  /// In it, this message translates to:
  /// **'Vedi dettagli'**
  String get rcbSeeDetails;

  /// No description provided for @rcbDismiss.
  ///
  /// In it, this message translates to:
  /// **'Ignora'**
  String get rcbDismiss;

  /// No description provided for @rcbIncomingChanges.
  ///
  /// In it, this message translates to:
  /// **'Modifiche in arrivo'**
  String get rcbIncomingChanges;

  /// No description provided for @rcbTapPageHint.
  ///
  /// In it, this message translates to:
  /// **'Tocca una pagina per applicare e andare lì'**
  String get rcbTapPageHint;

  /// No description provided for @rcbNewImagesCount.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{1 nuova immagine} other{{count} nuove immagini}}'**
  String rcbNewImagesCount(num count);

  /// No description provided for @rcbKeepMine.
  ///
  /// In it, this message translates to:
  /// **'Mantieni i miei'**
  String get rcbKeepMine;

  /// No description provided for @rcbApplyAll.
  ///
  /// In it, this message translates to:
  /// **'Applica tutto'**
  String get rcbApplyAll;

  /// No description provided for @rcbBadgeNew.
  ///
  /// In it, this message translates to:
  /// **'NUOVA'**
  String get rcbBadgeNew;

  /// No description provided for @rcbBadgeModified.
  ///
  /// In it, this message translates to:
  /// **'MODIFICATA'**
  String get rcbBadgeModified;

  /// No description provided for @rcbPageTitle.
  ///
  /// In it, this message translates to:
  /// **'Pagina {pageNumber}'**
  String rcbPageTitle(int pageNumber);

  /// No description provided for @rcbContentUpdated.
  ///
  /// In it, this message translates to:
  /// **'Contenuto aggiornato'**
  String get rcbContentUpdated;

  /// No description provided for @rcbSummaryModifiedPages.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} pag. modificata} other{{count} pag. modificate}}'**
  String rcbSummaryModifiedPages(num count);

  /// No description provided for @rcbSummaryNewPages.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} nuova} other{{count} nuove}}'**
  String rcbSummaryNewPages(num count);

  /// No description provided for @rcbSummaryImages.
  ///
  /// In it, this message translates to:
  /// **'{count, plural, one{{count} immagine} other{{count} immagini}}'**
  String rcbSummaryImages(num count);

  /// No description provided for @rcbChangesDetected.
  ///
  /// In it, this message translates to:
  /// **'Cambiamenti rilevati'**
  String get rcbChangesDetected;

  /// No description provided for @nbUntitled.
  ///
  /// In it, this message translates to:
  /// **'Senza titolo'**
  String get nbUntitled;

  /// No description provided for @nbDefaultChapterTitle.
  ///
  /// In it, this message translates to:
  /// **'Capitolo 1'**
  String get nbDefaultChapterTitle;

  /// No description provided for @nbOpeningNotebook.
  ///
  /// In it, this message translates to:
  /// **'Apertura taccuino…'**
  String get nbOpeningNotebook;

  /// No description provided for @nbNoLocalCopyOffline.
  ///
  /// In it, this message translates to:
  /// **'Nessuna copia locale di questo taccuino, e non sei connesso a un server per scaricarlo.'**
  String get nbNoLocalCopyOffline;

  /// No description provided for @nbOpenFailed.
  ///
  /// In it, this message translates to:
  /// **'Impossibile aprire: {error}'**
  String nbOpenFailed(String error);

  /// No description provided for @nbSortModifiedDesc.
  ///
  /// In it, this message translates to:
  /// **'Modificati (più recenti)'**
  String get nbSortModifiedDesc;

  /// No description provided for @nbSortModifiedAsc.
  ///
  /// In it, this message translates to:
  /// **'Modificati (meno recenti)'**
  String get nbSortModifiedAsc;

  /// No description provided for @nbSortTitleAsc.
  ///
  /// In it, this message translates to:
  /// **'Titolo A→Z'**
  String get nbSortTitleAsc;

  /// No description provided for @nbSortTitleDesc.
  ///
  /// In it, this message translates to:
  /// **'Titolo Z→A'**
  String get nbSortTitleDesc;

  /// No description provided for @nbSortCreatedDesc.
  ///
  /// In it, this message translates to:
  /// **'Creati (più recenti)'**
  String get nbSortCreatedDesc;

  /// No description provided for @nbSortCreatedAsc.
  ///
  /// In it, this message translates to:
  /// **'Creati (meno recenti)'**
  String get nbSortCreatedAsc;

  /// No description provided for @nbSortColorGroup.
  ///
  /// In it, this message translates to:
  /// **'Colore copertina'**
  String get nbSortColorGroup;

  /// No description provided for @cvFormatTooNew.
  ///
  /// In it, this message translates to:
  /// **'Questo taccuino usa un formato più recente (v{fileVersion}, supportato: v{supportedVersion}). Aggiorna AbelNotes per aprirlo.'**
  String cvFormatTooNew(int fileVersion, int supportedVersion);

  /// No description provided for @setLanguageSystem.
  ///
  /// In it, this message translates to:
  /// **'Sistema'**
  String get setLanguageSystem;

  /// No description provided for @setLanguageEnglish.
  ///
  /// In it, this message translates to:
  /// **'English'**
  String get setLanguageEnglish;

  /// No description provided for @setLanguageSpanish.
  ///
  /// In it, this message translates to:
  /// **'Español'**
  String get setLanguageSpanish;

  /// No description provided for @onbAppName.
  ///
  /// In it, this message translates to:
  /// **'AbelNotes'**
  String get onbAppName;

  /// No description provided for @setAboutAppName.
  ///
  /// In it, this message translates to:
  /// **'AbelNotes'**
  String get setAboutAppName;

  /// No description provided for @chromeLabelHighlighter.
  ///
  /// In it, this message translates to:
  /// **'Evidenziatore'**
  String get chromeLabelHighlighter;

  /// No description provided for @chromeLabelLaser.
  ///
  /// In it, this message translates to:
  /// **'Laser'**
  String get chromeLabelLaser;

  /// No description provided for @importSourceTitle.
  ///
  /// In it, this message translates to:
  /// **'Importa nella libreria'**
  String get importSourceTitle;

  /// No description provided for @importSourceNcnote.
  ///
  /// In it, this message translates to:
  /// **'Taccuino .ncnote'**
  String get importSourceNcnote;

  /// No description provided for @importSourceObsidian.
  ///
  /// In it, this message translates to:
  /// **'Vault Obsidian'**
  String get importSourceObsidian;

  /// No description provided for @importSourceObsidianHint.
  ///
  /// In it, this message translates to:
  /// **'Cartella con file Markdown'**
  String get importSourceObsidianHint;

  /// No description provided for @importSourceNotion.
  ///
  /// In it, this message translates to:
  /// **'Export Notion'**
  String get importSourceNotion;

  /// No description provided for @importSourceNotionHint.
  ///
  /// In it, this message translates to:
  /// **'File .zip (Markdown e CSV)'**
  String get importSourceNotionHint;

  /// No description provided for @importPhaseScanning.
  ///
  /// In it, this message translates to:
  /// **'Analisi sorgente…'**
  String get importPhaseScanning;

  /// No description provided for @importPhaseParsing.
  ///
  /// In it, this message translates to:
  /// **'Lettura file {current} di {total}'**
  String importPhaseParsing(int current, int total);

  /// No description provided for @importPhasePaginating.
  ///
  /// In it, this message translates to:
  /// **'Impaginazione capitolo {current} di {total}'**
  String importPhasePaginating(int current, int total);

  /// No description provided for @importPhasePackaging.
  ///
  /// In it, this message translates to:
  /// **'Creazione taccuino…'**
  String get importPhasePackaging;

  /// No description provided for @importCancel.
  ///
  /// In it, this message translates to:
  /// **'Annulla'**
  String get importCancel;

  /// No description provided for @importCancelled.
  ///
  /// In it, this message translates to:
  /// **'Importazione annullata'**
  String get importCancelled;

  /// No description provided for @importReportTitle.
  ///
  /// In it, this message translates to:
  /// **'{count} avvisi durante l\'import'**
  String importReportTitle(int count);

  /// No description provided for @importReportCopy.
  ///
  /// In it, this message translates to:
  /// **'Copia'**
  String get importReportCopy;

  /// No description provided for @importReportClose.
  ///
  /// In it, this message translates to:
  /// **'Chiudi'**
  String get importReportClose;

  /// No description provided for @importSourceOneNote.
  ///
  /// In it, this message translates to:
  /// **'File OneNote'**
  String get importSourceOneNote;

  /// No description provided for @importSourceOneNoteHint.
  ///
  /// In it, this message translates to:
  /// **'Sezione .one o taccuino .onetoc2'**
  String get importSourceOneNoteHint;

  /// No description provided for @setOpenSourceLicenses.
  ///
  /// In it, this message translates to:
  /// **'Licenze open source'**
  String get setOpenSourceLicenses;

  /// No description provided for @setOpenSourceLicensesSub.
  ///
  /// In it, this message translates to:
  /// **'Componenti di terze parti inclusi nell\'app'**
  String get setOpenSourceLicensesSub;

  /// No description provided for @csBackToContent.
  ///
  /// In it, this message translates to:
  /// **'Torna al contenuto'**
  String get csBackToContent;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
