// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get csPdfTextCopied => 'Texto copiado';

  @override
  String csCopyFailed(String error) {
    return 'Falha ao copiar: $error';
  }

  @override
  String get csCopy => 'Copiar';

  @override
  String get csSyncInProgress => 'Sincronização em andamento…';

  @override
  String get csSaved => 'Salvo!';

  @override
  String csErrorGeneric(String error) {
    return 'Erro: $error';
  }

  @override
  String get csSelectionCopied => 'Seleção copiada';

  @override
  String get csSelectionCut => 'Seleção recortada';

  @override
  String get csShortcutsTitle => 'Atalhos de teclado';

  @override
  String get csShortcutGroupGeneral => 'Geral';

  @override
  String get csSaveNow => 'Salvar agora';

  @override
  String get csShortcutUndo => 'Desfazer';

  @override
  String get csShortcutRedo => 'Refazer';

  @override
  String get csSelectAll => 'Selecionar tudo';

  @override
  String get csShortcutResetZoom => 'Redefinir zoom';

  @override
  String get csShortcutDeselect => 'Desmarcar / cancelar';

  @override
  String get csShortcutThisGuide => 'Este guia';

  @override
  String get csShortcutGroupClipboard => 'Área de transferência';

  @override
  String get csShortcutCopySelection => 'Copiar seleção';

  @override
  String get csShortcutCutSelection => 'Recortar seleção';

  @override
  String get csPaste => 'Colar';

  @override
  String get csShortcutDuplicateSelection => 'Duplicar seleção';

  @override
  String get csShortcutKeyDeleteBackspace => 'Del / Backspace';

  @override
  String get csShortcutDeleteElementOrSelection =>
      'Excluir elemento ou seleção';

  @override
  String get csShortcutGroupTools => 'Ferramentas';

  @override
  String get csToolPen => 'Caneta';

  @override
  String get csToolBrush => 'Pincel';

  @override
  String get csToolEraser => 'Borracha';

  @override
  String get csToolLasso => 'Laço';

  @override
  String get csToolHand => 'Mão / mover';

  @override
  String get csToolText => 'Texto';

  @override
  String get csToolShape => 'Forma';

  @override
  String get csClose => 'Fechar';

  @override
  String get csUnsavedChangesTitle => 'Alterações não salvas';

  @override
  String get csUnsavedChangesBody => 'Quer salvar antes de sair?';

  @override
  String get csDiscard => 'Descartar';

  @override
  String get csCancel => 'Cancelar';

  @override
  String get csSave => 'Salvar';

  @override
  String get csOpeningLink => 'Abrindo o link…';

  @override
  String get csCannotOpenLink => 'Não foi possível abrir o link';

  @override
  String get csCameraUnavailable => 'Câmera não disponível neste dispositivo';

  @override
  String get csPhotoCaptureFailed => 'Não foi possível tirar a foto';

  @override
  String get csPdfRasterizing => 'Rasterizando o PDF…';

  @override
  String csPdfImportProgress(int done, int total) {
    return 'Importando PDF: $done/$total';
  }

  @override
  String get csPdfReadFailed =>
      'Não foi possível ler o PDF: nenhuma página encontrada';

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
    return 'Erro na importação do PDF: $error';
  }

  @override
  String get csNoNotebookOpen => 'Nenhum caderno aberto';

  @override
  String get csMissingPageDataTitle => 'Dados da página ausentes';

  @override
  String get csNoPages => 'Nenhuma página';

  @override
  String csMissingPagesBodyMany(int count) {
    return 'Esta página e outras $count não foram recuperadas do servidor. Os arquivos podem ter sido perdidos em uma sincronização parcial.';
  }

  @override
  String get csMissingPageBodyOne =>
      'O arquivo desta página não foi recuperado do servidor. Ele pode ter sido perdido em uma sincronização parcial.';

  @override
  String get csRetrySync => 'Tentar sincronizar de novo';

  @override
  String get csRestoreAsBlankPage => 'Restaurar como página em branco';

  @override
  String csRestoreAllMissing(int count) {
    return 'Restaurar todas ($count)';
  }

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas restauradas em branco',
      one: '$count página restaurada em branco',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'Excluir página';

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
  String get csConfirmShapeSemantics => 'Confirmar a forma reconhecida';

  @override
  String get csConfirm => 'Confirmar';

  @override
  String get csCancelShapeSemantics => 'Cancelar a forma reconhecida';

  @override
  String csTapToPlaceSymbol(String name) {
    return 'Toque para posicionar: $name';
  }

  @override
  String get csCancelSymbolInsertSemantics => 'Cancelar a inserção do símbolo';

  @override
  String get csTapToPlaceCopy => 'Toque para posicionar a cópia';

  @override
  String get csCancelPasteSemantics => 'Cancelar a colagem';

  @override
  String get csNewPage => 'Nova página';

  @override
  String get csImageCopied => 'Imagem copiada';

  @override
  String get csImageCut => 'Imagem recortada';

  @override
  String get csImageCommentTitle => 'Comentário da imagem';

  @override
  String get csAddCommentHint => 'Adicione um comentário...';

  @override
  String get csRemove => 'Remover';

  @override
  String get csCut => 'Recortar';

  @override
  String get csDuplicate => 'Duplicar';

  @override
  String get csSelectionDuplicated => 'Seleção duplicada';

  @override
  String get csChangeColor => 'Mudar a cor';

  @override
  String get csThickness => 'Espessura';

  @override
  String get csDelete => 'Excluir';

  @override
  String get csMore => 'Mais';

  @override
  String get csPresentationMode => 'Modo apresentação';

  @override
  String get csPresentationModeSub =>
      'Tela cheia, sem ferramentas — ótimo para mostrar páginas';

  @override
  String get csRecognizeHandwriting => 'Reconhecer a escrita à mão';

  @override
  String get csRecognizeHandwritingSub =>
      'Transforma a tinta em texto pesquisável (no dispositivo)';

  @override
  String get csRecognizeInProgress => 'Reconhecendo…';

  @override
  String get csRecognizeNothing => 'Nenhum texto reconhecido.';

  @override
  String csRecognizeDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count linhas reconhecidas',
      one: '$count linha reconhecida',
    );
    return '$_temp0.';
  }

  @override
  String csRecognizeFailed(String error) {
    return 'Falha no reconhecimento: $error';
  }

  @override
  String get csShareLink => 'Compartilhar por link';

  @override
  String get csShareLinkSub =>
      'Envia um PDF para o seu Nextcloud e cria um link público';

  @override
  String get csShareLinkInProgress => 'Criando o link…';

  @override
  String get csShareLinkTitle => 'Link público';

  @override
  String get csShareLinkBody =>
      'Qualquer pessoa com este link pode ver o PDF. Você pode revogá-lo no seu Nextcloud.';

  @override
  String get csShareLinkCopied => 'Link copiado para a área de transferência.';

  @override
  String csShareLinkFailed(String error) {
    return 'Falha ao compartilhar: $error';
  }

  @override
  String get csCopyLink => 'Copiar link';

  @override
  String get csShare => 'Compartilhar';

  @override
  String get csRevokeLink => 'Revogar link';

  @override
  String get csRevokeLinkDone => 'Link revogado.';

  @override
  String get csShareLinkUpdate => 'Atualizar o PDF compartilhado';

  @override
  String get csShareLinkUpdated => 'PDF atualizado.';

  @override
  String get csChangeSelectionColor => 'Mudar a cor da seleção';

  @override
  String get csSelectionThickness => 'Espessura da seleção';

  @override
  String csWidthPx(String width) {
    return '$width px';
  }

  @override
  String get csFlipHorizontal => 'Espelhar na horizontal';

  @override
  String get csFlipVertical => 'Espelhar na vertical';

  @override
  String get csCopyAsImage => 'Copiar como imagem';

  @override
  String get csPasteInAnotherNotebook => 'Colar em outro caderno…';

  @override
  String get csKeyDelete => 'Del';

  @override
  String get csCreateSymbol => 'Criar símbolo';

  @override
  String get csSelect => 'Selecionar';

  @override
  String get csImportFile => 'Importar arquivo…';

  @override
  String get csTakePhoto => 'Tirar foto';

  @override
  String get csInsertText => 'Inserir texto';

  @override
  String csInsertSymbolCount(int count) {
    return 'Inserir símbolo ($count)';
  }

  @override
  String get csClearPage => 'Limpar a página';

  @override
  String get csExportPng => 'Exportar PNG';

  @override
  String get csExportPdf => 'Exportar PDF';

  @override
  String get csClearPageConfirmBody =>
      'Todos os elementos desta página serão excluídos. Continuar?';

  @override
  String get csClear => 'Limpar';

  @override
  String get csCreateSymbolTitle => 'Criar símbolo reutilizável';

  @override
  String get csSymbolNameLabel => 'Nome do símbolo';

  @override
  String get csLibraryLabel => 'Biblioteca:';

  @override
  String get csNoLibraryNotice =>
      'Nenhuma biblioteca existente. Uma biblioteca \"Símbolos\" será criada.';

  @override
  String get csCreate => 'Criar';

  @override
  String csSymbolCreated(String name) {
    return 'Símbolo \"$name\" criado!';
  }

  @override
  String csSaveFileDialogTitle(String fileName) {
    return 'Salvar $fileName';
  }

  @override
  String get csExportCurrentPagePng => 'Página atual (PNG)';

  @override
  String get csExportCurrentChapter => 'Capítulo atual';

  @override
  String get csExportEntireNotebook => 'Caderno inteiro';

  @override
  String csExportingPages(int count) {
    return 'Exportando $count páginas...';
  }

  @override
  String csChooseFolderForImages(int count) {
    return 'Escolha uma pasta para as $count imagens';
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
    return 'Erro na exportação: $error';
  }

  @override
  String get csExportCurrentPage => 'Página atual';

  @override
  String csGeneratingPdf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return 'Gerando o PDF ($_temp0)...';
  }

  @override
  String csPdfExportError(String error) {
    return 'Erro na exportação do PDF: $error';
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
  String get csSelectionCopiedAsImage => 'Seleção copiada como imagem';

  @override
  String csCopyImageError(String error) {
    return 'Erro ao copiar a imagem: $error';
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
  String get csExportNotebookTitle => 'Exportar o caderno inteiro';

  @override
  String get csChapterSeparatorQuestion =>
      'Inserir uma página separadora antes de cada capítulo?';

  @override
  String get csYesWithSeparators => 'Sim, com separadores';

  @override
  String get csNoPagesOnly => 'Não, só as páginas';

  @override
  String csTotalPages(int count) {
    return 'Total de páginas: $count';
  }

  @override
  String csFromPage(int page) {
    return 'Da página: $page';
  }

  @override
  String csToPage(int page) {
    return 'Até a página: $page';
  }

  @override
  String csWillExportPages(int count, int start, int end) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas serão exportadas ($start–$end)',
      one: '$count página será exportada ($start–$end)',
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
  String get csGoToPage => 'Ir para a página';

  @override
  String get csDuplicatePage => 'Duplicar a página';

  @override
  String get csNewPageAfter => 'Nova página depois';

  @override
  String get csDeletePageConfirmTitle => 'Excluir a página?';

  @override
  String csDeletePageConfirmBody(int number) {
    return 'A página $number e todo o seu conteúdo serão excluídos.';
  }

  @override
  String get csExportAsPdf => 'Exportar como PDF';

  @override
  String get csExportAsPng => 'Exportar como PNG';

  @override
  String get csExportAsNcnote => 'Exportar como .abelnote (nativo)';

  @override
  String get csExportNcnoteSubtitle =>
      'Formato nativo, qualidade vetorial completa (para backup ou transferência)';

  @override
  String get csGeneratingNcnote => 'Gerando o .abelnote…';

  @override
  String csNcnoteExported(String size) {
    return '.abelnote exportado ($size KB)';
  }

  @override
  String csNcnoteExportError(String error) {
    return 'Erro na exportação do .abelnote: $error';
  }

  @override
  String get csImageOrPdf => 'Imagem ou PDF';

  @override
  String get csChangePaperType => 'Mudar o tipo de papel';

  @override
  String get csPenToMonitor => 'Caneta → Monitor';

  @override
  String get csPenToMonitorSubtitle => 'Restringir a caneta a uma única tela';

  @override
  String get csPaperType => 'Tipo de papel';

  @override
  String get csPaperBlank => 'Em branco';

  @override
  String get csPaperLinedNarrow => 'Linhas estreitas';

  @override
  String get csPaperLinedWide => 'Linhas largas';

  @override
  String get csPaperGrid => 'Quadriculado';

  @override
  String get csPaperDotted => 'Pontilhado';

  @override
  String get csPaperCornell => 'Cornell';

  @override
  String get csPaperIsometric => 'Isométrico';

  @override
  String get csPaperMusic => 'Pauta musical';

  @override
  String get csMapPenToMonitor => 'Associar a caneta a um monitor';

  @override
  String csPenMappedTo(String monitor) {
    return 'Caneta associada a $monitor';
  }

  @override
  String get csAllMonitors => 'Todos os monitores';

  @override
  String get csAllMonitorsSubtitle => 'Redefinir (caneta em todo o desktop)';

  @override
  String get csPenReset => 'Caneta redefinida';

  @override
  String get csShapeLine => 'Linha';

  @override
  String get csShapeCircle => 'Círculo';

  @override
  String get csShapeRectangle => 'Retângulo';

  @override
  String get csShapeTriangle => 'Triângulo';

  @override
  String get csShapeArrow => 'Seta';

  @override
  String get csInvalidRangeError => 'Informe um intervalo válido (ex.: 1–10).';

  @override
  String csPdfStartOutOfRange(int count) {
    return 'O PDF tem cerca de $count páginas. O início está fora do intervalo.';
  }

  @override
  String get csImportPdfTitle => 'Importar PDF';

  @override
  String csPdfEstimatedPages(int count) {
    return 'O PDF tem cerca de $count páginas.';
  }

  @override
  String csAllPagesWithCount(int count) {
    return 'Todas as páginas ($count)';
  }

  @override
  String get csAllPages => 'Todas as páginas';

  @override
  String get csCustomRange => 'Intervalo personalizado';

  @override
  String get csFromLabel => 'De';

  @override
  String get csToLabel => 'Até';

  @override
  String get csImport => 'Importar';

  @override
  String libErrorGeneric(String error) {
    return 'Erro: $error';
  }

  @override
  String libErrorOpen(String error) {
    return 'Erro ao abrir: $error';
  }

  @override
  String get libImportCannotReadFile => 'Não foi possível ler o arquivo';

  @override
  String get libImportInProgress => 'Importando…';

  @override
  String get libServiceUnavailable => 'Serviço indisponível';

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
  String get libImportCorruptedFile =>
      'Este arquivo não é um caderno válido do AbelNotes — pode estar incompleto ou danificado.';

  @override
  String get libExport => 'Exportar';

  @override
  String get libImportOneNoteUnreadable =>
      'O AbelNotes não consegue ler este arquivo do OneNote — ele pode usar um formato que o importador ainda não suporta, ou estar danificado.';

  @override
  String libErrorImport(String error) {
    return 'Erro na importação: $error';
  }

  @override
  String libErrorCreate(String error) {
    return 'Erro ao criar: $error';
  }

  @override
  String get libSketchDefaultTitle => 'Rascunho';

  @override
  String libErrorCreateSketch(String error) {
    return 'Erro ao criar o rascunho: $error';
  }

  @override
  String get libRemoveFromFavorites => 'Remover dos favoritos';

  @override
  String get libAddToFavorites => 'Adicionar aos favoritos';

  @override
  String get libRename => 'Renomear';

  @override
  String get libChangeCover => 'Mudar a capa';

  @override
  String get libMoveToFolder => 'Mover para uma pasta';

  @override
  String get libNoFolder => 'Sem pasta';

  @override
  String get libNewFolder => 'Nova pasta';

  @override
  String get libRenameFolder => 'Renomear a pasta';

  @override
  String get libFolderNameHint => 'Nome da pasta';

  @override
  String get libAllNotebooks => 'Todos';

  @override
  String get libDeleteFolder => 'Excluir a pasta';

  @override
  String libDeleteFolderTitle(String name) {
    return 'Excluir a pasta \"$name\"?';
  }

  @override
  String get libDeleteFolderBody =>
      'Os cadernos dentro dela não são excluídos — ficam na biblioteca, sem pasta.';

  @override
  String get libDelete => 'Excluir';

  @override
  String get libDeleteNotebookTitle => 'Excluir este caderno?';

  @override
  String get libDeleteNotebookBody =>
      'Ele vai para a lixeira. Você pode restaurá-lo em Configurações > Armazenamento.';

  @override
  String get libCancel => 'Cancelar';

  @override
  String get libRenameNotebookTitle => 'Renomear o caderno';

  @override
  String get libSave => 'Salvar';

  @override
  String get libSortTitle => 'Ordenar';

  @override
  String get libAppName => 'AbelNotes';

  @override
  String get libSearchHintShort => 'Buscar…';

  @override
  String get libSearchHintNotebooks => 'Buscar cadernos…';

  @override
  String get libImport => 'Importar';

  @override
  String get libImportTooltip => 'Importar um arquivo .abelnote';

  @override
  String get libSettingsTooltip => 'Configurações';

  @override
  String get libMoreTooltip => 'Mais';

  @override
  String get libViewAsList => 'Visualizar em lista';

  @override
  String get libViewAsGrid => 'Visualizar em grade';

  @override
  String libSortWithLabel(String sortLabel) {
    return 'Ordenar: $sortLabel';
  }

  @override
  String get libImportNcnoteMenu => 'Importar…';

  @override
  String get libYourNotebooks => 'Seus cadernos';

  @override
  String libItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count itens',
      one: '$count item',
    );
    return '$_temp0';
  }

  @override
  String get libNewNotebook => 'Novo caderno';

  @override
  String get libSketches => 'Rascunhos';

  @override
  String get libInfiniteSpace => 'espaço infinito';

  @override
  String get libNewSketch => 'Novo rascunho';

  @override
  String get libInfiniteCanvas => 'Tela infinita';

  @override
  String get libNew => 'Novo';

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
  String get libFooterLocalFirst => 'App local-first';

  @override
  String get libSyncingWithServer => 'Sincronizando com o servidor…';

  @override
  String libDownloadingProgress(int done, int total) {
    return 'Baixando $done/$total cadernos…';
  }

  @override
  String get libLoadingNotebooks => 'Carregando os cadernos…';

  @override
  String get libLoadingNotebooksFromServer =>
      'Carregando os cadernos do servidor…';

  @override
  String get libTimeNow => 'agora';

  @override
  String libTimeMinutesAgo(int count) {
    return 'há $count min';
  }

  @override
  String libTimeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count horas',
      one: 'há $count hora',
    );
    return '$_temp0';
  }

  @override
  String libTimeDaysAgo(int count) {
    return 'há ${count}d';
  }

  @override
  String libTimeWeeksAgo(int count) {
    return 'há $count sem';
  }

  @override
  String libTimeMonthsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count meses',
      one: 'há $count mês',
    );
    return '$_temp0';
  }

  @override
  String libTimeYearsAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'há $count anos',
      one: 'há $count ano',
    );
    return '$_temp0';
  }

  @override
  String get libNotebookTitleLabel => 'Título';

  @override
  String get libCoverLabel => 'Capa';

  @override
  String get libPaperLabel => 'Papel';

  @override
  String get libPaperBlank => 'Em branco';

  @override
  String get libPaperLined => 'Com linhas';

  @override
  String get libPaperGrid => 'Quadriculado';

  @override
  String get libPaperDotted => 'Pontilhado';

  @override
  String get libCreate => 'Criar';

  @override
  String get setSectionGeneral => 'Geral';

  @override
  String get setSectionInput => 'Caneta e entrada';

  @override
  String get setSectionSync => 'Sincronização';

  @override
  String get setSectionStorage => 'Armazenamento';

  @override
  String get setSectionShortcuts => 'Atalhos';

  @override
  String get setSectionAdvanced => 'Avançado';

  @override
  String get setSectionAbout => 'Sobre';

  @override
  String get setBackToLibrary => 'Biblioteca';

  @override
  String get setSettingsTitle => 'Configurações';

  @override
  String get setThemeLabel => 'Tema';

  @override
  String get setThemeLight => 'Claro';

  @override
  String get setThemePaper => 'Papel';

  @override
  String get setThemeDark => 'Escuro';

  @override
  String get setLanguage => 'Idioma';

  @override
  String get setLanguageSub => 'Idioma da interface';

  @override
  String get setLanguageItalian => 'Italiano';

  @override
  String get setFavoritesFirst => 'Favoritos primeiro';

  @override
  String get setFavoritesFirstSub =>
      'Mostrar os cadernos favoritos no topo da biblioteca';

  @override
  String get setStylusOnly => 'Somente caneta';

  @override
  String get setStylusOnlySub =>
      'Ignora o toque do dedo durante a escrita. Pinçar e arrastar continuam funcionando com dois dedos.';

  @override
  String get setPalmRejection => 'Rejeição de palma';

  @override
  String get setPalmRejectionSub => 'Detecção automática da palma apoiada';

  @override
  String get setPressureThickness => 'Pressão → espessura';

  @override
  String get setPressureThicknessSub =>
      'Modulação do traço conforme a pressão da caneta';

  @override
  String get setTiltCalligraphy => 'Inclinação → caligrafia';

  @override
  String get setTiltCalligraphySub =>
      'A inclinação da caneta muda a largura e o ângulo do traço';

  @override
  String get setStrokeContinuation => 'Continuação do traço';

  @override
  String get setStrokeContinuationSub =>
      'Compensa interrupções breves do sensor (ex.: o ponto do i)';

  @override
  String get setSyncConnectedDesc =>
      'Conectado a um servidor WebDAV. Os cadernos sincronizam em todos os seus dispositivos.';

  @override
  String get setSyncLocalOnlyDesc =>
      'Modo somente local: os cadernos ficam neste dispositivo. Conecte um servidor WebDAV para acessá-los de vários dispositivos.';

  @override
  String get setSyncWebdav => 'WebDAV';

  @override
  String get setSyncLocalOnly => 'Somente local';

  @override
  String setSyncAccountInfo(String host, String username) {
    return '$host · $username';
  }

  @override
  String get setSyncNoServer => 'Nenhum servidor conectado';

  @override
  String get setDisconnect => 'Desconectar';

  @override
  String get setConnect => 'Conectar';

  @override
  String get setDisconnectTitle => 'Desconectar o servidor?';

  @override
  String get setDisconnectBody =>
      'Os cadernos já baixados ficam neste dispositivo. A sincronização para até você reconectar.';

  @override
  String get setCheckCert => 'Verificar o certificado do servidor';

  @override
  String get setCertCheckFailed =>
      'Não foi possível verificar o certificado do servidor.';

  @override
  String get setCertUnchanged =>
      'O certificado não mudou desde a última conexão.';

  @override
  String get setCertChangedTitle => 'Novo certificado detectado';

  @override
  String setCertChangedBody(String oldFingerprint, String newFingerprint) {
    return 'O servidor está apresentando uma impressão digital diferente da que foi salva. Se você mesmo renovou o certificado, confirme para continuar sincronizando. Se não, CANCELE e verifique a sua rede antes de tentar de novo.\n\nImpressão digital salva: $oldFingerprint\nImpressão digital atual: $newFingerprint';
  }

  @override
  String get setCertConfirmNew => 'Confirmar o novo certificado';

  @override
  String get setCancel => 'Cancelar';

  @override
  String get setShortcutPen => 'Caneta';

  @override
  String get setShortcutUndo => 'Desfazer';

  @override
  String get setShortcutBrush => 'Pincel';

  @override
  String get setShortcutRedo => 'Refazer';

  @override
  String get setShortcutEraser => 'Borracha';

  @override
  String get setShortcutSelectAll => 'Selecionar tudo';

  @override
  String get setShortcutLasso => 'Laço';

  @override
  String get setShortcutCopy => 'Copiar';

  @override
  String get setShortcutHand => 'Mão';

  @override
  String get setShortcutCut => 'Recortar';

  @override
  String get setShortcutText => 'Texto';

  @override
  String get setShortcutPaste => 'Colar';

  @override
  String get setShortcutShape => 'Forma';

  @override
  String get setShortcutDuplicate => 'Duplicar';

  @override
  String get setShortcutChangePage => 'Mudar de página';

  @override
  String get setShortcutSave => 'Salvar';

  @override
  String get setShortcutFit => 'Ajustar';

  @override
  String get setShortcutCheatSheet => 'Resumo';

  @override
  String get setKeyboardShortcutsTitle => 'Atalhos de teclado';

  @override
  String get setClearCache => 'Limpar o cache';

  @override
  String get setClearCacheSub =>
      'Remove arquivos temporários. Os cadernos não são afetados.';

  @override
  String get setClear => 'Limpar';

  @override
  String get setTrash => 'Lixeira';

  @override
  String get setTrashSub => 'Cadernos excluídos, ainda restauráveis';

  @override
  String get setOpenTrash => 'Abrir a lixeira';

  @override
  String get setClearCacheDone => 'Cache limpo.';

  @override
  String get setExportLibrary => 'Exportar a biblioteca';

  @override
  String get setExportLibrarySub =>
      'Salva todos os cadernos em um único arquivo zip.';

  @override
  String get setExport => 'Exportar';

  @override
  String get setExportLibraryEmpty => 'Nenhum caderno para exportar.';

  @override
  String get setExportLibraryInProgress => 'Exportando…';

  @override
  String setExportLibraryDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exportados $count cadernos',
      one: 'Exportado $count caderno',
    );
    return '$_temp0.';
  }

  @override
  String setExportLibraryFailed(String error) {
    return 'Falha na exportação: $error';
  }

  @override
  String setTrashPurgeTitle(String title) {
    return 'Excluir \"$title\" definitivamente?';
  }

  @override
  String get setTrashPurgeBody => 'Não será possível recuperá-lo.';

  @override
  String get setTrashPurge => 'Excluir para sempre';

  @override
  String get setTrashEmptyTitle => 'Esvaziar a lixeira?';

  @override
  String get setTrashEmptyBody =>
      'Todos os cadernos na lixeira serão excluídos definitivamente.';

  @override
  String get setTrashEmpty => 'Esvaziar a lixeira';

  @override
  String get setTrashEmptyState => 'A lixeira está vazia.';

  @override
  String setTrashDeletedAgo(String time) {
    return 'Excluído há $time';
  }

  @override
  String get setTrashRestore => 'Restaurar';

  @override
  String get setAdvancedIntro =>
      'Ferramentas de recuperação para os casos raros de um caderno travado na sincronização. Use-as só se a sincronização continuar falhando depois de um \"Forçar sincronização\" normal na biblioteca.';

  @override
  String get setForceReloadTitle =>
      'Forçar o recarregamento do caderno do servidor';

  @override
  String get setForceReloadDesc =>
      'Baixa de novo todo o conteúdo do caderno da pasta delta do servidor e sobrescreve a cópia local. Útil se a contagem de páginas parecer errada ou o caderno não abrir. Nenhum dado é perdido no servidor.';

  @override
  String setErrorGeneric(String error) {
    return 'Erro: $error';
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
  String get setReload => 'Recarregar';

  @override
  String get setCloseNotebookFirst =>
      'Feche o caderno antes de recarregá-lo do servidor.';

  @override
  String setReloadConfirmTitle(String title) {
    return 'Recarregar \"$title\"?';
  }

  @override
  String get setReloadConfirmBody =>
      'Baixa de novo metadados, documento, páginas e recursos da pasta delta do servidor. A cópia local é substituída.\n\nAs alterações locais ainda não sincronizadas serão perdidas. Continuar?';

  @override
  String setReloadInProgress(String title) {
    return 'Recarregando \"$title\"…';
  }

  @override
  String get setNotConnectedWebdav => 'Não conectado a um servidor WebDAV.';

  @override
  String setReloadDone(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return '\"$title\" recarregado — $_temp0.';
  }

  @override
  String setReloadFailed(String error) {
    return 'Falha ao recarregar: $error';
  }

  @override
  String get setAboutTagline => 'Um app de escrita à mão local-first.';

  @override
  String get setAboutOffline =>
      'Funciona offline; a sincronização WebDAV é opcional.';

  @override
  String setAboutVersion(String version, String commit) {
    return 'Versão $version · build $commit';
  }

  @override
  String get setReportProblem => 'Relatar um problema';

  @override
  String get setReportProblemSub =>
      'Copia o log de erros para a área de transferência, para anexar ao seu relato.';

  @override
  String get setCopyLog => 'Copiar o log';

  @override
  String get setReportProblemEmpty => 'Nenhum erro registrado.';

  @override
  String get setCopyLogDone => 'Log copiado para a área de transferência.';

  @override
  String get onbTagline =>
      'Notas à mão e desenho livre, sincronizados com o SEU servidor. Escolha como começar — pode mudar depois.';

  @override
  String get onbTryNowTitle => 'Experimente agora';

  @override
  String get onbTryNowSubtitle =>
      'Comece a escrever já. Os cadernos ficam neste dispositivo — sem conta, sem servidor.';

  @override
  String get onbConnectNextcloudTitle => 'Conecte o seu Nextcloud';

  @override
  String get onbConnectNextcloudSubtitle =>
      'Sincronize com o seu servidor WebDAV / Nextcloud pessoal e acesse de todos os seus dispositivos.';

  @override
  String get onbManagedServerTitle => 'Servidor gerenciado AbelNotes';

  @override
  String get onbManagedServerSubtitle =>
      'Não tem um servidor? Em breve você poderá usar o nosso, sem nada para configurar.';

  @override
  String get onbComingSoonBadge => 'Em breve';

  @override
  String get onbDriveTitle => 'Sincronizar com o Google Drive';

  @override
  String get onbDriveSubtitle =>
      'Nada para configurar: seus cadernos sincronizam pelo seu próprio Google Drive.';

  @override
  String get driveSignInFailed =>
      'O login do Google não foi concluído. Nada foi alterado.';

  @override
  String get driveSignInCancelled => 'Login cancelado.';

  @override
  String get driveNotConfigured =>
      'Esta build não tem credenciais do Google, então a sincronização com o Drive não está disponível.';

  @override
  String get driveNoKeyring =>
      'Este sistema não tem armazenamento seguro, então a conta do Google não pode ser guardada com segurança. A sincronização com o Drive não está disponível aqui.';

  @override
  String get driveConnectedTitle => 'Google Drive conectado';

  @override
  String get setSyncDriveTitle => 'Google Drive';

  @override
  String get setSyncDriveConnected =>
      'Os cadernos sincronizam pelo seu Google Drive.';

  @override
  String get setSyncDriveNotConnected => 'Não conectado.';

  @override
  String get setSyncDriveDesktopOnly =>
      'Por enquanto disponível no computador.';

  @override
  String get setDriveDisconnectTitle => 'Desconectar o Google Drive?';

  @override
  String get setDriveDisconnectBody =>
      'Os cadernos que já estão no seu Drive continuam lá — este app só para de sincronizar com eles. Os cadernos neste dispositivo não são afetados.';

  @override
  String get setDriveDisconnectConfirm => 'Desconectar';

  @override
  String get setSyncOneBackendNote =>
      'Os cadernos sincronizam com um destino por vez: o seu próprio servidor ou o seu Google Drive.';

  @override
  String get setSyncSwitchTitle =>
      'Passar a sincronização para o Google Drive?';

  @override
  String get setSyncSwitchBody =>
      'Seus cadernos ficam neste dispositivo e são enviados para o seu Google Drive. As cópias que já estão no seu servidor permanecem onde estão, mas param de receber atualizações a partir de agora. Nada é excluído.';

  @override
  String get setSyncSwitchConfirm => 'Passar para o Drive';

  @override
  String get setSyncInactiveNote =>
      'Configurado, mas não em uso: a sincronização está indo para o outro destino.';

  @override
  String libPendingUploadsDrive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos ainda para enviar ao Google Drive',
      one: '$count caderno ainda para enviar ao Google Drive',
    );
    return '$_temp0';
  }

  @override
  String libPendingUploadsServer(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos ainda para enviar ao seu servidor',
      one: '$count caderno ainda para enviar ao seu servidor',
    );
    return '$_temp0';
  }

  @override
  String get libPendingUploadsHint =>
      'Enquanto isso, eles ficam neste dispositivo. Deixe o app aberto um instante.';

  @override
  String get libStorageFullDrive => 'O seu Google Drive está cheio';

  @override
  String get libStorageFullServer => 'O seu servidor está sem espaço';

  @override
  String get libStorageFullBody =>
      'Os cadernos ficam a salvo neste dispositivo, mas não podem ser enviados até você liberar espaço. O espaço do Google Drive é compartilhado com o Gmail e o Fotos.';

  @override
  String get libStorageFullBodyServer =>
      'Os cadernos ficam a salvo neste dispositivo, mas não podem ser enviados até que se libere espaço no servidor.';

  @override
  String get libLocalOnlyTitle => 'Somente neste dispositivo';

  @override
  String get libLocalOnlyBody =>
      'Seus cadernos ficam neste dispositivo. Conecte o seu servidor ou o Google Drive para tê-los em todos os lugares — pode fazer isso quando quiser.';

  @override
  String get libKeepOnDevice => 'Manter somente neste dispositivo';

  @override
  String get libResumeSync => 'Voltar a sincronizar este caderno';

  @override
  String get libLocalOnlyBadge => 'Somente neste dispositivo';

  @override
  String get libKeepOnDeviceTitle =>
      'Manter este caderno somente neste dispositivo?';

  @override
  String get libKeepOnDeviceBody =>
      'Ele deixa de ser enviado, e os outros dispositivos não vão mais recebê-lo. Aqui continua totalmente utilizável.';

  @override
  String get libKeepOnDeviceRemoveCopy => 'Excluir também a cópia já enviada';

  @override
  String get libKeepOnDeviceConfirm => 'Manter só aqui';

  @override
  String get libLocalOnlyDone => 'Mantido somente neste dispositivo.';

  @override
  String get libSyncResumedDone => 'Este caderno vai voltar a sincronizar.';

  @override
  String get syncLocalOnlyTooltip => 'Mantido somente neste dispositivo';

  @override
  String get libFreeSpace => 'Liberar espaço neste dispositivo';

  @override
  String get libKeepOnThisDevice => 'Baixar para este dispositivo';

  @override
  String get libFreeSpaceTitle => 'Remover este caderno deste dispositivo?';

  @override
  String get libFreeSpaceBody =>
      'O caderno continua no destino remoto e nos seus outros dispositivos. Aqui ele passa a ser um cartão que você pode tocar para baixá-lo de novo. Até você fazer isso, não é possível abri-lo offline e a busca não olha dentro dele.';

  @override
  String get libFreeSpaceConfirm => 'Liberar espaço';

  @override
  String libFreeSpaceDone(String size) {
    return 'Removido deste dispositivo. $size liberados.';
  }

  @override
  String get libFreeSpaceNotSynced =>
      'Este caderno tem alterações que o destino remoto ainda não tem. Será possível depois que forem enviadas.';

  @override
  String get libFreeSpaceOpenNotebook => 'Feche o caderno primeiro.';

  @override
  String get libKeepOnThisDeviceDone =>
      'Ele será baixado para este dispositivo de novo.';

  @override
  String get syncNotOnDeviceTooltip =>
      'No destino remoto, não neste dispositivo';

  @override
  String get onbSyncQuestion => 'Sincronize suas notas';

  @override
  String get onbSyncQuestionSub =>
      'Escolha onde os seus cadernos vão ficar. Você pode mudar isso depois.';

  @override
  String get onbDriveShort => 'Google Drive';

  @override
  String get onbNextcloudShort => 'Nextcloud / WebDAV';

  @override
  String get onbStartWithoutSync => 'Começar sem sincronizar';

  @override
  String get onbDriveUnavailable => 'Não disponível nesta build';

  @override
  String get onbLicenseNote =>
      'Ao abrir o app você aceita a licença AGPL-3.0. \"AbelNotes\" é uma marca do projeto.';

  @override
  String get logConnectionFailed =>
      'Não foi possível conectar. Verifique a URL, o nome de usuário e a senha.';

  @override
  String logConnectionError(String error) {
    return 'Erro de conexão: $error';
  }

  @override
  String get logCertificateChanged =>
      'O certificado do servidor mudou desde a última conexão. Se foi você (ex.: renovação do certificado), vá em Configurações > Sincronização para confirmar a nova impressão digital.';

  @override
  String get logCertConfirmTitle => 'Verificar a identidade do servidor';

  @override
  String get logCertConfirmBody =>
      'Primeira conexão com este servidor. Compare esta impressão digital com a do seu servidor (ex.: pela linha de comando) antes de continuar:';

  @override
  String get logCertConfirmTrust => 'Eu confio, continuar';

  @override
  String get logBackTooltip => 'Voltar';

  @override
  String get logTitle => 'Conecte o seu Nextcloud';

  @override
  String get logSubtitle =>
      'Qualquer servidor WebDAV / Nextcloud (VPS, self-hosted, rede local). Nenhuma nuvem de terceiros.';

  @override
  String get logServerUrlLabel => 'URL do servidor';

  @override
  String get logServerUrlHint => 'https://cloud.exemplo.com';

  @override
  String get logServerUrlRequired => 'Informe a URL do servidor';

  @override
  String get logServerUrlInvalid => 'Precisa começar com http:// ou https://';

  @override
  String get logUsernameLabel => 'Nome de usuário';

  @override
  String get logUsernameRequired => 'Nome de usuário obrigatório';

  @override
  String get logPasswordLabel => 'Senha / senha de aplicativo';

  @override
  String get logPasswordRequired => 'Senha obrigatória';

  @override
  String get logAppPasswordHint =>
      'Recomendado: uma senha de aplicativo gerada nas configurações do Nextcloud.';

  @override
  String get logServerTypeNextcloud => 'Nextcloud / ownCloud';

  @override
  String get logServerTypeWebdav => 'Outro WebDAV';

  @override
  String get logServerUrlHintWebdav => 'https://dav.exemplo.com/pasta';

  @override
  String get logWebdavExperimental =>
      'Os backends WebDAV genéricos (Synology, Seafile, rclone…) são experimentais: só o Nextcloud é totalmente testado. Mantenha backups dos seus cadernos.';

  @override
  String get logWebdavUrlHint =>
      'URL WebDAV completa, com o caminho — ex.: Synology https://nas:5006/home, Seafile https://servidor/seafdav. O compartilhamento por link não está disponível no WebDAV genérico.';

  @override
  String get logConnectButton => 'Conectar';

  @override
  String get chromeBackToLibraryTooltip => 'Voltar para a biblioteca';

  @override
  String get chromeLibrary => 'Biblioteca';

  @override
  String get chromeUnsaved => 'Não salvo';

  @override
  String get chromeMouseDrawsTooltip =>
      'Mouse: desenha — toque para usá-lo na seleção';

  @override
  String get chromeMouseSelectsTooltip =>
      'Mouse: seleção — toque para desenhar com o mouse';

  @override
  String get chromeTouchDrawsTooltip =>
      'Dedo: desenha — toque para usá-lo para arrastar a tela';

  @override
  String get chromeTouchPansTooltip =>
      'Dedo: arrasta a tela — toque para desenhar com o dedo';

  @override
  String get chromeUndo => 'Desfazer';

  @override
  String get chromeRedo => 'Refazer';

  @override
  String get chromeAllPages => 'Todas as páginas';

  @override
  String chromePageIndicator(String current, int total) {
    return '$current / $total';
  }

  @override
  String get chromeAddPage => 'Adicionar página';

  @override
  String get chromeSymbols => 'Símbolos';

  @override
  String get chromeExport => 'Exportar';

  @override
  String get chromeMore => 'Mais';

  @override
  String get chromeMoreEllipsis => 'Mais…';

  @override
  String get chromeToolPen => 'Caneta · P';

  @override
  String get chromeToolHighlighter => 'Marca-texto';

  @override
  String get chromeToolEraser => 'Borracha · E';

  @override
  String get chromeToolLasso => 'Laço · L';

  @override
  String get chromeToolText => 'Texto · T';

  @override
  String get chromeToolLaser => 'Laser';

  @override
  String get chromeToolPan => 'Mão · H';

  @override
  String get chromeDragToMoveBar => 'Arraste para mover a barra de ferramentas';

  @override
  String get chromeShapeGuessOn => 'Formas automáticas · ligado';

  @override
  String get chromeShapeGuessOff => 'Formas automáticas · desligado';

  @override
  String get chromeLabelPen => 'Caneta';

  @override
  String get chromeLabelBallpoint => 'Esferográfica';

  @override
  String get chromeLabelBrush => 'Pincel';

  @override
  String get chromeLabelCalligraphy => 'Caligrafia';

  @override
  String get chromeLabelEraser => 'Borracha';

  @override
  String get chromeLabelLasso => 'Laço';

  @override
  String get chromeLabelText => 'Texto';

  @override
  String get chromeLabelShape => 'Forma';

  @override
  String get chromeLabelImage => 'Imagem';

  @override
  String get chromeLabelPan => 'Mão';

  @override
  String get chromePresetsSection => 'Predefinições';

  @override
  String get chromePresetHint => 'Toque e segure para salvar/limpar';

  @override
  String get chromeColorSection => 'Cor';

  @override
  String get chromeColorEditHint => 'Toque e segure uma cor para mudá-la';

  @override
  String get chromeThicknessSection => 'Espessura';

  @override
  String chromeThicknessPx(String value) {
    return '$value px';
  }

  @override
  String get chromePreview => 'Prévia';

  @override
  String get chromeModeSection => 'Modo';

  @override
  String get chromeEraserPerArea => 'Por área';

  @override
  String get chromeEraserPerStroke => 'Por traço';

  @override
  String get chromeSizeSection => 'Tamanho';

  @override
  String get chromeSizeSmall => 'P';

  @override
  String get chromeSizeMedium => 'M';

  @override
  String get chromeSizeLarge => 'G';

  @override
  String get chromePresetOverwrite => 'Sobrescrever com o atual';

  @override
  String get chromePresetClearSlot => 'Limpar o espaço';

  @override
  String get chromeNoPages => 'Nenhuma página';

  @override
  String get chromeHidePageBar => 'Ocultar a barra de páginas';

  @override
  String get chromeShowPageBar => 'Mostrar a barra de páginas';

  @override
  String chromePrevPageTooltip(int number) {
    return 'Página anterior $number — toque para voltar';
  }

  @override
  String chromePageOfChapterTooltip(int number, int globalNumber) {
    return 'Página $number do capítulo · página $globalNumber do caderno';
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
  String get pmNone => 'Nenhum';

  @override
  String get pmCreateChapterFirst => 'Crie pelo menos um capítulo antes.';

  @override
  String pmAssignChapterCount(int count) {
    return 'Atribuir capítulo ($count pág.)';
  }

  @override
  String pmDeletePagesConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluir $count páginas?',
      one: 'Excluir 1 página?',
    );
    return '$_temp0';
  }

  @override
  String get pmActionCannotBeUndone => 'Esta ação não pode ser desfeita.';

  @override
  String get pmCancel => 'Cancelar';

  @override
  String get pmDelete => 'Excluir';

  @override
  String pmPagesCut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count páginas recortadas — abra o caderno de destino para colar.',
      one: '1 página recortada — abra o caderno de destino para colar.',
    );
    return '$_temp0';
  }

  @override
  String pmPagesCutSkipped(int count, int skipped) {
    return '$count páginas recortadas ($skipped ainda não carregadas, ignoradas) — abra o caderno de destino para colar.';
  }

  @override
  String pmSelectedCount(int count) {
    return '$count selecionadas';
  }

  @override
  String get pmSelectAllButton => 'Todas';

  @override
  String get pmClearSelection => 'Limpar a seleção';

  @override
  String pmPagesCount(int count) {
    return 'Páginas ($count)';
  }

  @override
  String pmPagesFilteredCount(int visible, int total) {
    return 'Páginas ($visible/$total)';
  }

  @override
  String get pmGoToPageTooltip => 'Ir para a página…';

  @override
  String get pmExitSelection => 'Sair da seleção';

  @override
  String get pmSelectPages => 'Selecionar páginas';

  @override
  String get pmPastePages => 'Colar páginas';

  @override
  String pmPagesPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas coladas.',
      one: '1 página colada.',
    );
    return '$_temp0';
  }

  @override
  String get pmAddPage => 'Adicionar página';

  @override
  String get pmClose => 'Fechar';

  @override
  String get pmNewChapter => 'Novo capítulo';

  @override
  String get pmChapterNameHint => 'Nome do capítulo';

  @override
  String pmPageDeleted(int number) {
    return 'Página $number excluída';
  }

  @override
  String get pmUndo => 'Desfazer';

  @override
  String get pmAssignChapter => 'Atribuir capítulo';

  @override
  String get pmRename => 'Renomear';

  @override
  String get pmRenameChapter => 'Renomear o capítulo';

  @override
  String get pmDeleteChapter => 'Excluir o capítulo';

  @override
  String pmDeleteChapterConfirm(String title) {
    return 'Excluir \"$title\"? As páginas dele continuam, mas sem capítulo.';
  }

  @override
  String get pmGoToPage => 'Ir para a página';

  @override
  String pmPageRangeHint(int max) {
    return '1–$max';
  }

  @override
  String get pmGo => 'Ir';

  @override
  String get pmOk => 'OK';

  @override
  String pmCountPagesShort(int count) {
    return '$count pág.';
  }

  @override
  String get pmChapter => 'Capítulo';

  @override
  String get pmCut => 'Recortar';

  @override
  String get pmInsertBefore => 'Inserir antes';

  @override
  String get pmInsertAfter => 'Inserir depois';

  @override
  String get pmDuplicate => 'Duplicar';

  @override
  String get pmMoveTo => 'Mover para a página…';

  @override
  String get pmMove => 'Mover';

  @override
  String get pmMoveToPage => 'Mover para a página';

  @override
  String get pmChapterEllipsis => 'Capítulo…';

  @override
  String pmPageChapterLabel(int number, String chapter) {
    return '$number • $chapter';
  }

  @override
  String get pmCorruptAssetTooltip =>
      'Recurso corrompido no servidor (truncado) — importe o PDF original de novo para recuperar';

  @override
  String get pmLoadingImageTooltip => 'Carregando a imagem do servidor…';

  @override
  String get tedInsertTextTitle => 'Inserir texto';

  @override
  String get tedEditTextTitle => 'Editar texto';

  @override
  String get tedBoldTooltip => 'Negrito (Ctrl+B)';

  @override
  String get tedItalicTooltip => 'Itálico (Ctrl+I)';

  @override
  String get tedUnderlineTooltip => 'Sublinhado (Ctrl+U)';

  @override
  String get tedStrikethroughTooltip => 'Riscado';

  @override
  String get tedAlignLeft => 'Esquerda';

  @override
  String get tedAlignCenter => 'Centro';

  @override
  String get tedAlignRight => 'Direita';

  @override
  String get tedWriteHereHint => 'Escreva aqui…';

  @override
  String get tedCancel => 'Cancelar';

  @override
  String get tedInsert => 'Inserir';

  @override
  String get cropTitle => 'Recortar imagem';

  @override
  String get cropCancel => 'Cancelar';

  @override
  String get cropConfirm => 'Recortar';

  @override
  String get imgFontSmaller => 'Texto menor';

  @override
  String get imgFontLarger => 'Texto maior';

  @override
  String get imgCrop => 'Recortar';

  @override
  String get imgCopy => 'Copiar';

  @override
  String get imgUnlock => 'Desbloquear';

  @override
  String get imgLock => 'Bloquear';

  @override
  String get imgDelete => 'Excluir';

  @override
  String get imgDeselect => 'Desmarcar';

  @override
  String get imgMoreActions => 'Mais ações';

  @override
  String get imgBringToFront => 'Trazer para a frente';

  @override
  String get imgSendToBack => 'Enviar para trás';

  @override
  String get imgComment => 'Comentário';

  @override
  String get imgFlipHChecked => 'Espelhar H ✓';

  @override
  String get imgFlipH => 'Espelhar H';

  @override
  String get imgCut => 'Recortar';

  @override
  String get syncOkTooltip => 'Sincronizado';

  @override
  String get syncPendingTooltip => 'Sincronizando…';

  @override
  String get syncOfflineTooltip => 'Offline';

  @override
  String get syncConflictTooltip => 'Conflito';

  @override
  String get confDecideLater => 'Decidir depois';

  @override
  String confTitlePageDeletedElsewhere(int pageNumber) {
    return 'Página $pageNumber excluída em outro lugar';
  }

  @override
  String confTitleConflictPage(int pageNumber) {
    return 'Conflito — Página $pageNumber';
  }

  @override
  String get confDeletionExplainer =>
      'Você editou esta página, mas outro dispositivo a excluiu. Quer mantê-la ou excluí-la?';

  @override
  String get confKeepPage => 'Manter a página';

  @override
  String get confLocalYours => 'Local (sua)';

  @override
  String get confRemoteOtherDevice => 'Remota (outro dispositivo)';

  @override
  String get confKeepAllLocal => 'Manter todas as locais';

  @override
  String get confAcceptAllRemote => 'Aceitar todas as remotas';

  @override
  String confProgressIndicator(int current, int total, num decided) {
    String _temp0 = intl.Intl.pluralLogic(
      decided,
      locale: localeName,
      other: '$decided decididas',
      one: '$decided decidida',
    );
    return '$current / $total  ($_temp0)';
  }

  @override
  String get confApplyChoices => 'Aplicar as escolhas';

  @override
  String confDecidedProgress(int decided, num total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'decididas',
      one: 'decidida',
    );
    return '$decided/$total $_temp0';
  }

  @override
  String get confJumpToConflict => 'Ir para o conflito';

  @override
  String confJumpDecidedCount(int decided, int total) {
    return '$decided/$total decididas';
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
  String get confDismissDialogTitle => 'Cancelar?';

  @override
  String get confDismissDialogBody =>
      'As escolhas não aplicadas serão perdidas. A versão local será mantida.';

  @override
  String get confContinue => 'Continuar';

  @override
  String get confCancel => 'Cancelar';

  @override
  String get confModifiedJustNow => 'Agora mesmo';

  @override
  String confModifiedMinutesAgo(int minutes) {
    return 'há $minutes min';
  }

  @override
  String confModifiedHoursAgo(num hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: 'há $hours horas',
      one: 'há $hours hora',
    );
    return '$_temp0';
  }

  @override
  String get confDeletePage => 'Excluir a página';

  @override
  String get confAsOnOtherDevice => 'Como no outro dispositivo';

  @override
  String get symNewLibraryTitle => 'Nova biblioteca';

  @override
  String get symNewLibraryHint => 'Informe o nome da biblioteca';

  @override
  String get symRenameLibraryTitle => 'Renomear a biblioteca';

  @override
  String get symNewNameHint => 'Novo nome';

  @override
  String get symDeleteLibraryTitle => 'Excluir a biblioteca';

  @override
  String symDeleteLibraryConfirm(String name) {
    return 'Excluir \"$name\" e todos os seus símbolos?';
  }

  @override
  String get symCancel => 'Cancelar';

  @override
  String get symDelete => 'Excluir';

  @override
  String get symRenameSymbolTitle => 'Renomear o símbolo';

  @override
  String get symPanelTitle => 'Bibliotecas de símbolos';

  @override
  String get symNoLibraries => 'Nenhuma biblioteca';

  @override
  String get symNew => 'Nova';

  @override
  String get symSelectLibrary => 'Selecione uma biblioteca';

  @override
  String get symNoSymbolsHint =>
      'Nenhum símbolo\nSelecione elementos com o laço e toque em ✚';

  @override
  String get symLassoSaveHint =>
      'Selecione elementos com o laço → ✚ para salvar na biblioteca ativa';

  @override
  String get symRename => 'Renomear';

  @override
  String get symInsert => 'Inserir';

  @override
  String get symOk => 'OK';

  @override
  String get rcbBannerTitle => 'Alterações de outro dispositivo';

  @override
  String get rcbSeeDetails => 'Ver detalhes';

  @override
  String get rcbDismiss => 'Ignorar';

  @override
  String get rcbIncomingChanges => 'Alterações recebidas';

  @override
  String get rcbTapPageHint => 'Toque em uma página para aplicar e ir até ela';

  @override
  String rcbNewImagesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imagens novas',
      one: '1 imagem nova',
    );
    return '$_temp0';
  }

  @override
  String get rcbKeepMine => 'Manter as minhas';

  @override
  String get rcbApplyAll => 'Aplicar todas';

  @override
  String get rcbBadgeNew => 'NOVA';

  @override
  String get rcbBadgeModified => 'MODIFICADA';

  @override
  String rcbPageTitle(int pageNumber) {
    return 'Página $pageNumber';
  }

  @override
  String get rcbContentUpdated => 'Conteúdo atualizado';

  @override
  String rcbSummaryModifiedPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas modificadas',
      one: '$count página modificada',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryNewPages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count novas',
      one: '$count nova',
    );
    return '$_temp0';
  }

  @override
  String rcbSummaryImages(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imagens',
      one: '$count imagem',
    );
    return '$_temp0';
  }

  @override
  String get rcbChangesDetected => 'Alterações detectadas';

  @override
  String get nbUntitled => 'Sem título';

  @override
  String get nbDefaultChapterTitle => 'Capítulo 1';

  @override
  String get nbOpeningNotebook => 'Abrindo o caderno…';

  @override
  String get nbNoLocalCopyOffline =>
      'Não há cópia local deste caderno, e você não está conectado a um servidor para baixá-lo.';

  @override
  String nbOpenFailed(String error) {
    return 'Não foi possível abrir: $error';
  }

  @override
  String get nbSortModifiedDesc => 'Modificação (mais recente primeiro)';

  @override
  String get nbSortModifiedAsc => 'Modificação (mais antiga primeiro)';

  @override
  String get nbSortTitleAsc => 'Título A→Z';

  @override
  String get nbSortTitleDesc => 'Título Z→A';

  @override
  String get nbSortCreatedDesc => 'Criação (mais recente primeiro)';

  @override
  String get nbSortCreatedAsc => 'Criação (mais antiga primeiro)';

  @override
  String get nbSortColorGroup => 'Cor da capa';

  @override
  String cvFormatTooNew(int fileVersion, int supportedVersion) {
    return 'Este caderno usa um formato mais novo (v$fileVersion, suportado: v$supportedVersion). Atualize o AbelNotes para abri-lo.';
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
  String get chromeLabelHighlighter => 'Marca-texto';

  @override
  String get chromeLabelLaser => 'Laser';

  @override
  String get importSourceTitle => 'Importar para a biblioteca';

  @override
  String get importSourceNcnote => 'Caderno .abelnote';

  @override
  String get importSourceObsidian => 'Vault do Obsidian';

  @override
  String get importSourceObsidianHint => 'Pasta com arquivos Markdown';

  @override
  String get importSourceNotion => 'Exportação do Notion';

  @override
  String get importSourceNotionHint => 'Arquivo .zip (Markdown e CSV)';

  @override
  String get importPhaseScanning => 'Analisando a origem…';

  @override
  String importPhaseParsing(int current, int total) {
    return 'Lendo o arquivo $current de $total';
  }

  @override
  String importPhasePaginating(int current, int total) {
    return 'Montando o capítulo $current de $total';
  }

  @override
  String get importPhasePackaging => 'Criando o caderno…';

  @override
  String get importCancel => 'Cancelar';

  @override
  String get importCancelled => 'Importação cancelada';

  @override
  String importReportTitle(int count) {
    return '$count avisos na importação';
  }

  @override
  String get importReportCopy => 'Copiar';

  @override
  String get importReportClose => 'Fechar';

  @override
  String get importSourceOneNote => 'Arquivo do OneNote';

  @override
  String get importSourceOneNoteHint => 'Seção .one ou caderno .onetoc2';

  @override
  String get setOpenSourceLicenses => 'Licenças de código aberto';

  @override
  String get setOpenSourceLicensesSub =>
      'Componentes de terceiros incluídos no app';

  @override
  String get csBackToContent => 'Voltar ao conteúdo';

  @override
  String get setLanguageGerman => 'Deutsch';

  @override
  String get setLanguageFrench => 'Français';

  @override
  String get setLanguagePortuguese => 'Português';

  @override
  String get setLanguageChinese => '中文';
}
