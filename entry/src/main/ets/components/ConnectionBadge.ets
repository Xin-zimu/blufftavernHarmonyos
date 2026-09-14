// 连接状态指示器组件

import { ConnectionStatus } from '../model/GameTypes'

@Component
export struct ConnectionBadge {
  @Prop status: ConnectionStatus = 'connecting'

  build() {
    Row() {
      Circle()
        .width(8)
        .height(8)
        .fill(this.status === 'connected' ? '#4CAF50' :
              this.status === 'connecting' ? '#FFC107' : '#F44336')

      Text(this.status === 'connected' ? '已连接' :
           this.status === 'connecting' ? '连接中' : '未连接')
        .fontSize(10)
        .fontColor('#888899')
        .margin({ left: 4 })
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor('#2A2A4E')
    .borderRadius(12)
  }
}
