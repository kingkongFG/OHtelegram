import { getTdClient } from '../tdkit/Globals';
import { TdError, TdObject, TdRequest } from '../tdkit/TdTypes';
import { logW } from '../util/log';

// Telegram Business 数据层。
//
// 字段名不是猜的：全部对着 td/generate/scheme/td_api.tl 逐个核过，并回查了随包的
// libtdjson.so（采购版）里对应的字段名字符串——businessInfo / businessRecipients /
// businessGreetingMessageSettings / businessAwayMessageSettings / businessStartPage /
// businessChatLink / businessOpeningHoursInterval 的每一个字段都能在 so 中命中。
//
// 与官方客户端的差异只有一处，且是**故意**的：businessInfo 里没有 businessIntro
// （那是 user 的商家介绍），商家「介绍」在 TDLib 侧对应 businessStartPage，所以
// 页面上叫「开始页」，不叫「简介」。
//
// 所有读取都做存在性兜底：服务器不下发某字段时只是少一项，不会让整页崩。

export interface BusinessRecipientState {
  chatIds: number[];
  excludedChatIds: number[];
  selectExistingChats: boolean;
  selectNewChats: boolean;
  selectContacts: boolean;
  selectNonContacts: boolean;
  excludeSelected: boolean;
}

export interface BusinessHourInterval {
  startMinute: number;   // 自周一 00:00 起的分钟数
  endMinute: number;
}

export interface BusinessOpeningHours {
  timeZoneId: string;
  intervals: BusinessHourInterval[];
}

export interface BusinessLocation {
  address: string;
  latitude: number;
  longitude: number;
}

export interface BusinessStartPage {
  title: string;
  message: string;
}

export interface BusinessGreeting {
  shortcutId: number;
  inactivityDays: number;
  recipients: BusinessRecipientState;
}

export interface BusinessAway {
  shortcutId: number;
  scheduleType: string;      // businessAwayMessageScheduleXxx
  offlineOnly: boolean;
  recipients: BusinessRecipientState;
}

export interface BusinessChatLink {
  link: string;
  title: string;
  text: string;
  viewCount: number;
}

export interface BusinessBotInfo {
  botUserId: number;
  connectionDate: number;
  deviceModel: string;
  location: string;
}

export interface BusinessInfo {
  location: BusinessLocation;
  openingHours: BusinessOpeningHours;        // 服务器时区（商家所在地）
  localOpeningHours: BusinessOpeningHours;   // 换算到本机时区
  nextOpenIn: number;
  nextCloseIn: number;
  greeting: BusinessGreeting | null;
  away: BusinessAway | null;
  startPage: BusinessStartPage | null;
}

export interface BusinessQuickReply {
  id: number;
  name: string;
  messageCount: number;
}

export interface BusinessOverview {
  isPremium: boolean;
  info: BusinessInfo | null;
  links: BusinessChatLink[];
  bot: BusinessBotInfo | null;
  starCount: number;
  connectionId: string;   // 空串＝当前账号没有已启用的 business 连接
}

export const SCHEDULE_ALWAYS: string = 'businessAwayMessageScheduleAlways';
export const SCHEDULE_OUTSIDE_HOURS: string = 'businessAwayMessageScheduleOutsideOfOpeningHours';
export const SCHEDULE_CUSTOM: string = 'businessAwayMessageScheduleCustom';

// ---- 读取辅助 ------------------------------------------------------------
// TdObject 是 Record<string, Object>，类型上不含 undefined，但服务器不下发某字段
// 时运行时就是 undefined——typeof 判断对两者都安全。

function num(o: TdObject, key: string): number {
  const v: Object = o[key];
  return typeof v === 'number' ? v as number : 0;
}

function text(o: TdObject, key: string): string {
  const v: Object = o[key];
  return typeof v === 'string' ? v as string : '';
}

function flag(o: TdObject, key: string): boolean {
  const v: Object = o[key];
  return typeof v === 'boolean' ? v as boolean : false;
}

function child(o: TdObject | null, key: string): TdObject | null {
  if (o === null) {
    return null;
  }
  const v: Object = o[key];
  return (typeof v === 'object' && v !== null) ? v as TdObject : null;
}

function list(o: TdObject | null, key: string): TdObject[] {
  if (o === null) {
    return [];
  }
  const v: Object = o[key];
  return Array.isArray(v) ? v as TdObject[] : [];
}

