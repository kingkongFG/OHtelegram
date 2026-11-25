import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest } from '../tdkit/TdTypes';

// Telegram Premium 数据层。
//
// 字段名不是猜的：全部对着 td/generate/scheme/td_api.tl（TDLib 权威 schema）
// 逐个核过，且每个字段名都能在随包的 libtdjson.so 里命中字符串——采购版 so 是
// 1.8.65，premiumState 的 animations / business_animations 这两个 1.8.6x 之后
// 才加的字段在本包不一定齐，所以下面每个读取都做存在性兜底，缺字段只是少一行，
// 不会让整页崩。

export interface PremiumPaymentOption {
  currency: string;
  amount: number;          // 最小货币单位（分），显示时 /100
  discountPercentage: number;
  monthCount: number;
  isCurrent: boolean;
  isUpgrade: boolean;
}

export interface PremiumLimit {
  type: string;            // premiumLimitTypeXxx
  defaultValue: number;
  premiumValue: number;
}

export interface PremiumFeatures {
  features: string[];      // premiumFeatureXxx
  limits: PremiumLimit[];
  paymentLink: string;     // payment_link 的 @type，空串表示无外链
}

export interface PremiumState {
  isPremium: boolean;      // 取自 getMe().is_premium，不看文案猜
  stateText: string;       // premiumState.state 的富文本正文（到期时间等）
  options: PremiumPaymentOption[];
}

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

function child(o: TdObject, key: string): TdObject | null {
  const v: Object = o[key];
  // TdObject 是 Record<string, Object>，类型上不含 undefined，但服务器不下发某字段
  // 时运行时就是 undefined——typeof 判断对两者都安全，别换成 v !== null 那种写法。
  return (typeof v === 'object' && v !== null) ? v as TdObject : null;
}

function list(o: TdObject, key: string): TdObject[] {
  const v: Object = o[key];
  return Array.isArray(v) ? v as TdObject[] : [];
}

function typeOf(o: TdObject | null): string {
  return o === null ? '' : text(o, '@type');
}

// premiumState.state 是 formattedText，不是裸字符串。
function formattedTextOf(o: TdObject | null): string {
  if (o === null) { return ''; }
  return text(o, 'text');
}

function toOption(raw: TdObject): PremiumPaymentOption {
  const po: TdObject | null = child(raw, 'payment_option');
  return {
    currency: po === null ? '' : text(po, 'currency'),
    amount: po === null ? 0 : num(po, 'amount'),
    discountPercentage: po === null ? 0 : num(po, 'discount_percentage'),
    monthCount: po === null ? 0 : num(po, 'month_count'),
    isCurrent: flag(raw, 'is_current'),
    isUpgrade: flag(raw, 'is_upgrade')
  };
}

export async function loadPremiumState(): Promise<PremiumState> {
  const stateReq: TdRequest = { '@type': 'getPremiumState' };
  const meReq: TdRequest = { '@type': 'getMe' };
  const results: TdObject[] = await Promise.all([
    getTdClient().send(stateReq, 15000),
    getTdClient().send(meReq, 15000)
  ]);
  const state: TdObject = results[0];
  const me: TdObject = results[1];
  const rows: TdObject[] = list(state, 'payment_options');
  const options: PremiumPaymentOption[] = rows.map(
    (raw: TdObject): PremiumPaymentOption => toOption(raw));
  return {
    isPremium: flag(me, 'is_premium'),
    stateText: formattedTextOf(child(state, 'state')),
    options: options
  };
}

// source 用 premiumSourceSettings：设置页进入时官方也是这个来源，
// 不同 source 会影响后端返回的 feature 排序与是否下发限时优惠。
export async function loadPremiumFeatures(): Promise<PremiumFeatures> {
  const source: TdObject = { '@type': 'premiumSourceSettings' };
  const req: TdRequest = { '@type': 'getPremiumFeatures' };
  req['source'] = source;
  const resp: TdObject = await getTdClient().send(req, 15000);
  const featureRows: TdObject[] = list(resp, 'features');
  const limitRows: TdObject[] = list(resp, 'limits');
  return {
    features: featureRows.map((row: TdObject): string => typeOf(row)),
    limits: limitRows.map((row: TdObject): PremiumLimit => {
      return {
        type: typeOf(child(row, 'type')),
        defaultValue: num(row, 'default_value'),
        premiumValue: num(row, 'premium_value')
      };
    }),
    paymentLink: typeOf(child(resp, 'payment_link'))
  };
}

// ---- 文案键映射 ----------------------------------------------------------
// 29 个 PremiumFeature 与 22 个 PremiumLimitType 都是 so 里逐个核对过的枚举值。
// 用 Record 而不是 switch：后面官方加类型时只补一行，漏了会落到 generic 文案，
// 不会因为少一个分支就整页空白。

