import 'package:yaml/yaml.dart';

/// Result of [stripFrontmatter]: the body without the YAML block plus the
/// metadata we care about (tags).
class FrontmatterResult {
  final String body;
  final List<String> tags;

  const FrontmatterResult({required this.body, this.tags = const []});
}

/// Strips a leading `---\n…\n---` YAML frontmatter block (Obsidian, Notion
/// via plugins, Jekyll, …) and extracts `tags:` — either a YAML list or a
/// comma/space separated string. Malformed YAML is ignored, never fatal.
FrontmatterResult stripFrontmatter(String source) {
  if (!source.startsWith('---')) {
    return FrontmatterResult(body: source);
  }
  final firstLineEnd = source.indexOf('\n');
  if (firstLineEnd < 0 || source.substring(0, firstLineEnd).trim() != '---') {
    return FrontmatterResult(body: source);
  }
  final closeIdx = RegExp(r'^---\s*$', multiLine: true)
      .allMatches(source, firstLineEnd)
      .firstOrNull;
  if (closeIdx == null) return FrontmatterResult(body: source);

  final yamlText = source.substring(firstLineEnd + 1, closeIdx.start);
  final body = source.substring(closeIdx.end).trimLeft();
  final tags = <String>[];
  try {
    final doc = loadYaml(yamlText);
    if (doc is YamlMap) {
      final raw = doc['tags'] ?? doc['tag'];
      if (raw is YamlList) {
        tags.addAll(raw.map((e) => e.toString().trim()));
      } else if (raw is String) {
        tags.addAll(raw
            .split(RegExp(r'[,\s]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty));
      }
    }
  } catch (_) {
    // Frontmatter is best-effort metadata; a broken block never fails the file.
  }
  return FrontmatterResult(
    body: body,
    tags: tags.map((t) => t.startsWith('#') ? t.substring(1) : t).toList(),
  );
}