function typeOf(o: TdObject | null): string {
  return o === null ? '' : text(o, '@type');
}

function req(type: string): TdRequest {
  const r: TdRequest = { '@type': type };
  return r;
}

// number[] 在 ArkTS 里无法用 list() 取（它不是 TdObject[]），单独判一次。
function intArray(o: TdObject | null, key: string): number[] {
  if (o === null) {
    return [];
  }
  const v: Object = o[key];
  if (!Array.isArray(v)) {
    return [];
  }
  const raw: Object[] = v as Object[];
  const out: number[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item: Object = raw[i];
    if (typeof item === 'number') {
      out.push(item as number);
    }
  }
  return out;
}

// ---- businessRecipients -------------------------------------------------
// 官方默认值（新建时）：选中所有已有会话与联系人。

export function defaultRecipients(): BusinessRecipientState {
  return {
    chatIds: [],
    excludedChatIds: [],
    selectExistingChats: true,
    selectNewChats: true,
    selectContacts: true,
    selectNonContacts: true,
    excludeSelected: false
  };
}

function parseRecipients(o: TdObject | null): BusinessRecipientState {
  if (o === null) {
    return defaultRecipients();
  }
  return {
    chatIds: intArray(o, 'chat_ids'),
    excludedChatIds: intArray(o, 'excluded_chat_ids'),
    selectExistingChats: flag(o, 'select_existing_chats'),
    selectNewChats: flag(o, 'select_new_chats'),
    selectContacts: flag(o, 'select_contacts'),
    selectNonContacts: flag(o, 'select_non_contacts'),
    excludeSelected: flag(o, 'exclude_selected')
  };
}

function recipientsToTd(r: BusinessRecipientState): TdObject {
  const o: TdObject = {};
  o['@type'] = 'businessRecipients';
  o['chat_ids'] = r.chatIds;
  o['excluded_chat_ids'] = r.excludedChatIds;
  o['select_existing_chats'] = r.selectExistingChats;
  o['select_new_chats'] = r.selectNewChats;
  o['select_contacts'] = r.selectContacts;
  o['select_non_contacts'] = r.selectNonContacts;
  o['exclude_selected'] = r.excludeSelected;
  return o;
}

// ---- 各结构解析 ---------------------------------------------------------

function parseLocation(o: TdObject | null): BusinessLocation {
  const loc: TdObject | null = child(o, 'location');
  return {
    address: o === null ? '' : text(o, 'address'),
    latitude: loc === null ? 0 : num(loc, 'latitude'),
    longitude: loc === null ? 0 : num(loc, 'longitude')
  };
}

function parseOpeningHours(o: TdObject | null): BusinessOpeningHours {
  const rows: TdObject[] = list(o, 'opening_hours');
  const intervals: BusinessHourInterval[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row: TdObject = rows[i];
    intervals.push({
      startMinute: num(row, 'start_minute'),
      endMinute: num(row, 'end_minute')
    });
  }
  return {
    timeZoneId: o === null ? '' : text(o, 'time_zone_id'),
    intervals: intervals
  };
}

function parseStartPage(o: TdObject | null): BusinessStartPage | null {
  if (o === null) {
    return null;
  }
  const title: string = text(o, 'title');
  const message: string = text(o, 'message');
  if (title === '' && message === '') {
    return null;
  }
  return { title: title, message: message };
}

function parseGreeting(o: TdObject | null): BusinessGreeting | null {
  if (o === null) {
    return null;
  }
  const shortcutId: number = num(o, 'shortcut_id');
  if (shortcutId === 0) {
    return null;
  }
  return {
    shortcutId: shortcutId,
    inactivityDays: num(o, 'inactivity_days'),
    recipients: parseRecipients(child(o, 'recipients'))
  };
}

function parseAway(o: TdObject | null): BusinessAway | null {
  if (o === null) {
    return null;
  }
  const shortcutId: number = num(o, 'shortcut_id');
  if (shortcutId === 0) {
    return null;
  }
  return {
    shortcutId: shortcutId,
    scheduleType: typeOf(child(o, 'schedule')),
    offlineOnly: flag(o, 'offline_only'),
    recipients: parseRecipients(child(o, 'recipients'))
  };
}

