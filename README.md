## 与上游项目的区别

本 fork 只会对 android 部分的内容进行修改.

额外功能(勾选项即为上游仓库后来已实现):

- 支持独立于系统音量的应用内音量调节与倍率放大，可设置更大的播放音量。
- 优化横向手势拖动视频时的进度条 cursor 显示, 拖动定位更明显。
- 优化全屏横向手势的方向锁定, 先轻微竖向滑动后也能更稳定地拖动调整进度
- 视频播放器在进度条下方新增逐帧调整按钮, 并移除左右切集按钮, 支持前后逐帧查看并减少误触.
- 视频封面长按弹窗支持直接选择不感兴趣。
- 检测更新时改为提示同步上游仓库, 不直接提示下载上游 release。
- 关闭全局相对滑动时, 可为短于指定时长阈值的视频单独启用相对时长拖动.
- 评论"前往"按钮支持在跳转视频时自动切换并聚焦到对应评论楼层.
- 视频评论区和子评论页新增评论查找按钮, 支持评论用户联想选择, 多用户查找, 关键词, 时间段和常用条件快速过滤已加载评论.
  - 视频评论楼中楼查找面板新增"楼主"复选框, 可快速筛选一级评论作者的回复.
  - 视频评论区和子评论页的评论查找新增IP属地过滤, 并会列出当前评论区中存在的属地供快速查找.
  - 评论查找面板新增搜索楼中楼开关, 可控制是否将楼中楼回复纳入查找结果.
  - 评论查找面板将关键词输入框调整到顶部并重排输入项顺序, 新增点赞数上下界筛选, 留空时对应方向不设边界.
- 空降助手的手动跳过按钮改为在片段区域内持续显示, 不再只在片段起点附近短暂出现, 点击跳转后也不会再短暂闪现.
- [x] 搜索页面和搜索结果中的 HTML 实体会被正确解码, 不再显示为编码形式.
- 设置中的推荐标题, 分区, 评论, 动态关键词过滤改为规则列表, 支持逐项启用或停用, 并可按正则或原文匹配.
- 空降助手跳过时支持跳到片段结束前的可配置时长, 并在偏移过大或当前位置已越过目标点时自动避免回跳.
- 首页推荐视频卡片在播放量和弹幕数量一行新增发布时间显示, 并在 app 推荐缺失字段时自动补拉详情.
- 直播 SC 列表支持保留本次直播已获取的历史记录, 自下向上显示, 并展示发送时间.
- Android 端屏蔽异常 hover 事件, 避免出现固定位置的悬浮高亮或类似虚拟光标的效果.
- 评论区新增本地按点赞数量排序, 可对当前已加载评论和楼中楼回复手动按赞数重排, 加载更多后可再次触发重排.
- 高能进度条在缺少官方 pbp 数据时支持异步抽样弹幕估算, 并以不同颜色显示.
- 评论区新增屏蔽纯 @ 用户评论开关, 可过滤忽略空白后仅包含 @ 用户提及的评论.
- 向仓库 push 非文档改动后, 会自动构建所有支持平台的安装包, 并上传到对应 GitHub Actions 运行的 artifacts.

---

<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>



<div align="center">
    <h1>PiliPlus</h1>
<div align="center">

