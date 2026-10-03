export interface RandomService {
  nextInt(maxExclusive: number): number;
}

export const cryptoRandom: RandomService = {
  nextInt: (maxExclusive) => Math.floor(Math.random() * maxExclusive),
};