function parseBusinessInfo(o: TdObject | null): BusinessInfo | null {
  if (o === null) {
    return null;
  }
  return {
    location: parseLocation(child(o, 'location')),
    openingHours: parseOpeningHours(child(o, 'opening_hours')),
    localOpeningHours: parseOpeningHours(child(o, 'local_opening_hours')),
    nextOpenIn: num(o, 'next_open_in'),
    nextCloseIn: num(o, 'next_close_in'),
    greeting: parseGreeting(child(o, 'greeting_message_settings')),
    away: parseAway(child(o, 'away_message_settings')),
    startPage: parseStartPage(child(o, 'start_page'))
  };
}

// ---- business 连接跟踪 ---------------------------------------------------
// setBusinessAccountXxx / getBusinessAccountStarAmount / transferBusinessAccountStars
// 都要 business_connection_id，而它只能来自 updateBusinessConnection 推送。
// 这里只缓存「已启用」的那一条：自己的商家账号在登录后 TDLib 会推一次，
// 没推就是没连机器人，相关功能据此隐藏而不是报错。

let connectionTracked: boolean = false;
let activeConnectionId: string = '';

function ensureConnectionTracking(): void {
  if (connectionTracked) {
    return;
  }
  connectionTracked = true;
  getTdClient().onUpdate('updateBusinessConnection', (update: TdObject): void => {
    const conn: TdObject | null = child(update, 'connection');
    if (conn === null) {
      return;
    }
    const id: string = text(conn, 'id');
    if (flag(conn, 'is_enabled')) {
      activeConnectionId = id;
    } else if (activeConnectionId === id) {
      activeConnectionId = '';
    }
  });
}

export function businessConnectionId(): string {
  return activeConnectionId;
}

// ---- 读取 ---------------------------------------------------------------

export async function loadBusinessInfo(): Promise<BusinessInfo | null> {
  const client = getTdClient();
  const me: TdObject = await client.send(req('getMe'), 15000);
  const fullReq: TdRequest = req('getUserFullInfo');
  fullReq['user_id'] = num(me, 'id');
  const full: TdObject = await client.send(fullReq, 15000);
  return parseBusinessInfo(child(full, 'business_info'));
}

// userFullInfo 每次变更 TDLib 都会推 updateUserFullInfo，页面不必轮询；
// 这里给出订阅入口，返回退订函数。
export function onBusinessInfoChanged(handler: (info: BusinessInfo | null) => void): () => void {
  const meBox: number[] = [0];
  getTdClient().send(req('getMe'), 15000).then((me: TdObject): void => {
    meBox[0] = num(me, 'id');
  }).catch((): void => {
  });
  return getTdClient().onUpdate('updateUserFullInfo', (update: TdObject): void => {
    const userId: number = num(update, 'user_id');
    if (meBox[0] !== 0 && userId !== meBox[0]) {
      return;
    }
    handler(parseBusinessInfo(child(update, 'user_full_info')));
  });
}

/** formattedText 是嵌套对象，child 可能为 null，这里统一收口避免 null 透传。 */
function innerText(row: TdObject): string {
  const formatted: TdObject | null = child(row, 'text');
  return formatted === null ? '' : text(formatted, 'text');
}

export async function loadBusinessChatLinks(): Promise<BusinessChatLink[]> {
  const resp: TdObject = await getTdClient().send(req('getBusinessChatLinks'), 15000);
  const rows: TdObject[] = list(resp, 'links');
  const out: BusinessChatLink[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row: TdObject = rows[i];
    out.push({
      link: text(row, 'link'),
      title: text(row, 'title'),
      text: innerText(row),
      viewCount: num(row, 'view_count')
    });
  }
  return out;
}

export async function loadBusinessBot(): Promise<BusinessBotInfo | null> {
  const resp: TdObject = await getTdClient().send(req('getBusinessConnectedBot'), 15000);
  const bot: TdObject | null = child(resp, 'bot');
  const botUserId: number = bot === null ? 0 : num(bot, 'bot_user_id');
  if (botUserId === 0) {
    return null;
  }
  return {
    botUserId: botUserId,
    connectionDate: num(resp, 'connection_date'),
    deviceModel: text(resp, 'device_model'),
    location: text(resp, 'location')
  };
}

export async function loadBusinessStarCount(): Promise<number> {
  const connectionId: string = businessConnectionId();
  if (connectionId === '') {
    return 0;
  }
  const r: TdRequest = req('getBusinessAccountStarAmount');
  r['business_connection_id'] = connectionId;
  try {
    const resp: TdObject = await getTdClient().send(r, 15000);
    return num(resp, 'star_count');
  } catch (e) {
    // 连接失效时后端返回 400，余额就是「未知」，不当成页面错误。
    return 0;
  }
}

