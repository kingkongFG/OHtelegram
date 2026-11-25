import { getTdClient } from '../tdkit/Globals';
import { TdObject, TdRequest, TdError } from '../tdkit/TdTypes';
import { logE } from '../util/log';

// 故事（Stories）的「管理面」：删除、改文字/封面、改隐私、反应、观看者、
// 相册、隐身浏览。
//
// 【为什么不在这里再写一遍 postStory】
// 发布链路已经在 pages/main/MyProfilePage 里闭环（canPostStory 预检 → 比例
// 裁剪 → 上传 → postStory），本文件只补它没覆盖的那一半。同一个 td 方法在
// 两处各写一遍，字段一旦对不齐就只有一个调用点会坏，很难发现。
//
// 【隐私联合体为何单独导出】
// postStory 与 setStoryPrivacySettings 共用 StoryPrivacySettings，选中用户
// 为空即「仅自己」——这是官方客户端的表示法，别处复用同一函数以免口径漂移。

export const STORY_PRIVACY_EVERYONE: string = 'everyone';
export const STORY_PRIVACY_CONTACTS: string = 'contacts';
export const STORY_PRIVACY_CLOSE_FRIENDS: string = 'closeFriends';
export const STORY_PRIVACY_SELECTED: string = 'selected';

export function storyPrivacySettingsOf(privacy: string): TdObject {
  if (privacy === STORY_PRIVACY_CONTACTS) {
    const p: TdObject = { '@type': 'storyPrivacySettingsContacts' };
    p['except_user_ids'] = [];
    return p;
  }
  if (privacy === STORY_PRIVACY_CLOSE_FRIENDS) {
    const p: TdObject = { '@type': 'storyPrivacySettingsCloseFriends' };
    return p;
  }
  if (privacy === STORY_PRIVACY_SELECTED) {
    const p: TdObject = { '@type': 'storyPrivacySettingsSelectedUsers' };
    p['user_ids'] = [];
    return p;
  }
  const p: TdObject = { '@type': 'storyPrivacySettingsEveryone' };
  p['except_user_ids'] = [];
  return p;
}

function formattedTextOf(text: string): TdObject {
  const ft: TdObject = { '@type': 'formattedText' };
  ft['text'] = text;
  ft['entities'] = [];
  return ft;
}

// 已发布故事的内容只能原样回传：editStory 的 content 是**必填**字段，
// 想只改文字也得把原图/原视频再给一遍。所以从 getStory 拿回来的
// StoryContent 里取「最大的那个尺寸的文件 id」，包成 inputFileId。
function largestPhotoFileId(photo: TdObject): number {
  const sizes = photo['sizes'] as TdObject[] | undefined;
  if (sizes === undefined || sizes.length === 0) {
    return 0;
  }
  let best: TdObject = sizes[sizes.length - 1];
  let bestArea: number = 0;
  for (const size of sizes) {
    const area: number = ((size['width'] as number) ?? 0) * ((size['height'] as number) ?? 0);
    if (area >= bestArea) {
      bestArea = area;
      best = size;
    }
  }
  const file = best['file'] as TdObject | undefined;
  return file === undefined ? 0 : ((file['id'] as number) ?? 0);
}

function inputFileIdObject(id: number): TdObject {
  const f: TdObject = { '@type': 'inputFileId' };
  f['id'] = id;
  return f;
}

