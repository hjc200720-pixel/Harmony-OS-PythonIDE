/**
 * 文件类型图标映射。
 * 图标全部取自 PyCharm 自带的 expui 资源（解包自 intellij.platform.ide.jar 的 expui/fileTypes/*），
 * 与 PyCharm 工程树 / 编辑器标签页的类型图标一一对应。
 */
export function fileIconOf(name: string): string {
  const lower: string = name.toLowerCase();
  if (lower === '.gitignore' || lower === '.gitattributes') {
    return 'icons/gitignore.svg';
  }
  const dot: number = lower.lastIndexOf('.');
  const ext: string = dot >= 0 ? lower.substring(dot) : '';
  if (ext === '.py' || ext === '.pyw' || ext === '.pyi' || ext === '.pyx') {
    return 'icons/python.svg';
  }
  if (ext === '.md' || ext === '.markdown' || ext === '.rst') {
    return 'icons/fileMarkdown.svg';
  }
  if (ext === '.json') {
    return 'icons/json.svg';
  }
  if (ext === '.yaml' || ext === '.yml') {
    return 'icons/yaml.svg';
  }
  if (ext === '.toml' || ext === '.cfg' || ext === '.ini' || ext === '.conf' || ext === '.properties') {
    return 'icons/toml.svg';
  }
  if (ext === '.csv' || ext === '.tsv') {
    return 'icons/csv.svg';
  }
  if (ext === '.svg' || ext === '.png' || ext === '.jpg' || ext === '.jpeg'
    || ext === '.gif' || ext === '.webp' || ext === '.bmp') {
    return 'icons/image.svg';
  }
  if (ext === '.zip' || ext === '.tar' || ext === '.gz' || ext === '.7z' || ext === '.rar') {
    return 'icons/archive.svg';
  }
  if (ext === '.txt' || ext === '.log' || ext === '.text') {
    return 'icons/fileText20.svg';
  }
  return 'icons/fileText20.svg';
}
