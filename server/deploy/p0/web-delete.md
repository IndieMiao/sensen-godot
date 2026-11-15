# gensen.app/delete（SGODOT-484）

页面与服务端真实删除都在本PR，但**未发布域名/部署服务**。正式上线、真实Apple/Google登录和邮件送达需要
用户批准及专用测试账号。只打开页面不能当验收通过；测试必须核原账号存档/身份/token已删除、其他账号不变。

## 路径与部署交接

- 服务端页面：`GET /v1/web/delete/page`，公网服务已有前缀为`/preview/p0`。
- 运维批准后把`https://gensen.app/delete` **内部反代**到
  `https://farm.sensenjoy.cn/preview/p0/v1/web/delete/page`；保持浏览器URL为gensen.app/delete，不用302，Apple Return URL仍是它。
- 页面API基址固定为`https://farm.sensenjoy.cn/preview/p0/v1/web`；Caddy已有剥前缀规则，不把新接口塞到/v1/p0。
- 允许浏览器Origin仅`https://gensen.app`与`https://farm.sensenjoy.cn`；不使用Cookie、不把x-p0-key写进网页。
  TLS/代理可信IP配置需运维核实，API按Fastify req.ip限流，不能把不可信转发头当真实用户。
- Apple网页使用APPLE_SERVICES_IDS（第一项给按钮），不接受App的APPLE_BUNDLE_IDS。
  Google网页使用GOOGLE_CLIENT_IDS的**第一项Web Client ID**，运维必须核第一项确是Web客户端（后续项可为iOS），
  不能把Android/iOS客户端ID拿来渲染Google网页按钮。只有相关配置存在才显示该方式。
- 邮箱严格跟P0_EMAIL_LOGIN和mailer/key可用性显示，关闭时隐藏邮箱栏并拒绝邮箱证明路径；共用App的EmailCodes、限流与mailer。

## 浏览器协议与身份

`GET /v1/web/delete/options` 给配置和十分钟内存challenge、nonce_hash。nonce原文仅服务端留存，
Apple JS popup和Google Identity Services拿nonce_hash申请ID token；服务端复用现有RS256/JWKS/issuer/aud/expiry/nonce验签。
挑战绑定请求IP，随机256位、总量上限2000；每IP整个网页API每分钟30次，邮箱另用共享每地址/IP/全局限额。
挑战与限流记录按期回收，重启失效；没有token、邮箱、验证码存浏览器localStorage或服务端文件。

`POST /v1/web/email/start {email,lang?}` 是App发码handler的另一注册点，经过网页Origin/IP检查；不暴露邮箱有无账号。
这不是另一个码表或额度池。邮件服务短暂处理收件明文；身份查找用既有HMAC(email)，本服务不打印邮箱或验证码。

最终`POST /v1/web/delete`严格接受：
- `{challenge,confirmed:true,provider:"apple"|"google",id_token}`；或
- `{challenge,confirmed:true,provider:"email",email,code}`。

页面有明确不可逆警告、确认勾选及第二次确认，才发最终删除请求。服务器只按验过的provider+sub查已有账号，
不收player/support_code代替身份证明，不建档、不发游戏session。身份不存在回no_farm。
同challenge并发共用操作，成功结果短时幂等；本地写失败时保留已验目标供同challenge重试，避免邮箱码已消费后无法续删。
更换身份或IP不能用原挑战；过期需重新验证。账号被停用仍能依法删除。

删除复用deleteAccount：正常或ACCOUNT_DELETE_INCOMPLETE回ok（后者脱敏告警，交管理补删）；其他异常500 delete_failed。
Apple撤销使用存档已有的aud/refresh回调，不将网页Services ID硬编码到原令牌的client_id；没有refresh时沿共用逻辑记录skip，
撤销失败仍为best effort。需要真Apple测试验证Services ID与App同用户sub的实际关联及撤销结果，不以合成签名代替。

## 验证与限制

本地HTTP测试使用临时磁盘和本地签名RSA令牌，经过真实Apple/Google验签函数并调用真实deleteAccount；
邮箱使用真实共享码服务和假mailer。覆盖三种删除、重复/并发、Origin/IP/nonce/aud/过期/确认拒绝、旧token撤销、
其他账号保留、邮箱开关与共享额度、失败重入。测试不连接真实供应商。

Chromium本地页面英文/中文实走：邮箱→获取假mailer验证码→确认→实际临时存档/身份删除，其他农场保留；
所有外部请求阻断。截图上传484。Apple/Google官方按钮与真实popup尚待专用账号及已部署域名验证，不能报真实登录验收完成。
页面中测试码和未登录新版老号说明沿李白定稿/隐私政策§7，支持邮箱shaojie@gensen.app；不出现游客入口。