![GitHub repo size](https://img.shields.io/github/repo-size/bggRGjQaUbCoE/PiliPlus)
![GitHub Repo stars](https://img.shields.io/github/stars/bggRGjQaUbCoE/PiliPlus)
![GitHub all releases](https://img.shields.io/github/downloads/bggRGjQaUbCoE/PiliPlus/total)
</div>
    <p>使用Flutter开发的BiliBili第三方客户端</p>

<img src="assets/screenshots/510shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/174shots_so.png" width="32%" alt="home" />
<img src="assets/screenshots/850shots_so.png" width="32%" alt="home" />
<br/>
<img src="assets/screenshots/main_screen.png" width="96%" alt="home" />
<br/>
</div>


<br/>

## 适配平台

- [x] Android
- [x] iOS
- [x] Pad
- [x] Windows
- [x] Linux

[![Packaging status](https://repology.org/badge/vertical-allrepos/piliplus.svg)](https://repology.org/project/piliplus/versions)

## refactor

- [ ] gRPC [wip]
- [x] 用户界面
- [x] 其他

## feat

- [x] 编辑动态
- [x] DLNA 投屏
- [x] 离线缓存/播放
- [x] 移动端支持点击弹幕悬停，点赞、复制、举报
  by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 播放音频
- [x] 跳过番剧片头/片尾
- [x] 安卓端 `loudnorm` 适配 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] Win/Mac 支持极验、短信登录 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 视频截取动图 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] AI 原声翻译
- [x] SuperChat
- [x] 播放课堂视频
- [x] 发起投票
- [x] 发布动态/评论支持`富文本编辑`/`表情显示`/`@用户`
- [x] 修改消息设置
- [x] 修改聊天设置
- [x] 展示折叠消息
- [x] 查看用户图文
- [x] 动态话题
- [x] 直播分区
- [x] 分享`视频`/`番剧`/`动态`/`专栏`/`直播`至消息
- [x] 创建/修改/删除关注分组
- [x] 移除粉丝
- [x] 直播弹幕发送表情
- [x] 收藏夹排序
- [x] 稍后再看 ~~`未看`~~ / `未看完` / ~~`已看完`~~ 分类
- [x] WebDAV 备份/恢复设置
- [x] 保存评论/动态
- [x] 高级弹幕 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 取消/置顶评论
- [x] 记笔记
- [x] 多账号支持 by [@My-Responsitories](https://github.com/My-Responsitories)
- [x] 屏蔽带货动态/评论
- [x] 互动视频
- [x] 发评/动态反诈
- [x] 高能进度条
- [x] 滑动跳转预览视频缩略图
- [x] Live Photo
- [x] 复制/移动/排序收藏夹/稍后再看视频
- [x] 超分辨率
- [x] 合并弹幕
- [x] 会员彩色弹幕
- [x] 播放全部/继续播放/倒序播放
- [x] Cookie登录
- [x] 显示视频分段信息
- [x] 调节字幕大小
- [x] 调节全屏弹幕大小
- [x] 收藏夹/稍后再看多选删除
- [x] 搜索用户动态
- [x] 直播弹幕
- [x] 修改头像/用户名/签名/性别/生日
- [x] 创建/编辑/删除收藏夹
- [x] 评论楼中楼查看对话
- [x] 评论楼中楼定位点击查看的评论
- [x] 评论楼中楼按热度/时间排序
- [x] 评论点踩
- [x] 私信发图
- [x] 投币动画
- [x] 取消/追番，更新追番状态
- [x] 取消/订阅合集
- [x] SponsorBlock
- [x] 显示视频完整合集
- [x] 三连动画
- [x] 番剧三连
- [x] 带图评论
- [x] 视频TAG
- [x] 筛选搜索
- [x] 转发动态
- [x] 合集图片
- [x] 删除/置顶/撤回私信
- [x] 举报用户/评论/视频/动态
- [x] 删除/发布/置顶文本/图片动态
- [x] 其他

## opt

- [x] 专栏界面
- [x] 私信界面
- [x] 收藏面板
- [x] PIP
- [x] 视频封面
- [x] 回复界面
- [x] 系统通知
- [x] 评论显示
- [x] 亮度调节
- [x] 视频播放
- [x] 视频staff
- [x] 防止bottomsheet遮挡全屏视频
- [x] 其他

## fix

- [x] 番剧分集点赞/投币/收藏
- [x] bugs

<br/>

## 功能

- [x] 推荐视频列表(app端)
- [x] 最热视频列表
- [x] 热门直播
- [x] 番剧列表
- [x] 屏蔽黑名单内用户视频
- [x] 无痕模式（播放视为未登录）
- [x] 游客模式（推荐视为未登录）

- [x] 用户相关
    - [x] 粉丝、关注用户、拉黑用户查看
    - [x] 用户主页查看
    - [x] 关注/取关用户
    - [x] 离线缓存
    - [x] 稍后再看
    - [x] 观看记录
    - [x] 我的收藏
    - [x] 站内私信

- [x] 动态相关
    - [x] 全部、投稿、番剧分类查看
    - [x] 动态评论查看
    - [x] 动态评论回复功能

- [x] 视频播放相关
    - [x] 双击快进/快退
    - [x] 双击播放/暂停
    - [x] 垂直方向调节亮度/音量
    - [x] 垂直方向上滑全屏、下滑退出全屏
    - [x] 水平方向手势快进/快退
    - [x] 全屏方向设置
    - [x] 倍速选择/长按2倍速
    - [x] 硬件加速（视机型而定）
    - [x] 画质选择（高清画质未解锁）
    - [x] 音质选择（视视频而定）
    - [x] 解码格式选择（视视频而定）
    - [x] 弹幕
    - [x] 字幕
    - [x] 记忆播放
    - [x] 视频比例：高度/宽度适应、填充、包含等

- [x] 搜索相关
    - [x] 热搜
    - [x] 搜索历史
    - [x] 默认搜索词
    - [x] 投稿、番剧、直播间、用户搜索
    - [x] 视频搜索排序、按时长筛选

- [x] 视频详情页相关
    - [x] 视频选集(分p)切换
    - [x] 点赞、投币、收藏/取消收藏
    - [x] 相关视频查看
    - [x] 评论用户身份标识
    - [x] 评论(排序)查看、二楼评论查看
    - [x] 主楼、二楼评论回复功能
    - [x] 评论点赞
    - [x] 评论笔记图片查看、保存

- [x] 设置相关
    - [x] 画质、音质、解码方式预设
    - [x] 图片质量设定
    - [x] 主题模式：亮色/暗色/跟随系统
    - [x] 震动反馈(可选)
    - [x] 高帧率
    - [x] 自动全屏
    - [x] 横屏适配
- [ ] 等等

<br/>

## 下载

可以通过右侧release进行下载或拉取代码到本地进行编译

<br/>

## 声明

此项目（PiliPlus）是个人为了兴趣而开发，仅用于学习和测试，请于下载后24小时内删除。
所用API皆从官方网站收集，不提供任何破解内容。
在此致敬原作者：[guozhigq/pilipala](https://github.com/guozhigq/pilipala)
在此致敬上游作者：[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)
本仓库做了更激进的修改，感谢原作者的开源精神。

感谢使用


<br/>

## 致谢

- [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)
- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- 等等

<br/>
<br/>
<br/>

## Star History

<a href="https://www.star-history.com/#bggRGjQaUbCoE/PiliPlus&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
 </picture>
</a>
