import { CardArtwork } from './CardArtwork'

// No implicit animation on this component: its progress is already interpolated
// by the native phase animator. Culling switches exactly at the edge (90deg).
// Both faces rotate in 3D, so the front ends at 0deg and can never be mirrored.
@ComponentV2
export struct RevealCard {
  @Param rank: string = 'A'
  @Param progress: number = 0
  @Param honest: boolean = true

  build() {
    Stack() {
      CardArtwork({ concealed: true, cardWidth: 76 })
        .rotate({ x: 0, y: 1, z: 0, angle: this.progress * 180, perspective: 900 })
        .opacity(this.progress < 0.5 ? 1 : 0)
      Stack() {
        CardArtwork({ rank: this.rank, cardWidth: 76 })
        // Decoration is a sibling of the art, never a filter/animation on the
        // rotating body. Verdict motion is applied to text elsewhere.
        Column().width(64).height(102).borderRadius(4)
          .border({ width: 1, color: this.honest ? '#C7F2C777' : '#C7FF756D' })
          .shadow({ radius: 14, color: this.honest ? '#66F2C777' : '#59FF756D' })
      }
      .rotate({ x: 0, y: 1, z: 0, angle: this.progress * 180 - 180, perspective: 900 })
      .opacity(this.progress >= 0.5 ? 1 : 0)
    }
    .width(76).height(114)
    .translate({ y: 6 * (1-this.progress) })
    .scale({ x: 0.96 + 0.04*this.progress, y: 0.96 + 0.04*this.progress })
  }
}

// Deliberately independent of RevealCard. No back, rotation or transition is
// present after REVEAL, including when a new snapshot arrives during punishment.
@ComponentV2
export struct StaticRevealedCard {
  @Param rank: string = 'A'
  @Param honest: boolean = true
  build() {
    Stack() {
      CardArtwork({ rank: this.rank, cardWidth: 52 })
      Column().width(44).height(70).borderRadius(4)
        .border({ width: 1, color: this.honest ? '#94F2C777' : '#B8FF756D' })
        .shadow({ radius: 12, color: this.honest ? '#3DF2C777' : '#47FF756D' })
    }.width(52).height(78)
  }
}
