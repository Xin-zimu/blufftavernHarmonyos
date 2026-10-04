import { z } from 'zod';
import { MAX_CARDS_PER_PLAY, MAX_NICKNAME_LENGTH, MAX_PLAYERS, MIN_NICKNAME_LENGTH, MIN_PLAYERS, PLAYABLE_GAME_MODES, ROOM_CODE_LENGTH, V7_ITEM_IDS } from '../constants/index.js';
import type { Ack, GameCue, GameSnapshot, GameView, RoomMembership, RoomPlayerEvent, RoomView, SessionResumeResult } from '../types/index.js';

export const nicknameSchema = z.string().trim().min(MIN_NICKNAME_LENGTH).max(MAX_NICKNAME_LENGTH);
export const roomCodeSchema = z.string().trim().toUpperCase().length(ROOM_CODE_LENGTH).regex(/^[2-9A-HJ-KM-NP-Z]+$/);
export const createRoomSchema = z.object({ nickname: nicknameSchema });
export const joinRoomSchema = z.object({ nickname: nicknameSchema, roomCode: roomCodeSchema });
export const leaveRoomSchema = z.object({ roomCode: roomCodeSchema });
export const requestIdSchema = z.string().uuid();
export const readyRoomSchema = z.object({ roomCode: roomCodeSchema, ready: z.boolean(), requestId: requestIdSchema });
export const v7ExtensionSettingsPatchSchema = z.object({
  itemsEnabled: z.boolean().optional(),
  tavernEventsEnabled: z.boolean().optional(),
  characterAbilitiesEnabled: z.boolean().optional(),
});
export const updateRoomSettingsSchema = z.object({
  roomCode: roomCodeSchema,
  maxPlayers: z.number().int().min(MIN_PLAYERS).max(MAX_PLAYERS),
  gameMode: z.enum(PLAYABLE_GAME_MODES).default('CLASSIC'),
  turnDurationSeconds: z.number().int().min(5).max(30).optional(),
  eventEnabled: z.boolean().optional(),
  bulletCount: z.number().int().min(1).max(5).nullable().optional(),
  v7: v7ExtensionSettingsPatchSchema.optional(),
  requestId: requestIdSchema,
});
export const kickPlayerSchema = z.object({ roomCode: roomCodeSchema, targetPlayerId: z.string().uuid(), requestId: requestIdSchema });
export const startGameSchema = z.object({ roomCode: roomCodeSchema, requestId: requestIdSchema });
export const playCardsSchema = z.object({
  roomCode: roomCodeSchema,
  cardIndexes: z.array(z.number().int().nonnegative()).min(1).max(MAX_CARDS_PER_PLAY),
  requestId: requestIdSchema,
}).refine((value) => new Set(value.cardIndexes).size === value.cardIndexes.length, { message: 'Card indexes must be unique' });
export const challengeSchema = z.object({ roomCode: roomCodeSchema, requestId: requestIdSchema });
export const restartGameSchema = z.object({ roomCode: roomCodeSchema, requestId: requestIdSchema });
export const returnToRoomSchema = z.object({ roomCode: roomCodeSchema, requestId: requestIdSchema });
export const resumeSessionSchema = z.object({ sessionToken: z.string().min(32).max(256) });
export const selectCharacterSchema = z.object({ roomCode: roomCodeSchema, characterId: z.enum(['WOLF', 'FOX', 'BEAR', 'RABBIT', 'CAT', 'RACCOON', 'FROG', 'PANDA']) });
export const sendEmoteSchema = z.object({ roomCode: roomCodeSchema, emoteId: z.enum(['CHEER', 'SUSPECT', 'BLUFF', 'LAUGH', 'GASP', 'NERVOUS', 'TOAST', 'GOOD_GAME']) });
export const useItemSchema = z.object({ roomCode: roomCodeSchema, itemId: z.enum(V7_ITEM_IDS), requestId: requestIdSchema });

export interface ClientToServerEvents {
  'room:create': (payload: z.input<typeof createRoomSchema>, ack: (result: Ack<RoomMembership>) => void) => void;
  'room:join': (payload: z.input<typeof joinRoomSchema>, ack: (result: Ack<RoomMembership>) => void) => void;
  'room:leave': (payload: z.input<typeof leaveRoomSchema>, ack: (result: Ack<null>) => void) => void;
  'room:ready': (payload: z.input<typeof readyRoomSchema>, ack: (result: Ack<RoomView>) => void) => void;
  'room:updateSettings': (payload: z.input<typeof updateRoomSettingsSchema>, ack: (result: Ack<RoomView>) => void) => void;
  'room:kick': (payload: z.input<typeof kickPlayerSchema>, ack: (result: Ack<RoomView>) => void) => void;
  'game:start': (payload: z.input<typeof startGameSchema>, ack: (result: Ack<GameView>) => void) => void;
  'game:playCards': (payload: z.input<typeof playCardsSchema>, ack: (result: Ack<GameView>) => void) => void;
  'game:challenge': (payload: z.input<typeof challengeSchema>, ack: (result: Ack<GameView>) => void) => void;
  'game:restart': (payload: z.input<typeof restartGameSchema>, ack: (result: Ack<GameView>) => void) => void;
  'game:returnToRoom': (payload: z.input<typeof returnToRoomSchema>, ack: (result: Ack<RoomView>) => void) => void;
  'session:resume': (payload: z.input<typeof resumeSessionSchema>, ack: (result: Ack<SessionResumeResult>) => void) => void;
  'room:selectCharacter': (payload: z.input<typeof selectCharacterSchema>, ack: (result: Ack<RoomView>) => void) => void;
  'game:sendEmote': (payload: z.input<typeof sendEmoteSchema>, ack: (result: Ack<null>) => void) => void;
  'game:useItem': (payload: z.input<typeof useItemSchema>, ack: (result: Ack<GameView>) => void) => void;
}

export interface ServerToClientEvents {
  'room:state': (room: RoomView) => void;
  'room:closed': () => void;
  'room:playerJoined': (event: RoomPlayerEvent) => void;
  'room:playerLeft': (event: RoomPlayerEvent) => void;
  'room:kicked': (message: string) => void;
  'session:replaced': (message: string) => void;
  'game:snapshot': (state: GameSnapshot) => void;
  'game:cue': (event: GameCue) => void;
  'game:state': (state: GameView) => void;
  'game:turnStarted': (state: GameView) => void;
  'game:cardsPlayed': (event: { playerId: string; count: number | null; roundNumber: number }) => void;
  'game:challengeStarted': (event: { challengerId: string; challengedPlayerId: string }) => void;
  'game:challengeResult': (state: GameView) => void;
  'game:punishmentStarted': (event: { playerId: string; chamber: number }) => void;
  'game:punishmentResult': (state: GameView) => void;
  'game:playerEliminated': (event: { playerId: string }) => void;
  'game:over': (state: GameView) => void;
  'game:emote': (event: { playerId: string; emoteId: z.infer<typeof sendEmoteSchema>['emoteId'] }) => void;
}

export type InterServerEvents = Record<string, never>;
export interface SocketData { playerId?: string; roomCode?: string }