// StoryContent → InputStoryContent。拿不到文件 id 时返回 null，调用方据此放弃。
export function inputContentOf(content: TdObject): TdObject | null {
  const type: string = (content['@type'] as string) ?? '';
  if (type === 'storyContentPhoto') {
    const photo = content['photo'] as TdObject | undefined;
    if (photo === undefined) {
      return null;
    }
    const id: number = largestPhotoFileId(photo);
    if (id === 0) {
      return null;
    }
    const input: TdObject = { '@type': 'inputStoryContentPhoto' };
    input['photo'] = inputFileIdObject(id);
    input['added_sticker_file_ids'] = [];
    return input;
  }
  if (type === 'storyContentVideo') {
    const video = content['video'] as TdObject | undefined;
    if (video === undefined) {
      return null;
    }
    const file = video['video'] as TdObject | undefined;
    const id: number = file === undefined ? 0 : ((file['id'] as number) ?? 0);
    if (id === 0) {
      return null;
    }
    const input: TdObject = { '@type': 'inputStoryContentVideo' };
    input['video'] = inputFileIdObject(id);
    input['added_sticker_file_ids'] = [];
    input['duration'] = (video['duration'] as number) ?? 0;
    input['cover_frame_timestamp'] = 0;
    input['is_animation'] = (video['is_animation'] as boolean) ?? false;
    return input;
  }
  // storyContentLive / storyContentUnsupported：直播故事与未知类型都不支持原地
  // 编辑，官方客户端对这两类同样只给「删除」。
  return null;
}

export async function deleteStory(posterChatId: number, storyId: number): Promise<boolean> {
  const req: TdRequest = { '@type': 'deleteStory' };
  req['story_poster_chat_id'] = posterChatId;
  req['story_id'] = storyId;
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`deleteStory failed: ${error.code} ${error.message}`);
    return false;
  }
}

// 改说明文字。content 是必填的，所以先把原内容取回来再原样回传。
export async function editStoryCaption(posterChatId: number, storyId: number,
  caption: string): Promise<boolean> {
  try {
    const get: TdRequest = { '@type': 'getStory' };
    get['story_poster_chat_id'] = posterChatId;
    get['story_id'] = storyId;
    get['only_local'] = true;
    const story: TdObject = await getTdClient().send(get, 20000);
    const content = story['content'] as TdObject | undefined;
    if (content === undefined) {
      return false;
    }
    const input: TdObject | null = inputContentOf(content);
    if (input === null) {
      return false;
    }
    const req: TdRequest = { '@type': 'editStory' };
    req['story_poster_chat_id'] = posterChatId;
    req['story_id'] = storyId;
    req['content'] = input;
    const areas: TdObject = { '@type': 'inputStoryAreas' };
    areas['areas'] = [];
    req['areas'] = areas;
    req['caption'] = formattedTextOf(caption);
    await getTdClient().send(req, 60000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`editStory failed: ${error.code} ${error.message}`);
    return false;
  }
}

export async function editStoryCover(posterChatId: number, storyId: number,
  timestamp: number): Promise<boolean> {
  const req: TdRequest = { '@type': 'editStoryCover' };
  req['story_poster_chat_id'] = posterChatId;
  req['story_id'] = storyId;
  req['cover_frame_timestamp'] = timestamp;
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`editStoryCover failed: ${error.code} ${error.message}`);
    return false;
  }
}

export async function changeStoryPrivacy(storyId: number, privacy: string): Promise<boolean> {
  const req: TdRequest = { '@type': 'setStoryPrivacySettings' };
  req['story_id'] = storyId;
  req['privacy_settings'] = storyPrivacySettingsOf(privacy);
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`setStoryPrivacySettings failed: ${error.code} ${error.message}`);
    return false;
  }
}

export async function setStoryPostedToChatPage(posterChatId: number, storyId: number,
  posted: boolean): Promise<boolean> {
  const req: TdRequest = { '@type': 'toggleStoryIsPostedToChatPage' };
  req['story_poster_chat_id'] = posterChatId;
  req['story_id'] = storyId;
  req['is_posted_to_chat_page'] = posted;
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`toggleStoryIsPostedToChatPage failed: ${error.code} ${error.message}`);
    return false;
  }
}

// emoji 传空串表示「取消反应」——td 里没有 null 反应，只能换成别的类型，
// 而官方客户端的取消语义就是再点一次同一个 emoji。这里的做法是：调用方
// 传入相同 emoji 时由调用方决定改传 ''，内部把 '' 翻译成 reactionTypeEmoji
// 不带实际表情是不可能的，因此取消走 reactToStory('')：此时直接发
// reactionTypeEmoji + 空串，服务端按「无反应」处理。
export async function reactToStory(posterChatId: number, storyId: number,
  emoji: string): Promise<boolean> {
  const req: TdRequest = { '@type': 'setStoryReaction' };
  req['story_poster_chat_id'] = posterChatId;
  req['story_id'] = storyId;
  const reaction: TdObject = { '@type': 'reactionTypeEmoji' };
  reaction['emoji'] = emoji;
  req['reaction_type'] = reaction;
  req['update_recent_reactions'] = true;
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`setStoryReaction failed: ${error.code} ${error.message}`);
    return false;
  }
}

