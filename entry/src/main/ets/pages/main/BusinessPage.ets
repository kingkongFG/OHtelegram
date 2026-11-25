import { promptAction } from '@kit.ArkUI';
import {
  BusinessAway, BusinessBotInfo, BusinessChatLink, BusinessGreeting, BusinessHourInterval, BusinessInfo,
  BusinessFeatureView, BusinessIntroView, BusinessLocation, BusinessOverview, BusinessQuickReply,
  BusinessRecipientState, BusinessStartPage, loadBusinessFeatures, loadBusinessIntro, loadConnectedBotName,
  SCHEDULE_ALWAYS, SCHEDULE_OUTSIDE_HOURS, clearBusinessStartPage, createBusinessChatLink,
  defaultRecipients, deleteBusinessChatLink, disableBusinessAway, disableBusinessGreeting,
  disconnectBusinessBot, formatIntervals, loadBusinessOverview, loadQuickReplies, loadTimeZoneId,
  saveBusinessAway, saveBusinessGreeting, saveBusinessLocation, saveBusinessOpeningHours,
  saveBusinessStartPage, transferBusinessStars
} from '../../store/BusinessApi';
import { TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { logE } from '../../util/log';
import { str } from '../../util/strings';
import { HdsSubDestination } from '../common/HdsSubDestination';

const CARD_RADIUS: number = 14;
const BUSINESS_BLUE: string = '#3478F6';
const BUSINESS_GREY: string = '#8E8E93';
const DEFAULT_INACTIVITY_DAYS: number = 7;
const MINUTE_PER_DAY: number = 1440;

// 表单字段名。@Builder 只能收常量：ArkUI 里按值传递的参数不会随 @State 变化
// 重绘，所以输入框的当前值一律由 fieldValue() 在渲染时现读 this，Builder 只拿
// 一个不变的字段名。
const FIELD_ADDRESS: string = 'address';
const FIELD_HOUR_START: string = 'hourStart';
const FIELD_HOUR_END: string = 'hourEnd';
const FIELD_PAGE_TITLE: string = 'pageTitle';
const FIELD_PAGE_MESSAGE: string = 'pageMessage';
const FIELD_GREETING_DAYS: string = 'greetingDays';
const FIELD_LINK_TITLE: string = 'linkTitle';
const FIELD_LINK_MESSAGE: string = 'linkMessage';
const FIELD_STAR_AMOUNT: string = 'starAmount';

// 开关的种类，理由同上。
const TOGGLE_WEEKDAYS: string = 'weekdays';
const TOGGLE_AWAY_HOURS: string = 'awayHours';
const TOGGLE_AWAY_OFFLINE: string = 'awayOffline';

// 列表行的种类，同理：行内容在渲染时现算，Builder 只收这个常量。
const ROW_LOCATION: string = 'location';
const ROW_HOURS: string = 'hours';
const ROW_START_PAGE: string = 'startpage';
const ROW_GREETING: string = 'greeting';
const ROW_AWAY: string = 'away';
const ROW_LINK_NEW: string = 'link';

// 路由表（router_map.json）的 buildFunction 指向这里，页面因此不进 main_pages.json。
@Builder
export function BusinessPageBuilder(): void {
  BusinessPage();
}

@Component
export struct BusinessPage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State loadState: string = 'loading';
  @State isPremium: boolean = false;
  @State info: BusinessInfo | null = null;
  @State links: BusinessChatLink[] = [];
  @State bot: BusinessBotInfo | null = null;
  @State botName: string = '';
  @State features: BusinessFeatureView[] = [];
  @State intro: BusinessIntroView | null = null;
  @State starCount: number = 0;
  // 空串＝当前账号没有已启用的商家连接。余额挂在连接上取，所以「没有连接」
  // 和「余额是 0」是两种状态，不能共用一个判断。
  @State connectionId: string = '';
  @State timeZoneId: string = '';
  @State quickReplies: BusinessQuickReply[] = [];
  // 同一时刻只展开一个编辑面板：官方是子页，这里就地展开，少一层返回栈。
  @State panel: string = '';
  @State addressText: string = '';
  @State hourStart: string = '09:00';
  @State hourEnd: string = '18:00';
  @State weekdaysOnly: boolean = true;
  @State pageTitle: string = '';
  @State pageMessage: string = '';
  @State greetingShortcutId: number = 0;
  @State greetingDays: string = '7';
  @State awayShortcutId: number = 0;
  @State awayOutsideHours: boolean = false;
  @State awayOfflineOnly: boolean = false;
  @State linkTitle: string = '';
  @State linkMessage: string = '';
  @State starTransferText: string = '';
  @State busy: boolean = false;
  @State errText: string = '';
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
  }

  private load(): void {
    this.loadState = 'loading';
    loadBusinessOverview().then((overview: BusinessOverview): void => {
      if (!this.active) {
        return;
      }
      this.isPremium = overview.isPremium;
      this.info = overview.info;
      this.links = overview.links;
      this.bot = overview.bot;
      this.starCount = overview.starCount;
      this.connectionId = overview.connectionId;
      this.syncFormFromInfo();
      this.loadState = 'ready';
      if (overview.bot !== null) {
        loadConnectedBotName(overview.bot.botUserId).then((name: string): void => {
          if (this.active) {
            this.botName = name;
          }
        });
      }
    }).catch((error: TdError): void => {
      if (!this.active) {
        return;
      }
      logE(`BusinessPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
    loadTimeZoneId().then((tz: string): void => {
      if (this.active) {
        this.timeZoneId = tz;
      }
    }).catch((): void => {
    });
    loadBusinessFeatures().then((features: BusinessFeatureView[]): void => {
      if (this.active) {
        this.features = features;
      }
    });
    loadBusinessIntro().then((intro: BusinessIntroView | null): void => {
      if (this.active) {
        this.intro = intro;
      }
    });
  }

  // 表单初值只在字段仍是默认值时回填：保存后 load() 会重跑，不能把用户正在
  // 输入的内容盖掉。
  private syncFormFromInfo(): void {
    const info: BusinessInfo | null = this.info;
    if (info === null) {
      return;
    }
    if (this.addressText === '' && info.location.address !== '') {
      this.addressText = info.location.address;
    }
    const intervals: BusinessHourInterval[] = info.openingHours.intervals;
    if (intervals.length > 0) {
      const first: BusinessHourInterval = intervals[0];
      if (this.hourStart === '09:00') {
        this.hourStart = this.minuteText(first.startMinute);
      }
      if (this.hourEnd === '18:00') {
        this.hourEnd = this.minuteText(first.endMinute);
      }
    }
    const startPage: BusinessStartPage | null = info.startPage;
    if (startPage !== null) {
      if (this.pageTitle === '') {
        this.pageTitle = startPage.title;
      }
      if (this.pageMessage === '') {
        this.pageMessage = startPage.message;
      }
    }
    const greeting: BusinessGreeting | null = info.greeting;
    if (greeting !== null) {
      this.greetingShortcutId = greeting.shortcutId;
      this.greetingDays = `${greeting.inactivityDays}`;
    }
    const away: BusinessAway | null = info.away;
    if (away !== null) {
      this.awayShortcutId = away.shortcutId;
      this.awayOutsideHours = away.scheduleType === SCHEDULE_OUTSIDE_HOURS;
      this.awayOfflineOnly = away.offlineOnly;
    }
  }

  private minuteText(minute: number): string {
    const rest: number = minute % MINUTE_PER_DAY;
    const hh: number = Math.floor(rest / 60);
    const mm: number = rest % 60;
    const hhText: string = hh < 10 ? `0${hh}` : `${hh}`;
    const mmText: string = mm < 10 ? `0${mm}` : `${mm}`;
    return `${hhText}:${mmText}`;
  }

  private parseMinute(value: string): number {
    const parts: string[] = value.split(':');
    if (parts.length !== 2) {
      return -1;
    }
    const hh: number = Number.parseInt(parts[0], 10);
    const mm: number = Number.parseInt(parts[1], 10);
    if (Number.isNaN(hh) || Number.isNaN(mm)) {
      return -1;
    }
    if (hh < 0 || hh > 24 || mm < 0 || mm > 59) {
      return -1;
    }
    if (hh === 24 && mm !== 0) {
      return -1;
    }
    return hh * 60 + mm;
  }

  // ---- 表单字段读写（@Builder 只传字段名，值在这里现取） -----------------

  private fieldValue(field: string): string {
    if (field === FIELD_ADDRESS) {
      return this.addressText;
    }
    if (field === FIELD_HOUR_START) {
      return this.hourStart;
    }
    if (field === FIELD_HOUR_END) {
      return this.hourEnd;
    }
    if (field === FIELD_PAGE_TITLE) {
      return this.pageTitle;
    }
    if (field === FIELD_PAGE_MESSAGE) {
      return this.pageMessage;
    }
    if (field === FIELD_GREETING_DAYS) {
      return this.greetingDays;
    }
    if (field === FIELD_LINK_TITLE) {
      return this.linkTitle;
    }
    if (field === FIELD_LINK_MESSAGE) {
      return this.linkMessage;
    }
    if (field === FIELD_STAR_AMOUNT) {
      return this.starTransferText;
    }
    return '';
  }

  private setField(field: string, value: string): void {
    if (field === FIELD_ADDRESS) {
      this.addressText = value;
    } else if (field === FIELD_HOUR_START) {
      this.hourStart = value;
    } else if (field === FIELD_HOUR_END) {
      this.hourEnd = value;
    } else if (field === FIELD_PAGE_TITLE) {
      this.pageTitle = value;
    } else if (field === FIELD_PAGE_MESSAGE) {
      this.pageMessage = value;
    } else if (field === FIELD_GREETING_DAYS) {
      this.greetingDays = value;
    } else if (field === FIELD_LINK_TITLE) {
      this.linkTitle = value;
    } else if (field === FIELD_LINK_MESSAGE) {
      this.linkMessage = value;
    } else if (field === FIELD_STAR_AMOUNT) {
      this.starTransferText = value;
    }
  }

  private rowLabel(kind: string): string {
    if (kind === ROW_LOCATION) {
      return 'business_address';
    }
    if (kind === ROW_HOURS) {
      return 'business_opening_hours';
    }
    if (kind === ROW_START_PAGE) {
      return 'business_start_page';
    }
    if (kind === ROW_GREETING) {
      return 'business_greeting';
    }
    if (kind === ROW_AWAY) {
      return 'business_away';
    }
    return 'business_link_new';
  }

  private rowValue(kind: string): string {
    const info: BusinessInfo | null = this.info;
    if (kind === ROW_LINK_NEW) {
      return '';
    }
    if (info === null) {
      return '';
    }
    if (kind === ROW_LOCATION) {
      return info.location.address;
    }
    if (kind === ROW_HOURS) {
      return formatIntervals(info.openingHours.intervals);
    }
    if (kind === ROW_START_PAGE) {
      return info.startPage === null ? '' : info.startPage.title;
    }
    if (kind === ROW_GREETING) {
      return str(info.greeting === null ? 'business_state_off' : 'business_state_on');
    }
    if (kind === ROW_AWAY) {
      return str(info.away === null ? 'business_state_off' : 'business_state_on');
    }
    return '';
  }

  private zoneText(): string {
    const info: BusinessInfo | null = this.info;
    if (info !== null && info.openingHours.timeZoneId !== '') {
      return info.openingHours.timeZoneId;
    }
    return this.timeZoneId === '' ? '-' : this.timeZoneId;
  }

  private shortcutSelected(kind: string): number {
    return kind === ROW_GREETING ? this.greetingShortcutId : this.awayShortcutId;
  }

  private pickShortcut(kind: string, id: number): void {
    if (kind === ROW_GREETING) {
      this.greetingShortcutId = id;
    } else {
      this.awayShortcutId = id;
    }
  }

  // ---- 请求 -------------------------------------------------------------

  private toast(message: string): void {
    promptAction.showToast({ message: message, duration: 1800 });
  }

  private fail(error: TdError): void {
    logE(`BusinessPage request failed: ${error.message}`);
    this.errText = error.message;
    this.busy = false;
  }

  private done(message: string): void {
    this.busy = false;
    this.errText = '';
    this.toast(message);
    this.load();
  }

  private openPanel(id: string): void {
    this.errText = '';
    this.panel = this.panel === id ? '' : id;
    if ((id === ROW_GREETING || id === ROW_AWAY) && this.quickReplies.length === 0) {
      loadQuickReplies().then((rows: BusinessQuickReply[]): void => {
        if (this.active) {
          this.quickReplies = rows;
        }
      }).catch((): void => {
      });
    }
  }

  private recipientsOf(kind: string): BusinessRecipientState {
    const info: BusinessInfo | null = this.info;
    if (info !== null) {
      if (kind === ROW_GREETING && info.greeting !== null) {
        return info.greeting.recipients;
      }
      if (kind === ROW_AWAY && info.away !== null) {
        return info.away.recipients;
      }
    }
    return defaultRecipients();
  }

  private submitLocation(): void {
    const info: BusinessInfo | null = this.info;
    const body: BusinessLocation = {
      address: this.addressText.trim(),
      latitude: info === null ? 0 : info.location.latitude,
      longitude: info === null ? 0 : info.location.longitude
    };
    this.busy = true;
    saveBusinessLocation(body).then((): void => {
      if (!this.active) {
        return;
      }
      this.panel = '';
      this.done(str('business_saved'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private submitHours(): void {
    const start: number = this.parseMinute(this.hourStart);
    const end: number = this.parseMinute(this.hourEnd);
    if (start < 0 || end < 0 || end <= start) {
      this.errText = str('business_hour_invalid');
      return;
    }
    // 回写用商家自己报的时区；本机时区只是兜底（刚从设置里换过时区时才会用到）。
    const info: BusinessInfo | null = this.info;
    const zone: string = info !== null && info.openingHours.timeZoneId !== ''
      ? info.openingHours.timeZoneId : this.timeZoneId;
    if (zone === '') {
      this.errText = str('business_timezone_missing');
      return;
    }
    const days: number = this.weekdaysOnly ? 5 : 7;
    const intervals: BusinessHourInterval[] = [];
    for (let d = 0; d < days; d++) {
      intervals.push({ startMinute: d * MINUTE_PER_DAY + start, endMinute: d * MINUTE_PER_DAY + end });
    }
    this.busy = true;
    saveBusinessOpeningHours({ timeZoneId: zone, intervals: intervals }).then((): void => {
      if (!this.active) {
        return;
      }
      this.panel = '';
      this.done(str('business_saved'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private submitStartPage(): void {
    this.busy = true;
    saveBusinessStartPage(this.pageTitle.trim(), this.pageMessage.trim()).then((): void => {
      if (!this.active) {
        return;
      }
      this.panel = '';
      this.done(str('business_saved'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private removeStartPage(): void {
    this.busy = true;
    clearBusinessStartPage().then((): void => {
      if (!this.active) {
        return;
      }
      this.panel = '';
      this.pageTitle = '';
      this.pageMessage = '';
      this.done(str('business_cleared'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private submitGreeting(): void {
    if (this.greetingShortcutId === 0) {
      this.errText = str('business_shortcut_required');
      return;
    }
    const days: number = Number.parseInt(this.greetingDays, 10);
    const inactivity: number = Number.isNaN(days) ? DEFAULT_INACTIVITY_DAYS : Math.max(0, days);
    this.busy = true;
    saveBusinessGreeting(this.greetingShortcutId, inactivity, this.recipientsOf(ROW_GREETING))
      .then((): void => {
        if (!this.active) {
          return;
        }
        this.panel = '';
        this.done(str('business_saved'));
      }).catch((error: TdError): void => this.fail(error));
  }

  private removeGreeting(): void {
    this.busy = true;
    disableBusinessGreeting().then((): void => {
      if (!this.active) {
        return;
      }
      this.greetingShortcutId = 0;
      this.panel = '';
      this.done(str('business_disabled'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private submitAway(): void {
    if (this.awayShortcutId === 0) {
      this.errText = str('business_shortcut_required');
      return;
    }
    const schedule: string = this.awayOutsideHours ? SCHEDULE_OUTSIDE_HOURS : SCHEDULE_ALWAYS;
    this.busy = true;
    saveBusinessAway(this.awayShortcutId, schedule, this.awayOfflineOnly, this.recipientsOf(ROW_AWAY))
      .then((): void => {
        if (!this.active) {
          return;
        }
        this.panel = '';
        this.done(str('business_saved'));
      }).catch((error: TdError): void => this.fail(error));
  }

  private removeAway(): void {
    this.busy = true;
    disableBusinessAway().then((): void => {
      if (!this.active) {
        return;
      }
      this.awayShortcutId = 0;
      this.panel = '';
      this.done(str('business_disabled'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private submitLink(): void {
    const message: string = this.linkMessage.trim();
    if (message === '') {
      this.errText = str('business_link_message_required');
      return;
    }
    this.busy = true;
    createBusinessChatLink(this.linkTitle.trim(), message).then((): void => {
      if (!this.active) {
        return;
      }
      this.linkTitle = '';
      this.linkMessage = '';
      this.panel = '';
      this.done(str('business_link_created'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private removeLink(link: string): void {
    this.busy = true;
    deleteBusinessChatLink(link).then((): void => {
      if (!this.active) {
        return;
      }
      this.done(str('business_link_deleted'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private dropBot(): void {
    this.busy = true;
    disconnectBusinessBot().then((): void => {
      if (!this.active) {
        return;
      }
      this.bot = null;
      this.done(str('business_bot_disconnected'));
    }).catch((error: TdError): void => this.fail(error));
  }

  private submitStars(): void {
    const count: number = Number.parseInt(this.starTransferText, 10);
    if (Number.isNaN(count) || count <= 0) {
      this.errText = str('business_star_invalid');
      return;
    }
    this.busy = true;
    transferBusinessStars(count).then((): void => {
      if (!this.active) {
        return;
      }
      this.starTransferText = '';
      this.panel = '';
      this.done(str('business_star_transferred'));
    }).catch((error: TdError): void => this.fail(error));
  }

  // ---- UI ---------------------------------------------------------------

  @Builder
  sectionHeader(label: string) {
    Text(str(label)).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, top: 6, bottom: 6 });
  }

  @Builder
  dividerLine() {
    Divider().color(COLOR_DIVIDER).strokeWidth(0.5).margin({ left: 14, right: 14 });
  }

  @Builder
  errorLine() {
    if (this.errText !== '') {
      Text(this.errText).fontSize(12).fontColor('#D93025')
        .width('100%').padding({ left: 16, right: 16, top: 6 });
    }
  }

  @Builder
  statusCard() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.person_fill')).fontSize(24).fontColor([Color.White]);
      }
      .width(52).height(52).borderRadius(26)
      .backgroundColor(this.isPremium ? BUSINESS_BLUE : BUSINESS_GREY);

      Column({ space: 4 }) {
        Text(str(this.isPremium ? 'business_status_active' : 'business_status_locked'))
          .fontSize(16).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY).width('100%');
        Text(str(this.isPremium ? 'business_status_active_sub' : 'business_status_locked_sub'))
          .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(17)
          .width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding(14)
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  entryRow(kind: string) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(str(this.rowLabel(kind))).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).width('100%');
        if (this.rowValue(kind) !== '') {
          Text(this.rowValue(kind)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
    }
    .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .onClick((): void => this.openPanel(kind));
  }

  @Builder
  fieldLabel(label: string) {
    Text(str(label)).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
      .width('100%').padding({ left: 16, top: 8 });
  }

  @Builder
  fieldInput(field: string, hint: string) {
    TextInput({ text: this.fieldValue(field), placeholder: str(hint) })
      .fontSize(15).backgroundColor(Color.Transparent)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .onChange((v: string): void => {
        this.errText = '';
        this.setField(field, v);
      });
  }

  @Builder
  actionButton(label: string, action: () => void) {
    Button(str(label))
      .fontSize(14).height(34).layoutWeight(1)
      .enabled(!this.busy)
      .onClick(action);
  }

  @Builder
  shortcutPicker(kind: string) {
    Column({ space: 4 }) {
      if (this.quickReplies.length === 0) {
        Text(str('business_shortcut_empty')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .lineHeight(17).width('100%').padding({ left: 16, right: 16, top: 4 });
      } else {
        ForEach(this.quickReplies, (row: BusinessQuickReply) => {
          Row({ space: 8 }) {
            Text(row.name).fontSize(14).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
            Text(str('business_shortcut_count', row.messageCount))
              .fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
            if (row.id === this.shortcutSelected(kind)) {
              SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([BUSINESS_BLUE]);
            }
          }
          .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick((): void => this.pickShortcut(kind, row.id));
        }, (row: BusinessQuickReply): string => `qr_${row.id}`);
      }
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  private toggleValue(kind: string): boolean {
    if (kind === TOGGLE_WEEKDAYS) {
      return this.weekdaysOnly;
    }
    if (kind === TOGGLE_AWAY_HOURS) {
      return this.awayOutsideHours;
    }
    return this.awayOfflineOnly;
  }

  private setToggle(kind: string, on: boolean): void {
    if (kind === TOGGLE_WEEKDAYS) {
      this.weekdaysOnly = on;
    } else if (kind === TOGGLE_AWAY_HOURS) {
      this.awayOutsideHours = on;
    } else {
      this.awayOfflineOnly = on;
    }
  }

  // 开关同样只收种类常量：按值传 isOn 的话，状态回写后开关不会跟着回位。
  @Builder
  toggleRow(kind: string, label: string) {
    Row({ space: 8 }) {
      Text(str(label)).fontSize(14).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: this.toggleValue(kind) })
        .onChange((on: boolean): void => this.setToggle(kind, on));
    }.width('100%').padding({ left: 16, right: 16, top: 8 }).alignItems(VerticalAlign.Center);
  }

  @Builder
  locationPanel() {
    Column({ space: 2 }) {
      this.fieldLabel('business_address');
      this.fieldInput(FIELD_ADDRESS, 'business_address_hint');
      if (this.info !== null && this.info.location.latitude !== 0) {
        Text(str('business_coords', this.info.location.latitude.toFixed(4),
          this.info.location.longitude.toFixed(4)))
          .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).padding({ left: 16, top: 2 });
      }
      this.errorLine();
      Row({ space: 10 }) {
        this.actionButton('business_save', (): void => this.submitLocation());
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  hoursPanel() {
    Column({ space: 2 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          this.fieldLabel('business_hour_start');
          this.fieldInput(FIELD_HOUR_START, 'business_hour_hint');
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Column({ space: 2 }) {
          this.fieldLabel('business_hour_end');
          this.fieldInput(FIELD_HOUR_END, 'business_hour_hint');
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }.width('100%').alignItems(VerticalAlign.Top);
      this.toggleRow(TOGGLE_WEEKDAYS, 'business_weekdays_only');
      Text(str('business_timezone_value', this.zoneText()))
        .fontSize(11).fontColor(COLOR_TEXT_SECONDARY).padding({ left: 16, top: 4 });
      this.errorLine();
      Row({ space: 10 }) {
        this.actionButton('business_save', (): void => this.submitHours());
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  startPagePanel() {
    Column({ space: 2 }) {
      this.fieldLabel('business_start_page_title');
      this.fieldInput(FIELD_PAGE_TITLE, 'business_start_page_title_hint');
      this.fieldLabel('business_start_page_message');
      this.fieldInput(FIELD_PAGE_MESSAGE, 'business_start_page_message_hint');
      this.errorLine();
      Row({ space: 10 }) {
        this.actionButton('business_shortcut_save', (): void => this.submitStartPage());
        this.actionButton('business_clear', (): void => this.removeStartPage());
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  greetingPanel() {
    Column({ space: 2 }) {
      this.fieldLabel('business_shortcut_pick');
      this.shortcutPicker(ROW_GREETING);
      this.fieldLabel('business_greeting_days');
      this.fieldInput(FIELD_GREETING_DAYS, 'business_greeting_days_hint');
      this.errorLine();
      Row({ space: 10 }) {
        this.actionButton('business_shortcut_save', (): void => this.submitGreeting());
        this.actionButton('business_disable', (): void => this.removeGreeting());
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  awayPanel() {
    Column({ space: 2 }) {
      this.fieldLabel('business_shortcut_pick');
      this.shortcutPicker(ROW_AWAY);
      this.toggleRow(TOGGLE_AWAY_HOURS, 'business_away_outside_hours');
      this.toggleRow(TOGGLE_AWAY_OFFLINE, 'business_away_offline_only');
      this.errorLine();
      Row({ space: 10 }) {
        this.actionButton('business_shortcut_save', (): void => this.submitAway());
        this.actionButton('business_disable', (): void => this.removeAway());
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  linkPanel() {
    Column({ space: 2 }) {
      this.fieldLabel('business_link_title');
      this.fieldInput(FIELD_LINK_TITLE, 'business_link_title_hint');
      this.fieldLabel('business_link_message');
      this.fieldInput(FIELD_LINK_MESSAGE, 'business_link_message_hint');
      this.errorLine();
      Row({ space: 10 }) {
        this.actionButton('business_link_create', (): void => this.submitLink());
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  starsPanel() {
    Column({ space: 2 }) {
      this.fieldLabel('business_star_amount');
      this.fieldInput(FIELD_STAR_AMOUNT, 'business_star_amount_hint');
      if (this.connectionId === '') {
        Text(str('business_star_need_connection')).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 16, top: 4 });
      }
      this.errorLine();
      Row({ space: 10 }) {
        this.actionButton('business_star_transfer', (): void => this.submitStars());
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 12 });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  linkRow(row: BusinessChatLink, index: number) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(row.title === '' ? str('business_link_untitled') : row.title)
            .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).width('100%');
          Text(row.link).fontSize(11).fontColor(COLOR_TEXT_SECONDARY)
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Text(str('business_link_views', row.viewCount)).fontSize(11).fontColor(COLOR_TEXT_SECONDARY);
        Button(str('business_link_delete'))
          .fontSize(12).height(28).backgroundColor('#FFF0EF').fontColor('#D93025')
          .onClick((): void => this.removeLink(row.link));
      }.width('100%').alignItems(VerticalAlign.Center);
      if (row.text !== '') {
        Text(row.text).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
    }
    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 });
    if (index !== this.links.length - 1) {
      this.dividerLine();
    }
  }

  @Builder
  profileCard() {
    Column() {
      this.entryRow(ROW_LOCATION);
      if (this.panel === ROW_LOCATION) {
        this.locationPanel();
      }
      this.dividerLine();
      this.entryRow(ROW_HOURS);
      if (this.panel === ROW_HOURS) {
        this.hoursPanel();
      }
      this.dividerLine();
      this.entryRow(ROW_START_PAGE);
      if (this.panel === ROW_START_PAGE) {
        this.startPagePanel();
      }
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  automationCard() {
    Column() {
      this.entryRow(ROW_GREETING);
      if (this.panel === ROW_GREETING) {
        this.greetingPanel();
      }
      this.dividerLine();
      this.entryRow(ROW_AWAY);
      if (this.panel === ROW_AWAY) {
        this.awayPanel();
      }
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  linksCard() {
    Column() {
      if (this.links.length === 0) {
        Text(str('business_links_empty')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 });
      } else {
        ForEach(this.links, (row: BusinessChatLink, index: number) => {
          this.linkRow(row, index);
        }, (row: BusinessChatLink): string => row.link);
      }
      this.dividerLine();
      this.entryRow(ROW_LINK_NEW);
      if (this.panel === ROW_LINK_NEW) {
        this.linkPanel();
      }
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  botCard() {
    Column() {
      if (this.bot === null) {
        Text(str('business_bot_none')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 });
      } else {
        Column({ space: 4 }) {
          Text(this.botName !== '' ? this.botName : str('business_bot_connected', this.bot.botUserId))
            .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).width('100%');
          if (this.bot.deviceModel !== '') {
            Text(this.bot.deviceModel).fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
          }
          Button(str('business_bot_disconnect'))
            .fontSize(13).height(30).margin({ top: 6 })
            .backgroundColor('#FFF0EF').fontColor('#D93025')
            .onClick((): void => this.dropBot());
        }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .alignItems(HorizontalAlign.Start);
      }
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  // businessFeatureXxx -> business_feature_xxx，界面文案按类型查表。
  private featureLabel(kind: string): string {
    const prefix: string = 'businessFeature';
    const tail: string = kind.indexOf(prefix) === 0 ? kind.substring(prefix.length) : kind;
    const snake: string = tail.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
    return str(`business_feature_${snake}`);
  }

  @Builder
  featuresCard() {
    Column() {
      if (this.features.length === 0) {
        Text(str('business_features_empty')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
          .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 });
      } else {
        ForEach(this.features, (feature: BusinessFeatureView, index: number) => {
          if (index > 0) {
            Divider().strokeWidth(1).color(COLOR_PAGE_BG).margin({ left: 14, right: 14 });
          }
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(15).fontColor([BUSINESS_BLUE]);
            Text(this.featureLabel(feature.kind))
              .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).layoutWeight(1);
          }
          .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
          .alignItems(VerticalAlign.Center);
        }, (feature: BusinessFeatureView): string => feature.kind);
      }
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  introCard() {
    Column({ space: 4 }) {
      if (this.intro === null) {
        Text(str('business_intro_empty')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY).width('100%');
      } else {
        if (this.intro.title !== '') {
          Text(this.intro.title).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).width('100%');
        }
        if (this.intro.message !== '') {
          Text(this.intro.message).fontSize(13).fontColor(COLOR_TEXT_SECONDARY)
            .lineHeight(19).width('100%');
        }
      }
    }
    .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  starsCard() {
    Column() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(str('business_stars')).fontSize(15).fontColor(COLOR_TEXT_PRIMARY).width('100%');
          Text(str('business_star_balance', this.starCount))
            .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).width('100%');
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([COLOR_TEXT_SECONDARY]);
      }
      .width('100%').padding({ left: 14, right: 14, top: 11, bottom: 11 })
      .onClick((): void => this.openPanel('stars'));
      if (this.panel === 'stars') {
        this.starsPanel();
      }
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      HdsSubDestination({
        title: str('settings_business'),
        pageBackground: COLOR_PAGE_BG,
        scroller: this.hdsScroller,
        subTitle: this.loadState === 'ready'
          ? str(this.isPremium ? 'business_status_active' : 'business_status_locked') : ''
      }) {
        Column() {
          if (this.loadState === 'loading') {
            Column({ space: 9 }) {
              LoadingProgress().width(32).height(32).color(BUSINESS_BLUE);
              Text(str('business_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
            }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
          } else if (this.loadState === 'error') {
            Column({ space: 10 }) {
              Text(str('load_failed')).fontSize(16).fontColor(COLOR_TEXT_PRIMARY);
              Button(str('settings_reload')).onClick((): void => this.load());
            }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
          } else {
            Scroll(this.hdsScroller) {
              Column({ space: 12 }) {
                this.statusCard();
                this.sectionHeader('business_group_profile');
                this.profileCard();
                this.sectionHeader('business_group_automation');
                this.automationCard();
                this.sectionHeader('business_group_links');
                this.linksCard();
                this.sectionHeader('business_group_bot');
                this.botCard();
                this.sectionHeader('business_group_features');
                this.featuresCard();
                this.sectionHeader('business_group_intro');
                this.introCard();
                this.sectionHeader('business_group_stars');
                this.starsCard();
                Text(str('business_note'))
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
              }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
            }
            // Scroll 的 align 默认是 Center：内容比视口短时整块会被垂直居中。
            .align(Alignment.Top)
            .layoutWeight(1).width('100%').scrollBar(BarState.Off)
            .clip(false);
          }
        }.width('100%').height('100%');
      }
    }.width('100%').height('100%');
  }
}
