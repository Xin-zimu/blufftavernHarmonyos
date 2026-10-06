import { getCardImage, getCardBackImage } from '../utils/ArtResources'

// All supplied card PNGs are 1024 × 1536. A/K/Q are unlettered base art;
// only those need a single rank, while the Joker artwork must remain unobscured.
@ComponentV2
export struct CardArtwork {
  @Param rank: string = 'A'
  @Param concealed: boolean = false
  @Param cardWidth: number = 68

  build() {
    Stack() {
      Image(this.concealed ? getCardBackImage() : getCardImage(this.rank))
        .width('100%').height('100%').objectFit(ImageFit.Contain)
      if (!this.concealed && this.rank !== 'JOKER') {
        Text(this.rank).fontFamily('serif').fontSize(this.cardWidth * 0.43)
          .fontWeight(FontWeight.Bold).fontColor('#5B1F28')
      }
    }
    .width(this.cardWidth).height(this.cardWidth * 1.5)
    .accessibilityText(this.concealed ? '未公开的牌' : this.rank)
  }
}
