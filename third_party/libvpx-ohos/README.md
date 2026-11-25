libvpx（**仅 VP9 解码器**），供透明 webm 贴纸使用。

由 scripts/build-libvpx-ohos.sh 生成，请勿手工修改。
- 版本：86ecca1d566d4e892e8100933832a9510d68a039
- 目标：aarch64-linux-ohos
- 开关：--enable-vp9-decoder --disable-vp8 --disable-vp9-encoder

为什么不复用 libtgcalls_ohos.so 里那份 VP9 解码器、为什么不用系统
OH_AVCodec，见构建脚本开头的注释。
