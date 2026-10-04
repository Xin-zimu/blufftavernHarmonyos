// 服务器地址集中配置
// 联调时修改 SERVER_URL 后重新编译安装即可（例如指向本机 Node.js 服务器）。
// 生产环境改为正式域名。

export class ServerConfig {
  static readonly SERVER_URL: string = 'http://192.168.2.66:3001'
}