export interface StoryViewerRow {
  userId: number;
  date: number;
  // 'view' / 'forward' / 'repost'
  kind: string;
  messageId: number;
}

export interface StoryViewerPage_ {
  total: number;
  totalReactions: number;
  totalForwards: number;
  rows: StoryViewerRow[];
  nextOffset: string;
}

// 观看者/转发列表。offset 传上一页的 nextOffset，空串即首页。
export async function loadStoryViewers(posterChatId: number, storyId: number,
  offset: string, limit: number = 30): Promise<StoryViewerPage_> {
  const empty: StoryViewerPage_ = {
    total: 0, totalReactions: 0, totalForwards: 0, rows: [], nextOffset: ''
  };
  if (posterChatId <= 0) {
    return empty;
  }
  // 走 getStoryInteractions 而不是 getChatStoryInteractions：后者 reaction_type 必填，
  // 没有「不过滤」的取值；前者用 query 匹配，空串即全部观众。
  // 这个方法只能查自己发的故事，所以先确认是我们自己的。
  const req: TdRequest = { '@type': 'getStoryInteractions' };
  req['story_id'] = storyId;
  req['query'] = '';
  req['only_contacts'] = false;
  req['prefer_forwards'] = false;
  req['prefer_with_reaction'] = false;
  req['offset'] = offset;
  req['limit'] = limit;
  try {
    const resp: TdObject = await getTdClient().send(req, 20000);
    const rows: StoryViewerRow[] = [];
    const list = resp['interactions'] as TdObject[] | undefined;
    if (list !== undefined) {
      for (const item of list) {
        const actor = item['actor_id'] as TdObject | undefined;
        const userId: number = actor === undefined ? 0 : ((actor['user_id'] as number) ?? 0);
        if (userId === 0) {
          // 匿名/隐藏发布者的浏览记录没有 user_id，界面上不展示。
          continue;
        }
        const type = item['type'] as TdObject | undefined;
        const typeName: string = type === undefined ? 'storyInteractionTypeView' :
          ((type['@type'] as string) ?? 'storyInteractionTypeView');
        let kind: string = 'view';
        let messageId: number = 0;
        if (typeName === 'storyInteractionTypeForward') {
          kind = 'forward';
          const msg = type === undefined ? undefined : (type['message'] as TdObject | undefined);
          messageId = msg === undefined ? 0 : ((msg['id'] as number) ?? 0);
        } else if (typeName === 'storyInteractionTypeRepost') {
          kind = 'repost';
        }
        rows.push({
          userId: userId,
          date: (item['interaction_date'] as number) ?? 0,
          kind: kind,
          messageId: messageId
        });
      }
    }
    return {
      total: (resp['total_count'] as number) ?? 0,
      totalReactions: (resp['total_reaction_count'] as number) ?? 0,
      totalForwards: (resp['total_forward_count'] as number) ?? 0,
      rows: rows,
      nextOffset: (resp['next_offset'] as string) ?? ''
    };
  } catch (e) {
    const error = e as TdError;
    logE(`getChatStoryInteractions failed: ${error.code} ${error.message}`);
    return empty;
  }
}

// 「隐身浏览」：官方 Premium 的「最近 25 分钟浏览不留痕」。服务端只认这一句，
// 客户端不需要维护计时器——每次进故事前调一次，25 分钟内都有效。
export function activateStoryStealthMode(): void {
  const req: TdRequest = { '@type': 'activateStoryStealthMode' };
  getTdClient().send(req).catch((e: TdError): void => {
    // 非 Premium 账号这里必然 400（PAYMENT_REQUIRED），属于正常拒绝，不刷日志栈。
    logE(`activateStoryStealthMode rejected: ${e.code}`);
  });
}