export async function loadBusinessOverview(): Promise<BusinessOverview> {
  ensureConnectionTracking();
  const client = getTdClient();
  const me: TdObject = await client.send(req('getMe'), 15000);
  const isPremium: boolean = flag(me, 'is_premium');
  const info: BusinessInfo | null = await loadBusinessInfo();
  const links: BusinessChatLink[] = await loadBusinessChatLinks();
  const bot: BusinessBotInfo | null = await loadBusinessBot();
  const starCount: number = await loadBusinessStarCount();
  return {
    isPremium: isPremium,
    info: info,
    links: links,
    bot: bot,
    starCount: starCount,
    connectionId: businessConnectionId()
  };
}

// getOption('timezone') 返回的是 tz database id（"Asia/Shanghai"），
// 正好是 businessOpeningHours.time_zone_id 要的格式，不用自己换算偏移。
export async function loadTimeZoneId(): Promise<string> {
  const r: TdRequest = req('getOption');
  r['name'] = 'timezone';
  try {
    const resp: TdObject = await getTdClient().send(r, 8000);
    const value: TdObject | null = child(resp, 'value');
    return value === null ? '' : text(value, 'value');
  } catch (e) {
    return '';
  }
}

// 问候/离线消息都只能引用「快捷回复」。TDLib 侧没有 getQuickReplyShortcuts，
// 只能 loadQuickReplyShortcuts() 之后收 updateQuickReplyShortcut 推送，
// 所以这里开一个短窗口收集，超时就返回已收到的部分。
export function loadQuickReplies(waitMs: number = 1500): Promise<BusinessQuickReply[]> {
  const client = getTdClient();
  const found: Map<number, BusinessQuickReply> = new Map();
  let timeoutId: number = -1;
  const offOne: () => void = client.onUpdate('updateQuickReplyShortcut', (update: TdObject): void => {
    const s: TdObject | null = child(update, 'shortcut');
    if (s === null) {
      return;
    }
    const id: number = num(s, 'id');
    if (id === 0) {
      return;
    }
    found.set(id, { id: id, name: text(s, 'name'), messageCount: num(s, 'message_count') });
  });
  const finish = (resolve: (rows: BusinessQuickReply[]) => void): void => {
    offOne();
    if (timeoutId !== -1) {
      clearTimeout(timeoutId);
      timeoutId = -1;
    }
    const rows: BusinessQuickReply[] = [];
    const values: IterableIterator<BusinessQuickReply> = found.values();
    let cursor: IteratorResult<BusinessQuickReply> = values.next();
    while (!cursor.done) {
      rows.push(cursor.value);
      cursor = values.next();
    }
    rows.sort((a: BusinessQuickReply, b: BusinessQuickReply): number => a.id - b.id);
    resolve(rows);
  };
  return new Promise<BusinessQuickReply[]>((resolve: (rows: BusinessQuickReply[]) => void): void => {
    timeoutId = setTimeout((): void => finish(resolve), waitMs);
    client.send(req('loadQuickReplyShortcuts'), 15000).catch((): void => finish(resolve));
  });
}

// ---- 写入 ---------------------------------------------------------------

export async function saveBusinessLocation(location: BusinessLocation): Promise<void> {
  const loc: TdObject = {};
  loc['@type'] = 'location';
  loc['latitude'] = location.latitude;
  loc['longitude'] = location.longitude;
  loc['horizontal_accuracy'] = 0;
  const body: TdObject = {};
  body['@type'] = 'businessLocation';
  body['location'] = loc;
  body['address'] = location.address;
  const r: TdRequest = req('setBusinessLocation');
  r['location'] = body;
  await getTdClient().send(r, 15000);
}

export async function saveBusinessOpeningHours(hours: BusinessOpeningHours): Promise<void> {
  const rows: TdObject[] = [];
  for (let i = 0; i < hours.intervals.length; i++) {
    const iv: BusinessHourInterval = hours.intervals[i];
    const row: TdObject = {};
    row['@type'] = 'businessOpeningHoursInterval';
    row['start_minute'] = iv.startMinute;
    row['end_minute'] = iv.endMinute;
    rows.push(row);
  }
  const body: TdObject = {};
  body['@type'] = 'businessOpeningHours';
  body['time_zone_id'] = hours.timeZoneId;
  body['opening_hours'] = rows;
  const r: TdRequest = req('setBusinessOpeningHours');
  r['opening_hours'] = body;
  await getTdClient().send(r, 15000);
}

