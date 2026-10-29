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
  String get csNoPages => 'Nenhuma página';

  @override
  String get csRetrySync => 'Tentar sincronizar de novo';

  @override
  String csPagesRestoredBlank(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas substituídas por páginas em branco',
      one: '$count página substituída por uma em branco',
    );
    return '$_temp0';
  }

  @override
  String get csDeletePage => 'Excluir página';

  @override
  String csMissingDownloadingTitle(int page) {
    return 'Baixando a página $page…';
  }

  @override
  String get csMissingDownloadingBody =>
      'Esta página ainda não está neste dispositivo. O servidor a tem: ela está sendo baixada e aparecerá aqui quando estiver pronta.';

  @override
  String csMissingOfflineTitle(int page) {
    return 'Página $page ainda não baixada';
  }

  @override
  String get csMissingOfflineBody =>
      'Esta página ainda não está neste dispositivo e o servidor não está respondendo agora. Nova tentativa automática; a página aparecerá quando a conexão voltar. Nada é alterado enquanto isso.';

  @override
  String csMissingGoneTitle(int page) {
    return 'Página $page ausente';
  }

  @override
  String get csMissingGoneBody =>
      'O arquivo desta página não está neste dispositivo nem no servidor. Se outro dispositivo ainda mostra a página, abra-a lá: ela será enviada de novo e voltará aqui também.';

  @override
  String get csMissingNoServerBody =>
      'O arquivo desta página não está neste dispositivo e o caderno não sincroniza com um servidor.';

  @override
  String get csMissingPreviousPage => 'Página anterior';

  @override
  String get csMissingLastResort =>
      'Só se tiver certeza de que a página não existe mais em lugar nenhum:';

  @override
  String get csMissingReplaceAction => 'Substituir por página em branco';

  @override
  String csMissingReplaceAll(int count) {
    return 'Substituir todas ($count)';
  }

  @override
  String csMissingReplaceConfirmTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Substituir $count páginas por páginas em branco?',
      one: 'Substituir a página por uma em branco?',
    );
    return '$_temp0';
  }

  @override
  String csMissingReplaceConfirmBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'As páginas em branco são sincronizadas em todos os seus dispositivos. Se os originais ainda existirem em outro dispositivo, serão sobrescritos.',
      one:
          'A página em branco é sincronizada em todos os seus dispositivos. Se o original ainda existir em outro dispositivo, será sobrescrito.',
    );
    return '$_temp0';
  }

  @override
  String get csMissingDeleteConfirmTitle => 'Excluir a página?';

  @override
  String get csMissingDeleteConfirmBody =>
      'A página é removida do caderno em todos os dispositivos sincronizados.';

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
  String get libCoverColor => 'Cor';

  @override
  String get libCoverPattern => 'Padrão';

  @override
  String get libCoverApply => 'Aplicar';

  @override
  String get libCoverStyleAuto => 'Automático (pelo tipo de papel)';

  @override
  String get libCoverStylePlain => 'Liso';

  @override
  String get libCoverStylePinstripe => 'Risca de giz';

  @override
  String get libCoverStyleDiagonal => 'Listras diagonais';

  @override
  String get libCoverStylePolka => 'Bolinhas';

  @override
  String get libCoverStyleGingham => 'Xadrez vichy';

  @override
  String get libCoverStyleWaves => 'Ondas';

  @override
  String get libCoverStyleLabel => 'Etiqueta';

  @override
  String get libCoverStyleTwoTone => 'Bicolor';

  @override
  String get libCoverStyleSheen => 'Brilho';

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
  String get libShowAll => 'Ver tudo';

  @override
  String get libShowLess => 'Ver menos';

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
  String get setPressureThickness => 'Pressão → espessura';

  @override
  String get setPressureThicknessSub =>
      'Modulação do traço conforme a pressão da caneta';

  @override
  String get setStrokeContinuation => 'Continuação do traço';

  @override
  String get setStrokeContinuationSub =>
      'Compensa interrupções breves do sensor (ex.: o ponto do i)';

  @override
  String get setFillShapes => 'Preencher formas';

  @override
  String get setFillShapesSub =>
      'Círculos, retângulos e triângulos reconhecidos recebem um tom suave da cor da tinta';

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
  String libPendingNewDrive(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos ainda não estão no Google Drive: $names',
      one: '«$names» ainda não está no Google Drive',
    );
    return '$_temp0';
  }

  @override
  String libPendingNewServer(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos ainda não estão no seu servidor: $names',
      one: '«$names» ainda não está no seu servidor',
    );
    return '$_temp0';
  }

  @override
  String libPendingChanges(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Alterações em $count cadernos ainda não enviadas: $names',
      one: 'Alterações em «$names» ainda não enviadas',
    );
    return '$_temp0';
  }

  @override
  String get libPendingUploadsHint =>
      'Enquanto isso, eles ficam neste dispositivo. Deixe o app aberto um instante.';

  @override
  String get libDeleteRemotePending =>
      'Excluído aqui. A remoção da nuvem falhou: será tentada de novo automaticamente.';

  @override
  String libPendingRemoteDeletes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos excluídos aqui, ainda para remover da nuvem',
      one: '$count caderno excluído aqui, ainda para remover da nuvem',
    );
    return '$_temp0';
  }

  @override
  String get libPendingRemoteDeletesHint =>
      'Até lá, seus outros dispositivos ainda podem vê-lo. Nova tentativa assim que a conexão voltar.';

  @override
  String get libServerUnreachable => 'Servidor inacessível';

  @override
  String get libServerUnreachableHint =>
      'As alterações ficam neste dispositivo e são enviadas assim que a conexão voltar.';

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
  String get libLocalOnlyBodyWeb =>
      'Seus cadernos ficam neste navegador. Exporte os que quiser manter ou conecte o Google Drive para tê-los em todos os lugares. O Safari pode apagar os dados de sites não usados há alguns dias, a menos que você adicione o app à tela de início.';

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
  String get chromeHoldForOptions =>
      'Toque e segure ou clique com o botão direito para ver as opções';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selecionadas',
      one: '1 selecionada',
    );
    return '$_temp0';
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

  @override
  String get qlTrashDeletedNow => 'Excluído agora mesmo';

  @override
  String qlTrashDeletedMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluído há $count minutos',
      one: 'Excluído há $count minuto',
    );
    return '$_temp0';
  }

  @override
  String qlTrashDeletedHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluído há $count horas',
      one: 'Excluído há $count hora',
    );
    return '$_temp0';
  }

  @override
  String qlTrashDeletedDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Excluído há $count dias',
      one: 'Excluído há $count dia',
    );
    return '$_temp0';
  }

  @override
  String get qlAdvancedLocalOnly =>
      'Estas ferramentas de recuperação só se aplicam quando um servidor ou o Google Drive está conectado.';

  @override
  String get qlNameRequired => 'Digite um nome';

  @override
  String get qlDuplicate => 'Duplicar';

  @override
  String qlDuplicateTitle(String title) {
    return '$title (cópia)';
  }

  @override
  String get qlDuplicated => 'Caderno duplicado';

  @override
  String get qlDuplicateNoLocalCopy =>
      'Este caderno não está neste dispositivo. Abra-o uma vez para baixá-lo e depois duplique-o.';

  @override
  String get qlDeleteOrphanBody =>
      'Não resta nenhuma cópia deste caderno neste dispositivo, então ele não poderá ser restaurado. Ele será removido da biblioteca.';

  @override
  String get qlDeletedNoTrash =>
      'Removido. Não havia nenhuma cópia neste dispositivo, então nada foi para a lixeira.';

  @override
  String get qlOpenCorrupt =>
      'Os dados deste caderno estão danificados e não podem ser abertos.';

  @override
  String qlSearchNoResults(String query) {
    return 'Nenhum caderno corresponde a “$query”.';
  }

  @override
  String get qcMouseSelectHint =>
      'O rato seleciona enquanto uma caneta está ativa. Ative o desenho com o rato para desenhar com ele.';

  @override
  String get qcMouseDrawEnable => 'Desenhar com o rato';

  @override
  String qiIssueRemoteImage(String arg) {
    return 'Imagem remota não transferida: $arg';
  }

  @override
  String qiIssueImageNotFound(String arg) {
    return 'Imagem não encontrada: $arg';
  }

  @override
  String qiIssueImageUnreadable(String arg) {
    return 'Não foi possível ler a imagem: $arg';
  }

  @override
  String qiIssueAttachmentUnsupported(String arg) {
    return 'Anexo não suportado (apenas imagens): $arg';
  }

  @override
  String qiIssueAttachmentTooLarge(String arg) {
    return 'Anexo demasiado grande, ignorado: $arg';
  }

  @override
  String qiIssueEmbedUnsupported(String arg) {
    return 'Ficheiro incorporado não importado (apenas imagens e notas): $arg';
  }

  @override
  String qiIssueNoteEmbedNotFound(String arg) {
    return 'Nota incorporada não encontrada: $arg';
  }

  @override
  String qiIssueNoteEmbedSkipped(String arg) {
    return 'Nota incorporada não expandida (circular ou demasiado aninhada): $arg';
  }

  @override
  String get qiIssueFileUnreadable => 'Não foi possível ler o ficheiro';

  @override
  String qiIssueFileTooLarge(int count) {
    return 'Ficheiro demasiado grande ($count MB), ignorado';
  }

  @override
  String get qiIssueEncodingFallback =>
      'O texto não era UTF-8 válido, lido como Latin-1';

  @override
  String get qiIssueCsvUnreadable => 'Não foi possível ler a tabela';

  @override
  String qiIssueZipEntryTooLarge(int count) {
    return 'Item do arquivo demasiado grande ($count MB), ignorado';
  }

  @override
  String qiIssueZipTotalTooLarge(int count) {
    return 'O conteúdo do arquivo excede $count MB, os restantes ficheiros foram ignorados';
  }

  @override
  String qiIssueHiddenFolders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notas em pastas ocultas foram ignoradas',
      one: '1 nota numa pasta oculta foi ignorada',
    );
    return '$_temp0';
  }

  @override
  String qiIssueTooManyChapters(int count) {
    return '$count capítulos: considere importar as subpastas separadamente';
  }

  @override
  String qiIssuePagesTruncated(int count) {
    return 'Nota cortada após $count páginas';
  }

  @override
  String qiIssueOneNoteSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementos não suportados ignorados',
      one: '1 elemento não suportado ignorado',
    );
    return '$_temp0';
  }

  @override
  String get qiErrNoMarkdown =>
      'Nenhum ficheiro Markdown (.md) na pasta escolhida';

  @override
  String get qiErrNoNotionContent =>
      'O zip não contém ficheiros .md nem .csv: use uma exportação do Notion «Markdown e CSV»';

  @override
  String get qiErrNothingImportable => 'Nada para importar';

  @override
  String get qiErrZipUnreadable =>
      'O ficheiro zip está danificado ou não é um arquivo válido';

  @override
  String get qiErrNoOneNotePages => 'Nenhuma página importável neste ficheiro';

  @override
  String get qiErrUnexpected => 'erro inesperado';

  @override
  String qiOneNoteSection(int n) {
    return 'Secção $n';
  }

  @override
  String get qiOneNotePage => 'Página';

  @override
  String get qiPdfNotPdf => 'Este ficheiro não é um PDF válido';

  @override
  String get qiPdfCorrupt =>
      'Este PDF está danificado ou incompleto e não pode ser lido';

  @override
  String get qiPdfEmpty => 'Este PDF não tem páginas';

  @override
  String get qiPdfUnsupported =>
      'Este PDF usa uma proteção ou funcionalidade não suportada';

  @override
  String get qiPdfPasswordCancelled =>
      'Importação cancelada: palavra-passe não indicada';

  @override
  String get qiPdfImportFailed => 'Não foi possível importar o PDF';

  @override
  String get qiPdfPasswordTitle => 'PDF protegido por palavra-passe';

  @override
  String get qiPdfPasswordBody =>
      'Introduza a palavra-passe para importar este PDF.';

  @override
  String get qiPdfPasswordHint => 'Palavra-passe';

  @override
  String get qiPdfPasswordWrong => 'Palavra-passe errada, tente novamente';

  @override
  String get qiPdfPasswordOpen => 'Abrir';

  @override
  String qiPdfPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'O PDF tem $count páginas.',
      one: 'O PDF tem 1 página.',
    );
    return '$_temp0';
  }

  @override
  String qiPdfStartOutOfRange(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'O PDF tem $count páginas. O início está fora do intervalo.',
      one: 'O PDF tem 1 página. O início está fora do intervalo.',
    );
    return '$_temp0';
  }

  @override
  String get qsReauthBanner =>
      'O servidor não aceita mais o seu login. As suas alterações estão seguras neste dispositivo e serão sincronizadas depois de você entrar novamente.';

  @override
  String get qsDriveReauthBanner =>
      'O Google Drive pede que você entre novamente. Suas alterações estão seguras neste dispositivo e serão sincronizadas assim que você entrar.';

  @override
  String get qsBrowserStorageFull =>
      'Este navegador não tem mais espaço para salvar: suas últimas alterações podem se perder ao recarregar a página. Exporte seus cadernos ou libere espaço.';

  @override
  String get qsReauthAction => 'Entrar novamente';

  @override
  String qsDeletedElsewhere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count cadernos foram excluídos em outro dispositivo. As suas cópias ficam somente aqui.',
      one:
          '$count caderno foi excluído em outro dispositivo. A sua cópia fica somente aqui.',
    );
    return '$_temp0';
  }

  @override
  String get qsDeletedElsewhereHint =>
      'Mantenha pressionado um caderno e escolha \"Voltar a sincronizar este caderno\" para enviá-lo de volta.';

  @override
  String get qsRefreshTooltip => 'Atualizar a partir do servidor';

  @override
  String get qsResumeSyncPending =>
      'Servidor inacessível. Este caderno será enviado assim que ele voltar.';

  @override
  String get qsResumeSyncUploaded =>
      'Enviado. Este caderno voltou a sincronizar.';

  @override
  String get qsNoServerConnected => 'Nenhum servidor conectado.';

  @override
  String get qsLoginWrongCredentials =>
      'O servidor recusou o usuário ou a senha.';

  @override
  String get qsLoginNotAServer =>
      'Nenhum servidor Nextcloud ou WebDAV encontrado neste endereço. Verifique a URL.';

  @override
  String get qsLoginUnreachable =>
      'Não foi possível alcançar o servidor. Verifique o endereço e a sua conexão.';

  @override
  String get qsLoginThrottled =>
      'Muitas tentativas. O servidor pede que você aguarde um pouco antes de tentar novamente.';

  @override
  String get qsLoginServerError =>
      'O servidor retornou um erro. Tente novamente mais tarde.';

  @override
  String get quPenNoMonitor => 'Nenhum monitor ativo encontrado.';

  @override
  String get quPenNoDevice => 'Nenhum dispositivo de caneta encontrado.';

  @override
  String get quPenBadGeometry => 'Geometria da área de trabalho inválida.';

  @override
  String quPenToolMissing(String tool) {
    return '$tool não encontrado.';
  }

  @override
  String quPenToolFailed(String tool) {
    return '$tool falhou.';
  }

  @override
  String get quDiffStrokes => 'Traços';

  @override
  String get quDiffImages => 'Imagens';

  @override
  String get quDiffShapes => 'Formas';

  @override
  String get quDiffTexts => 'Textos';

  @override
  String get quDefaultChapter => 'Capítulo 1';

  @override
  String qtNeedsOpenToUpload(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos também mudaram em outro dispositivo',
      one: '$count caderno também mudou em outro dispositivo',
    );
    return '$_temp0';
  }

  @override
  String get qtNeedsOpenToUploadHint =>
      'Abra-o para mesclar e enviar as suas alterações.';

  @override
  String get qtResumeSyncNeedsOpen =>
      'Este caderno volta a sincronizar. Abra-o para mesclar as alterações feitas em outro dispositivo.';

  @override
  String libImportSuccessMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos importados',
      one: '$count caderno importado',
    );
    return '$_temp0';
  }

  @override
  String get pgtTitlePages => 'Páginas';

  @override
  String pgtEyebrow(String notebook, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return '$notebook · $_temp0';
  }

  @override
  String get pgtSelect => 'Selecionar';

  @override
  String get pgtSelectPages => 'Selecionar páginas';

  @override
  String get pgtAll => 'Todas';

  @override
  String get pgtNone => 'Nenhuma';

  @override
  String get pgtDone => 'Concluir';

  @override
  String get pgtNoChapter => 'Sem capítulo';

  @override
  String get pgtCopy => 'Copiar';

  @override
  String get pgtMove => 'Mover';

  @override
  String get pgtTagMoving => 'movendo';

  @override
  String get pgtHintPlaceMove =>
      'Toque numa página para colocá-las depois dela, ou na borda esquerda para colocá-las antes. Nada muda até você confirmar.';

  @override
  String get pgtHintPlaceCopy =>
      'Toque numa página para colar depois dela, ou na borda esquerda para colar antes.';

  @override
  String get pgtMoveHere => 'Mover aqui';

  @override
  String get pgtPasteHere => 'Colar aqui';

  @override
  String get pgtMoveShort => 'Mover';

  @override
  String get pgtPasteShort => 'Colar';

  @override
  String pgtPasteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return 'Colar $_temp0';
  }

  @override
  String pgtPasteCountShort(int count) {
    return 'Colar $count';
  }

  @override
  String get pgtThisNotebook => 'Este caderno';

  @override
  String get pgtAnotherNotebook => 'Outro caderno…';

  @override
  String pgtMoveToNb(String notebook) {
    return 'Mover para $notebook';
  }

  @override
  String pgtPasteIntoNb(String notebook) {
    return 'Colar em $notebook';
  }

  @override
  String get pgtPosStart => 'No início';

  @override
  String pgtPosAfter(int page) {
    return 'Depois da página $page';
  }

  @override
  String get pgtPosEnd => 'No fim';

  @override
  String pgtPosChapterEnd(String chapter) {
    return 'Fim de $chapter';
  }

  @override
  String get pgtChapterMenuHead => 'Capítulo para as páginas';

  @override
  String pgtTrayMoving(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas · movendo',
      one: '1 página · movendo',
    );
    return '$_temp0';
  }

  @override
  String pgtTrayCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas · copiadas',
      one: '1 página · copiada',
    );
    return '$_temp0';
  }

  @override
  String get pgtSavedShort => 'Salvo';

  @override
  String get pgtSavedLong =>
      'Salvo neste dispositivo. Continua aqui depois de fechar o app.';

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
    return 'de $notebook › vários capítulos';
  }

  @override
  String pgtSourceDeleted(String notebook) {
    return '$notebook foi excluído, estas páginas agora são uma cópia';
  }

  @override
  String get pgtTrayOptions => 'Opções da bandeja de páginas';

  @override
  String get pgtCancelMove => 'Cancelar a movimentação';

  @override
  String get pgtCancelMoveHint => 'As páginas nunca foram removidas';

  @override
  String get pgtClearTray => 'Esvaziar a bandeja';

  @override
  String get pgtChooseWhere => 'Escolher onde, em Páginas';

  @override
  String get pgtChooseWhereHint =>
      'Abre as páginas deste caderno com a bandeja pronta';

  @override
  String pgtOpenSource(String notebook) {
    return 'Abrir $notebook';
  }

  @override
  String get pgtOpenSourceHint => 'De onde vêm estas páginas';

  @override
  String get pgtUndo => 'Desfazer';

  @override
  String get pgtShow => 'Mostrar';

  @override
  String pgtChooserTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return 'Mover $_temp0 para…';
  }

  @override
  String get pgtRecent => 'Recentes';

  @override
  String get pgtChooserEmpty => 'Não há outros cadernos neste dispositivo.';

  @override
  String get pgtBrowseLibrary => 'Explorar a biblioteca';

  @override
  String pgtNbPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return '$_temp0';
  }

  @override
  String pgtNbChapters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capítulos',
      one: '1 capítulo',
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
      other: '$count páginas',
      one: '1 página',
    );
    return 'Escolha um caderno para onde mover $_temp0. Toque numa capa ou use o menu …';
  }

  @override
  String pgtLibHintPaste(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return 'Escolha um caderno onde colar $_temp0. Toque numa capa ou use o menu …';
  }

  @override
  String pgtBadgeMoving(int count) {
    return '$count movendo';
  }

  @override
  String pgtCardMoveHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return 'Mover $_temp0 para cá';
  }

  @override
  String pgtCardPasteHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return 'Colar $_temp0 aqui';
  }

  @override
  String pgtCardEndOfChapter(String chapter) {
    return 'No fim de $chapter';
  }

  @override
  String get pgtCardAtEnd => 'No fim';

  @override
  String get pgtWhereStart => 'no início';

  @override
  String pgtWhereAfter(int page) {
    return 'depois da página $page';
  }

  @override
  String get pgtWhereEnd => 'no fim';

  @override
  String pgtWhereChapterEnd(String chapter) {
    return 'no fim de $chapter';
  }

  @override
  String pgtToastCopied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas copiadas. Abra um caderno para colar.',
      one: '1 página copiada. Abra um caderno para colar.',
    );
    return '$_temp0';
  }

  @override
  String pgtToastCopiedSkipped(int count, int skipped) {
    return 'Copiadas $count páginas; $skipped ainda não carregadas foram ignoradas.';
  }

  @override
  String pgtToastMoveReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas prontas para mover. Nada muda até você confirmar.',
      one: '1 página pronta para mover. Nada muda até você confirmar.',
    );
    return '$_temp0';
  }

  @override
  String pgtToastMoveReadySkipped(int count, int skipped) {
    return '$count páginas prontas para mover; $skipped ainda não carregadas foram ignoradas. Nada muda até você confirmar.';
  }

  @override
  String pgtToastMoveCancelled(int count, String notebook) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Movimentação cancelada. $count páginas continuam em $notebook.',
      one: 'Movimentação cancelada. 1 página continua em $notebook.',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastTrayCleared => 'Bandeja esvaziada';

  @override
  String pgtToastPasted(int count, String notebook, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas coladas em $notebook, $where',
      one: '1 página colada em $notebook, $where',
    );
    return '$_temp0';
  }

  @override
  String pgtToastMoved(int count, String notebook, String where) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas movidas para $notebook, $where',
      one: '1 página movida para $notebook, $where',
    );
    return '$_temp0';
  }

  @override
  String pgtToastDuplicated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas duplicadas',
      one: '1 página duplicada',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastUndone => 'Desfeito';

  @override
  String pgtToastTooMany(int max) {
    return 'A bandeja comporta até $max páginas. Selecione menos.';
  }

  @override
  String get pgtToastNothing =>
      'Estas páginas ainda não estão prontas (carregando). Tente de novo em instantes.';

  @override
  String get pgtToastTrayNotSaved =>
      'Não foi possível salvar a bandeja neste dispositivo. Ela será perdida ao fechar o app.';

  @override
  String get pgtToastPagesGone => 'Essas páginas não estão mais neste caderno.';

  @override
  String get pgtToastTrayDamaged =>
      'A bandeja salva está incompleta, nada foi colado.';

  @override
  String get pgtToastDestFailed =>
      'Não foi possível salvar as páginas coladas. Nada foi alterado.';

  @override
  String get pgtToastDestUnavailable =>
      'Esse caderno não pode ser editado agora. Nada foi alterado.';

  @override
  String pgtToastSourceFailed(String notebook) {
    return 'As páginas foram adicionadas, mas não puderam ser removidas de $notebook. Estão nos dois cadernos; a bandeja agora é uma cópia.';
  }

  @override
  String pgtToastMoveResumed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'A movimentação interrompida de $count páginas foi concluída.',
      one: 'A movimentação interrompida de 1 página foi concluída.',
    );
    return '$_temp0';
  }

  @override
  String get pgtToastUndoFailed =>
      'Não foi possível desfazer. Verifique os dois cadernos.';
}
