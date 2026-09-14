// 连接状态徽章组件

import { ConnectionStatus } from '../model/GameTypes'

@Component
export struct ConnectionBadge {
  @Prop status: ConnectionStatus = 'disconnected'

  private getStatusText(): string {
    if (this.status === 'connected') return '已连接'
    if (this.status === 'connecting') return '连接中...'
    if (this.status === 'reconnecting') return '重连中...'
    return '已断开'
  }

  private getStatusColor(): string {
    if (this.status === 'connected') return '#4CAF50'
    if (this.status === 'connecting') return '#FFC107'
    if (this.status === 'reconnecting') return '#FF9800'
    return '#F44336'
  }

  build() {
    Row() {
      // 状态指示灯
      Circle({ width: 8, height: 8 })
        .fill(this.getStatusColor())

      Text(this.getStatusText())
        .fontSize(12)
        .fontColor(this.getStatusColor())
        .margin({ left: 6 })
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .borderRadius(12)
    .backgroundColor('#1A1A2E')
    .border({ width: 1, color: '#333355', style: BorderStyle.Solid })
  }
}
