// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get csPdfTextCopied => 'Texte copié';

  @override
  String csCopyFailed(String error) {
    return 'Échec de la copie : $error';
  }

  @override
  String get csCopy => 'Copier';

  @override
  String get csSyncInProgress => 'Synchronisation en cours…';

  @override
  String get csSaved => 'Enregistré !';

  @override
  String csErrorGeneric(String error) {
    return 'Erreur : $error';
  }

  @override
  String get csSelectionCopied => 'Sélection copiée';

  @override
  String get csSelectionCut => 'Sélection coupée';

  @override
  String get csShortcutsTitle => 'Raccourcis clavier';

  @override
  String get csShortcutGroupGeneral => 'Général';

  @override
  String get csSaveNow => 'Enregistrer maintenant';

  @override
  String get csShortcutUndo => 'Annuler';

  @override
  String get csShortcutRedo => 'Rétablir';

  @override
  String get csSelectAll => 'Tout sélectionner';

  @override
  String get csShortcutResetZoom => 'Réinitialiser le zoom';

  @override
  String get csShortcutDeselect => 'Désélectionner / annuler';

  @override
  String get csShortcutThisGuide => 'Cet aide-mémoire';

  @override
  String get csShortcutGroupClipboard => 'Presse-papiers';

  @override
  String get csShortcutCopySelection => 'Copier la sélection';

  @override
  String get csShortcutCutSelection => 'Couper la sélection';

  @override
  String get csPaste => 'Coller';

  @override
  String get csShortcutDuplicateSelection => 'Dupliquer la sélection';

  @override
  String get csShortcutKeyDeleteBackspace => 'Suppr / Retour arrière';

  @override
  String get csShortcutDeleteElementOrSelection =>
      'Supprimer l\'élément ou la sélection';

  @override
  String get csShortcutGroupTools => 'Outils';

  @override
  String get csToolPen => 'Stylo';

  @override
  String get csToolBrush => 'Pinceau';

  @override
  String get csToolEraser => 'Gomme';

  @override
  String get csToolLasso => 'Lasso';

  @override
  String get csToolHand => 'Main / déplacer';

  @override
  String get csToolText => 'Texte';

  @override
  String get csToolShape => 'Forme';

  @override
  String get csClose => 'Fermer';

  @override
  String get csUnsavedChangesTitle => 'Modifications non enregistrées';

  @override
  String get csUnsavedChangesBody =>
      'Voulez-vous enregistrer avant de quitter ?';

  @override
  String get csDiscard => 'Ne pas enregistrer';

  @override
  String get csCancel => 'Annuler';

  @override
  String get csSave => 'Enregistrer';

  @override
  String get csOpeningLink => 'Ouverture du lien…';

  @override
  String get csCannotOpenLink => 'Impossible d\'ouvrir le lien';

  @override
  String get csCameraUnavailable =>
      'Aucun appareil photo disponible sur cet appareil';

  @override
  String get csPhotoCaptureFailed => 'Impossible de prendre la photo';

  @override
  String get csPdfRasterizing => 'Rastérisation du PDF…';

  @override
  String csPdfImportProgress(int done, int total) {
    return 'Import du PDF : $done/$total';
  }

  @override
  String get csPdfReadFailed =>
      'Impossible de lire le PDF : aucune page trouvée';

  @override
  String csPdfImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'PDF importé : $_temp0';
  }

  @override
  String csPdfImportError(String error) {
    return 'Erreur d\'import du PDF : $error';
  }

  @override
  String get csNoNotebookOpen => 'Aucun carnet ouvert';

  @override
  String get csMissingPageDataTitle => 'Données de page manquantes';

  @override
  String get csNoPages => 'Aucune page';

  @override
  String csMissingPagesBodyMany(int count) {
    return 'Cette page et $count autres n\'ont pas pu être récupérées depuis le serveur. Les fichiers ont peut-être été perdus lors d\'une synchronisation incomplète.';
  }

  @override
  String get csMissingPageBodyOne =>
      'Le fichier de cette page n\'a pas pu être récupéré depuis le serveur. Il a peut-être été perdu lors d\'une synchronisation incomplète.';

  @override
  String get csRetrySync => 'Relancer la synchronisation';

  @override
  String get csRestoreAsBlankPage => 'Restaurer comme page vierge';

  @override
  String csRestoreAllMissing(int count) {
    return 'Tout restaurer ($count)';
  }

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages restaurées comme vierges',
      one: '$count page restaurée comme vierge',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'Supprimer la page';

  @override
  String csSyncProgressCount(int done, int total) {
    return 'Synchronisation $done/$total';
  }

  @override
  String get csSyncing => 'Synchronisation…';

  @override
  String csShapeRecognizedLabel(String shape) {
    return 'Forme : $shape';
  }

  @override
  String get csConfirmShapeSemantics => 'Confirmer la forme reconnue';

  @override
  String get csConfirm => 'Confirmer';

  @override
  String get csCancelShapeSemantics => 'Annuler la forme reconnue';

  @override
  String csTapToPlaceSymbol(String name) {
    return 'Toucher pour placer : $name';
  }

  @override
  String get csCancelSymbolInsertSemantics => 'Annuler l\'insertion du symbole';

  @override
  String get csTapToPlaceCopy => 'Toucher pour placer la copie';

  @override
  String get csCancelPasteSemantics => 'Annuler le collage';

  @override
  String get csNewPage => 'Nouvelle page';

  @override
  String get csImageCopied => 'Image copiée';

  @override
  String get csImageCut => 'Image coupée';

  @override
  String get csImageCommentTitle => 'Commentaire de l\'image';

  @override
  String get csAddCommentHint => 'Ajouter un commentaire...';

  @override
  String get csRemove => 'Retirer';

  @override
  String get csCut => 'Couper';

  @override
  String get csDuplicate => 'Dupliquer';

  @override
  String get csSelectionDuplicated => 'Sélection dupliquée';

  @override
  String get csChangeColor => 'Changer la couleur';

  @override
  String get csThickness => 'Épaisseur';

  @override
  String get csDelete => 'Supprimer';

  @override
  String get csMore => 'Plus';

  @override
  String get csPresentationMode => 'Mode présentation';

  @override
  String get csPresentationModeSub =>
      'Plein écran, sans outils — idéal pour montrer les pages';

  @override
  String get csRecognizeHandwriting => 'Reconnaître l\'écriture';

  @override
  String get csRecognizeHandwritingSub =>
      'Convertit l\'encre en texte recherchable (sur l\'appareil)';

  @override
  String get csRecognizeInProgress => 'Reconnaissance en cours…';

  @override
  String get csRecognizeNothing => 'Aucun texte reconnu.';

  @override
  String csRecognizeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lignes reconnues',
      one: '$count ligne reconnue',
    );
    return '$_temp0.';
  }

  @override
  String csRecognizeFailed(String error) {
    return 'Échec de la reconnaissance : $error';
  }

  @override
  String get csShareLink => 'Partager par lien';

  @override
  String get csShareLinkSub =>
      'Envoie un PDF sur votre Nextcloud et crée un lien public';

  @override
  String get csShareLinkInProgress => 'Création du lien…';

  @override
  String get csShareLinkTitle => 'Lien public';

  @override
  String get csShareLinkBody =>
      'Toute personne disposant de ce lien peut consulter le PDF. Révocable depuis votre Nextcloud.';

  @override
  String get csShareLinkCopied => 'Lien copié dans le presse-papiers.';

  @override
  String csShareLinkFailed(String error) {
    return 'Échec du partage : $error';
  }

  @override
  String get csCopyLink => 'Copier le lien';

  @override
  String get csShare => 'Partager';

  @override
  String get csRevokeLink => 'Révoquer le lien';

  @override
  String get csRevokeLinkDone => 'Lien révoqué.';

  @override
  String get csShareLinkUpdate => 'Mettre à jour le PDF partagé';

  @override
  String get csShareLinkUpdated => 'PDF mis à jour.';

  @override
  String get csChangeSelectionColor => 'Changer la couleur de la sélection';

  @override
  String get csSelectionThickness => 'Épaisseur de la sélection';

  @override
  String csWidthPx(String width) {
    return '$width px';
  }

  @override
  String get csFlipHorizontal => 'Retourner horizontalement';

  @override
  String get csFlipVertical => 'Retourner verticalement';

  @override
  String get csCopyAsImage => 'Copier comme image';

  @override
  String get csPasteInAnotherNotebook => 'Coller dans un autre carnet…';

  @override
  String get csKeyDelete => 'Suppr';

  @override
  String get csCreateSymbol => 'Créer un symbole';

  @override
  String get csSelect => 'Sélectionner';

  @override
  String get csImportFile => 'Importer un fichier…';

  @override
  String get csTakePhoto => 'Prendre une photo';

  @override
  String get csInsertText => 'Insérer du texte';

  @override
  String csInsertSymbolCount(int count) {
    return 'Insérer un symbole ($count)';
  }

  @override
  String get csClearPage => 'Vider la page';

  @override
  String get csExportPng => 'Exporter en PNG';

  @override
  String get csExportPdf => 'Exporter en PDF';

  @override
  String get csClearPageConfirmBody =>
      'Tous les éléments de cette page seront supprimés. Continuer ?';

  @override
  String get csClear => 'Vider';

  @override
  String get csCreateSymbolTitle => 'Créer un symbole réutilisable';

  @override
  String get csSymbolNameLabel => 'Nom du symbole';

  @override
  String get csLibraryLabel => 'Bibliothèque :';

  @override
  String get csNoLibraryNotice =>
      'Aucune bibliothèque existante. Une bibliothèque « Symboles » sera créée.';

  @override
  String get csCreate => 'Créer';

  @override
  String csSymbolCreated(String name) {
    return 'Symbole « $name » créé !';
  }

  @override
  String csSaveFileDialogTitle(String fileName) {
    return 'Enregistrer $fileName';
  }

  @override
  String get csExportCurrentPagePng => 'Page actuelle (PNG)';

  @override
  String get csExportCurrentChapter => 'Chapitre actuel';

  @override
  String get csExportEntireNotebook => 'Carnet entier';

  @override
  String csExportingPages(int count) {
    return 'Export de $count pages...';
  }

  @override
  String csChooseFolderForImages(int count) {
    return 'Choisir un dossier pour les $count images';
  }

  @override
  String csPngExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'PNG exporté ($_temp0)';
  }

  @override
  String csExportError(String error) {
    return 'Erreur d\'export : $error';
  }

  @override
  String get csExportCurrentPage => 'Page actuelle';

  @override
  String csGeneratingPdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'Génération du PDF ($_temp0)...';
  }

  @override
  String csPdfExportError(String error) {
    return 'Erreur d\'export PDF : $error';
  }

  @override
  String csPdfExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'PDF exporté : $_temp0';
  }

  @override
  String get csChapterSeparatorEyebrow => 'CHAPITRE';

  @override
  String get csSelectionCopiedAsImage => 'Sélection copiée comme image';

  @override
  String csCopyImageError(String error) {
    return 'Erreur de copie de l\'image : $error';
  }

  @override
  String get csExport => 'Exporter';

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
  String get csExportChapterTitle => 'Exporter le chapitre';

  @override
  String get csExportNotebookTitle => 'Exporter le carnet entier';

  @override
  String get csChapterSeparatorQuestion =>
      'Insérer une page de séparation avant chaque chapitre ?';

  @override
  String get csYesWithSeparators => 'Oui, avec séparateurs';

  @override
  String get csNoPagesOnly => 'Non, seulement les pages';

  @override
  String csTotalPages(int count) {
    return 'Pages au total : $count';
  }

  @override
  String csFromPage(int page) {
    return 'De la page : $page';
  }

  @override
  String csToPage(int page) {
    return 'À la page : $page';
  }

  @override
  String csWillExportPages(int count, int start, int end) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages seront exportées ($start–$end)',
      one: '$count page sera exportée ($start–$end)',
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
  String get csGoToPage => 'Aller à la page';

  @override
  String get csDuplicatePage => 'Dupliquer la page';

  @override
  String get csNewPageAfter => 'Nouvelle page après';

  @override
  String get csDeletePageConfirmTitle => 'Supprimer la page ?';

  @override
  String csDeletePageConfirmBody(int number) {
    return 'La page $number et tout son contenu seront supprimés.';
  }

  @override
  String get csExportAsPdf => 'Exporter en PDF';

  @override
  String get csExportAsPng => 'Exporter en PNG';

  @override
  String get csExportAsNcnote => 'Exporter en .abelnote (natif)';

  @override
  String get csExportNcnoteSubtitle =>
      'Format natif, qualité vectorielle complète (pour sauvegarde ou transfert)';

  @override
  String get csGeneratingNcnote => 'Génération du .abelnote…';

  @override
  String csNcnoteExported(String size) {
    return '.abelnote exporté ($size Ko)';
  }

  @override
  String csNcnoteExportError(String error) {
    return 'Erreur d\'export .abelnote : $error';
  }

  @override
  String get csImageOrPdf => 'Image ou PDF';

  @override
  String get csChangePaperType => 'Changer le type de papier';

  @override
  String get csPenToMonitor => 'Stylet → Écran';

  @override
  String get csPenToMonitorSubtitle => 'Limiter le stylet à un seul écran';

  @override
  String get csPaperType => 'Type de papier';

  @override
  String get csPaperBlank => 'Blanc';

  @override
  String get csPaperLinedNarrow => 'Lignes serrées';

  @override
  String get csPaperLinedWide => 'Lignes larges';

  @override
  String get csPaperGrid => 'Quadrillage';

  @override
  String get csPaperDotted => 'Pointillé';

  @override
  String get csPaperCornell => 'Cornell';

  @override
  String get csPaperIsometric => 'Isométrique';

  @override
  String get csPaperMusic => 'Portée musicale';

  @override
  String get csMapPenToMonitor => 'Associer le stylet à un écran';

  @override
  String csPenMappedTo(String monitor) {
    return 'Stylet associé à $monitor';
  }

  @override
  String get csAllMonitors => 'Tous les écrans';

  @override
  String get csAllMonitorsSubtitle =>
      'Réinitialiser (stylet sur tout le bureau)';

  @override
  String get csPenReset => 'Stylet réinitialisé';

  @override
  String get csShapeLine => 'Ligne';

  @override
  String get csShapeCircle => 'Cercle';

  @override
  String get csShapeRectangle => 'Rectangle';

  @override
  String get csShapeTriangle => 'Triangle';

  @override
  String get csShapeArrow => 'Flèche';

  @override
  String get csInvalidRangeError =>
      'Saisissez un intervalle valide (par ex. 1–10).';

  @override
  String csPdfStartOutOfRange(int count) {
    return 'Le PDF contient environ $count pages. Le début est hors intervalle.';
  }

  @override
  String get csImportPdfTitle => 'Importer un PDF';

  @override
  String csPdfEstimatedPages(int count) {
    return 'Le PDF contient environ $count pages.';
  }

  @override
  String csAllPagesWithCount(int count) {
    return 'Toutes les pages ($count)';
  }

  @override
  String get csAllPages => 'Toutes les pages';

  @override
  String get csCustomRange => 'Intervalle personnalisé';

  @override
  String get csFromLabel => 'De';

  @override
  String get csToLabel => 'À';

  @override
  String get csImport => 'Importer';

  @override
  String libErrorGeneric(String error) {
    return 'Erreur : $error';
  }

  @override
  String libErrorOpen(String error) {
    return 'Erreur à l\'ouverture : $error';
  }

  @override
  String get libImportCannotReadFile => 'Impossible de lire le fichier';

  @override
  String get libImportInProgress => 'Import en cours…';

  @override
  String get libServiceUnavailable => 'Service indisponible';

  @override
  String libImportedTitleSuffix(String title) {
    return '$title (importé)';
  }

  @override
  String libImportSuccess(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return 'Importé : « $title » ($_temp0)';
  }

  @override
  String get libImportCorruptedFile =>
      'Ce fichier n\'est pas un carnet AbelNotes valide — il est peut-être incomplet ou endommagé.';

  @override
  String get libExport => 'Exporter';

  @override
  String get libImportOneNoteUnreadable =>
      'AbelNotes ne parvient pas à lire ce fichier OneNote — il utilise peut-être un format pas encore pris en charge, ou il est endommagé.';

  @override
  String libErrorImport(String error) {
    return 'Erreur d\'import : $error';
  }

  @override
  String libErrorCreate(String error) {
    return 'Erreur de création : $error';
  }

  @override
  String get libSketchDefaultTitle => 'Croquis';

  @override
  String libErrorCreateSketch(String error) {
    return 'Erreur de création du croquis : $error';
  }

  @override
  String get libRemoveFromFavorites => 'Retirer des favoris';

  @override
  String get libAddToFavorites => 'Ajouter aux favoris';

  @override
  String get libRename => 'Renommer';

  @override
  String get libChangeCover => 'Changer la couverture';

  @override
  String get libMoveToFolder => 'Déplacer vers un dossier';

  @override
  String get libNoFolder => 'Aucun dossier';

  @override
  String get libNewFolder => 'Nouveau dossier';

  @override
  String get libRenameFolder => 'Renommer le dossier';

  @override
  String get libFolderNameHint => 'Nom du dossier';

  @override
  String get libAllNotebooks => 'Tous';

  @override
  String get libDeleteFolder => 'Supprimer le dossier';

  @override
  String libDeleteFolderTitle(String name) {
    return 'Supprimer le dossier « $name » ?';
  }

  @override
  String get libDeleteFolderBody =>
      'Les carnets qu\'il contient ne sont pas supprimés — ils restent dans la bibliothèque sans dossier.';

  @override
  String get libDelete => 'Supprimer';

  @override
  String get libDeleteNotebookTitle => 'Supprimer ce carnet ?';

  @override
  String get libDeleteNotebookBody =>
      'Il sera déplacé vers la corbeille. Vous pourrez le restaurer depuis Réglages > Stockage.';

  @override
  String get libCancel => 'Annuler';

  @override
  String get libRenameNotebookTitle => 'Renommer le carnet';

  @override
  String get libSave => 'Enregistrer';

  @override
  String get libSortTitle => 'Tri';

  @override
  String get libAppName => 'AbelNotes';

  @override
  String get libSearchHintShort => 'Rechercher…';

  @override
  String get libSearchHintNotebooks => 'Rechercher des carnets…';

  @override
  String get libImport => 'Importer';

  @override
  String get libImportTooltip => 'Importer un fichier .abelnote';

  @override
  String get libSettingsTooltip => 'Réglages';

  @override
  String get libMoreTooltip => 'Plus';

  @override
  String get libViewAsList => 'Vue en liste';

  @override
  String get libViewAsGrid => 'Vue en grille';

  @override
  String libSortWithLabel(String sortLabel) {
    return 'Tri : $sortLabel';
  }

  @override
  String get libImportNcnoteMenu => 'Importer…';

  @override
  String get libYourNotebooks => 'Vos carnets';

  @override
  String libItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments',
      one: '$count élément',
    );
    return '$_temp0';
  }

  @override
  String get libNewNotebook => 'Nouveau carnet';

  @override
  String get libSketches => 'Croquis';

  @override
  String get libInfiniteSpace => 'espace infini';

  @override
  String get libNewSketch => 'Nouveau croquis';

  @override
  String get libInfiniteCanvas => 'Toile infinie';

  @override
  String get libNew => 'Nouveau';

  @override
  String libPagesAbbrev(int count) {
    return '$count p.';
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
  String get libFooterLocalFirst => 'Application local-first';

  @override
  String get libSyncingWithServer => 'Synchronisation avec le serveur…';

  @override
  String libDownloadingProgress(int done, int total) {
    return 'Téléchargement de $done/$total carnets…';
  }

  @override
  String get libLoadingNotebooks => 'Chargement des carnets…';

  @override
  String get libLoadingNotebooksFromServer =>
      'Chargement des carnets depuis le serveur…';

  @override
  String get libTimeNow => 'maintenant';

  @override
  String libTimeMinutesAgo(int count) {
    return 'il y a $count min';
  }

  @override
  String libTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count heures',
      one: 'il y a $count heure',
    );
    return '$_temp0';
  }

  @override
  String libTimeDaysAgo(int count) {
    return 'il y a $count j';
  }

  @override
  String libTimeWeeksAgo(int count) {
    return 'il y a $count sem.';
  }

  @override
  String libTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count mois',
      one: 'il y a $count mois',
    );
    return '$_temp0';
  }

  @override
  String libTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count ans',
      one: 'il y a $count an',
    );
    return '$_temp0';
  }

  @override
  String get libNotebookTitleLabel => 'Titre';

  @override
  String get libCoverLabel => 'Couverture';

  @override
  String get libPaperLabel => 'Papier';

  @override
  String get libPaperBlank => 'Blanc';

  @override
  String get libPaperLined => 'Ligné';

  @override
  String get libPaperGrid => 'Quadrillé';

  @override
  String get libPaperDotted => 'Pointillé';

  @override
  String get libCreate => 'Créer';

  @override
  String get setSectionGeneral => 'Général';

  @override
  String get setSectionInput => 'Stylet et saisie';

  @override
  String get setSectionSync => 'Synchronisation';

  @override
  String get setSectionStorage => 'Stockage';

  @override
  String get setSectionShortcuts => 'Raccourcis';

  @override
  String get setSectionAdvanced => 'Avancé';

  @override
  String get setSectionAbout => 'À propos';

  @override
  String get setBackToLibrary => 'Bibliothèque';

  @override
  String get setSettingsTitle => 'Réglages';

  @override
  String get setThemeLabel => 'Thème';

  @override
  String get setThemeLight => 'Clair';

  @override
  String get setThemePaper => 'Papier';

  @override
  String get setThemeDark => 'Sombre';

  @override
  String get setLanguage => 'Langue';

  @override
  String get setLanguageSub => 'Langue de l\'interface';

  @override
  String get setLanguageItalian => 'Italien';

  @override
  String get setFavoritesFirst => 'Favoris en premier';

  @override
  String get setFavoritesFirstSub =>
      'Afficher les carnets favoris en haut de la bibliothèque';

  @override
  String get setStylusOnly => 'Stylet uniquement';

  @override
  String get setStylusOnlySub =>
      'Ignore le toucher du doigt pendant l\'écriture. Le zoom et le déplacement à deux doigts continuent de fonctionner.';

  @override
  String get setPalmRejection => 'Rejet de la paume';

  @override
  String get setPalmRejectionSub => 'Détection automatique de la paume posée';

  @override
  String get setPressureThickness => 'Pression → épaisseur';

  @override
  String get setPressureThicknessSub =>
      'Modulation du trait selon la pression du stylet';

  @override
  String get setTiltCalligraphy => 'Inclinaison → calligraphie';

  @override
  String get setTiltCalligraphySub =>
      'L\'inclinaison du stylet modifie la largeur et l\'angle du trait';

  @override
  String get setStrokeContinuation => 'Continuité du trait';

  @override
  String get setStrokeContinuationSub =>
      'Compense de brèves interruptions du capteur (par ex. le point du i)';

  @override
  String get setSyncConnectedDesc =>
      'Connecté à un serveur WebDAV. Les carnets se synchronisent sur tous vos appareils.';

  @override
  String get setSyncLocalOnlyDesc =>
      'Mode local uniquement : les carnets restent sur cet appareil. Connectez un serveur WebDAV pour y accéder depuis plusieurs appareils.';

  @override
  String get setSyncWebdav => 'WebDAV';

  @override
  String get setSyncLocalOnly => 'Local uniquement';

  @override
  String setSyncAccountInfo(String host, String username) {
    return '$host · $username';
  }

  @override
  String get setSyncNoServer => 'Aucun serveur connecté';

  @override
  String get setDisconnect => 'Déconnecter';

  @override
  String get setConnect => 'Connecter';

  @override
  String get setDisconnectTitle => 'Déconnecter le serveur ?';

  @override
  String get setDisconnectBody =>
      'Les carnets déjà téléchargés restent sur cet appareil. La synchronisation s\'arrête jusqu\'à la reconnexion.';

  @override
  String get setCheckCert => 'Vérifier le certificat du serveur';

  @override
  String get setCertCheckFailed =>
      'Impossible de vérifier le certificat du serveur.';

  @override
  String get setCertUnchanged =>
      'Le certificat n\'a pas changé depuis la dernière connexion.';

  @override
  String get setCertChangedTitle => 'Nouveau certificat détecté';

  @override
  String setCertChangedBody(String oldFingerprint, String newFingerprint) {
    return 'Le serveur présente une empreinte différente de celle enregistrée. Si vous avez renouvelé le certificat vous-même, confirmez pour continuer à synchroniser. Sinon, ANNULEZ et vérifiez votre réseau avant de réessayer.\n\nEmpreinte enregistrée : $oldFingerprint\nEmpreinte actuelle : $newFingerprint';
  }

  @override
  String get setCertConfirmNew => 'Confirmer le nouveau certificat';

  @override
  String get setCancel => 'Annuler';

  @override
  String get setShortcutPen => 'Stylo';

  @override
  String get setShortcutUndo => 'Annuler';

  @override
  String get setShortcutBrush => 'Pinceau';

  @override
  String get setShortcutRedo => 'Rétablir';

  @override
  String get setShortcutEraser => 'Gomme';

  @override
  String get setShortcutSelectAll => 'Tout sélectionner';

  @override
  String get setShortcutLasso => 'Lasso';

  @override
  String get setShortcutCopy => 'Copier';

  @override
  String get setShortcutHand => 'Main';

  @override
  String get setShortcutCut => 'Couper';

  @override
  String get setShortcutText => 'Texte';

  @override
  String get setShortcutPaste => 'Coller';

  @override
  String get setShortcutShape => 'Forme';

  @override
  String get setShortcutDuplicate => 'Dupliquer';

  @override
  String get setShortcutChangePage => 'Changer de page';

  @override
  String get setShortcutSave => 'Enregistrer';

  @override
  String get setShortcutFit => 'Ajuster';

  @override
  String get setShortcutCheatSheet => 'Aide-mémoire';

  @override
  String get setKeyboardShortcutsTitle => 'Raccourcis clavier';

  @override
  String get setClearCache => 'Vider le cache';

  @override
  String get setClearCacheSub =>
      'Supprime les fichiers temporaires. Les carnets ne sont pas touchés.';

  @override
  String get setClear => 'Vider';

  @override
  String get setTrash => 'Corbeille';

  @override
  String get setTrashSub => 'Carnets supprimés, restaurables';

  @override
  String get setOpenTrash => 'Ouvrir la corbeille';

  @override
  String get setClearCacheDone => 'Cache vidé.';

  @override
  String get setExportLibrary => 'Exporter la bibliothèque';

  @override
  String get setExportLibrarySub =>
      'Enregistre tous les carnets dans une seule archive zip.';

  @override
  String get setExport => 'Exporter';

  @override
  String get setExportLibraryEmpty => 'Aucun carnet à exporter.';

  @override
  String get setExportLibraryInProgress => 'Export en cours…';

  @override
  String setExportLibraryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets exportés',
      one: '$count carnet exporté',
    );
    return '$_temp0.';
  }

  @override
  String setExportLibraryFailed(String error) {
    return 'Échec de l\'export : $error';
  }

  @override
  String setTrashPurgeTitle(String title) {
    return 'Supprimer définitivement « $title » ?';
  }

  @override
  String get setTrashPurgeBody => 'Vous ne pourrez plus le récupérer.';

  @override
  String get setTrashPurge => 'Supprimer définitivement';

  @override
  String get setTrashEmptyTitle => 'Vider la corbeille ?';

  @override
  String get setTrashEmptyBody =>
      'Tous les carnets de la corbeille seront définitivement supprimés.';

  @override
  String get setTrashEmpty => 'Vider la corbeille';

  @override
  String get setTrashEmptyState => 'La corbeille est vide.';

  @override
  String setTrashDeletedAgo(String time) {
    return 'Supprimé il y a $time';
  }

  @override
  String get setTrashRestore => 'Restaurer';

  @override
  String get setAdvancedIntro =>
      'Outils de récupération pour les rares cas où un carnet reste bloqué en synchronisation. Ne les utilisez que si la synchronisation échoue encore après une « Forcer la synchro » normale depuis la bibliothèque.';

  @override
  String get setForceReloadTitle =>
      'Forcer le rechargement du carnet depuis le serveur';

  @override
  String get setForceReloadDesc =>
      'Retélécharge tout le contenu du carnet depuis le dossier delta du serveur et écrase la copie locale. Utile si le nombre de pages semble faux ou si le carnet ne s\'ouvre pas. Aucune donnée n\'est perdue côté serveur.';

  @override
  String setErrorGeneric(String error) {
    return 'Erreur : $error';
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
  String get setReload => 'Recharger';

  @override
  String get setCloseNotebookFirst =>
      'Fermez le carnet avant de le recharger depuis le serveur.';

  @override
  String setReloadConfirmTitle(String title) {
    return 'Recharger « $title » ?';
  }

  @override
  String get setReloadConfirmBody =>
      'Retélécharge les métadonnées, le document, les pages et les médias depuis le dossier delta du serveur. La copie locale est remplacée.\n\nLes modifications locales pas encore synchronisées seront perdues. Continuer ?';

  @override
  String setReloadInProgress(String title) {
    return 'Rechargement de « $title »…';
  }

  @override
  String get setNotConnectedWebdav => 'Non connecté à un serveur WebDAV.';

  @override
  String setReloadDone(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return '« $title » rechargé — $_temp0.';
  }

  @override
  String setReloadFailed(String error) {
    return 'Échec du rechargement : $error';
  }

  @override
  String get setAboutTagline =>
      'Une application d\'écriture manuscrite local-first.';

  @override
  String get setAboutOffline =>
      'Fonctionne hors ligne ; la synchronisation WebDAV est facultative.';

  @override
  String setAboutVersion(String version, String commit) {
    return 'Version $version · build $commit';
  }

  @override
  String get setReportProblem => 'Signaler un problème';

  @override
  String get setReportProblemSub =>
      'Copie le journal d\'erreurs dans le presse-papiers pour le joindre à votre signalement.';

  @override
  String get setCopyLog => 'Copier le journal';

  @override
  String get setReportProblemEmpty => 'Aucune erreur enregistrée.';

  @override
  String get setCopyLogDone => 'Journal copié dans le presse-papiers.';

  @override
  String get onbTagline =>
      'Notes manuscrites et dessin à main levée, synchronisés sur VOTRE serveur. Choisissez comment commencer — vous pourrez changer plus tard.';

  @override
  String get onbTryNowTitle => 'Essayer tout de suite';

  @override
  String get onbTryNowSubtitle =>
      'Commencez à écrire maintenant. Les carnets restent sur cet appareil — pas de compte, pas de serveur.';

  @override
  String get onbConnectNextcloudTitle => 'Connecter votre Nextcloud';

  @override
  String get onbConnectNextcloudSubtitle =>
      'Synchronisez sur votre propre serveur WebDAV / Nextcloud et accédez-y depuis tous vos appareils.';

  @override
  String get onbManagedServerTitle => 'Serveur géré AbelNotes';

  @override
  String get onbManagedServerSubtitle =>
      'Pas de serveur ? Vous pourrez bientôt utiliser le nôtre, sans rien configurer.';

  @override
  String get onbComingSoonBadge => 'Bientôt';

  @override
  String get onbDriveTitle => 'Synchroniser avec Google Drive';

  @override
  String get onbDriveSubtitle =>
      'Rien à configurer : vos carnets se synchronisent via votre propre Google Drive.';

  @override
  String get driveSignInFailed =>
      'La connexion à Google n\'a pas abouti. Rien n\'a été modifié.';

  @override
  String get driveSignInCancelled => 'Connexion annulée.';

  @override
  String get driveNotConfigured =>
      'Cette version ne contient pas d\'identifiants Google, la synchronisation Drive est donc indisponible.';

  @override
  String get driveNoKeyring =>
      'Ce système n\'a pas de stockage sécurisé, le compte Google ne peut donc pas être conservé en sécurité. La synchronisation Drive est indisponible ici.';

  @override
  String get driveConnectedTitle => 'Google Drive connecté';

  @override
  String get setSyncDriveTitle => 'Google Drive';

  @override
  String get setSyncDriveConnected =>
      'Les carnets se synchronisent via votre Google Drive.';

  @override
  String get setSyncDriveNotConnected => 'Non connecté.';

  @override
  String get setSyncDriveDesktopOnly =>
      'Disponible sur ordinateur pour l\'instant.';

  @override
  String get setDriveDisconnectTitle => 'Déconnecter Google Drive ?';

  @override
  String get setDriveDisconnectBody =>
      'Les carnets déjà présents dans votre Drive y restent — l\'application cesse simplement de les synchroniser. Les carnets sur cet appareil ne sont pas touchés.';

  @override
  String get setDriveDisconnectConfirm => 'Déconnecter';

  @override
  String get setSyncOneBackendNote =>
      'Les carnets se synchronisent à un seul endroit à la fois : votre propre serveur ou votre Google Drive.';

  @override
  String get setSyncSwitchTitle =>
      'Basculer la synchronisation vers Google Drive ?';

  @override
  String get setSyncSwitchBody =>
      'Vos carnets restent sur cet appareil et sont envoyés vers votre Google Drive. Les copies déjà présentes sur votre serveur restent où elles sont, mais ne reçoivent plus de mises à jour à partir de ce moment. Rien n\'est supprimé.';

  @override
  String get setSyncSwitchConfirm => 'Basculer vers Drive';

  @override
  String get setSyncInactiveNote =>
      'Configuré, mais inutilisé : la synchronisation se fait vers l\'autre destination.';

  @override
  String libPendingUploadsDrive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets restent à envoyer vers Google Drive',
      one: '$count carnet reste à envoyer vers Google Drive',
    );
    return '$_temp0';
  }

  @override
  String libPendingUploadsServer(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets restent à envoyer vers votre serveur',
      one: '$count carnet reste à envoyer vers votre serveur',
    );
    return '$_temp0';
  }

  @override
  String get libPendingUploadsHint =>
      'En attendant, ils restent sur cet appareil. Laissez l\'application ouverte un instant.';

  @override
  String get libStorageFullDrive => 'Votre Google Drive est plein';

  @override
  String get libStorageFullServer => 'Votre serveur n\'a plus d\'espace';

  @override
  String get libStorageFullBody =>
      'Les carnets restent en sécurité sur cet appareil, mais ne peuvent pas être envoyés tant que vous ne libérez pas d\'espace. Google Drive partage son espace avec Gmail et Photos.';

  @override
  String get libStorageFullBodyServer =>
      'Les carnets restent en sécurité sur cet appareil, mais ne peuvent pas être envoyés tant que de l\'espace n\'est pas libéré sur le serveur.';

  @override
  String get libKeepOnDevice => 'Garder uniquement sur cet appareil';

  @override
  String get libResumeSync => 'Synchroniser à nouveau ce carnet';

  @override
  String get libLocalOnlyBadge => 'Ici uniquement';

  @override
  String get libKeepOnDeviceTitle =>
      'Garder ce carnet uniquement sur cet appareil ?';

  @override
  String get libKeepOnDeviceBody =>
      'Il cesse d\'être envoyé et les autres appareils ne le recevront plus. Il reste pleinement utilisable ici.';

  @override
  String get libKeepOnDeviceRemoveCopy =>
      'Supprimer aussi la copie déjà envoyée';

  @override
  String get libKeepOnDeviceConfirm => 'Garder ici uniquement';

  @override
  String get libLocalOnlyDone => 'Gardé uniquement sur cet appareil.';

  @override
  String get libSyncResumedDone => 'Ce carnet sera à nouveau synchronisé.';

  @override
  String get syncLocalOnlyTooltip => 'Gardé uniquement sur cet appareil';

  @override
  String get libFreeSpace => 'Libérer de l\'espace sur cet appareil';

  @override
  String get libKeepOnThisDevice => 'Télécharger sur cet appareil';

  @override
  String get libFreeSpaceTitle => 'Retirer ce carnet de cet appareil ?';

  @override
  String get libFreeSpaceBody =>
      'Le carnet reste sur le serveur distant et sur vos autres appareils. Ici, il devient une carte à toucher pour le retélécharger. D\'ici là, il ne s\'ouvre pas hors ligne et la recherche n\'explore pas son contenu.';

  @override
  String get libFreeSpaceConfirm => 'Libérer de l\'espace';

  @override
  String libFreeSpaceDone(String size) {
    return 'Retiré de cet appareil. $size libérés.';
  }

  @override
  String get libFreeSpaceNotSynced =>
      'Ce carnet contient des modifications que le serveur distant n\'a pas encore. Ce sera possible une fois qu\'elles auront été envoyées.';

  @override
  String get libFreeSpaceOpenNotebook => 'Fermez d\'abord le carnet.';

  @override
  String get libKeepOnThisDeviceDone =>
      'Il sera de nouveau téléchargé sur cet appareil.';

  @override
  String get syncNotOnDeviceTooltip =>
      'Sur le serveur distant, pas sur cet appareil';

  @override
  String get onbSyncQuestion => 'Synchroniser vos notes';

  @override
  String get onbSyncQuestionSub =>
      'Choisissez où vivent vos carnets. Vous pourrez changer plus tard.';

  @override
  String get onbDriveShort => 'Google Drive';

  @override
  String get onbNextcloudShort => 'Nextcloud / WebDAV';

  @override
  String get onbStartWithoutSync => 'Commencer sans synchronisation';

  @override
  String get onbDriveUnavailable => 'Indisponible dans cette version';

  @override
  String get onbLicenseNote =>
      'En ouvrant l\'application, vous acceptez la licence AGPL-3.0. « AbelNotes » est une marque du projet.';

  @override
  String get logConnectionFailed =>
      'Connexion impossible. Vérifiez l\'URL, le nom d\'utilisateur et le mot de passe.';

  @override
  String logConnectionError(String error) {
    return 'Erreur de connexion : $error';
  }

  @override
  String get logCertificateChanged =>
      'Le certificat du serveur a changé depuis la dernière connexion. Si cela vient de vous (par ex. renouvellement du certificat), allez dans Réglages > Synchronisation pour confirmer la nouvelle empreinte.';

  @override
  String get logCertConfirmTitle => 'Vérifier l\'identité du serveur';

  @override
  String get logCertConfirmBody =>
      'Première connexion à ce serveur. Comparez cette empreinte avec celle de votre serveur (par ex. en ligne de commande) avant de continuer :';

  @override
  String get logCertConfirmTrust => 'Je fais confiance, continuer';

  @override
  String get logBackTooltip => 'Retour';

  @override
  String get logTitle => 'Connecter votre Nextcloud';

  @override
  String get logSubtitle =>
      'N\'importe quel serveur WebDAV / Nextcloud (VPS, auto-hébergé, LAN). Aucun cloud tiers.';

  @override
  String get logServerUrlLabel => 'URL du serveur';

  @override
  String get logServerUrlHint => 'https://cloud.example.com';

  @override
  String get logServerUrlRequired => 'Saisissez l\'URL du serveur';

  @override
  String get logServerUrlInvalid => 'Doit commencer par http:// ou https://';

  @override
  String get logUsernameLabel => 'Nom d\'utilisateur';

  @override
  String get logUsernameRequired => 'Nom d\'utilisateur requis';

  @override
  String get logPasswordLabel => 'Mot de passe / mot de passe d\'application';

  @override
  String get logPasswordRequired => 'Mot de passe requis';

  @override
  String get logAppPasswordHint =>
      'Recommandé : un mot de passe d\'application généré depuis les réglages de Nextcloud.';

  @override
  String get logServerTypeNextcloud => 'Nextcloud / ownCloud';

  @override
  String get logServerTypeWebdav => 'Autre WebDAV';

  @override
  String get logServerUrlHintWebdav => 'https://dav.example.com/dossier';

  @override
  String get logWebdavExperimental =>
      'Les serveurs WebDAV génériques (Synology, Seafile, rclone…) sont expérimentaux : seul Nextcloud est testé en profondeur. Conservez des sauvegardes de vos carnets.';

  @override
  String get logWebdavUrlHint =>
      'URL WebDAV complète, chemin inclus — par ex. Synology https://nas:5006/home, Seafile https://serveur/seafdav. Le partage par lien n\'est pas disponible en WebDAV générique.';

  @override
  String get logConnectButton => 'Connecter';

  @override
  String get chromeBackToLibraryTooltip => 'Retour à la bibliothèque';

  @override
  String get chromeLibrary => 'Bibliothèque';

  @override
  String get chromeUnsaved => 'Non enregistré';

  @override
  String get chromeMouseDrawsTooltip =>
      'Souris : dessine — touchez pour l\'utiliser pour la sélection';

  @override
  String get chromeMouseSelectsTooltip =>
      'Souris : sélection — touchez pour dessiner à la souris';

  @override
  String get chromeTouchDrawsTooltip =>
      'Doigt : dessine — touchez pour l\'utiliser pour naviguer';

  @override
  String get chromeTouchPansTooltip =>
      'Doigt : navigue — touchez pour dessiner au doigt';

  @override
  String get chromeUndo => 'Annuler';

  @override
  String get chromeRedo => 'Rétablir';

  @override
  String get chromeAllPages => 'Toutes les pages';

  @override
  String chromePageIndicator(String current, int total) {
    return '$current / $total';
  }

  @override
  String get chromeAddPage => 'Ajouter une page';

  @override
  String get chromeSymbols => 'Symboles';

  @override
  String get chromeExport => 'Exporter';

  @override
  String get chromeMore => 'Plus';

  @override
  String get chromeMoreEllipsis => 'Plus…';

  @override
  String get chromeToolPen => 'Stylo · P';

  @override
  String get chromeToolHighlighter => 'Surligneur';

  @override
  String get chromeToolEraser => 'Gomme · E';

  @override
  String get chromeToolLasso => 'Lasso · L';

  @override
  String get chromeToolText => 'Texte · T';

  @override
  String get chromeToolLaser => 'Laser';

  @override
  String get chromeToolPan => 'Main · H';

  @override
  String get chromeDragToMoveBar =>
      'Faites glisser pour déplacer la barre d\'outils';

  @override
  String get chromeShapeGuessOn => 'Forme auto · activée';

  @override
  String get chromeShapeGuessOff => 'Forme auto · désactivée';

  @override
  String get chromeLabelPen => 'Stylo';

  @override
  String get chromeLabelBallpoint => 'Stylo à bille';

  @override
  String get chromeLabelBrush => 'Pinceau';

  @override
  String get chromeLabelCalligraphy => 'Calligraphie';

  @override
  String get chromeLabelEraser => 'Gomme';

  @override
  String get chromeLabelLasso => 'Lasso';

  @override
  String get chromeLabelText => 'Texte';

  @override
  String get chromeLabelShape => 'Forme';

  @override
  String get chromeLabelImage => 'Image';

  @override
  String get chromeLabelPan => 'Main';

  @override
  String get chromePresetsSection => 'Préréglages';

  @override
  String get chromePresetHint => 'Appui long pour enregistrer/effacer';

  @override
  String get chromeColorSection => 'Couleur';

  @override
  String get chromeColorEditHint =>
      'Appui long sur une couleur pour la modifier';

  @override
  String get chromeThicknessSection => 'Épaisseur';

  @override
  String chromeThicknessPx(String value) {
    return '$value px';
  }

  @override
  String get chromePreview => 'Aperçu';

  @override
  String get chromeModeSection => 'Mode';

  @override
  String get chromeEraserPerArea => 'Par zone';

  @override
  String get chromeEraserPerStroke => 'Par trait';

  @override
  String get chromeSizeSection => 'Taille';

  @override
  String get chromeSizeSmall => 'S';

  @override
  String get chromeSizeMedium => 'M';

  @override
  String get chromeSizeLarge => 'L';

  @override
  String get chromePresetOverwrite => 'Remplacer par l\'actuel';

  @override
  String get chromePresetClearSlot => 'Vider l\'emplacement';

  @override
  String get chromeNoPages => 'Aucune page';

  @override
  String get chromeHidePageBar => 'Masquer la barre des pages';

  @override
  String get chromeShowPageBar => 'Afficher la barre des pages';

  @override
  String chromePrevPageTooltip(int number) {
    return 'Page précédente $number — touchez pour revenir';
  }

  @override
  String chromePageOfChapterTooltip(int number, int globalNumber) {
    return 'Page $number du chapitre · page $globalNumber du carnet';
  }

  @override
  String chromePageTooltip(int number) {
    return 'Page $number';
  }

  @override
  String get chromeHexLabel => 'Hexadécimal';

  @override
  String get chromeCancel => 'Annuler';

  @override
  String get chromeApply => 'Appliquer';

  @override
  String get pmNone => 'Aucun';

  @override
  String get pmCreateChapterFirst => 'Créez d\'abord au moins un chapitre.';

  @override
  String pmAssignChapterCount(int count) {
    return 'Attribuer un chapitre ($count p.)';
  }

  @override
  String pmDeletePagesConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count pages ?',
      one: 'Supprimer 1 page ?',
    );
    return '$_temp0';
  }

  @override
  String get pmActionCannotBeUndone => 'Cette action est irréversible.';

  @override
  String get pmCancel => 'Annuler';

  @override
  String get pmDelete => 'Supprimer';

  @override
  String pmPagesCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count pages coupées — ouvrez le carnet de destination pour coller.',
      one: '1 page coupée — ouvrez le carnet de destination pour coller.',
    );
    return '$_temp0';
  }

  @override
  String pmPagesCutSkipped(int count, int skipped) {
    return '$count pages coupées ($skipped pas encore chargées, ignorées) — ouvrez le carnet de destination pour coller.';
  }

  @override
  String pmSelectedCount(int count) {
    return '$count sélectionnées';
  }

  @override
  String get pmSelectAllButton => 'Toutes';

  @override
  String get pmClearSelection => 'Annuler la sélection';

  @override
  String pmPagesCount(int count) {
    return 'Pages ($count)';
  }

  @override
  String pmPagesFilteredCount(int visible, int total) {
    return 'Pages ($visible/$total)';
  }

  @override
  String get pmGoToPageTooltip => 'Aller à la page…';

  @override
  String get pmExitSelection => 'Quitter la sélection';

  @override
  String get pmSelectPages => 'Sélectionner des pages';

  @override
  String get pmPastePages => 'Coller les pages';

  @override
  String pmPagesPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages collées.',
      one: '1 page collée.',
    );
    return '$_temp0';
  }

  @override
  String get pmAddPage => 'Ajouter une page';

  @override
  String get pmClose => 'Fermer';

  @override
  String get pmNewChapter => 'Nouveau chapitre';

  @override
  String get pmChapterNameHint => 'Nom du chapitre';

  @override
  String pmPageDeleted(int number) {
    return 'Page $number supprimée';
  }

  @override
  String get pmUndo => 'Annuler';

  @override
  String get pmAssignChapter => 'Attribuer un chapitre';

  @override
  String get pmRename => 'Renommer';

  @override
  String get pmRenameChapter => 'Renommer le chapitre';

  @override
  String get pmDeleteChapter => 'Supprimer le chapitre';

  @override
  String pmDeleteChapterConfirm(String title) {
    return 'Supprimer « $title » ? Les pages qu\'il contient resteront, mais sans chapitre.';
  }

  @override
  String get pmGoToPage => 'Aller à la page';

  @override
  String pmPageRangeHint(int max) {
    return '1–$max';
  }

  @override
  String get pmGo => 'Aller';

  @override
  String get pmOk => 'OK';

  @override
  String pmCountPagesShort(int count) {
    return '$count p.';
  }

  @override
  String get pmChapter => 'Chapitre';

  @override
  String get pmCut => 'Couper';

  @override
  String get pmInsertBefore => 'Insérer avant';

  @override
  String get pmInsertAfter => 'Insérer après';

  @override
  String get pmDuplicate => 'Dupliquer';

  @override
  String get pmMoveTo => 'Déplacer à la page…';

  @override
  String get pmMove => 'Déplacer';

  @override
  String get pmMoveToPage => 'Déplacer à la page';

  @override
  String get pmChapterEllipsis => 'Chapitre…';

  @override
  String pmPageChapterLabel(int number, String chapter) {
    return '$number • $chapter';
  }

  @override
  String get pmCorruptAssetTooltip =>
      'Média corrompu sur le serveur (tronqué) — réimportez le PDF d\'origine pour le récupérer';

  @override
  String get pmLoadingImageTooltip =>
      'Chargement de l\'image depuis le serveur…';

  @override
  String get tedInsertTextTitle => 'Insérer du texte';

  @override
  String get tedEditTextTitle => 'Modifier le texte';

  @override
  String get tedBoldTooltip => 'Gras (Ctrl+B)';

  @override
  String get tedItalicTooltip => 'Italique (Ctrl+I)';

  @override
  String get tedUnderlineTooltip => 'Souligné (Ctrl+U)';

  @override
  String get tedStrikethroughTooltip => 'Barré';

  @override
  String get tedAlignLeft => 'Gauche';

  @override
  String get tedAlignCenter => 'Centré';

  @override
  String get tedAlignRight => 'Droite';

  @override
  String get tedWriteHereHint => 'Écrivez ici…';

  @override
  String get tedCancel => 'Annuler';

  @override
  String get tedInsert => 'Insérer';

  @override
  String get cropTitle => 'Rogner l\'image';

  @override
  String get cropCancel => 'Annuler';

  @override
  String get cropConfirm => 'Rogner';

  @override
  String get imgFontSmaller => 'Texte plus petit';

  @override
  String get imgFontLarger => 'Texte plus grand';

  @override
  String get imgCrop => 'Rogner';

  @override
  String get imgCopy => 'Copier';

  @override
  String get imgUnlock => 'Déverrouiller';

  @override
  String get imgLock => 'Verrouiller';

  @override
  String get imgDelete => 'Supprimer';

  @override
  String get imgDeselect => 'Désélectionner';

  @override
  String get imgMoreActions => 'Autres actions';

  @override
  String get imgBringToFront => 'Mettre au premier plan';

  @override
  String get imgSendToBack => 'Mettre à l\'arrière-plan';

  @override
  String get imgComment => 'Commentaire';

  @override
  String get imgFlipHChecked => 'Retourner H ✓';

  @override
  String get imgFlipH => 'Retourner H';

  @override
  String get imgCut => 'Couper';

  @override
  String get syncOkTooltip => 'Synchronisé';

  @override
  String get syncPendingTooltip => 'Synchronisation…';

  @override
  String get syncOfflineTooltip => 'Hors ligne';

  @override
  String get syncConflictTooltip => 'Conflit';

  @override
  String get confDecideLater => 'Décider plus tard';

  @override
  String confTitlePageDeletedElsewhere(int pageNumber) {
    return 'Page $pageNumber supprimée ailleurs';
  }

  @override
  String confTitleConflictPage(int pageNumber) {
    return 'Conflit — Page $pageNumber';
  }

  @override
  String get confDeletionExplainer =>
      'Vous avez modifié cette page, mais un autre appareil l\'a supprimée. Voulez-vous la conserver ou la supprimer ?';

  @override
  String get confKeepPage => 'Conserver la page';

  @override
  String get confLocalYours => 'Local (le vôtre)';

  @override
  String get confRemoteOtherDevice => 'Distant (autre appareil)';

  @override
  String get confKeepAllLocal => 'Tout garder en local';

  @override
  String get confAcceptAllRemote => 'Accepter tout le distant';

  @override
  String confProgressIndicator(int current, int total, num decided) {
    String _temp0 = intl.Intl.pluralLogic(
      decided,
      locale: localeName,
      other: '$decided décidées',
      one: '$decided décidée',
    );
    return '$current / $total  ($_temp0)';
  }

  @override
  String get confApplyChoices => 'Appliquer les choix';

  @override
  String confDecidedProgress(int decided, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'décidées',
      one: 'décidée',
    );
    return '$decided/$total $_temp0';
  }

  @override
  String get confJumpToConflict => 'Aller au conflit';

  @override
  String confJumpDecidedCount(int decided, int total) {
    return '$decided/$total décidées';
  }

  @override
  String confJumpItemPage(int pageNumber) {
    return 'P. $pageNumber';
  }

  @override
  String confJumpItemPageWithChapter(int pageNumber, String chapterName) {
    return 'P. $pageNumber — $chapterName';
  }

  @override
  String get confDismissDialogTitle => 'Annuler ?';

  @override
  String get confDismissDialogBody =>
      'Les choix non appliqués seront perdus. La version locale sera conservée.';

  @override
  String get confContinue => 'Continuer';

  @override
  String get confCancel => 'Annuler';

  @override
  String get confModifiedJustNow => 'À l\'instant';

  @override
  String confModifiedMinutesAgo(int minutes) {
    return 'il y a $minutes min';
  }

  @override
  String confModifiedHoursAgo(num hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'il y a $hours heures',
      one: 'il y a $hours heure',
    );
    return '$_temp0';
  }

  @override
  String get confDeletePage => 'Supprimer la page';

  @override
  String get confAsOnOtherDevice => 'Comme sur l\'autre appareil';

  @override
  String get symNewLibraryTitle => 'Nouvelle bibliothèque';

  @override
  String get symNewLibraryHint => 'Saisissez le nom de la bibliothèque';

  @override
  String get symRenameLibraryTitle => 'Renommer la bibliothèque';

  @override
  String get symNewNameHint => 'Nouveau nom';

  @override
  String get symDeleteLibraryTitle => 'Supprimer la bibliothèque';

  @override
  String symDeleteLibraryConfirm(String name) {
    return 'Supprimer « $name » et tous ses symboles ?';
  }

  @override
  String get symCancel => 'Annuler';

  @override
  String get symDelete => 'Supprimer';

  @override
  String get symRenameSymbolTitle => 'Renommer le symbole';

  @override
  String get symPanelTitle => 'Bibliothèques de symboles';

  @override
  String get symNoLibraries => 'Aucune bibliothèque';

  @override
  String get symNew => 'Nouvelle';

  @override
  String get symSelectLibrary => 'Sélectionnez une bibliothèque';

  @override
  String get symNoSymbolsHint =>
      'Aucun symbole\nSélectionnez des éléments avec le lasso et appuyez sur ✚';

  @override
  String get symLassoSaveHint =>
      'Sélectionnez des éléments avec le lasso → ✚ pour les enregistrer dans la bibliothèque active';

  @override
  String get symRename => 'Renommer';

  @override
  String get symInsert => 'Insérer';

  @override
  String get symOk => 'OK';

  @override
  String get rcbBannerTitle => 'Modifications depuis un autre appareil';

  @override
  String get rcbSeeDetails => 'Voir les détails';

  @override
  String get rcbDismiss => 'Ignorer';

  @override
  String get rcbIncomingChanges => 'Modifications entrantes';

  @override
  String get rcbTapPageHint =>
      'Touchez une page pour l\'appliquer et vous y rendre';

  @override
  String rcbNewImagesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouvelles images',
      one: '1 nouvelle image',
    );
    return '$_temp0';
  }

  @override
  String get rcbKeepMine => 'Garder les miennes';

  @override
  String get rcbApplyAll => 'Tout appliquer';

  @override
  String get rcbBadgeNew => 'NOUVELLE';

  @override
  String get rcbBadgeModified => 'MODIFIÉE';

  @override
  String rcbPageTitle(int pageNumber) {
    return 'Page $pageNumber';
  }

  @override
  String get rcbContentUpdated => 'Contenu mis à jour';

  @override
  String rcbSummaryModifiedPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages modifiées',
      one: '$count page modifiée',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryNewPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nouvelles',
      one: '$count nouvelle',
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
  String get rcbChangesDetected => 'Modifications détectées';

  @override
  String get nbUntitled => 'Sans titre';

  @override
  String get nbDefaultChapterTitle => 'Chapitre 1';

  @override
  String get nbOpeningNotebook => 'Ouverture du carnet…';

  @override
  String get nbNoLocalCopyOffline =>
      'Aucune copie locale de ce carnet, et vous n\'êtes connecté à aucun serveur pour le télécharger.';

  @override
  String nbOpenFailed(String error) {
    return 'Impossible d\'ouvrir : $error';
  }

  @override
  String get nbSortModifiedDesc => 'Modifiés (plus récents d\'abord)';

  @override
  String get nbSortModifiedAsc => 'Modifiés (plus anciens d\'abord)';

  @override
  String get nbSortTitleAsc => 'Titre A→Z';

  @override
  String get nbSortTitleDesc => 'Titre Z→A';

  @override
  String get nbSortCreatedDesc => 'Créés (plus récents d\'abord)';

  @override
  String get nbSortCreatedAsc => 'Créés (plus anciens d\'abord)';

  @override
  String get nbSortColorGroup => 'Couleur de couverture';

  @override
  String cvFormatTooNew(int fileVersion, int supportedVersion) {
    return 'Ce carnet utilise un format plus récent (v$fileVersion, pris en charge : v$supportedVersion). Mettez AbelNotes à jour pour l\'ouvrir.';
  }

  @override
  String get setLanguageSystem => 'Système';

  @override
  String get setLanguageEnglish => 'English';

  @override
  String get setLanguageSpanish => 'Español';

  @override
  String get onbAppName => 'AbelNotes';

  @override
  String get setAboutAppName => 'AbelNotes';

  @override
  String get chromeLabelHighlighter => 'Surligneur';

  @override
  String get chromeLabelLaser => 'Laser';

  @override
  String get importSourceTitle => 'Importer dans la bibliothèque';

  @override
  String get importSourceNcnote => 'Carnet .abelnote';

  @override
  String get importSourceObsidian => 'Coffre Obsidian';

  @override
  String get importSourceObsidianHint => 'Dossier de fichiers Markdown';

  @override
  String get importSourceNotion => 'Export Notion';

  @override
  String get importSourceNotionHint => 'Fichier .zip (Markdown et CSV)';

  @override
  String get importPhaseScanning => 'Analyse de la source…';

  @override
  String importPhaseParsing(int current, int total) {
    return 'Lecture du fichier $current sur $total';
  }

  @override
  String importPhasePaginating(int current, int total) {
    return 'Mise en page du chapitre $current sur $total';
  }

  @override
  String get importPhasePackaging => 'Création du carnet…';

  @override
  String get importCancel => 'Annuler';

  @override
  String get importCancelled => 'Import annulé';

  @override
  String importReportTitle(int count) {
    return '$count avertissements pendant l\'import';
  }

  @override
  String get importReportCopy => 'Copier';

  @override
  String get importReportClose => 'Fermer';

  @override
  String get importSourceOneNote => 'Fichier OneNote';

  @override
  String get importSourceOneNoteHint => 'Section .one ou carnet .onetoc2';

  @override
  String get setOpenSourceLicenses => 'Licences open source';

  @override
  String get setOpenSourceLicensesSub =>
      'Composants tiers inclus dans l\'application';

  @override
  String get csBackToContent => 'Retour au contenu';

  @override
  String get setLanguageGerman => 'Deutsch';

  @override
  String get setLanguageFrench => 'Français';
}