export async function saveBusinessGreeting(shortcutId: number, inactivityDays: number,
  recipients: BusinessRecipientState): Promise<void> {
  const body: TdObject = {};
  body['@type'] = 'businessGreetingMessageSettings';
  body['shortcut_id'] = shortcutId;
  body['inactivity_days'] = inactivityDays;
  body['recipients'] = recipientsToTd(recipients);
  const r: TdRequest = req('setBusinessGreetingMessageSettings');
  r['greeting_message_settings'] = body;
  await getTdClient().send(r, 15000);
}

export async function saveBusinessAway(shortcutId: number, scheduleType: string,
  offlineOnly: boolean, recipients: BusinessRecipientState): Promise<void> {
  const schedule: TdObject = {};
  schedule['@type'] = scheduleType;
  const body: TdObject = {};
  body['@type'] = 'businessAwayMessageSettings';
  body['shortcut_id'] = shortcutId;
  body['schedule'] = schedule;
  body['offline_only'] = offlineOnly;
  body['recipients'] = recipientsToTd(recipients);
  const r: TdRequest = req('setBusinessAwayMessageSettings');
  r['away_message_settings'] = body;
  await getTdClient().send(r, 15000);
}

// 关闭＝shortcut_id 传 0，官方客户端也是这个语义（不是删掉结构）。
export async function disableBusinessGreeting(): Promise<void> {
  await saveBusinessGreeting(0, 0, defaultRecipients());
}

export async function disableBusinessAway(): Promise<void> {
  await saveBusinessAway(0, SCHEDULE_ALWAYS, false, defaultRecipients());
}

export async function saveBusinessStartPage(title: string, message: string): Promise<void> {
  const sticker: TdObject = {};
  sticker['@type'] = 'inputFileNone';
  const body: TdObject = {};
  body['@type'] = 'inputBusinessStartPage';
  body['title'] = title;
  body['message'] = message;
  body['sticker'] = sticker;
  const r: TdRequest = req('setBusinessStartPage');
  r['start_page'] = body;
  await getTdClient().send(r, 15000);
}

export async function clearBusinessStartPage(): Promise<void> {
  await saveBusinessStartPage('', '');
}

function inputLink(title: string, message: string): TdObject {
  const ft: TdObject = {};
  ft['@type'] = 'formattedText';
  ft['text'] = message;
  ft['entities'] = [];
  const body: TdObject = {};
  body['@type'] = 'inputBusinessChatLink';
  body['text'] = ft;
  body['title'] = title;
  return body;
}

export async function createBusinessChatLink(title: string, message: string): Promise<string> {
  const r: TdRequest = req('createBusinessChatLink');
  r['link_info'] = inputLink(title, message);
  const resp: TdObject = await getTdClient().send(r, 15000);
  return text(resp, 'link');
}

export async function editBusinessChatLink(link: string, title: string, message: string): Promise<void> {
  const r: TdRequest = req('editBusinessChatLink');
  r['link'] = link;
  r['link_info'] = inputLink(title, message);
  await getTdClient().send(r, 15000);
}

export async function deleteBusinessChatLink(link: string): Promise<void> {
  const r: TdRequest = req('deleteBusinessChatLink');
  r['link'] = link;
  await getTdClient().send(r, 15000);
}

export async function disconnectBusinessBot(): Promise<void> {
  const bot: BusinessBotInfo | null = await loadBusinessBot();
  if (bot === null) {
    return;
  }
  const r: TdRequest = req('deleteBusinessConnectedBot');
  r['bot_user_id'] = bot.botUserId;
  await getTdClient().send(r, 15000);
}

export async function transferBusinessStars(starCount: number): Promise<void> {
  const connectionId: string = businessConnectionId();
  if (connectionId === '') {
    throw new Error('business connection unavailable');
  }
  const r: TdRequest = req('transferBusinessAccountStars');
  r['business_connection_id'] = connectionId;
  r['star_count'] = starCount;
  await getTdClient().send(r, 20000);
}

// ---- 展示辅助 -----------------------------------------------------------

