// 全域「触点光透」的**唯一**出口（Beta8 新增）。
//
// 官方依据（华为《点光源效果 Point-Light Effect》指南 +
// SDK @hms.hds.hdsBaseComponent.d.ets 的 PointLightEffect 声明，6.0.0(20) 起）：
//   · 点光源由**组件自身的触摸事件**激发，光源位置就是触点，接口里**没有**传坐标
//     的参数——所以"触点光透"不是自己画光斑，而是把这个面交给系统，让光从触点
//     向外透出来；
//   · 同一组件同时存在的光源数量上限 12，因此不能每个子件都挂，只能挂在"一个
//     可触控面"的根上；
//   · PointLightIlluminatedType：BORDER(1) / CONTENT(2) / BORDER_CONTENT(3) /
//     DEFAULT_FEATHERING_BORDER(20)。BORDER 只照一圈边，大面上几乎看不见——这
//     正是之前的作用（避免输入框、菜单整块发白）；而气泡、胶囊、圆键这种**小面**
//     要的是羽化后的一团柔光，用 DEFAULT_FEATHERING_BORDER 才看得见"光透"。
//
// 与 util/hdsPointLight（hdsVisualEffect）的关系：
//   · hdsPointLight 面向**大面**（菜单/输入框/顶栏），统一 BORDER，历史行为不动；
//   · 本模块面向**小面触点**（气泡、信息胶囊、dock 键、圆键），按面选照亮类型，
//     并且与 hdsPointLight 共用同一套开关判据（pointLightOn / pointShadowOn 的
//     前置：光感档位、省电、材质总开关），保证用户在设置里关掉光感时这里一起灭。
//
// 接入方式（一行）：
//     .visualEffect(touchGlow('bubble'))
// 关闭态返回空 effect（visualEffect 不收 undefined），调用方不需要分支。

import { hdsEffect } from '@kit.UIDesignKit';
import { MATERIAL_EPOCH, OverlaySurface, pointLightOn } from './overlayMaterial';
import { hdsMaterialLevelIndex } from './overlayMaterial';
import { HDS_LEVEL_EXQUISITE } from './materialTuning';

// 可触控面的语义分类。新增界面时优先复用这四类，不要随手加名字——
// 每加一个都要回答"照亮哪儿、光多亮"两个问题。
export type TouchSurface =
  | 'bubble'   // 聊天气泡、通话记录气泡（小面、圆角大，要羽化柔光）
  | 'chip'     // 信息胶囊、dock 按键、圆角小控件（同上，但面积更小）
  | 'bar'      // 顶栏/悬浮条（长条大面，沿用只照边框）
  | 'control'; // 输入框、搜索框（大面，沿用只照边框）

function touchOverlay(surface: TouchSurface): OverlaySurface {
  // 复用 overlayMaterial 已有的面角色，避免再维护一套档位/省电判据。
  switch (surface) {
    case 'bubble':
      return 'bubble';
    case 'chip':
      return 'control';
    case 'bar':
      return 'bar';
    default:
      return 'card';
  }
}

// 小面走羽化照亮，大面保持只照边框。这是本模块与 hdsPointLight 的唯一差异点。
function illuminatedOf(surface: TouchSurface): hdsEffect.PointLightIlluminatedType {
  return surface === 'bubble' || surface === 'chip'
    ? hdsEffect.PointLightIlluminatedType.DEFAULT_FEATHERING_BORDER
    : hdsEffect.PointLightIlluminatedType.BORDER;
}

function sourceTypeOf(): hdsEffect.PointLightSourceType {
  return hdsMaterialLevelIndex() === HDS_LEVEL_EXQUISITE
    ? hdsEffect.PointLightSourceType.BRIGHT
    : hdsEffect.PointLightSourceType.SOFT;
}

function build(surface: TouchSurface): VisualEffect {
  const builder: hdsEffect.HdsEffectBuilder = new hdsEffect.HdsEffectBuilder();
  if (pointLightOn(touchOverlay(surface))) {
    builder.pointLight({
      sourceType: sourceTypeOf(),
      illuminatedType: illuminatedOf(surface),
      // 不填 color = 系统默认光色；不填 height/bloom = 系统默认扩散范围。
      // 小面自己缩范围会更"贴"，但没有实测依据，先不猜参数。
      options: {}
    });
  }
  return builder.buildEffect();
}

// 按「面 + 材质纪元」缓存：气泡数量多（复用池里可见行数十个），每个都新建
// VisualEffect 会在滚动时持续产生垃圾；同一面的 effect 可以共享一份。
const cache: Map<string, VisualEffect> = new Map<string, VisualEffect>();
let cachedEpoch: number = -1;

export function touchGlow(surface: TouchSurface): VisualEffect {
  const epoch: number = AppStorage.get<number>(MATERIAL_EPOCH) ?? 0;
  if (epoch !== cachedEpoch) {
    cache.clear();
    cachedEpoch = epoch;
  }
  const hit: VisualEffect | undefined = cache.get(surface);
  if (hit !== undefined) {
    return hit;
  }
  const built: VisualEffect = build(surface);
  cache.set(surface, built);
  return built;
}

// 明确"不挂"的语义出口：需要在同一处按条件开关时用，读代码比空 builder 直观。
export function touchGlowOff(): VisualEffect {
  return new hdsEffect.HdsEffectBuilder().buildEffect();
}
