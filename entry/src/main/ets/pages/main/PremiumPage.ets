import { promptAction } from '@kit.ArkUI';
import {
  PremiumLimit, PremiumPaymentOption, formatPremiumPrice, loadPremiumFeatures, loadPremiumState,
  premiumFeatureKey, premiumLimitGain, premiumLimitKey
} from '../../store/PremiumApi';
import { TdError } from '../../tdkit/TdTypes';
import {
  COLOR_DIVIDER, COLOR_PAGE_BG, COLOR_SURFACE, COLOR_TEXT_PRIMARY, COLOR_TEXT_SECONDARY
} from '../../util/theme';
import { logE } from '../../util/log';
import { str } from '../../util/strings';
import { HdsSubDestination } from '../common/HdsSubDestination';

const CARD_RADIUS: number = 14;
const PREMIUM_GOLD: string = '#E9A81B';
const FREE_GREY: string = '#8E8E93';

// 路由表（router_map.json）的 buildFunction 指向这里，页面因此不进 main_pages.json
// ——一个页面不能同时是 router 页和 NavDestination。形状与 EmojiStatusPageBuilder 一致。
@Builder
export function PremiumPageBuilder(): void {
  PremiumPage();
}

@Component
export struct PremiumPage {
  private hdsScroller: Scroller = new Scroller();
  @StorageProp('topSafeHeight') topSafe: number = 0;
  @StorageProp('bottomSafeHeight') bottomSafe: number = 0;
  @State loadState: string = 'loading';
  @State isPremium: boolean = false;
  @State stateText: string = '';
  @State options: PremiumPaymentOption[] = [];
  @State features: string[] = [];
  @State limits: PremiumLimit[] = [];
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
    Promise.all([loadPremiumState(), loadPremiumFeatures()]).then((res): void => {
      if (!this.active) { return; }
      this.isPremium = res[0].isPremium;
      this.stateText = res[0].stateText;
      this.options = res[0].options;
      this.features = res[1].features;
      this.limits = res[1].limits;
      this.loadState = 'ready';
    }).catch((error: TdError): void => {
      if (!this.active) { return; }
      logE(`PremiumPage.load failed: ${error.message}`);
      this.loadState = 'error';
    });
  }

  // 官方客户端的订阅按钮走应用内支付（Google Play / App Store）。本客户端没有
  // 接支付通道，所以这里只提示，不做假流程——点了就有反应的假按钮比没按钮更糟。
  private onOptionTap(option: PremiumPaymentOption): void {
    promptAction.showToast({
      message: str(option.amount > 0 ? 'premium_payment_unavailable' : 'premium_no_options'),
      duration: 2200
    });
  }

  @Builder
  statusCard() {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.star_fill')).fontSize(26)
          .fontColor([Color.White]);
      }
      .width(54).height(54).borderRadius(27)
      .backgroundColor(this.isPremium ? PREMIUM_GOLD : FREE_GREY);

      Column({ space: 4 }) {
        Text(str(this.isPremium ? 'premium_status_active' : 'premium_status_free'))
          .fontSize(17).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY)
          .width('100%');
        if (this.stateText !== '') {
          Text(this.stateText).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .lineHeight(17).width('100%').maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis });
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding(14)
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  optionRow(option: PremiumPaymentOption, last: boolean) {
    Column() {
      Row({ space: 10 }) {
        Column({ space: 3 }) {
          Text(str('premium_month_count', option.monthCount))
            .fontSize(15).fontColor(COLOR_TEXT_PRIMARY).width('100%');
          if (option.isCurrent) {
            Text(str('premium_current')).fontSize(11).fontColor(PREMIUM_GOLD).width('100%');
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);

        if (option.discountPercentage > 0) {
          // 百分号在代码里拼，不进资源串：带参数的资源串里出现裸 % 会被当成
          // 格式化占位符，sprintf 目标上一律是麻烦。
          Text(`-${option.discountPercentage}%`).fontSize(12).fontColor(Color.White)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(PREMIUM_GOLD).borderRadius(8);
        }

        Text(formatPremiumPrice(option))
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLOR_TEXT_PRIMARY);
      }
      .width('100%').height(52).padding({ left: 14, right: 14 });

      if (!last) {
        Divider().color(COLOR_DIVIDER).strokeWidth(0.5).margin({ left: 14, right: 14 });
      }
    }.width('100%')
    .onClick((): void => this.onOptionTap(option));
  }

  @Builder
  subscribeCard() {
    Column({ space: 0 }) {
      if (this.options.length === 0) {
        Column({ space: 6 }) {
          Text(str('premium_no_options')).fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
            .width('100%');
          Text(str('premium_subscribe_hint')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
            .lineHeight(17).width('100%');
        }.width('100%').padding(14).alignItems(HorizontalAlign.Start);
      } else {
        ForEach(this.options, (option: PremiumPaymentOption, index: number) => {
          this.optionRow(option, index === this.options.length - 1);
        }, (option: PremiumPaymentOption): string => `opt_${option.monthCount}_${option.isCurrent}`);
      }
    }
    .width('100%').backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  featuresCard() {
    Column({ space: 0 }) {
      Text(str('premium_benefits')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 4 })
        .textAlign(TextAlign.Start);
      ForEach(this.features, (type: string, index: number) => {
        Column() {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(15)
              .fontColor([this.isPremium ? PREMIUM_GOLD : FREE_GREY]);
            Text(str(premiumFeatureKey(type))).fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
              .layoutWeight(1);
          }
          .width('100%').height(42).padding({ left: 14, right: 14 });
          if (index !== this.features.length - 1) {
            Divider().color(COLOR_DIVIDER).strokeWidth(0.5).margin({ left: 40, right: 14 });
          }
        }.width('100%');
      }, (type: string): string => `feat_${type}`);
    }
    .width('100%').padding({ bottom: 6 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  @Builder
  limitsCard() {
    Column({ space: 0 }) {
      Text(str('premium_limits')).fontSize(12).fontColor(COLOR_TEXT_SECONDARY)
        .width('100%').padding({ left: 14, right: 14, top: 12, bottom: 4 });
      ForEach(this.limits, (limit: PremiumLimit, index: number) => {
        Column() {
          Row({ space: 10 }) {
            Text(str(premiumLimitKey(limit.type))).fontSize(14).fontColor(COLOR_TEXT_PRIMARY)
              .layoutWeight(1);
            Text(str('premium_limit_values', limit.defaultValue, limit.premiumValue))
              .fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
            if (premiumLimitGain(limit) > 0) {
              Text(`+${premiumLimitGain(limit)}%`).fontSize(11).fontColor(PREMIUM_GOLD);
            }
          }
          .width('100%').height(42).padding({ left: 14, right: 14 });
          if (index !== this.limits.length - 1) {
            Divider().color(COLOR_DIVIDER).strokeWidth(0.5).margin({ left: 14, right: 14 });
          }
        }.width('100%');
      }, (limit: PremiumLimit): string => `lim_${limit.type}`);
    }
    .width('100%').padding({ bottom: 6 })
    .backgroundColor(COLOR_SURFACE).borderRadius(CARD_RADIUS);
  }

  build() {
    Column() {
      HdsSubDestination({
        title: str('settings_premium'),
        pageBackground: COLOR_PAGE_BG,
        scroller: this.hdsScroller,
        subTitle: this.loadState === 'ready'
          ? str(this.isPremium ? 'premium_status_active' : 'premium_status_free') : ''
      }) {
        Column() {
          if (this.loadState === 'loading') {
            Column({ space: 9 }) {
              LoadingProgress().width(32).height(32).color(PREMIUM_GOLD);
              Text(str('premium_loading')).fontSize(13).fontColor(COLOR_TEXT_SECONDARY);
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
                if (!this.isPremium) {
                  this.subscribeCard();
                }
                if (this.features.length > 0) {
                  this.featuresCard();
                }
                if (this.limits.length > 0) {
                  this.limitsCard();
                }
                Text(str('premium_note'))
                  .fontSize(12).fontColor(COLOR_TEXT_SECONDARY).lineHeight(18).width('100%');
              }.width('100%').padding({ left: 12, right: 12, bottom: this.bottomSafe + 24 });
            }
            // Scroll 的 align 默认是 Center：内容比视口短时整块会被垂直居中，
            // 页面就悬在屏幕中间离标题老远。全应用纵向滚动区都要显式写这句。
            .align(Alignment.Top)
            .layoutWeight(1).width('100%').scrollBar(BarState.Off)
            .clip(false);
          }
        }.width('100%').height('100%');
      }
    }.width('100%').height('100%');
  }
}
