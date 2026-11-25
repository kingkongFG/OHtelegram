import { chatDoodleStrokeColor } from '../../util/chatBubbleGradient';

// 【Beta3 第 2 批】聊天页的「浅色卡通图案纹理」层。
//
// 参考图（微信图片_20261105002155_59_21.jpg）的对话底是**深蓝黑底 + 低透明度
// 浅色手绘小图案**。工程里已有的 PatternTileLayer 只能平铺一张图片母题
// （chatBg.path，来自服务端下发的主题），没有母题时就什么都画不出来；而本批
// 明确禁止新增外部美术资源。所以这里用 Canvas 现画一层极简线稿：斜向网格上
// 交替摆四种小图形（对话气泡、光圈、笑脸、加号），统一一种细线条 + 极低
// 透明度，远看是纹理、近看是小卡通，与参考图的气质一致。
//
// 三条硬约束：
//   · **纯绘制，不引入任何图片文件**（本文件只有 Canvas + 色值常量）；
//   · 不参与点击（hitTestBehavior None，否则会挡气泡/滚动）；
//   · 不跟随时钟/相位重绘（只在本层尺寸或深浅色变化时重画一次），省电。

// 网格间距与线宽（vp）。间距取 96：一屏 360vp 宽约 4 列，图案密度接近参考图，
// 又不至于在长列表滚动时形成视觉噪点。
const DOODLE_CELL: number = 96;
const DOODLE_LINE_WIDTH: number = 1.4;
// 图案整体透明度：再低就看不出，再高就抢文字。
const DOODLE_OPACITY: number = 0.9;

@Component
export struct ChatDoodleLayer {
  // 深浅色：只决定线条颜色（深色近白、浅色近黑），不决定画不画。
  @Prop @Watch('repaint') dark: boolean = true;

  // 本层自己的实测尺寸。@State 而不是 @Prop：尺寸由本节点自己量，别让父组件
  // 每帧替背景层算一遍（父层已经有 areaW/areaH，那套是给壁纸用的窗口尺寸）。
  @State private w: number = 0;
  @State private h: number = 0;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  // onReady 之前画不了（canvas 还没绑定），之后尺寸变化不会再触发 onReady，
  // 所以两个入口都要走 repaint()：ready 标志决定这一次能不能真画。
  private ready: boolean = false;

  private repaint(): void {
    if (this.ready) {
      this.paint();
    }
  }

  private paint(): void {
    const w: number = this.w;
    const h: number = this.h;
    if (w <= 0 || h <= 0) {
      return;
    }
    this.ctx.clearRect(0, 0, w, h);
    this.ctx.lineWidth = DOODLE_LINE_WIDTH;
    this.ctx.strokeStyle = chatDoodleStrokeColor(this.dark);
    this.ctx.fillStyle = chatDoodleStrokeColor(this.dark);
    this.ctx.globalAlpha = DOODLE_OPACITY;

    // 多画一圈/一列（-1 起步、多算一格），保证边缘图案不被裁在半截。
    const cols: number = Math.ceil(w / DOODLE_CELL) + 2;
    const rows: number = Math.ceil(h / DOODLE_CELL) + 2;
    for (let r = -1; r < rows; r++) {
      for (let c = -1; c < cols; c++) {
        // 交错半格，避免形成整齐的方阵（整齐的格子看起来像表格而不是手绘）。
        const ox: number = c * DOODLE_CELL + (r % 2 === 0 ? 0 : DOODLE_CELL / 2);
        const oy: number = r * DOODLE_CELL;
        // 用坐标做伪随机，保证同一屏每次重绘的图案位置完全一致（不随重绘跳变）。
        const seed: number = Math.abs((c * 37 + r * 61) % 4);
        this.drawMotif(seed, ox, oy);
      }
    }
    this.ctx.globalAlpha = 1;
  }

  // 四种母题，按 seed 轮转。传进来的 (x, y) 是这一格的左上角，母题画在格心。
  private drawMotif(seed: number, x: number, y: number): void {
    const cx: number = x + DOODLE_CELL / 2;
    const cy: number = y + DOODLE_CELL / 2;
    if (seed === 0) {
      // 对话气泡：圆角矩形 + 左下小尾巴
      const bw: number = 30;
      const bh: number = 22;
      this.ctx.beginPath();
      this.ctx.moveTo(cx - bw / 2 + 7, cy - bh / 2);
      this.ctx.arcTo(cx + bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2, 7);
      this.ctx.arcTo(cx + bw / 2, cy + bh / 2, cx - bw / 2, cy + bh / 2, 7);
      this.ctx.arcTo(cx - bw / 2, cy + bh / 2, cx - bw / 2, cy - bh / 2, 7);
      this.ctx.arcTo(cx - bw / 2, cy - bh / 2, cx + bw / 2, cy - bh / 2, 7);
      this.ctx.stroke();
      this.ctx.beginPath();
      this.ctx.moveTo(cx - bw / 2 + 6, cy + bh / 2);
      this.ctx.lineTo(cx - bw / 2 + 3, cy + bh / 2 + 6);
      this.ctx.stroke();
    } else if (seed === 1) {
      // 光圈 + 两个小点（"在线/呼叫"的意象）
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, 11, 0, Math.PI * 2);
      this.ctx.stroke();
      this.ctx.beginPath();
      this.ctx.arc(cx, cy, 3, 0, Math.PI * 2);
      this.ctx.fill();
    } else if (seed === 2) {
      // 笑脸：一段弧 + 两只眼睛
      this.ctx.beginPath();
      this.ctx.arc(cx, cy - 2, 11, Math.PI * 0.15, Math.PI * 0.85);
      this.ctx.stroke();
      this.ctx.beginPath();
      this.ctx.arc(cx - 4, cy - 8, 1.3, 0, Math.PI * 2);
      this.ctx.arc(cx + 4, cy - 8, 1.3, 0, Math.PI * 2);
      this.ctx.fill();
    } else {
      // 加号 + 短斜线，凑一点"手账"味
      this.ctx.beginPath();
      this.ctx.moveTo(cx - 9, cy);
      this.ctx.lineTo(cx + 9, cy);
      this.ctx.moveTo(cx, cy - 9);
      this.ctx.lineTo(cx, cy + 9);
      this.ctx.stroke();
      this.ctx.beginPath();
      this.ctx.moveTo(cx + 10, cy + 10);
      this.ctx.lineTo(cx + 16, cy + 16);
      this.ctx.stroke();
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onReady((): void => {
        this.ready = true;
        this.paint();
      })
      // 尺寸靠自身 onAreaChange 量：首帧拿到 0 时宁可不画，也不要按窗口尺寸
      // 画一屏再被裁（分栏时背景只占右栏，按窗宽画会溢到左栏）。
      .onAreaChange((_old: Area, area: Area): void => {
        const w: number = area.width as number;
        const h: number = area.height as number;
        if (w > 0 && h > 0 && (w !== this.w || h !== this.h)) {
          this.w = w;
          this.h = h;
          this.repaint();
        }
      });
  }
}
