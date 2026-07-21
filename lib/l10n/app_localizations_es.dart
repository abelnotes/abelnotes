// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get csPdfTextCopied => 'Texto copiado';

  @override
  String csCopyFailed(String error) {
    return 'No se pudo copiar: $error';
  }

  @override
  String get csCopy => 'Copiar';

  @override
  String get csSyncInProgress => 'Sincronización en curso…';

  @override
  String get csSaved => '¡Guardado!';

  @override
  String csErrorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String get csSelectionCopied => 'Selección copiada';

  @override
  String get csSelectionCut => 'Selección cortada';

  @override
  String get csShortcutsTitle => 'Atajos de teclado';

  @override
  String get csShortcutGroupGeneral => 'General';

  @override
  String get csSaveNow => 'Guardar ahora';

  @override
  String get csShortcutUndo => 'Deshacer';

  @override
  String get csShortcutRedo => 'Rehacer';

  @override
  String get csSelectAll => 'Seleccionar todo';

  @override
  String get csShortcutResetZoom => 'Restablecer zoom';

  @override
  String get csShortcutDeselect => 'Deseleccionar / cancelar';

  @override
  String get csShortcutThisGuide => 'Esta guía';

  @override
  String get csShortcutGroupClipboard => 'Portapapeles';

  @override
  String get csShortcutCopySelection => 'Copiar selección';

  @override
  String get csShortcutCutSelection => 'Cortar selección';

  @override
  String get csPaste => 'Pegar';

  @override
  String get csShortcutDuplicateSelection => 'Duplicar selección';

  @override
  String get csShortcutKeyDeleteBackspace => 'Supr / Retroceso';

  @override
  String get csShortcutDeleteElementOrSelection =>
      'Eliminar elemento o selección';

  @override
  String get csShortcutGroupTools => 'Herramientas';

  @override
  String get csToolPen => 'Pluma';

  @override
  String get csToolBrush => 'Pincel';

  @override
  String get csToolEraser => 'Borrador';

  @override
  String get csToolLasso => 'Lazo';

  @override
  String get csToolHand => 'Mano / mover';

  @override
  String get csToolText => 'Texto';

  @override
  String get csToolShape => 'Forma';

  @override
  String get csClose => 'Cerrar';

  @override
  String get csUnsavedChangesTitle => 'Cambios sin guardar';

  @override
  String get csUnsavedChangesBody => '¿Quieres guardar antes de salir?';

  @override
  String get csDiscard => 'Descartar';

  @override
  String get csCancel => 'Cancelar';

  @override
  String get csSave => 'Guardar';

  @override
  String get csOpeningLink => 'Abriendo enlace…';

  @override
  String get csCannotOpenLink => 'No se pudo abrir el enlace';

  @override
  String get csCameraUnavailable => 'Cámara no disponible en este dispositivo';

  @override
  String get csPhotoCaptureFailed => 'No se pudo tomar la foto';

  @override
  String get csPdfRasterizing => 'Rasterizando PDF…';

  @override
  String csPdfImportProgress(int done, int total) {
    return 'Importando PDF: $done/$total';
  }

  @override
  String get csPdfReadFailed =>
      'No se pudo leer el PDF: no se encontraron páginas';

  @override
  String csPdfImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return 'PDF importado: $_temp0';
  }

  @override
  String csPdfImportError(String error) {
    return 'Error al importar el PDF: $error';
  }

  @override
  String get csNoNotebookOpen => 'Ningún cuaderno abierto';

  @override
  String get csMissingPageDataTitle => 'Faltan datos de la página';

  @override
  String get csNoPages => 'Sin páginas';

  @override
  String csMissingPagesBodyMany(int count) {
    return 'Esta página y otras $count no se recuperaron del servidor. Los archivos podrían haberse perdido durante una sincronización parcial.';
  }

  @override
  String get csMissingPageBodyOne =>
      'El archivo de esta página no se recuperó del servidor. Podría haberse perdido durante una sincronización parcial.';

  @override
  String get csRetrySync => 'Reintentar sincronización';

  @override
  String get csRestoreAsBlankPage => 'Restaurar como página en blanco';

  @override
  String csRestoreAllMissing(int count) {
    return 'Restaurar todas ($count)';
  }

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas restauradas en blanco',
      one: '$count página restaurada en blanco',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'Eliminar página';

  @override
  String csSyncProgressCount(int done, int total) {
    return 'Sincronizando $done/$total';
  }

  @override
  String get csSyncing => 'Sincronizando…';

  @override
  String csShapeRecognizedLabel(String shape) {
    return 'Forma: $shape';
  }

  @override
  String get csConfirmShapeSemantics => 'Confirmar forma reconocida';

  @override
  String get csConfirm => 'Confirmar';

  @override
  String get csCancelShapeSemantics => 'Cancelar forma reconocida';

  @override
  String csTapToPlaceSymbol(String name) {
    return 'Toca para colocar: $name';
  }

  @override
  String get csCancelSymbolInsertSemantics => 'Cancelar inserción de símbolo';

  @override
  String get csTapToPlaceCopy => 'Toca para colocar la copia';

  @override
  String get csCancelPasteSemantics => 'Cancelar pegado';

  @override
  String get csNewPage => 'Página nueva';

  @override
  String get csImageCopied => 'Imagen copiada';

  @override
  String get csImageCut => 'Imagen cortada';

  @override
  String get csImageCommentTitle => 'Comentario de la imagen';

  @override
  String get csAddCommentHint => 'Añade un comentario...';

  @override
  String get csRemove => 'Quitar';

  @override
  String get csCut => 'Cortar';

  @override
  String get csDuplicate => 'Duplicar';

  @override
  String get csSelectionDuplicated => 'Selección duplicada';

  @override
  String get csChangeColor => 'Cambiar color';

  @override
  String get csThickness => 'Grosor';

  @override
  String get csDelete => 'Eliminar';

  @override
  String get csMore => 'Más';

  @override
  String get csPresentationMode => 'Modo presentación';

  @override
  String get csPresentationModeSub =>
      'Pantalla completa, sin herramientas — ideal para mostrar páginas';

  @override
  String get csRecognizeHandwriting => 'Reconocer escritura';

  @override
  String get csRecognizeHandwritingSub =>
      'Convierte la tinta en texto buscable (en el dispositivo)';

  @override
  String get csRecognizeInProgress => 'Reconociendo…';

  @override
  String get csRecognizeNothing => 'No se reconoció texto.';

  @override
  String csRecognizeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count líneas reconocidas',
      one: '$count línea reconocida',
    );
    return '$_temp0.';
  }

  @override
  String csRecognizeFailed(String error) {
    return 'Reconocimiento fallido: $error';
  }

  @override
  String get csShareLink => 'Compartir con enlace';

  @override
  String get csShareLinkSub =>
      'Sube un PDF a tu Nextcloud y genera un enlace público';

  @override
  String get csShareLinkInProgress => 'Creando enlace…';

  @override
  String get csShareLinkTitle => 'Enlace público';

  @override
  String get csShareLinkBody =>
      'Cualquiera con este enlace puede ver el PDF. Revocable desde tu Nextcloud.';

  @override
  String get csShareLinkCopied => 'Enlace copiado al portapapeles.';

  @override
  String csShareLinkFailed(String error) {
    return 'Error al compartir: $error';
  }

  @override
  String get csCopyLink => 'Copiar enlace';

  @override
  String get csShare => 'Compartir';

  @override
  String get csRevokeLink => 'Revocar enlace';

  @override
  String get csRevokeLinkDone => 'Enlace revocado.';

  @override
  String get csShareLinkUpdate => 'Actualizar PDF compartido';

  @override
  String get csShareLinkUpdated => 'PDF actualizado.';

  @override
  String get csChangeSelectionColor => 'Cambiar color de la selección';

  @override
  String get csSelectionThickness => 'Grosor de la selección';

  @override
  String csWidthPx(String width) {
    return '$width px';
  }

  @override
  String get csFlipHorizontal => 'Voltear horizontalmente';

  @override
  String get csFlipVertical => 'Voltear verticalmente';

  @override
  String get csCopyAsImage => 'Copiar como imagen';

  @override
  String get csPasteInAnotherNotebook => 'Pegar en otro cuaderno…';

  @override
  String get csKeyDelete => 'Supr';

  @override
  String get csCreateSymbol => 'Crear símbolo';

  @override
  String get csSelect => 'Seleccionar';

  @override
  String get csImportFile => 'Importar archivo…';

  @override
  String get csTakePhoto => 'Tomar foto';

  @override
  String get csInsertText => 'Insertar texto';

  @override
  String csInsertSymbolCount(int count) {
    return 'Insertar símbolo ($count)';
  }

  @override
  String get csClearPage => 'Borrar página';

  @override
  String get csExportPng => 'Exportar PNG';

  @override
  String get csExportPdf => 'Exportar PDF';

  @override
  String get csClearPageConfirmBody =>
      'Se eliminarán todos los elementos de esta página. ¿Continuar?';

  @override
  String get csClear => 'Borrar';

  @override
  String get csCreateSymbolTitle => 'Crear símbolo reutilizable';

  @override
  String get csSymbolNameLabel => 'Nombre del símbolo';

  @override
  String get csLibraryLabel => 'Biblioteca:';

  @override
  String get csNoLibraryNotice =>
      'No hay ninguna biblioteca. Se creará una biblioteca \"Símbolos\".';

  @override
  String get csCreate => 'Crear';

  @override
  String csSymbolCreated(String name) {
    return '¡Símbolo \"$name\" creado!';
  }

  @override
  String csSaveFileDialogTitle(String fileName) {
    return 'Guardar $fileName';
  }

  @override
  String get csExportCurrentPagePng => 'Página actual (PNG)';

  @override
  String get csExportCurrentChapter => 'Capítulo actual';

  @override
  String get csExportEntireNotebook => 'Cuaderno completo';

  @override
  String csExportingPages(int count) {
    return 'Exportando $count páginas...';
  }

  @override
  String csChooseFolderForImages(int count) {
    return 'Elige una carpeta para las $count imágenes';
  }

  @override
  String csPngExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return 'PNG exportado ($_temp0)';
  }

  @override
  String csExportError(String error) {
    return 'Error de exportación: $error';
  }

  @override
  String get csExportCurrentPage => 'Página actual';

  @override
  String csGeneratingPdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return 'Generando PDF ($_temp0)...';
  }

  @override
  String csPdfExportError(String error) {
    return 'Error al exportar el PDF: $error';
  }

  @override
  String csPdfExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return 'PDF exportado: $_temp0';
  }

  @override
  String get csChapterSeparatorEyebrow => 'CAPÍTULO';

  @override
  String get csSelectionCopiedAsImage => 'Selección copiada como imagen';

  @override
  String csCopyImageError(String error) {
    return 'Error al copiar la imagen: $error';
  }

  @override
  String get csExport => 'Exportar';

  @override
  String csPageNumber(int number) {
    return 'Página $number';
  }

  @override
  String csPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return '$_temp0';
  }

  @override
  String get csExportChapterTitle => 'Exportar capítulo';

  @override
  String get csExportNotebookTitle => 'Exportar cuaderno completo';

  @override
  String get csChapterSeparatorQuestion =>
      '¿Insertar una página separadora antes de cada capítulo?';

  @override
  String get csYesWithSeparators => 'Sí, con separadores';

  @override
  String get csNoPagesOnly => 'No, solo las páginas';

  @override
  String csTotalPages(int count) {
    return 'Páginas totales: $count';
  }

  @override
  String csFromPage(int page) {
    return 'Desde la página: $page';
  }

  @override
  String csToPage(int page) {
    return 'Hasta la página: $page';
  }

  @override
  String csWillExportPages(int count, int start, int end) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se exportarán $count páginas ($start–$end)',
      one: 'Se exportará $count página ($start–$end)',
    );
    return '$_temp0';
  }

  @override
  String csChapterLabelWithCount(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return '$title ($_temp0)';
  }

  @override
  String get csGoToPage => 'Ir a la página';

  @override
  String get csDuplicatePage => 'Duplicar página';

  @override
  String get csNewPageAfter => 'Página nueva después';

  @override
  String get csDeletePageConfirmTitle => '¿Eliminar la página?';

  @override
  String csDeletePageConfirmBody(int number) {
    return 'La página $number y todo su contenido se eliminarán.';
  }

  @override
  String get csExportAsPdf => 'Exportar como PDF';

  @override
  String get csExportAsPng => 'Exportar como PNG';

  @override
  String get csExportAsNcnote => 'Exportar como .ncnote (nativo)';

  @override
  String get csExportNcnoteSubtitle =>
      'Formato nativo, calidad vectorial completa (para copia de seguridad o transferencia)';

  @override
  String get csGeneratingNcnote => 'Generando .ncnote…';

  @override
  String csNcnoteExported(String size) {
    return '.ncnote exportado ($size KB)';
  }

  @override
  String csNcnoteExportError(String error) {
    return 'Error al exportar .ncnote: $error';
  }

  @override
  String get csImageOrPdf => 'Imagen o PDF';

  @override
  String get csChangePaperType => 'Cambiar tipo de papel';

  @override
  String get csPenToMonitor => 'Lápiz → Monitor';

  @override
  String get csPenToMonitorSubtitle => 'Limitar el lápiz a una sola pantalla';

  @override
  String get csPaperType => 'Tipo de papel';

  @override
  String get csPaperBlank => 'Blanco';

  @override
  String get csPaperLinedNarrow => 'Rayado estrecho';

  @override
  String get csPaperLinedWide => 'Rayado ancho';

  @override
  String get csPaperGrid => 'Cuadrícula';

  @override
  String get csPaperDotted => 'Punteado';

  @override
  String get csPaperCornell => 'Cornell';

  @override
  String get csPaperIsometric => 'Isométrico';

  @override
  String get csPaperMusic => 'Pentagrama';

  @override
  String get csMapPenToMonitor => 'Asignar el lápiz a un monitor';

  @override
  String csPenMappedTo(String monitor) {
    return 'Lápiz asignado a $monitor';
  }

  @override
  String get csAllMonitors => 'Todos los monitores';

  @override
  String get csAllMonitorsSubtitle =>
      'Restablecer (lápiz en todo el escritorio)';

  @override
  String get csPenReset => 'Lápiz restablecido';

  @override
  String get csShapeLine => 'Línea';

  @override
  String get csShapeCircle => 'Círculo';

  @override
  String get csShapeRectangle => 'Rectángulo';

  @override
  String get csShapeTriangle => 'Triángulo';

  @override
  String get csShapeArrow => 'Flecha';

  @override
  String get csInvalidRangeError =>
      'Introduce un intervalo válido (p. ej. 1–10).';

  @override
  String csPdfStartOutOfRange(int count) {
    return 'El PDF tiene unas $count páginas. El inicio está fuera de rango.';
  }

  @override
  String get csImportPdfTitle => 'Importar PDF';

  @override
  String csPdfEstimatedPages(int count) {
    return 'El PDF tiene unas $count páginas.';
  }

  @override
  String csAllPagesWithCount(int count) {
    return 'Todas las páginas ($count)';
  }

  @override
  String get csAllPages => 'Todas las páginas';

  @override
  String get csCustomRange => 'Intervalo personalizado';

  @override
  String get csFromLabel => 'De';

  @override
  String get csToLabel => 'A';

  @override
  String get csImport => 'Importar';

  @override
  String libErrorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String libErrorOpen(String error) {
    return 'Error al abrir: $error';
  }

  @override
  String get libImportCannotReadFile => 'No se puede leer el archivo';

  @override
  String get libImportInProgress => 'Importando…';

  @override
  String get libServiceUnavailable => 'Servicio no disponible';

  @override
  String libImportedTitleSuffix(String title) {
    return '$title (importado)';
  }

  @override
  String libImportSuccess(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return 'Importado: \"$title\" ($_temp0)';
  }

  @override
  String libErrorImport(String error) {
    return 'Error de importación: $error';
  }

  @override
  String libErrorCreate(String error) {
    return 'Error al crear: $error';
  }

  @override
  String get libSketchDefaultTitle => 'Boceto';

  @override
  String libErrorCreateSketch(String error) {
    return 'Error al crear el boceto: $error';
  }

  @override
  String get libRemoveFromFavorites => 'Quitar de favoritos';

  @override
  String get libAddToFavorites => 'Añadir a favoritos';

  @override
  String get libRename => 'Renombrar';

  @override
  String get libChangeCover => 'Cambiar portada';

  @override
  String get libMoveToFolder => 'Mover a carpeta';

  @override
  String get libNoFolder => 'Sin carpeta';

  @override
  String get libNewFolder => 'Nueva carpeta';

  @override
  String get libRenameFolder => 'Renombrar carpeta';

  @override
  String get libFolderNameHint => 'Nombre de la carpeta';

  @override
  String get libAllNotebooks => 'Todos';

  @override
  String get libDeleteFolder => 'Eliminar carpeta';

  @override
  String libDeleteFolderTitle(String name) {
    return '¿Eliminar la carpeta \"$name\"?';
  }

  @override
  String get libDeleteFolderBody =>
      'Los cuadernos que contiene no se eliminan, permanecen en la biblioteca sin carpeta.';

  @override
  String get libDelete => 'Eliminar';

  @override
  String get libDeleteNotebookTitle => '¿Eliminar el cuaderno?';

  @override
  String get libDeleteNotebookBody =>
      'Se moverá a la papelera. Podrás restaurarlo desde Ajustes > Almacenamiento.';

  @override
  String get libCancel => 'Cancelar';

  @override
  String get libRenameNotebookTitle => 'Renombrar cuaderno';

  @override
  String get libSave => 'Guardar';

  @override
  String get libSortTitle => 'Ordenar';

  @override
  String get libAppName => 'AbelNotes';

  @override
  String get libSearchHintShort => 'Buscar…';

  @override
  String get libSearchHintNotebooks => 'Buscar cuadernos…';

  @override
  String get libImport => 'Importar';

  @override
  String get libImportTooltip => 'Importar un archivo .ncnote';

  @override
  String get libSettingsTooltip => 'Ajustes';

  @override
  String get libMoreTooltip => 'Más';

  @override
  String get libViewAsList => 'Vista de lista';

  @override
  String get libViewAsGrid => 'Vista de cuadrícula';

  @override
  String libSortWithLabel(String sortLabel) {
    return 'Ordenar: $sortLabel';
  }

  @override
  String get libImportNcnoteMenu => 'Importar…';

  @override
  String get libYourNotebooks => 'Tus cuadernos';

  @override
  String libItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos',
      one: '$count elemento',
    );
    return '$_temp0';
  }

  @override
  String get libNewNotebook => 'Nuevo cuaderno';

  @override
  String get libSketches => 'Bocetos';

  @override
  String get libInfiniteSpace => 'espacio infinito';

  @override
  String get libNewSketch => 'Nuevo boceto';

  @override
  String get libInfiniteCanvas => 'Lienzo infinito';

  @override
  String get libNew => 'Nuevo';

  @override
  String libPagesAbbrev(int count) {
    return '$count pág.';
  }

  @override
  String libPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return '$_temp0';
  }

  @override
  String get libFooterWebdav => 'WebDAV';

  @override
  String get libFooterLocalFirst => 'Aplicación local-first';

  @override
  String get libSyncingWithServer => 'Sincronizando con el servidor…';

  @override
  String libDownloadingProgress(int done, int total) {
    return 'Descargando $done/$total cuadernos…';
  }

  @override
  String get libLoadingNotebooks => 'Cargando cuadernos…';

  @override
  String get libLoadingNotebooksFromServer =>
      'Cargando cuadernos desde el servidor…';

  @override
  String get libTimeNow => 'ahora';

  @override
  String libTimeMinutesAgo(int count) {
    return 'hace $count min';
  }

  @override
  String libTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count horas',
      one: 'hace $count hora',
    );
    return '$_temp0';
  }

  @override
  String libTimeDaysAgo(int count) {
    return 'hace $count d';
  }

  @override
  String libTimeWeeksAgo(int count) {
    return 'hace $count sem';
  }

  @override
  String libTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count meses',
      one: 'hace $count mes',
    );
    return '$_temp0';
  }

  @override
  String libTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'hace $count años',
      one: 'hace $count año',
    );
    return '$_temp0';
  }

  @override
  String get libNotebookTitleLabel => 'Título';

  @override
  String get libCoverLabel => 'Portada';

  @override
  String get libPaperLabel => 'Papel';

  @override
  String get libPaperBlank => 'Blanco';

  @override
  String get libPaperLined => 'Rayado';

  @override
  String get libPaperGrid => 'Cuadrícula';

  @override
  String get libPaperDotted => 'Punteado';

  @override
  String get libCreate => 'Crear';

  @override
  String get setSectionGeneral => 'General';

  @override
  String get setSectionInput => 'Stylus y entrada';

  @override
  String get setSectionSync => 'Sincronización';

  @override
  String get setSectionStorage => 'Almacenamiento';

  @override
  String get setSectionShortcuts => 'Atajos';

  @override
  String get setSectionAdvanced => 'Avanzado';

  @override
  String get setSectionAbout => 'Información';

  @override
  String get setBackToLibrary => 'Biblioteca';

  @override
  String get setSettingsTitle => 'Ajustes';

  @override
  String get setThemeLabel => 'Tema';

  @override
  String get setThemeLight => 'Claro';

  @override
  String get setThemePaper => 'Papel';

  @override
  String get setThemeDark => 'Oscuro';

  @override
  String get setLanguage => 'Idioma';

  @override
  String get setLanguageSub => 'Idioma de la interfaz';

  @override
  String get setLanguageItalian => 'Italiano';

  @override
  String get setFavoritesFirst => 'Favoritos primero';

  @override
  String get setFavoritesFirstSub =>
      'Muestra los cuadernos favoritos al principio de la biblioteca';

  @override
  String get setStylusOnly => 'Solo stylus';

  @override
  String get setStylusOnlySub =>
      'Ignora el toque del dedo mientras escribes. Pellizcar y desplazar siguen funcionando con dos dedos.';

  @override
  String get setPalmRejection => 'Rechazo de palma';

  @override
  String get setPalmRejectionSub => 'Detección automática de la palma apoyada';

  @override
  String get setPressureThickness => 'Presión → grosor';

  @override
  String get setPressureThicknessSub =>
      'Modulación del trazo según la presión del stylus';

  @override
  String get setTiltCalligraphy => 'Inclinación → caligrafía';

  @override
  String get setTiltCalligraphySub =>
      'La inclinación del stylus altera el ancho y el ángulo del trazo';

  @override
  String get setStrokeContinuation => 'Continuación del trazo';

  @override
  String get setStrokeContinuationSub =>
      'Compensa breves interrupciones del sensor (p. ej., el punto de la i)';

  @override
  String get setSyncConnectedDesc =>
      'Conectado a un servidor WebDAV. Los cuadernos se sincronizan en todos tus dispositivos.';

  @override
  String get setSyncLocalOnlyDesc =>
      'Modo solo local: los cuadernos permanecen en este dispositivo. Conecta un servidor WebDAV para acceder a ellos desde varios dispositivos.';

  @override
  String get setSyncWebdav => 'WebDAV';

  @override
  String get setSyncLocalOnly => 'Solo local';

  @override
  String setSyncAccountInfo(String host, String username) {
    return '$host · $username';
  }

  @override
  String get setSyncNoServer => 'Ningún servidor conectado';

  @override
  String get setDisconnect => 'Desconectar';

  @override
  String get setConnect => 'Conectar';

  @override
  String get setDisconnectTitle => '¿Desconectar el servidor?';

  @override
  String get setDisconnectBody =>
      'Los cuadernos ya descargados permanecen en este dispositivo. La sincronización se detiene hasta que vuelvas a conectarte.';

  @override
  String get setCheckCert => 'Verificar certificado del servidor';

  @override
  String get setCertCheckFailed =>
      'No se pudo verificar el certificado del servidor.';

  @override
  String get setCertUnchanged =>
      'El certificado no ha cambiado desde la última conexión.';

  @override
  String get setCertChangedTitle => 'Nuevo certificado detectado';

  @override
  String setCertChangedBody(String oldFingerprint, String newFingerprint) {
    return 'El servidor presenta una huella distinta de la guardada. Si has renovado tú el certificado, confirma para seguir sincronizando. Si no has sido tú, CANCELA y revisa tu red antes de reintentar.\n\nHuella guardada: $oldFingerprint\nHuella actual: $newFingerprint';
  }

  @override
  String get setCertConfirmNew => 'Confirmar nuevo certificado';

  @override
  String get setCancel => 'Cancelar';

  @override
  String get setShortcutPen => 'Pluma';

  @override
  String get setShortcutUndo => 'Deshacer';

  @override
  String get setShortcutBrush => 'Pincel';

  @override
  String get setShortcutRedo => 'Rehacer';

  @override
  String get setShortcutEraser => 'Borrador';

  @override
  String get setShortcutSelectAll => 'Seleccionar todo';

  @override
  String get setShortcutLasso => 'Lazo';

  @override
  String get setShortcutCopy => 'Copiar';

  @override
  String get setShortcutHand => 'Mano';

  @override
  String get setShortcutCut => 'Cortar';

  @override
  String get setShortcutText => 'Texto';

  @override
  String get setShortcutPaste => 'Pegar';

  @override
  String get setShortcutShape => 'Forma';

  @override
  String get setShortcutDuplicate => 'Duplicar';

  @override
  String get setShortcutChangePage => 'Cambiar página';

  @override
  String get setShortcutSave => 'Guardar';

  @override
  String get setShortcutFit => 'Ajustar';

  @override
  String get setShortcutCheatSheet => 'Hoja de referencia';

  @override
  String get setKeyboardShortcutsTitle => 'Atajos de teclado';

  @override
  String get setClearCache => 'Limpiar caché';

  @override
  String get setClearCacheSub =>
      'Elimina los archivos temporales. Los cuadernos no se tocan.';

  @override
  String get setClear => 'Limpiar';

  @override
  String get setTrash => 'Papelera';

  @override
  String get setTrashSub => 'Cuadernos eliminados, restaurables';

  @override
  String get setOpenTrash => 'Abrir papelera';

  @override
  String get setClearCacheDone => 'Caché limpiada.';

  @override
  String get setExportLibrary => 'Exportar biblioteca';

  @override
  String get setExportLibrarySub =>
      'Guarda todos los cuadernos en un único archivo zip.';

  @override
  String get setExport => 'Exportar';

  @override
  String get setExportLibraryEmpty => 'No hay cuadernos para exportar.';

  @override
  String get setExportLibraryInProgress => 'Exportando…';

  @override
  String setExportLibraryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se exportaron $count cuadernos',
      one: 'Se exportó $count cuaderno',
    );
    return '$_temp0.';
  }

  @override
  String setExportLibraryFailed(String error) {
    return 'Error al exportar: $error';
  }

  @override
  String setTrashPurgeTitle(String title) {
    return '¿Eliminar definitivamente \"$title\"?';
  }

  @override
  String get setTrashPurgeBody => 'No podrás recuperarlo.';

  @override
  String get setTrashPurge => 'Eliminar definitivamente';

  @override
  String get setTrashEmptyTitle => '¿Vaciar la papelera?';

  @override
  String get setTrashEmptyBody =>
      'Todos los cuadernos de la papelera se eliminarán definitivamente.';

  @override
  String get setTrashEmpty => 'Vaciar papelera';

  @override
  String get setTrashEmptyState => 'La papelera está vacía.';

  @override
  String setTrashDeletedAgo(String time) {
    return 'Eliminado hace $time';
  }

  @override
  String get setTrashRestore => 'Restaurar';

  @override
  String get setAdvancedIntro =>
      'Herramientas de recuperación para casos raros de un cuaderno bloqueado en la sincronización. Úsalas solo si la sincronización sigue fallando tras un \"Forzar sincronización\" normal desde la biblioteca.';

  @override
  String get setForceReloadTitle =>
      'Forzar recarga del cuaderno desde el servidor';

  @override
  String get setForceReloadDesc =>
      'Vuelve a descargar todo el contenido del cuaderno desde la carpeta delta del servidor y sobrescribe la copia local. Útil si el número de páginas parece incorrecto o el cuaderno no se abre. No se pierden datos en el servidor.';

  @override
  String setErrorGeneric(String error) {
    return 'Error: $error';
  }

  @override
  String setPagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return '$_temp0';
  }

  @override
  String get setReload => 'Recargar';

  @override
  String get setCloseNotebookFirst =>
      'Cierra el cuaderno antes de recargarlo desde el servidor.';

  @override
  String setReloadConfirmTitle(String title) {
    return '¿Recargar \"$title\"?';
  }

  @override
  String get setReloadConfirmBody =>
      'Vuelve a descargar metadatos, documento, páginas y recursos desde la carpeta delta del servidor. La copia local se reemplaza.\n\nLos cambios locales aún no sincronizados se perderán. ¿Continuar?';

  @override
  String setReloadInProgress(String title) {
    return 'Recargando \"$title\"…';
  }

  @override
  String get setNotConnectedWebdav => 'No conectado a un servidor WebDAV.';

  @override
  String setReloadDone(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return '\"$title\" recargado — $_temp0.';
  }

  @override
  String setReloadFailed(String error) {
    return 'Recarga fallida: $error';
  }

  @override
  String get setAboutTagline => 'Aplicación de escritura a mano, local-first.';

  @override
  String get setAboutOffline =>
      'Funciona sin conexión; la sincronización con WebDAV es opcional.';

  @override
  String setAboutVersion(String version, String commit) {
    return 'Versión $version · build $commit';
  }

  @override
  String get setReportProblem => 'Informar un problema';

  @override
  String get setReportProblemSub =>
      'Copia el registro de errores al portapapeles para adjuntarlo a tu informe.';

  @override
  String get setCopyLog => 'Copiar registro';

  @override
  String get setReportProblemEmpty => 'No hay errores registrados.';

  @override
  String get setCopyLogDone => 'Registro copiado al portapapeles.';

  @override
  String get onbTagline =>
      'Notas y dibujo a mano alzada, sincronizados en TU servidor. Elige cómo empezar — puedes cambiarlo más adelante.';

  @override
  String get onbTryNowTitle => 'Pruébalo ahora';

  @override
  String get onbTryNowSubtitle =>
      'Empieza a escribir ya. Los cuadernos permanecen en este dispositivo — sin cuenta, sin servidor.';

  @override
  String get onbConnectNextcloudTitle => 'Conecta tu Nextcloud';

  @override
  String get onbConnectNextcloudSubtitle =>
      'Sincroniza en tu servidor WebDAV / Nextcloud personal y accede desde todos tus dispositivos.';

  @override
  String get onbManagedServerTitle => 'Servidor gestionado de AbelNotes';

  @override
  String get onbManagedServerSubtitle =>
      '¿No tienes servidor? Pronto podrás usar el nuestro, sin configurar nada.';

  @override
  String get onbComingSoonBadge => 'Próximamente';

  @override
  String get onbLicenseNote =>
      'Al abrir la aplicación aceptas la licencia AGPL-3.0. \"AbelNotes\" es una marca del proyecto.';

  @override
  String get logConnectionFailed =>
      'No se puede conectar. Verifica la URL, el nombre de usuario y la contraseña.';

  @override
  String logConnectionError(String error) {
    return 'Error de conexión: $error';
  }

  @override
  String get logCertificateChanged =>
      'El certificado del servidor ha cambiado desde la última conexión. Si has sido tú (p. ej. renovación del certificado), ve a Ajustes > Sincronización para confirmar la nueva huella.';

  @override
  String get logCertConfirmTitle => 'Verificar identidad del servidor';

  @override
  String get logCertConfirmBody =>
      'Primera conexión a este servidor. Compara esta huella con la de tu servidor (p. ej. desde la línea de comandos) antes de continuar:';

  @override
  String get logCertConfirmTrust => 'Confío, continuar';

  @override
  String get logBackTooltip => 'Atrás';

  @override
  String get logTitle => 'Conecta tu Nextcloud';

  @override
  String get logSubtitle =>
      'Cualquier servidor WebDAV / Nextcloud (VPS, autoalojado, LAN). Sin nubes de terceros.';

  @override
  String get logServerUrlLabel => 'URL del servidor';

  @override
  String get logServerUrlHint => 'https://cloud.example.com';

  @override
  String get logServerUrlRequired => 'Introduce la URL del servidor';

  @override
  String get logServerUrlInvalid => 'Debe empezar por http:// o https://';

  @override
  String get logUsernameLabel => 'Nombre de usuario';

  @override
  String get logUsernameRequired => 'Nombre de usuario obligatorio';

  @override
  String get logPasswordLabel => 'Contraseña / Contraseña de aplicación';

  @override
  String get logPasswordRequired => 'Contraseña obligatoria';

  @override
  String get logAppPasswordHint =>
      'Recomendado: una contraseña de aplicación generada desde los ajustes de Nextcloud.';

  @override
  String get logServerTypeNextcloud => 'Nextcloud / ownCloud';

  @override
  String get logServerTypeWebdav => 'Otro WebDAV';

  @override
  String get logServerUrlHintWebdav => 'https://dav.example.com/carpeta';

  @override
  String get logWebdavExperimental =>
      'Los backends WebDAV genéricos (Synology, Seafile, rclone…) son experimentales: solo Nextcloud está probado a fondo. Mantén copias de seguridad de tus cuadernos.';

  @override
  String get logWebdavUrlHint =>
      'URL WebDAV completa, ruta incluida — p. ej. Synology https://nas:5006/home, Seafile https://servidor/seafdav. Compartir enlaces no está disponible en WebDAV genérico.';

  @override
  String get logConnectButton => 'Conectar';

  @override
  String get chromeBackToLibraryTooltip => 'Volver a la biblioteca';

  @override
  String get chromeLibrary => 'Biblioteca';

  @override
  String get chromeUnsaved => 'Sin guardar';

  @override
  String get chromeMouseDrawsTooltip =>
      'Ratón: dibuja — toca para usarlo como selección';

  @override
  String get chromeMouseSelectsTooltip =>
      'Ratón: selección — toca para dibujar con el ratón';

  @override
  String get chromeTouchDrawsTooltip =>
      'Dedo: dibuja — toca para usarlo para desplazar';

  @override
  String get chromeTouchPansTooltip =>
      'Dedo: desplaza — toca para dibujar con el dedo';

  @override
  String get chromeUndo => 'Deshacer';

  @override
  String get chromeRedo => 'Rehacer';

  @override
  String get chromeAllPages => 'Todas las páginas';

  @override
  String chromePageIndicator(String current, int total) {
    return '$current / $total';
  }

  @override
  String get chromeAddPage => 'Añadir página';

  @override
  String get chromeSymbols => 'Símbolos';

  @override
  String get chromeExport => 'Exportar';

  @override
  String get chromeMore => 'Más';

  @override
  String get chromeMoreEllipsis => 'Más…';

  @override
  String get chromeToolPen => 'Pluma · P';

  @override
  String get chromeToolHighlighter => 'Resaltador';

  @override
  String get chromeToolEraser => 'Borrador · E';

  @override
  String get chromeToolLasso => 'Lazo · L';

  @override
  String get chromeToolText => 'Texto · T';

  @override
  String get chromeToolLaser => 'Láser';

  @override
  String get chromeToolPan => 'Mano · H';

  @override
  String get chromeDragToMoveBar => 'Arrastra para mover la barra';

  @override
  String get chromeShapeGuessOn => 'Autoforma · activado';

  @override
  String get chromeShapeGuessOff => 'Autoforma · desactivado';

  @override
  String get chromeLabelPen => 'Pluma';

  @override
  String get chromeLabelBallpoint => 'Bolígrafo';

  @override
  String get chromeLabelBrush => 'Pincel';

  @override
  String get chromeLabelCalligraphy => 'Caligrafía';

  @override
  String get chromeLabelEraser => 'Borrador';

  @override
  String get chromeLabelLasso => 'Lazo';

  @override
  String get chromeLabelText => 'Texto';

  @override
  String get chromeLabelShape => 'Forma';

  @override
  String get chromeLabelImage => 'Imagen';

  @override
  String get chromeLabelPan => 'Mano';

  @override
  String get chromePresetsSection => 'Preajustes';

  @override
  String get chromePresetHint => 'Mantén pulsado para guardar/borrar';

  @override
  String get chromeColorSection => 'Color';

  @override
  String get chromeColorEditHint => 'Mantén pulsado un color para cambiarlo';

  @override
  String get chromeThicknessSection => 'Grosor';

  @override
  String chromeThicknessPx(String value) {
    return '$value px';
  }

  @override
  String get chromePreview => 'Vista previa';

  @override
  String get chromeModeSection => 'Modo';

  @override
  String get chromeEraserPerArea => 'Por área';

  @override
  String get chromeEraserPerStroke => 'Por trazo';

  @override
  String get chromeSizeSection => 'Tamaño';

  @override
  String get chromeSizeSmall => 'S';

  @override
  String get chromeSizeMedium => 'M';

  @override
  String get chromeSizeLarge => 'L';

  @override
  String get chromePresetOverwrite => 'Sobrescribir con el actual';

  @override
  String get chromePresetClearSlot => 'Vaciar ranura';

  @override
  String get chromeNoPages => 'Sin páginas';

  @override
  String get chromeHidePageBar => 'Ocultar la barra de páginas';

  @override
  String get chromeShowPageBar => 'Mostrar la barra de páginas';

  @override
  String chromePrevPageTooltip(int number) {
    return 'Página anterior $number — toca para volver';
  }

  @override
  String chromePageOfChapterTooltip(int number, int globalNumber) {
    return 'Página $number del capítulo · página $globalNumber del cuaderno';
  }

  @override
  String chromePageTooltip(int number) {
    return 'Página $number';
  }

  @override
  String get chromeHexLabel => 'Hexadecimal';

  @override
  String get chromeCancel => 'Cancelar';

  @override
  String get chromeApply => 'Aplicar';

  @override
  String get pmNone => 'Ninguno';

  @override
  String get pmCreateChapterFirst => 'Crea primero al menos un capítulo.';

  @override
  String pmAssignChapterCount(int count) {
    return 'Asignar capítulo ($count pág.)';
  }

  @override
  String pmDeletePagesConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¿Eliminar $count páginas?',
      one: '¿Eliminar 1 página?',
    );
    return '$_temp0';
  }

  @override
  String get pmActionCannotBeUndone => 'Esta acción no se puede deshacer.';

  @override
  String get pmCancel => 'Cancelar';

  @override
  String get pmDelete => 'Eliminar';

  @override
  String pmPagesCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count páginas cortadas — abre el cuaderno de destino para pegar.',
      one: '1 página cortada — abre el cuaderno de destino para pegar.',
    );
    return '$_temp0';
  }

  @override
  String pmPagesCutSkipped(int count, int skipped) {
    return '$count páginas cortadas ($skipped aún no cargadas, omitidas) — abre el cuaderno de destino para pegar.';
  }

  @override
  String pmSelectedCount(int count) {
    return '$count seleccionadas';
  }

  @override
  String get pmSelectAllButton => 'Todas';

  @override
  String get pmClearSelection => 'Cancelar selección';

  @override
  String pmPagesCount(int count) {
    return 'Páginas ($count)';
  }

  @override
  String pmPagesFilteredCount(int visible, int total) {
    return 'Páginas ($visible/$total)';
  }

  @override
  String get pmGoToPageTooltip => 'Ir a la página…';

  @override
  String get pmExitSelection => 'Salir de la selección';

  @override
  String get pmSelectPages => 'Seleccionar páginas';

  @override
  String get pmPastePages => 'Pegar páginas';

  @override
  String pmPagesPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas pegadas.',
      one: '1 página pegada.',
    );
    return '$_temp0';
  }

  @override
  String get pmAddPage => 'Añadir página';

  @override
  String get pmClose => 'Cerrar';

  @override
  String get pmNewChapter => 'Nuevo capítulo';

  @override
  String get pmChapterNameHint => 'Nombre del capítulo';

  @override
  String pmPageDeleted(int number) {
    return 'Página $number eliminada';
  }

  @override
  String get pmUndo => 'Deshacer';

  @override
  String get pmAssignChapter => 'Asignar capítulo';

  @override
  String get pmRename => 'Renombrar';

  @override
  String get pmRenameChapter => 'Renombrar capítulo';

  @override
  String get pmDeleteChapter => 'Eliminar capítulo';

  @override
  String pmDeleteChapterConfirm(String title) {
    return '¿Eliminar \"$title\"? Las páginas que contiene se conservarán, pero sin capítulo.';
  }

  @override
  String get pmGoToPage => 'Ir a la página';

  @override
  String pmPageRangeHint(int max) {
    return '1–$max';
  }

  @override
  String get pmGo => 'Ir';

  @override
  String get pmOk => 'Aceptar';

  @override
  String pmCountPagesShort(int count) {
    return '$count pág.';
  }

  @override
  String get pmChapter => 'Capítulo';

  @override
  String get pmCut => 'Cortar';

  @override
  String get pmInsertBefore => 'Insertar antes';

  @override
  String get pmInsertAfter => 'Insertar después';

  @override
  String get pmDuplicate => 'Duplicar';

  @override
  String get pmMoveTo => 'Mover a la página…';

  @override
  String get pmMove => 'Mover';

  @override
  String get pmMoveToPage => 'Mover a la página';

  @override
  String get pmChapterEllipsis => 'Capítulo…';

  @override
  String pmPageChapterLabel(int number, String chapter) {
    return '$number • $chapter';
  }

  @override
  String get pmCorruptAssetTooltip =>
      'Recurso dañado en el servidor (truncado) — vuelve a importar el PDF original para recuperarlo';

  @override
  String get pmLoadingImageTooltip => 'Cargando imagen del servidor…';

  @override
  String get tedInsertTextTitle => 'Insertar texto';

  @override
  String get tedEditTextTitle => 'Editar texto';

  @override
  String get tedBoldTooltip => 'Negrita (Ctrl+B)';

  @override
  String get tedItalicTooltip => 'Cursiva (Ctrl+I)';

  @override
  String get tedUnderlineTooltip => 'Subrayado (Ctrl+U)';

  @override
  String get tedStrikethroughTooltip => 'Tachado';

  @override
  String get tedAlignLeft => 'Izquierda';

  @override
  String get tedAlignCenter => 'Centro';

  @override
  String get tedAlignRight => 'Derecha';

  @override
  String get tedWriteHereHint => 'Escribe aquí…';

  @override
  String get tedCancel => 'Cancelar';

  @override
  String get tedInsert => 'Insertar';

  @override
  String get cropTitle => 'Recortar imagen';

  @override
  String get cropCancel => 'Cancelar';

  @override
  String get cropConfirm => 'Recortar';

  @override
  String get imgFontSmaller => 'Texto más pequeño';

  @override
  String get imgFontLarger => 'Texto más grande';

  @override
  String get imgCrop => 'Recortar';

  @override
  String get imgCopy => 'Copiar';

  @override
  String get imgUnlock => 'Desbloquear';

  @override
  String get imgLock => 'Bloquear';

  @override
  String get imgDelete => 'Eliminar';

  @override
  String get imgDeselect => 'Deseleccionar';

  @override
  String get imgMoreActions => 'Más acciones';

  @override
  String get imgBringToFront => 'Traer al frente';

  @override
  String get imgSendToBack => 'Enviar al fondo';

  @override
  String get imgComment => 'Comentario';

  @override
  String get imgFlipHChecked => 'Voltear H ✓';

  @override
  String get imgFlipH => 'Voltear H';

  @override
  String get imgCut => 'Cortar';

  @override
  String get syncOkTooltip => 'Sincronizado';

  @override
  String get syncPendingTooltip => 'Sincronizando…';

  @override
  String get syncOfflineTooltip => 'Sin conexión';

  @override
  String get syncConflictTooltip => 'Conflicto';

  @override
  String get confDecideLater => 'Decidir más tarde';

  @override
  String confTitlePageDeletedElsewhere(int pageNumber) {
    return 'Página $pageNumber eliminada en otro dispositivo';
  }

  @override
  String confTitleConflictPage(int pageNumber) {
    return 'Conflicto — Página $pageNumber';
  }

  @override
  String get confDeletionExplainer =>
      'Has modificado esta página, pero otro dispositivo la ha eliminado. ¿Quieres conservarla o eliminarla?';

  @override
  String get confKeepPage => 'Conservar la página';

  @override
  String get confLocalYours => 'Local (tuyo)';

  @override
  String get confRemoteOtherDevice => 'Remoto (otro dispositivo)';

  @override
  String get confKeepAllLocal => 'Mantener todos locales';

  @override
  String get confAcceptAllRemote => 'Aceptar todos remotos';

  @override
  String confProgressIndicator(int current, int total, num decided) {
    String _temp0 = intl.Intl.pluralLogic(
      decided,
      locale: localeName,
      other: '$decided decididos',
      one: '$decided decidido',
    );
    return '$current / $total  ($_temp0)';
  }

  @override
  String get confApplyChoices => 'Aplicar selecciones';

  @override
  String confDecidedProgress(int decided, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'decididos',
      one: 'decidido',
    );
    return '$decided/$total $_temp0';
  }

  @override
  String get confJumpToConflict => 'Ir al conflicto';

  @override
  String confJumpDecidedCount(int decided, int total) {
    return '$decided/$total decididos';
  }

  @override
  String confJumpItemPage(int pageNumber) {
    return 'Pág. $pageNumber';
  }

  @override
  String confJumpItemPageWithChapter(int pageNumber, String chapterName) {
    return 'Pág. $pageNumber — $chapterName';
  }

  @override
  String get confDismissDialogTitle => '¿Cancelar?';

  @override
  String get confDismissDialogBody =>
      'Las selecciones no aplicadas se perderán. Se conservará la versión local.';

  @override
  String get confContinue => 'Continuar';

  @override
  String get confCancel => 'Cancelar';

  @override
  String get confModifiedJustNow => 'Ahora';

  @override
  String confModifiedMinutesAgo(int minutes) {
    return 'hace $minutes min';
  }

  @override
  String confModifiedHoursAgo(num hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'hace $hours horas',
      one: 'hace $hours hora',
    );
    return '$_temp0';
  }

  @override
  String get confDeletePage => 'Eliminar la página';

  @override
  String get confAsOnOtherDevice => 'Como en el otro dispositivo';

  @override
  String get symNewLibraryTitle => 'Nueva biblioteca';

  @override
  String get symNewLibraryHint => 'Introduce el nombre de la biblioteca';

  @override
  String get symRenameLibraryTitle => 'Renombrar biblioteca';

  @override
  String get symNewNameHint => 'Nuevo nombre';

  @override
  String get symDeleteLibraryTitle => 'Eliminar biblioteca';

  @override
  String symDeleteLibraryConfirm(String name) {
    return '¿Eliminar \"$name\" y todos sus símbolos?';
  }

  @override
  String get symCancel => 'Cancelar';

  @override
  String get symDelete => 'Eliminar';

  @override
  String get symRenameSymbolTitle => 'Renombrar símbolo';

  @override
  String get symPanelTitle => 'Bibliotecas de símbolos';

  @override
  String get symNoLibraries => 'Ninguna biblioteca';

  @override
  String get symNew => 'Nueva';

  @override
  String get symSelectLibrary => 'Selecciona una biblioteca';

  @override
  String get symNoSymbolsHint =>
      'Ningún símbolo\nSelecciona elementos con el lazo y pulsa ✚';

  @override
  String get symLassoSaveHint =>
      'Selecciona elementos con el lazo → ✚ para guardar en la biblioteca activa';

  @override
  String get symRename => 'Renombrar';

  @override
  String get symInsert => 'Insertar';

  @override
  String get symOk => 'OK';

  @override
  String get rcbBannerTitle => 'Cambios desde otro dispositivo';

  @override
  String get rcbSeeDetails => 'Ver detalles';

  @override
  String get rcbDismiss => 'Ignorar';

  @override
  String get rcbIncomingChanges => 'Cambios entrantes';

  @override
  String get rcbTapPageHint => 'Toca una página para aplicar e ir allí';

  @override
  String rcbNewImagesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imágenes nuevas',
      one: '1 imagen nueva',
    );
    return '$_temp0';
  }

  @override
  String get rcbKeepMine => 'Mantener los míos';

  @override
  String get rcbApplyAll => 'Aplicar todo';

  @override
  String get rcbBadgeNew => 'NUEVA';

  @override
  String get rcbBadgeModified => 'MODIFICADA';

  @override
  String rcbPageTitle(int pageNumber) {
    return 'Página $pageNumber';
  }

  @override
  String get rcbContentUpdated => 'Contenido actualizado';

  @override
  String rcbSummaryModifiedPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count págs. modificadas',
      one: '$count pág. modificada',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryNewPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nuevas',
      one: '$count nueva',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryImages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imágenes',
      one: '$count imagen',
    );
    return '$_temp0';
  }

  @override
  String get rcbChangesDetected => 'Cambios detectados';

  @override
  String get nbUntitled => 'Sin título';

  @override
  String get nbDefaultChapterTitle => 'Capítulo 1';

  @override
  String get nbOpeningNotebook => 'Abriendo cuaderno…';

  @override
  String get nbNoLocalCopyOffline =>
      'No hay una copia local de este cuaderno y no estás conectado a un servidor para descargarlo.';

  @override
  String nbOpenFailed(String error) {
    return 'No se pudo abrir: $error';
  }

  @override
  String get nbSortModifiedDesc => 'Modificados (más recientes)';

  @override
  String get nbSortModifiedAsc => 'Modificados (menos recientes)';

  @override
  String get nbSortTitleAsc => 'Título A→Z';

  @override
  String get nbSortTitleDesc => 'Título Z→A';

  @override
  String get nbSortCreatedDesc => 'Creados (más recientes)';

  @override
  String get nbSortCreatedAsc => 'Creados (menos recientes)';

  @override
  String get nbSortColorGroup => 'Color de portada';

  @override
  String cvFormatTooNew(int fileVersion, int supportedVersion) {
    return 'Este cuaderno usa un formato más reciente (v$fileVersion, compatible: v$supportedVersion). Actualiza AbelNotes para abrirlo.';
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
  String get chromeLabelHighlighter => 'Resaltador';

  @override
  String get chromeLabelLaser => 'Láser';

  @override
  String get importSourceTitle => 'Importar en la biblioteca';

  @override
  String get importSourceNcnote => 'Cuaderno .ncnote';

  @override
  String get importSourceObsidian => 'Vault de Obsidian';

  @override
  String get importSourceObsidianHint => 'Carpeta con archivos Markdown';

  @override
  String get importSourceNotion => 'Export de Notion';

  @override
  String get importSourceNotionHint => 'Archivo .zip (Markdown y CSV)';

  @override
  String get importPhaseScanning => 'Analizando origen…';

  @override
  String importPhaseParsing(int current, int total) {
    return 'Leyendo archivo $current de $total';
  }

  @override
  String importPhasePaginating(int current, int total) {
    return 'Maquetando capítulo $current de $total';
  }

  @override
  String get importPhasePackaging => 'Creando cuaderno…';

  @override
  String get importCancel => 'Cancelar';

  @override
  String get importCancelled => 'Importación cancelada';

  @override
  String importReportTitle(int count) {
    return '$count avisos durante la importación';
  }

  @override
  String get importReportCopy => 'Copiar';

  @override
  String get importReportClose => 'Cerrar';

  @override
  String get importSourceOneNote => 'Archivo OneNote';

  @override
  String get importSourceOneNoteHint => 'Sección .one o cuaderno .onetoc2';

  @override
  String get setOpenSourceLicenses => 'Licencias open source';

  @override
  String get setOpenSourceLicensesSub =>
      'Componentes de terceros incluidos en la app';

  @override
  String get csBackToContent => 'Volver al contenido';
}
