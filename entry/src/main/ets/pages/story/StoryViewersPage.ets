import { router } from '@kit.ArkUI';
import { getTdClient } from '../../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../../tdkit/TdTypes';
import { AvatarView } from '../chatlist/AvatarView';
import { loadStoryViewers, StoryViewerPage_, StoryViewerRow } from '../../store/StoryManageApi';
import {
  COLOR_ICON_SECONDARY, COLOR_PAGE_BG, COLOR_PRIMARY, COLOR_SURFACE,
  COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { str } from '../../util/strings';
import { formatTime } from '../../util/formatTime';
import { LANGUAGE_EPOCH } from '../../util/appLanguage';
import { MATERIAL_EPOCH } from '../../util/overlayMaterial';
import { logW } from '../../util/log';
import { contentSideGutter } from '../../util/contentWidth';

const PAGE_LIMIT: number = 30;
const CARD_RADIUS: number = 16;

interface ViewerRow {
  key: string;
  userId: number;
  title: string;
  subtitle: string;
  initials: string;
  avatarPath: string;
  timeLabel: string;
  isForward: boolean;
}

// 故事的观众列表：普通浏览 + 转发都在这一个列表里，类型靠副标题区分。
// 分页用 storyInteractions 的 next_offset，offset 为 0 表示已经到底。
@Entry
@Component
struct StoryViewersPage {
  @StorageProp(MATERIAL_EPOCH) private materialEpoch: number = 0;
  @StorageProp(LANGUAGE_EPOCH) langEpoch: number = 0;
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @StorageProp('screenWidthVp') screenW: number = 360;
  @State rows: ViewerRow[] = [];
  @State loadState: string = 'loading';
  @State pageState: string = 'idle';
  @State totalCount: number = 0;
  @State forwardCount: number = 0;
  @State reactionCount: number = 0;
  private posterChatId: number = 0;
  private storyId: number = 0;
  private nextOffset: string = '';
  private active: boolean = false;
  private sequence: number = 0;
  private unsubscribeFile: (() => void) | null = null;
  private fileKeys: Map<number, string[]> = new Map();

  aboutToAppear(): void {
    const params = router.getParams() as Record<string, Object> | undefined;
    if (params !== undefined) {
      this.posterChatId = (params['chatId'] as number | undefined) ?? 0;
      this.storyId = (params['storyId'] as number | undefined) ?? 0;
    }
    this.active = true;
    this.unsubscribeFile = getTdClient().onUpdate('updateFile', (update: TdObject): void => {
      const file = update['file'] as TdObject | undefined;
      if (file !== undefined) { this.applyFile(file); }
    });
    this.load(true);
  }

  aboutToDisappear(): void {
    this.active = false;
    this.sequence++;
    if (this.unsubscribeFile !== null) { this.unsubscribeFile(); this.unsubscribeFile = null; }
    this.fileKeys.clear();
  }

  private viewerRow(item: StoryViewerRow): ViewerRow {
    const forward: boolean = item.kind === 'forward';
    return {
      key: `v_${item.userId}_${item.messageId}`,
      userId: item.userId,
      title: '',
      subtitle: forward ? str('st_viewer_forward') : str('st_viewer_viewed'),
      initials: '?',
      avatarPath: '',
      timeLabel: formatTime(item.date, Math.floor(Date.now() / 1000)),
      isForward: forward
    };
  }

  private merge(incoming: ViewerRow[]): ViewerRow[] {
    const merged: ViewerRow[] = this.rows.slice();
    for (const row of incoming) {
      if (merged.findIndex((item: ViewerRow): boolean => item.key === row.key) < 0) {
        merged.push(row);
      }
    }
    return merged;
  }

  private load(initial: boolean): void {
    if (this.posterChatId <= 0 || this.storyId <= 0) {
      this.loadState = 'error';
      return;
    }
    if (!initial && (this.pageState === 'loading' || this.nextOffset.length === 0)) { return; }
    const sequence: number = initial ? ++this.sequence : this.sequence;
    if (initial) {
      this.loadState = 'loading';
      this.pageState = 'idle';
      this.rows = [];
      this.totalCount = 0;
      this.forwardCount = 0;
      this.reactionCount = 0;
      this.nextOffset = '';
      this.fileKeys.clear();
    } else {
      this.pageState = 'loading';
    }
    loadStoryViewers(this.posterChatId, this.storyId, initial ? '' : this.nextOffset, PAGE_LIMIT)
      .then((page: StoryViewerPage_): void => {
        if (!this.active || sequence !== this.sequence) { return; }
        const incoming: ViewerRow[] = page.rows.map((item: StoryViewerRow): ViewerRow => this.viewerRow(item));
        const merged: ViewerRow[] = initial ? incoming : this.merge(incoming);
        this.rows = merged;
        this.totalCount = Math.max(page.total, merged.length);
        this.forwardCount = page.totalForwards;
        this.reactionCount = page.totalReactions;
        this.nextOffset = page.nextOffset;
        this.loadState = 'ready';
        this.pageState = this.nextOffset.length > 0 && incoming.length > 0 ? 'idle' : 'done';
        for (const row of incoming) { this.resolveRow(row); }
      })
      .catch((error: TdError): void => {
        if (!this.active || sequence !== this.sequence) { return; }
        logW(`StoryViewersPage.load failed: ${error.message}`);
        if (initial) { this.loadState = 'error'; } else { this.pageState = 'error'; }
      });
  }

  private filePath(file: TdObject | undefined): string {
    const local = file !== undefined ? file['local'] as TdObject | undefined : undefined;
    if (local === undefined) { return ''; }
    const completed: boolean = (local['is_downloading_completed'] as boolean | undefined) ?? false;
    return completed ? ((local['path'] as string | undefined) ?? '') : '';
  }

  private watchFile(file: TdObject | undefined, key: string): string {
    if (file === undefined) { return ''; }
    const path: string = this.filePath(file);
    if (path !== '') { return path; }
    const id: number = (file['id'] as number | undefined) ?? 0;
    if (id <= 0) { return ''; }
    const keys: string[] = this.fileKeys.get(id) ?? [];
    if (keys.indexOf(key) < 0) { keys.push(key); this.fileKeys.set(id, keys); }
    const request: TdRequest = { '@type': 'downloadFile' };
    request['file_id'] = id;
    request['priority'] = 32;
    request['offset'] = 0;
    request['limit'] = 0;
    request['synchronous'] = false;
    getTdClient().send(request).catch((): void => {});
    return '';
  }

  private applyFile(file: TdObject): void {
    const id: number = (file['id'] as number | undefined) ?? 0;
    const path: string = this.filePath(file);
    const keys: string[] | undefined = this.fileKeys.get(id);
    if (path === '' || keys === undefined) { return; }
    this.fileKeys.delete(id);
    this.rows = this.rows.map((row: ViewerRow): ViewerRow => {
      if (keys.indexOf(row.key) < 0) { return row; }
      return {
        key: row.key, userId: row.userId, title: row.title, subtitle: row.subtitle,
        initials: row.initials, avatarPath: path, timeLabel: row.timeLabel, isForward: row.isForward
      };
    });
  }

  private resolveRow(row: ViewerRow): void {
    const request: TdRequest = { '@type': 'getUser' };
    request['user_id'] = row.userId;
    getTdClient().send(request).then((user: TdObject): void => {
      if (!this.active) { return; }
      const first: string = (user['first_name'] as string | undefined) ?? '';
      const last: string = (user['last_name'] as string | undefined) ?? '';
      const name: string = `${first}${last !== '' ? ` ${last}` : ''}`.trim();
      const title: string = name !== '' ? name : str('deleted_account');
      const photo = user['profile_photo'] as TdObject | undefined;
      const small = photo !== undefined ? photo['small'] as TdObject | undefined : undefined;
      const avatarPath: string = this.watchFile(small, row.key);
      this.rows = this.rows.map((item: ViewerRow): ViewerRow => {
        if (item.key !== row.key) { return item; }
        return {
          key: item.key, userId: item.userId, title, subtitle: item.subtitle,
          initials: title.substring(0, 1).toUpperCase(), avatarPath, timeLabel: item.timeLabel,
          isForward: item.isForward
        };
      });
    }).catch((error: TdError): void => {
      logW(`StoryViewersPage.resolveRow(${row.userId}) failed: ${error.message}`);
    });
  }

  @Builder
  header() {
    Row({ space: 8 }) {
      Button() {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([COLOR_TEXT_PRIMARY]);
      }
      .width(40).height(40).borderRadius(20).backgroundColor(Color.Transparent)
      .onClick((): void => { router.back(); });
      Column({ space: 1 }) {
        Text(str('gcm_viewer')).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLOR_TEXT_PRIMARY);
        if (this.loadState === 'ready') {
          Text(str('st_views', `${this.totalCount}`))
            .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').height(52).padding({ left: 8, right: 10 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  row(row: ViewerRow) {
    Row({ space: 12 }) {
      AvatarView({
        avatarPath: row.avatarPath, initials: row.initials,
        colorSeed: row.userId, avatarSize: 46
      });
      Text(row.title)
        .fontSize(16).fontColor(COLOR_TEXT_PRIMARY).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
      Row({ space: 5 }) {
        if (row.isForward) {
          SymbolGlyph($r('sys.symbol.arrowshape_turn_up_right')).fontSize(13)
            .fontColor([COLOR_PRIMARY]);
        } else {
          SymbolGlyph($r('sys.symbol.eye')).fontSize(13).fontColor([COLOR_ICON_SECONDARY]);
        }
        Text(row.timeLabel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY);
      }.alignItems(VerticalAlign.Center);
    }
    .width('100%').height(62).padding({ left: 12, right: 14 });
  }

  build() {
    Column() {
      this.header();
      if (this.loadState === 'loading') {
        Column({ space: 9 }) {
          LoadingProgress().width(34).height(34).color(COLOR_PRIMARY);
          Text(str('loading_short')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadState === 'error') {
        Column({ space: 10 }) {
          Text(str('bu_load_failed')).fontSize(17).fontColor(COLOR_TEXT_PRIMARY);
          Button(str('settings_reload')).onClick((): void => { this.load(true); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.rows.length === 0) {
        Column({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.eye')).fontSize(52).fontColor([COLOR_ICON_SECONDARY]);
          Text(str('st_no_views')).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
          Text(str('st_no_views_sub')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        List() {
          ForEach(this.rows, (row: ViewerRow) => {
            ListItem() { this.row(row); }
            .width('100%');
          }, (row: ViewerRow): string => `${row.key}_${row.title}_${row.avatarPath}`);
          ListItem() {
            if (this.pageState === 'loading') {
              Row({ space: 8 }) {
                LoadingProgress().width(18).height(18).color(COLOR_PRIMARY);
                Text(str('load_more')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
              }.width('100%').height(50).justifyContent(FlexAlign.Center);
            }
          }.width('100%');
        }
        .layoutWeight(1).width('100%')
        .padding({ left: 8, right: 8 })
        .divider({ strokeWidth: 1, color: COLOR_SURFACE, startMargin: 70, endMargin: 12 })
        .cachedCount(6)
        .onReachEnd((): void => { this.load(false); });
      }
    }
    .width('100%').height('100%')
    .backgroundColor(COLOR_PAGE_BG)
    .padding({
      top: this.topSafe, bottom: this.bottomSafe,
      left: contentSideGutter(this.screenW), right: contentSideGutter(this.screenW)
    });
  }
}

export const StoryViewersPageBuilder = (): void => {
  StoryViewersPage();
};