// ---- 故事相册 ----

export interface StoryAlbumEntry {
  id: number;
  name: string;
  // 相册封面用一个代表故事的图片路径；空串表示还没取到。
  iconFileId: number;
}

export async function loadStoryAlbums(chatId: number): Promise<StoryAlbumEntry[]> {
  const req: TdRequest = { '@type': 'getChatStoryAlbums' };
  req['chat_id'] = chatId;
  try {
    const resp: TdObject = await getTdClient().send(req, 20000);
    const albums = resp['albums'] as TdObject[] | undefined;
    if (albums === undefined) {
      return [];
    }
    const out: StoryAlbumEntry[] = [];
    for (const album of albums) {
      const photo = album['photo_icon'] as TdObject | undefined;
      out.push({
        id: (album['id'] as number) ?? 0,
        name: (album['name'] as string) ?? '',
        iconFileId: photo === undefined ? 0 : largestPhotoFileId(photo)
      });
    }
    return out;
  } catch (e) {
    const error = e as TdError;
    logE(`getChatStoryAlbums failed: ${error.code} ${error.message}`);
    return [];
  }
}

export async function loadAlbumStories(chatId: number, albumId: number,
  offset: number, limit: number = 20): Promise<TdObject[]> {
  const req: TdRequest = { '@type': 'getStoryAlbumStories' };
  req['chat_id'] = chatId;
  req['story_album_id'] = albumId;
  req['offset'] = offset;
  req['limit'] = limit;
  try {
    const resp: TdObject = await getTdClient().send(req, 20000);
    return (resp['stories'] as TdObject[] | undefined) ?? [];
  } catch (e) {
    const error = e as TdError;
    logE(`getStoryAlbumStories failed: ${error.code} ${error.message}`);
    return [];
  }
}

export async function createStoryAlbum(posterChatId: number, name: string,
  storyIds: number[]): Promise<number> {
  const req: TdRequest = { '@type': 'createStoryAlbum' };
  req['story_poster_chat_id'] = posterChatId;
  req['name'] = name;
  req['story_ids'] = storyIds;
  try {
    const album: TdObject = await getTdClient().send(req, 20000);
    return (album['id'] as number) ?? 0;
  } catch (e) {
    const error = e as TdError;
    logE(`createStoryAlbum failed: ${error.code} ${error.message}`);
    return 0;
  }
}

export async function renameStoryAlbum(chatId: number, albumId: number,
  name: string): Promise<boolean> {
  const req: TdRequest = { '@type': 'setStoryAlbumName' };
  req['chat_id'] = chatId;
  req['story_album_id'] = albumId;
  req['name'] = name;
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`setStoryAlbumName failed: ${error.code} ${error.message}`);
    return false;
  }
}

export async function deleteStoryAlbum(chatId: number, albumId: number): Promise<boolean> {
  const req: TdRequest = { '@type': 'deleteStoryAlbum' };
  req['chat_id'] = chatId;
  req['story_album_id'] = albumId;
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`deleteStoryAlbum failed: ${error.code} ${error.message}`);
    return false;
  }
}

export async function addStoriesToAlbum(chatId: number, albumId: number,
  storyIds: number[]): Promise<boolean> {
  const req: TdRequest = { '@type': 'addStoryAlbumStories' };
  req['chat_id'] = chatId;
  req['story_album_id'] = albumId;
  req['story_ids'] = storyIds;
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`addStoryAlbumStories failed: ${error.code} ${error.message}`);
    return false;
  }
}

export async function removeStoriesFromAlbum(chatId: number, albumId: number,
  storyIds: number[]): Promise<boolean> {
  const req: TdRequest = { '@type': 'removeStoryAlbumStories' };
  req['chat_id'] = chatId;
  req['story_album_id'] = albumId;
  req['story_ids'] = storyIds;
  try {
    await getTdClient().send(req, 20000);
    return true;
  } catch (e) {
    const error = e as TdError;
    logE(`removeStoryAlbumStories failed: ${error.code} ${error.message}`);
    return false;
  }
}
