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
  String get csNoPages => 'Aucune page';

  @override
  String get csRetrySync => 'Relancer la synchronisation';

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages remplacées par des pages vierges',
      one: '$count page remplacée par une page vierge',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'Supprimer la page';

  @override
  String csMissingDownloadingTitle(int page) {
    return 'Téléchargement de la page $page…';
  }

  @override
  String get csMissingDownloadingBody =>
      'Cette page n\'est pas encore sur cet appareil. Le serveur l\'a : elle se télécharge et apparaîtra ici dès qu\'elle sera prête.';

  @override
  String csMissingOfflineTitle(int page) {
    return 'Page $page pas encore téléchargée';
  }

  @override
  String get csMissingOfflineBody =>
      'Cette page n\'est pas encore sur cet appareil et le serveur ne répond pas pour le moment. Une nouvelle tentative a lieu automatiquement ; la page apparaîtra dès le retour de la connexion. Rien n\'est modifié entre-temps.';

  @override
  String csMissingGoneTitle(int page) {
    return 'Page $page manquante';
  }

  @override
  String get csMissingGoneBody =>
      'Le fichier de cette page n\'est ni sur cet appareil ni sur le serveur. Si un autre appareil affiche encore la page, ouvrez-la là-bas : elle sera de nouveau envoyée et reviendra aussi ici.';

  @override
  String get csMissingNoServerBody =>
      'Le fichier de cette page n\'est pas sur cet appareil et le carnet n\'est synchronisé avec aucun serveur.';

  @override
  String get csMissingPreviousPage => 'Page précédente';

  @override
  String get csMissingLastResort =>
      'Seulement si vous êtes sûr que la page n\'existe plus nulle part :';

  @override
  String get csMissingReplaceAction => 'Remplacer par une page vierge';

  @override
  String csMissingReplaceAll(int count) {
    return 'Tout remplacer ($count)';
  }

  @override
  String csMissingReplaceConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Remplacer $count pages par des pages vierges ?',
      one: 'Remplacer la page par une page vierge ?',
    );
    return '$_temp0';
  }

  @override
  String csMissingReplaceConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Les pages vierges sont synchronisées sur tous vos appareils. Si les originaux existent encore sur un autre appareil, ils seront écrasés.',
      one:
          'La page vierge est synchronisée sur tous vos appareils. Si l\'original existe encore sur un autre appareil, il sera écrasé.',
    );
    return '$_temp0';
  }

  @override
  String get csMissingDeleteConfirmTitle => 'Supprimer la page ?';

  @override
  String get csMissingDeleteConfirmBody =>
      'La page est retirée du carnet sur tous les appareils synchronisés.';

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
  String get libCoverColor => 'Couleur';

  @override
  String get libCoverPattern => 'Motif';

  @override
  String get libCoverApply => 'Appliquer';

  @override
  String get libCoverStyleAuto => 'Automatique (selon le type de papier)';

  @override
  String get libCoverStylePlain => 'Uni';

  @override
  String get libCoverStylePinstripe => 'Fines rayures';

  @override
  String get libCoverStyleDiagonal => 'Rayures diagonales';

  @override
  String get libCoverStylePolka => 'Pois';

  @override
  String get libCoverStyleGingham => 'Vichy';

  @override
  String get libCoverStyleWaves => 'Vagues';

  @override
  String get libCoverStyleLabel => 'Étiquette';

  @override
  String get libCoverStyleTwoTone => 'Bicolore';

  @override
  String get libCoverStyleSheen => 'Reflet';

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
  String get libShowAll => 'Tout afficher';

  @override
  String get libShowLess => 'Afficher moins';

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
  String get setLanguageItalian => 'Italiano';

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
  String get setPressureThickness => 'Pression → épaisseur';

  @override
  String get setPressureThicknessSub =>
      'Modulation du trait selon la pression du stylet';

  @override
  String get setStrokeContinuation => 'Continuité du trait';

  @override
  String get setStrokeContinuationSub =>
      'Compense de brèves interruptions du capteur (par ex. le point du i)';

  @override
  String get setFillShapes => 'Remplir les formes';

  @override
  String get setFillShapesSub =>
      'Les cercles, rectangles et triangles reconnus prennent une teinte légère de la couleur de l\'encre';

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
  String libPendingNewDrive(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets ne sont pas encore sur Google Drive : $names',
      one: '« $names » n\'est pas encore sur Google Drive',
    );
    return '$_temp0';
  }

  @override
  String libPendingNewServer(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets ne sont pas encore sur votre serveur : $names',
      one: '« $names » n\'est pas encore sur votre serveur',
    );
    return '$_temp0';
  }

  @override
  String libPendingChanges(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Modifications de $count carnets pas encore envoyées : $names',
      one: 'Modifications de « $names » pas encore envoyées',
    );
    return '$_temp0';
  }

  @override
  String get libPendingUploadsHint =>
      'En attendant, ils restent sur cet appareil. Laissez l\'application ouverte un instant.';

  @override
  String get libDeleteRemotePending =>
      'Supprimé ici. Échec du retrait du cloud : nouvel essai automatique.';

  @override
  String libPendingRemoteDeletes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets supprimés ici, encore à retirer du cloud',
      one: '$count carnet supprimé ici, encore à retirer du cloud',
    );
    return '$_temp0';
  }

  @override
  String get libPendingRemoteDeletesHint =>
      'En attendant, vos autres appareils peuvent encore le voir. Nouvel essai dès que la connexion revient.';

  @override
  String get libServerUnreachable => 'Serveur injoignable';

  @override
  String get libServerUnreachableHint =>
      'Les modifications restent sur cet appareil et sont envoyées dès le retour de la connexion.';

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
  String get libLocalOnlyTitle => 'Sur cet appareil uniquement';

  @override
  String get libLocalOnlyBody =>
      'Vos carnets restent sur cet appareil. Connectez votre serveur ou Google Drive pour les retrouver partout — vous pouvez le faire à tout moment.';

  @override
  String get libLocalOnlyBodyWeb =>
      'Vos carnets restent dans ce navigateur. Exportez ceux que vous voulez garder, ou connectez Google Drive pour les avoir partout. Safari peut effacer les données des sites inutilisés depuis quelques jours, sauf si vous ajoutez l\'app à l\'écran d\'accueil.';

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
  String get chromeHoldForOptions =>
      'Appui long ou clic droit pour les options';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sélectionnées',
      one: '1 sélectionnée',
    );
    return '$_temp0';
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

  @override
  String get setLanguagePortuguese => 'Português';

  @override
  String get setLanguageChinese => '中文';

  @override
  String get qlTrashDeletedNow => 'Supprimé à l\'instant';

  @override
  String qlTrashDeletedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimé il y a $count minutes',
      one: 'Supprimé il y a $count minute',
    );
    return '$_temp0';
  }

  @override
  String qlTrashDeletedHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimé il y a $count heures',
      one: 'Supprimé il y a $count heure',
    );
    return '$_temp0';
  }

  @override
  String qlTrashDeletedDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimé il y a $count jours',
      one: 'Supprimé il y a $count jour',
    );
    return '$_temp0';
  }

  @override
  String get qlAdvancedLocalOnly =>
      'Ces outils de récupération ne s\'appliquent que lorsqu\'un serveur ou Google Drive est connecté.';

  @override
  String get qlNameRequired => 'Saisissez un nom';

  @override
  String get qlDuplicate => 'Dupliquer';

  @override
  String qlDuplicateTitle(String title) {
    return '$title (copie)';
  }

  @override
  String get qlDuplicated => 'Carnet dupliqué';

  @override
  String get qlDuplicateNoLocalCopy =>
      'Ce carnet n\'est pas sur cet appareil. Ouvrez-le une fois pour le télécharger, puis dupliquez-le.';

  @override
  String get qlDeleteOrphanBody =>
      'Il ne reste aucune copie de ce carnet sur cet appareil, il ne pourra donc pas être restauré. Il sera retiré de la bibliothèque.';

  @override
  String get qlDeletedNoTrash =>
      'Retiré. Il n\'y avait aucune copie sur cet appareil, rien n\'a donc été placé dans la corbeille.';

  @override
  String get qlOpenCorrupt =>
      'Les données de ce carnet sont endommagées et ne peuvent pas être ouvertes.';

  @override
  String qlSearchNoResults(String query) {
    return 'Aucun carnet ne correspond à « $query ».';
  }

  @override
  String get qcMouseSelectHint =>
      'La souris sélectionne tant qu\'un stylo est actif. Activez le dessin à la souris pour dessiner avec.';

  @override
  String get qcMouseDrawEnable => 'Dessiner à la souris';

  @override
  String qiIssueRemoteImage(String arg) {
    return 'Image distante non téléchargée : $arg';
  }

  @override
  String qiIssueImageNotFound(String arg) {
    return 'Image introuvable : $arg';
  }

  @override
  String qiIssueImageUnreadable(String arg) {
    return 'Image illisible : $arg';
  }

  @override
  String qiIssueAttachmentUnsupported(String arg) {
    return 'Pièce jointe non prise en charge (images uniquement) : $arg';
  }

  @override
  String qiIssueAttachmentTooLarge(String arg) {
    return 'Pièce jointe trop volumineuse, ignorée : $arg';
  }

  @override
  String qiIssueEmbedUnsupported(String arg) {
    return 'Fichier intégré non importé (images et notes uniquement) : $arg';
  }

  @override
  String qiIssueNoteEmbedNotFound(String arg) {
    return 'Note intégrée introuvable : $arg';
  }

  @override
  String qiIssueNoteEmbedSkipped(String arg) {
    return 'Note intégrée non développée (circulaire ou trop imbriquée) : $arg';
  }

  @override
  String get qiIssueFileUnreadable => 'Fichier illisible';

  @override
  String qiIssueFileTooLarge(int count) {
    return 'Fichier trop volumineux ($count Mo), ignoré';
  }

  @override
  String get qiIssueEncodingFallback =>
      'Le texte n\'était pas de l\'UTF-8 valide, lu en Latin-1';

  @override
  String get qiIssueCsvUnreadable => 'Tableau illisible';

  @override
  String qiIssueZipEntryTooLarge(int count) {
    return 'Élément de l\'archive trop volumineux ($count Mo), ignoré';
  }

  @override
  String qiIssueZipTotalTooLarge(int count) {
    return 'Le contenu de l\'archive dépasse $count Mo, les fichiers restants ont été ignorés';
  }

  @override
  String qiIssueHiddenFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes dans des dossiers cachés ont été ignorées',
      one: '1 note dans un dossier caché a été ignorée',
    );
    return '$_temp0';
  }

  @override
  String qiIssueTooManyChapters(int count) {
    return '$count chapitres : envisagez d\'importer les sous-dossiers séparément';
  }

  @override
  String qiIssuePagesTruncated(int count) {
    return 'Note tronquée après $count pages';
  }

  @override
  String qiIssueOneNoteSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments non pris en charge ignorés',
      one: '1 élément non pris en charge ignoré',
    );
    return '$_temp0';
  }

  @override
  String get qiErrNoMarkdown =>
      'Aucun fichier Markdown (.md) dans le dossier choisi';

  @override
  String get qiErrNoNotionContent =>
      'Le zip ne contient aucun fichier .md ou .csv : utilisez un export Notion « Markdown et CSV »';

  @override
  String get qiErrNothingImportable => 'Rien à importer';

  @override
  String get qiErrZipUnreadable =>
      'Le fichier zip est endommagé ou n\'est pas une archive valide';

  @override
  String get qiErrNoOneNotePages => 'Aucune page importable dans ce fichier';

  @override
  String get qiErrUnexpected => 'erreur inattendue';

  @override
  String qiOneNoteSection(int n) {
    return 'Section $n';
  }

  @override
  String get qiOneNotePage => 'Page';

  @override
  String get qiPdfNotPdf => 'Ce fichier n\'est pas un PDF valide';

  @override
  String get qiPdfCorrupt =>
      'Ce PDF est endommagé ou incomplet et ne peut pas être lu';

  @override
  String get qiPdfEmpty => 'Ce PDF ne contient aucune page';

  @override
  String get qiPdfUnsupported =>
      'Ce PDF utilise une protection ou une fonction non prise en charge';

  @override
  String get qiPdfPasswordCancelled =>
      'Import annulé : aucun mot de passe fourni';

  @override
  String get qiPdfImportFailed => 'Impossible d\'importer le PDF';

  @override
  String get qiPdfPasswordTitle => 'PDF protégé par mot de passe';

  @override
  String get qiPdfPasswordBody =>
      'Saisissez le mot de passe pour importer ce PDF.';

  @override
  String get qiPdfPasswordHint => 'Mot de passe';

  @override
  String get qiPdfPasswordWrong => 'Mot de passe incorrect, réessayez';

  @override
  String get qiPdfPasswordOpen => 'Ouvrir';

  @override
  String qiPdfPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Le PDF compte $count pages.',
      one: 'Le PDF compte 1 page.',
    );
    return '$_temp0';
  }

  @override
  String qiPdfStartOutOfRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Le PDF compte $count pages. Le début est hors intervalle.',
      one: 'Le PDF compte 1 page. Le début est hors intervalle.',
    );
    return '$_temp0';
  }

  @override
  String get qsReauthBanner =>
      'Le serveur n\'accepte plus votre connexion. Vos modifications sont en sécurité sur cet appareil et seront synchronisées après une nouvelle connexion.';

  @override
  String get qsDriveReauthBanner =>
      'Google Drive vous demande de vous reconnecter. Vos modifications sont en sécurité sur cet appareil et se synchronisent dès que vous le faites.';

  @override
  String get qsBrowserStorageFull =>
      'Ce navigateur n\'a plus de place pour enregistrer : vos dernières modifications pourraient être perdues si la page se recharge. Exportez vos carnets ou libérez de l\'espace.';

  @override
  String get qsReauthAction => 'Se reconnecter';

  @override
  String qsDeletedElsewhere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count carnets ont été supprimés sur un autre appareil. Vos copies restent uniquement ici.',
      one:
          '$count carnet a été supprimé sur un autre appareil. Votre copie reste uniquement ici.',
    );
    return '$_temp0';
  }

  @override
  String get qsDeletedElsewhereHint =>
      'Appuyez longuement sur un carnet et choisissez \"Synchroniser à nouveau ce carnet\" pour le renvoyer.';

  @override
  String get qsRefreshTooltip => 'Actualiser depuis le serveur';

  @override
  String get qsResumeSyncPending =>
      'Serveur injoignable. Ce carnet sera envoyé dès qu\'il sera de nouveau disponible.';

  @override
  String get qsResumeSyncUploaded =>
      'Envoyé. Ce carnet est de nouveau synchronisé.';

  @override
  String get qsNoServerConnected => 'Aucun serveur connecté.';

  @override
  String get qsLoginWrongCredentials =>
      'Le serveur a refusé l\'identifiant ou le mot de passe.';

  @override
  String get qsLoginNotAServer =>
      'Aucun serveur Nextcloud ou WebDAV à cette adresse. Vérifiez l\'URL.';

  @override
  String get qsLoginUnreachable =>
      'Impossible de joindre le serveur. Vérifiez l\'adresse et votre connexion.';

  @override
  String get qsLoginThrottled =>
      'Trop de tentatives. Le serveur demande d\'attendre un moment avant de réessayer.';

  @override
  String get qsLoginServerError =>
      'Le serveur a renvoyé une erreur. Réessayez plus tard.';

  @override
  String get quPenNoMonitor => 'Aucun écran actif détecté.';

  @override
  String get quPenNoDevice => 'Aucun stylet détecté.';

  @override
  String get quPenBadGeometry => 'Géométrie du bureau invalide.';

  @override
  String quPenToolMissing(String tool) {
    return '$tool introuvable.';
  }

  @override
  String quPenToolFailed(String tool) {
    return '$tool a échoué.';
  }

  @override
  String get quDiffStrokes => 'Traits';

  @override
  String get quDiffImages => 'Images';

  @override
  String get quDiffShapes => 'Formes';

  @override
  String get quDiffTexts => 'Textes';

  @override
  String get quDefaultChapter => 'Chapitre 1';

  @override
  String qtNeedsOpenToUpload(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets ont aussi changé sur un autre appareil',
      one: '$count carnet a aussi changé sur un autre appareil',
    );
    return '$_temp0';
  }

  @override
  String get qtNeedsOpenToUploadHint =>
      'Ouvrez-le pour fusionner et envoyer vos modifications.';

  @override
  String get qtResumeSyncNeedsOpen =>
      'Ce carnet se synchronise à nouveau. Ouvrez-le pour fusionner les modifications faites sur un autre appareil.';

  @override
  String libImportSuccessMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carnets importés',
      one: '$count carnet importé',
    );
    return '$_temp0';
  }

  @override
  String get pgtTitlePages => 'Pages';

  @override
  String pgtEyebrow(String notebook, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$notebook · $_temp0';
  }

  @override
  String get pgtSelect => 'Sélectionner';

  @override
  String get pgtSelectPages => 'Sélectionner des pages';

  @override
  String get pgtAll => 'Toutes';

  @override
  String get pgtNone => 'Aucune';

  @override
  String get pgtDone => 'Terminé';

  @override
  String get pgtNoChapter => 'Sans chapitre';

  @override
  String get pgtCopy => 'Copier';

  @override
  String get pgtMove => 'Déplacer';

  @override
  String get pgtTagMoving => 'déplacement';

  @override
  String get pgtHintPlaceMove =>
      'Touchez une page pour les placer après elle, ou son bord gauche pour les placer avant. Rien ne change tant que vous ne confirmez pas.';

  @override
  String get pgtHintPlaceCopy =>
      'Touchez une page pour coller après elle, ou son bord gauche pour coller avant.';

  @override
  String get pgtMoveHere => 'Déplacer ici';

  @override
  String get pgtPasteHere => 'Coller ici';

  @override
  String get pgtMoveShort => 'Déplacer';

  @override
  String get pgtPasteShort => 'Coller';

  @override
  String pgtPasteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return 'Coller $_temp0';
  }

  @override
  String pgtPasteCountShort(int count) {
    return 'Coller $count';
  }

  @override
  String get pgtThisNotebook => 'Ce carnet';

  @override
  String get pgtAnotherNotebook => 'Autre carnet…';

  @override
  String pgtMoveToNb(String notebook) {
    return 'Déplacer vers $notebook';
  }

  @override
  String pgtPasteIntoNb(String notebook) {
    return 'Coller dans $notebook';
  }

  @override
  String get pgtPosStart => 'Au début';

  @override
  String pgtPosAfter(int page) {
    return 'Après la page $page';
  }

  @override
  String get pgtPosEnd => 'À la fin';

  @override
  String pgtPosChapterEnd(String chapter) {
    return 'Fin de $chapter';
  }

  @override
  String get pgtChapterMenuHead => 'Chapitre pour les pages';

  @override
  String pgtTrayMoving(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages · déplacement',
      one: '1 page · déplacement',
    );
    return '$_temp0';
  }

  @override
  String pgtTrayCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages · copiées',
      one: '1 page · copiée',
    );
    return '$_temp0';
  }

  @override
  String get pgtSavedShort => 'Enregistré';

  @override
  String get pgtSavedLong =>
      'Enregistré sur cet appareil. Reste après la fermeture de l\'app.';

  @override
  String pgtFrom(String notebook) {
    return 'de $notebook';
  }

  @override
  String pgtFromChapter(String notebook, String chapter) {
    return 'de $notebook › $chapter';
  }

  @override
  String pgtFromSeveral(String notebook) {
    return 'de $notebook › plusieurs chapitres';
  }

  @override
  String pgtSourceDeleted(String notebook) {
    return '$notebook a été supprimé, ces pages sont désormais une copie';
  }

  @override
  String get pgtTrayOptions => 'Options du plateau de pages';

  @override
  String get pgtCancelMove => 'Annuler le déplacement';

  @override
  String get pgtCancelMoveHint => 'Les pages n\'ont jamais été retirées';

  @override
  String get pgtClearTray => 'Vider le plateau';

  @override
  String get pgtChooseWhere => 'Choisir où, dans Pages';

  @override
  String get pgtChooseWhereHint =>
      'Ouvre les pages de ce carnet avec le plateau prêt';

  @override
  String pgtOpenSource(String notebook) {
    return 'Ouvrir $notebook';
  }

  @override
  String get pgtOpenSourceHint => 'D\'où viennent ces pages';

  @override
  String get pgtUndo => 'Annuler';

  @override
  String get pgtShow => 'Afficher';

  @override
  String pgtChooserTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return 'Déplacer $_temp0 vers…';
  }

  @override
  String get pgtRecent => 'Récents';

  @override
  String get pgtChooserEmpty =>
      'Il n\'y a pas d\'autre carnet sur cet appareil.';

  @override
  String get pgtBrowseLibrary => 'Parcourir la bibliothèque';

  @override
  String pgtNbPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String pgtNbChapters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapitres',
      one: '1 chapitre',
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
      other: '$count pages',
      one: '1 page',
    );
    return 'Choisissez un carnet où déplacer $_temp0. Touchez une couverture ou utilisez son menu …';
  }

  @override
  String pgtLibHintPaste(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return 'Choisissez un carnet où coller $_temp0. Touchez une couverture ou utilisez son menu …';
  }

  @override
  String pgtBadgeMoving(int count) {
    return '$count en déplacement';
  }

  @override
  String pgtCardMoveHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return 'Déplacer $_temp0 ici';
  }

  @override
  String pgtCardPasteHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return 'Coller $_temp0 ici';
  }

  @override
  String pgtCardEndOfChapter(String chapter) {
    return 'À la fin de $chapter';
  }

  @override
  String get pgtCardAtEnd => 'À la fin';

  @override
  String get pgtWhereStart => 'au début';

  @override
  String pgtWhereAfter(int page) {
    return 'après la page $page';
  }

  @override
  String get pgtWhereEnd => 'à la fin';

  @override
  String pgtWhereChapterEnd(String chapter) {
    return 'à la fin de $chapter';
  }

  @override
  String pgtToastCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages copiées. Ouvrez un carnet pour coller.',
      one: '1 page copiée. Ouvrez un carnet pour coller.',
    );
    return '$_temp0';
  }

  @override
  String pgtToastCopiedSkipped(int count, int skipped) {
    return '$count pages copiées ; $skipped pas encore chargées ont été ignorées.';
  }

  @override
  String pgtToastMoveReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count pages prêtes à déplacer. Rien ne change tant que vous ne confirmez pas.',
      one:
          '1 page prête à déplacer. Rien ne change tant que vous ne confirmez pas.',
    );
    return '$_temp0';
  }

  @override
  String pgtToastMoveReadySkipped(int count, int skipped) {
    return '$count pages prêtes à déplacer ; $skipped pas encore chargées ont été ignorées. Rien ne change tant que vous ne confirmez pas.';
  }

  @override
  String pgtToastMoveCancelled(int count, String notebook) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Déplacement annulé. $count pages restent dans $notebook.',
      one: 'Déplacement annulé. 1 page reste dans $notebook.',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastTrayCleared => 'Plateau vidé';

  @override
  String pgtToastPasted(int count, String notebook, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages collées dans $notebook, $where',
      one: '1 page collée dans $notebook, $where',
    );
    return '$_temp0';
  }

  @override
  String pgtToastMoved(int count, String notebook, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages déplacées vers $notebook, $where',
      one: '1 page déplacée vers $notebook, $where',
    );
    return '$_temp0';
  }

  @override
  String pgtToastDuplicated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages dupliquées',
      one: '1 page dupliquée',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastUndone => 'Annulé';

  @override
  String pgtToastTooMany(int max) {
    return 'Le plateau contient au plus $max pages. Sélectionnez-en moins.';
  }

  @override
  String get pgtToastNothing =>
      'Ces pages ne sont pas encore prêtes (chargement en cours). Réessayez dans un instant.';

  @override
  String get pgtToastTrayNotSaved =>
      'Impossible d\'enregistrer le plateau sur cet appareil. Il sera perdu à la fermeture de l\'app.';

  @override
  String get pgtToastPagesGone => 'Ces pages ne sont plus dans ce carnet.';

  @override
  String get pgtToastTrayDamaged =>
      'Le plateau enregistré est incomplet, rien n\'a été collé.';

  @override
  String get pgtToastDestFailed =>
      'Impossible d\'enregistrer les pages collées. Rien n\'a été modifié.';

  @override
  String get pgtToastDestUnavailable =>
      'Ce carnet ne peut pas être modifié pour le moment. Rien n\'a été modifié.';

  @override
  String pgtToastSourceFailed(String notebook) {
    return 'Les pages ont été ajoutées, mais n\'ont pas pu être retirées de $notebook. Elles sont dans les deux carnets ; le plateau est maintenant une copie.';
  }

  @override
  String pgtToastMoveResumed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Le déplacement interrompu de $count pages a été terminé.',
      one: 'Le déplacement interrompu de 1 page a été terminé.',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastUndoFailed =>
      'Impossible d\'annuler. Vérifiez les deux carnets.';
}