// 分钟数 → "09:00"。1440 表示一天结束，显示成 24:00 更符合营业时间的读法。
export function formatMinuteOfWeek(minute: number): string {
  const m: number = Math.max(0, Math.min(1440 * 7, minute));
  const dayMinute: number = m % 1440;
  const hh: number = Math.floor(dayMinute / 60);
  const mm: number = dayMinute % 60;
  const hhText: string = hh < 10 ? `0${hh}` : `${hh}`;
  const mmText: string = mm < 10 ? `0${mm}` : `${mm}`;
  return `${hhText}:${mmText}`;
}

// 一周区间压缩成「周一 09:00–18:00、周二 …」，同一天多段用逗号接。
export function formatIntervals(intervals: BusinessHourInterval[]): string {
  const out: string[] = [];
  for (let i = 0; i < intervals.length; i++) {
    const iv: BusinessHourInterval = intervals[i];
    const day: number = Math.floor(iv.startMinute / 1440);
    out.push(`${day}/${formatMinuteOfWeek(iv.startMinute)}-${formatMinuteOfWeek(iv.endMinute)}`);
  }
  return out.join(' ');
}

export function isScheduleAlways(scheduleType: string): boolean {
  return scheduleType === SCHEDULE_ALWAYS;
}

// t.me/m/<link_name> 这类「商家聊天链接」要先问服务器它指向哪个会话
// （getBusinessChatLinkInfo 回 chat_id + 预置文案）。解析不出来就返回 0，
// 由调用方决定退回浏览器——链接过期/被删时正是这条路径。
export async function resolveBusinessChatLink(linkName: string): Promise<number> {
  if (linkName === '') return 0;
  const r: TdRequest = req('getBusinessChatLinkInfo');
  r['link_name'] = linkName;
  try {
    const resp: TdObject = await getTdClient().send(r, 10000);
    return num(resp, 'chat_id');
  } catch (e) {
    return 0;
  }
}

// ---- Business 功能清单与个人介绍 ------------------------------------------
// getBusinessFeatures 返回的是「当前账号可用的 Business 功能」，每一项是一个
// businessFeatureXxx 对象，没有统一的标题字段，只能按 @type 在界面层映射文案。
export interface BusinessFeatureView {
  kind: string;
}

// 已连接机器人：getBusinessConnectedBot 只给 id，名字要另外查。
export async function loadConnectedBotName(botUserId: number): Promise<string> {
  if (botUserId <= 0) {
    return '';
  }
  try {
    const r: TdRequest = req('getUser');
    r['user_id'] = botUserId;
    const user: TdObject = await getTdClient().send(r, 10000);
    const first: string = text(user, 'first_name');
    const last: string = text(user, 'last_name');
    const name: string = `${first}${last !== '' ? ` ${last}` : ''}`.trim();
    return name !== '' ? name : text(user, 'username');
  } catch (e) {
    return '';
  }
}

export async function loadBusinessFeatures(): Promise<BusinessFeatureView[]> {
  try {
    const resp: TdObject = await getTdClient().send(req('getBusinessFeatures'), 15000);
    const items: TdObject[] = list(resp, 'features');
    const out: BusinessFeatureView[] = [];
    for (const item of items) {
      const kind: string = typeOf(item);
      if (kind !== '') {
        out.push({ kind });
      }
    }
    return out;
  } catch (e) {
    const error = e as TdError;
    logW(`loadBusinessFeatures failed: ${error.message}`);
    return [];
  }
}

// 自己的 Business 介绍（标题 + 正文），只读展示：TDLib 没有 setBusinessIntro，
// 编辑入口在官方客户端由服务端支持的 intro 字段完成，这里不伪造写入。
export interface BusinessIntroView {
  title: string;
  message: string;
}

export async function loadBusinessIntro(): Promise<BusinessIntroView | null> {
  try {
    const me: TdObject = await getTdClient().send(req('getMe'), 10000);
    const r: TdRequest = req('getUserFullInfo');
    r['user_id'] = num(me, 'id');
    const full: TdObject = await getTdClient().send(r, 15000);
    const businessInfo: TdObject | null = child(full, 'business_info');
    if (businessInfo === null) {
      return null;
    }
    const intro: TdObject | null = child(businessInfo, 'intro');
    if (intro === null) {
      return null;
    }
    const title: string = text(intro, 'title');
    const message: string = text(intro, 'message');
    if (title === '' && message === '') {
      return null;
    }
    return { title, message };
  } catch (e) {
    const error = e as TdError;
    logW(`loadBusinessIntro failed: ${error.message}`);
    return null;
  }
}
