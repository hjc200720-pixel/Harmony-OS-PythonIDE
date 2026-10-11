import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppSettings } from '../model/Models';

/**
 * 设置持久化（首选项数据库）。全部字段逐项读写，避免 ArkTS 下 JSON 反序列化丢类型。
 */
export class SettingsService {
  private static readonly STORE_NAME: string = 'pyide_settings';
  private static store: preferences.Preferences | undefined = undefined;

  static init(context: common.UIAbilityContext): AppSettings {
    // Options 是 interface（不是 class），只能用对象字面量，由参数类型做上下文推断
    SettingsService.store = preferences.getPreferencesSync(context, { name: SettingsService.STORE_NAME });
    return SettingsService.load();
  }

  static load(): AppSettings {
    const s = new AppSettings();
    const store = SettingsService.store;
    if (store === undefined) {
      return s;
    }
    s.themeName = store.getSync('themeName', s.themeName) as string;
    s.fontSize = store.getSync('fontSize', s.fontSize) as number;
    s.tabSize = store.getSync('tabSize', s.tabSize) as number;
    s.showLineNumbers = store.getSync('showLineNumbers', s.showLineNumbers) as boolean;
    s.wordWrap = store.getSync('wordWrap', s.wordWrap) as boolean;
    s.autoSave = store.getSync('autoSave', s.autoSave) as boolean;
    s.autoSaveDelayMs = store.getSync('autoSaveDelayMs', s.autoSaveDelayMs) as number;
    s.showIndentGuides = store.getSync('showIndentGuides', s.showIndentGuides) as boolean;
    s.highlightCurrentLine = store.getSync('highlightCurrentLine', s.highlightCurrentLine) as boolean;
    s.showLeftToolWindow = store.getSync('showLeftToolWindow', s.showLeftToolWindow) as boolean;
    s.showBottomToolWindow = store.getSync('showBottomToolWindow', s.showBottomToolWindow) as boolean;
    s.leftPanelWidth = store.getSync('leftPanelWidth', s.leftPanelWidth) as number;
    s.bottomPanelHeight = store.getSync('bottomPanelHeight', s.bottomPanelHeight) as number;
    s.lastProjectRoot = store.getSync('lastProjectRoot', s.lastProjectRoot) as string;
    s.pipIndexUrl = store.getSync('pipIndexUrl', s.pipIndexUrl) as string;
    s.pipOnline = store.getSync('pipOnline', s.pipOnline) as boolean;
    s.recentFiles = store.getSync('recentFiles', s.recentFiles) as string;
    s.foldedFolds = store.getSync('foldedFolds', s.foldedFolds) as string;
    s.paneSplit = store.getSync('paneSplit', s.paneSplit) as string;
    s.pane2Tabs = store.getSync('pane2Tabs', s.pane2Tabs) as string;
    s.paneRatio = store.getSync('paneRatio', s.paneRatio) as number;
    s.paneBefore = store.getSync('paneBefore', s.paneBefore) as boolean;
    return s;
  }

  /** 全量落盘；调用频率很低（仅在设置变更/退出时），因此直接写全部字段 */
  static save(s: AppSettings): void {
    const store = SettingsService.store;
    if (store === undefined) {
      return;
    }
    store.putSync('themeName', s.themeName);
    store.putSync('fontSize', s.fontSize);
    store.putSync('tabSize', s.tabSize);
    store.putSync('showLineNumbers', s.showLineNumbers);
    store.putSync('wordWrap', s.wordWrap);
    store.putSync('autoSave', s.autoSave);
    store.putSync('autoSaveDelayMs', s.autoSaveDelayMs);
    store.putSync('showIndentGuides', s.showIndentGuides);
    store.putSync('highlightCurrentLine', s.highlightCurrentLine);
    store.putSync('showLeftToolWindow', s.showLeftToolWindow);
    store.putSync('showBottomToolWindow', s.showBottomToolWindow);
    store.putSync('leftPanelWidth', s.leftPanelWidth);
    store.putSync('bottomPanelHeight', s.bottomPanelHeight);
    store.putSync('lastProjectRoot', s.lastProjectRoot);
    store.putSync('pipIndexUrl', s.pipIndexUrl);
    store.putSync('pipOnline', s.pipOnline);
    store.putSync('recentFiles', s.recentFiles);
    store.putSync('foldedFolds', s.foldedFolds);
    store.putSync('paneSplit', s.paneSplit);
    store.putSync('pane2Tabs', s.pane2Tabs);
    store.putSync('paneRatio', s.paneRatio);
    store.putSync('paneBefore', s.paneBefore);
    store.flush();
  }
}
