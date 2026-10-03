import { randomInt } from 'node:crypto';
import { ROOM_CODE_ALPHABET, ROOM_CODE_LENGTH } from '@bluff-tavern/shared';

export type RandomIndex = (max: number) => number;

export function createRoomCode(randomIndex: RandomIndex = randomInt): string {
  return Array.from({ length: ROOM_CODE_LENGTH }, () => ROOM_CODE_ALPHABET[randomIndex(ROOM_CODE_ALPHABET.length)]).join('');
}