const FEATURE_KEYS: Record<string, string> = {
  'premiumFeatureAccentColor': 'premium_feat_accent_color',
  'premiumFeatureAdvancedChatManagement': 'premium_feat_advanced_chat_management',
  'premiumFeatureAnimatedProfilePhoto': 'premium_feat_animated_profile_photo',
  'premiumFeatureAppIcons': 'premium_feat_app_icons',
  'premiumFeatureBackgroundForBoth': 'premium_feat_background_for_both',
  'premiumFeatureBusiness': 'premium_feat_business',
  'premiumFeatureChatBoost': 'premium_feat_chat_boost',
  'premiumFeatureChecklists': 'premium_feat_checklists',
  'premiumFeatureCustomEmoji': 'premium_feat_custom_emoji',
  'premiumFeatureDisabledAds': 'premium_feat_disabled_ads',
  'premiumFeatureEmojiStatus': 'premium_feat_emoji_status',
  'premiumFeatureForumTopicIcon': 'premium_feat_forum_topic_icon',
  'premiumFeatureImprovedDownloadSpeed': 'premium_feat_download_speed',
  'premiumFeatureIncreasedLimits': 'premium_feat_increased_limits',
  'premiumFeatureIncreasedUploadFileSize': 'premium_feat_upload_size',
  'premiumFeatureLastSeenTimes': 'premium_feat_last_seen_times',
  'premiumFeatureMessageEffects': 'premium_feat_message_effects',
  'premiumFeatureMessagePrivacy': 'premium_feat_message_privacy',
  'premiumFeaturePaidMessages': 'premium_feat_paid_messages',
  'premiumFeatureProfileBadge': 'premium_feat_profile_badge',
  'premiumFeaturePromotionAnimation': 'premium_feat_promotion_animation',
  'premiumFeatureProtectPrivateChatContent': 'premium_feat_protect_content',
  'premiumFeatureRealTimeChatTranslation': 'premium_feat_realtime_translation',
  'premiumFeatureSavedMessagesTags': 'premium_feat_saved_messages_tags',
  'premiumFeatureTextComposition': 'premium_feat_text_composition',
  'premiumFeatureUniqueReactions': 'premium_feat_unique_reactions',
  'premiumFeatureUniqueStickers': 'premium_feat_unique_stickers',
  'premiumFeatureUpgradedStories': 'premium_feat_upgraded_stories',
  'premiumFeatureVoiceRecognition': 'premium_feat_voice_recognition'
};

const LIMIT_KEYS: Record<string, string> = {
  'premiumLimitTypeActiveStoryCount': 'premium_limit_active_story',
  'premiumLimitTypeBioLength': 'premium_limit_bio_length',
  'premiumLimitTypeCaptionLength': 'premium_limit_caption_length',
  'premiumLimitTypeChatFolderChosenChatCount': 'premium_limit_folder_chat_count',
  'premiumLimitTypeChatFolderCount': 'premium_limit_folder_count',
  'premiumLimitTypeChatFolderInviteLinkCount': 'premium_limit_folder_invite',
  'premiumLimitTypeCreatedPublicChatCount': 'premium_limit_public_chats',
  'premiumLimitTypeCustomTextCompositionStyleCount': 'premium_limit_text_styles',
  'premiumLimitTypeFavoriteStickerCount': 'premium_limit_favorite_stickers',
  'premiumLimitTypeMessageTextLength': 'premium_limit_message_length',
  'premiumLimitTypeMonthlyPostedStoryCount': 'premium_limit_story_monthly',
  'premiumLimitTypeOwnedBotCount': 'premium_limit_owned_bots',
  'premiumLimitTypePinnedArchivedChatCount': 'premium_limit_pinned_archived',
  'premiumLimitTypePinnedChatCount': 'premium_limit_pinned_chats',
  'premiumLimitTypePinnedSavedMessagesTopicCount': 'premium_limit_pinned_saved',
  'premiumLimitTypeSavedAnimationCount': 'premium_limit_saved_animations',
  'premiumLimitTypeShareableChatFolderCount': 'premium_limit_shareable_folders',
  'premiumLimitTypeSimilarChatCount': 'premium_limit_similar_chats',
  'premiumLimitTypeStoryCaptionLength': 'premium_limit_story_caption',
  'premiumLimitTypeStorySuggestedReactionAreaCount': 'premium_limit_story_reactions',
  'premiumLimitTypeSupergroupCount': 'premium_limit_supergroups',
  'premiumLimitTypeWeeklyPostedStoryCount': 'premium_limit_story_weekly'
};

export function premiumFeatureKey(type: string): string {
  const key: string | undefined = FEATURE_KEYS[type];
  return key !== undefined ? key : 'premium_feat_generic';
}

export function premiumLimitKey(type: string): string {
  const key: string | undefined = LIMIT_KEYS[type];
  return key !== undefined ? key : 'premium_limit_generic';
}

// 任意限额类型都能算「会员多出多少倍」，用于列表右侧的 +N% 角标。
export function premiumLimitGain(limit: PremiumLimit): number {
  if (limit.defaultValue <= 0) { return 0; }
  return Math.round((limit.premiumValue - limit.defaultValue) * 100 / limit.defaultValue);
}

// premiumPaymentOption.amount 是最小货币单位（美分/欧分等），官方客户端也按
// /100 展示；币种符号未知时退化成 "1.45 USD"。
export function formatPremiumPrice(option: PremiumPaymentOption): string {
  const value: number = option.amount / 100;
  const fixed: string = value.toFixed(2);
  const currency: string = option.currency === '' ? '' : ` ${option.currency}`;
  return `${fixed}${currency}`;
}
