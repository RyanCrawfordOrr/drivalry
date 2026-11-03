# Drivalry: Convoy protocol

> How 2–6 cars share one session: signaling, the peer-to-peer mesh, positions, stops, chat, music sync, recap. Everything here runs on phones plus Supabase Realtime; nothing is a server we operate. Budget rules are in `03-architecture.md` §9–§10.

## 1. Pieces

| Piece | Transport | Why |
| --- | --- | --- |
| Membership, destination, stops, votes, expenses, photos | Postgres tables (`convoys`, `convoy_members`, `convoy_stops`, `convoy_stop_votes`, `convoy_expenses`, `convoy_photos`) with RLS; Realtime postgres_changes while the convoy screen is open | Durable, visible to late joiners, survives app restarts |
| WebRTC signaling, regroup pins, chat, position fallback | Supabase Realtime **Broadcast** on channel `convoy:<id>` | Ephemeral, no rows, no storage |
| Push-to-talk audio, positions every 3–5 s, DJ sync, convoy games | WebRTC full mesh (one `RTCPeerConnection` per other car): one Opus audio track, one data channel `drivalry` | Costs nothing per message; works car to car |
| ICE servers | Metered Open Relay credentials fetched by the phone with the `.env` key, STUN-only fallback | Free 20 GB/month; see §7 |

## 2. Lifecycle

```
create (leader) ─► planning ─► start ─► active ─► end ─► recap (30 days) ─► pruned
   invite link drivalry://join/convoy/<code> or QR; join_convoy(code) RPC
```

- `planning`: destination and stops editable by everyone; no mesh yet.
- `active`: every member joins `convoy:<id>`, tracks presence on it (Realtime presence, the built-in kind), and opens a peer connection to every other present member (see §4). Leaving the screen keeps the mesh alive while the convoy is active and the app is alive; the OS may still kill a backgrounded app, in which case the fallback in §5 covers positions and the member reconnects on resume.
- `end` by the leader (or automatically 2 h after the last position from anyone): members tear down the mesh and each phone builds its recap from what it received.

## 3. Broadcast messages (`convoy:<id>`)

Every broadcast payload is `{ v: 1, type, from: <userId>, t: <ms>, ... }`. Unknown `type` is ignored. Realtime broadcast is best-effort; anything that must survive goes in a table. Every send is wrapped so a dropped socket is logged, never thrown (`safeSend`).

One channel object exists per convoy per app run and is **reference-counted**: the live wiring (positions, regroup, lost sheep) and the radio each `join()` when they start and `leave()` when they stop; the socket opens on the first join and closes on the last leave, so stopping the radio never drops the live positions and vice versa. Provider disposal closes it regardless (`shutdown()`).

| type | fields | notes |
| --- | --- | --- |
| `hello` | `{ caps: ["audio","data"] }` | sent on join and on reconnect; peers answer with offers (§4) |
| `offer` / `answer` | `{ to, sdp }` | WebRTC SDP, unicast by convention (`to` filter) |
| `ice` | `{ to, candidate }` | trickle ICE |
| `bye` | – | leaving the mesh |
| `pos` | `{ lat, lon, speed, heading, acc }` | **fallback only**, every 15 s, when a peer's data channel is down; `t` is the fix time |
| `regroup` | `{ lat, lon, label }` | leader drops a pin; everyone gets a route (Routes API, capped) |
| `chat` | `{ text }` or `{ voice: <storage path> }` | voice notes are small Opus files in bucket `convoy-photos`? No: chat voice notes go over the data channel when connected (§5) and are not persisted. Text chat is broadcast; the screen keeps the last 100 lines locally. |
| `ptt` | `{ on: bool }` | who is talking, for the UI; audio itself is the WebRTC track |
| `dj` | see §6 | track changes and clock sync |

## 4. Mesh

- On `active`, each member fetches ICE servers from the `turn` function (cached 12 h), then for every other member already present: the member with the **lower userId creates the offer**. Newcomers trigger offers from everyone already there via `hello`. This keeps exactly one connection per pair.
- `RTCPeerConnection` config: ICE servers from §7, `sdpSemantics: unified-plan`, `bundlePolicy: max-bundle`. One audio transceiver (`sendrecv`, Opus, `maxaveragebitrate` 24000, DTX on), one data channel `drivalry` (ordered, created by the offerer).
- PTT: the local audio track starts **muted** (`enabled = false`). Holding the button sets `enabled = true` and broadcasts `ptt {on:true}`; release reverses both. Incoming audio plays through the phone's current route (Bluetooth, CarPlay, Android Auto) with music ducking; iOS uses `AVAudioSession` category `.playAndRecord` with `.allowBluetooth`, `.duckOthers`; Android uses `AudioFocusRequest` transient-may-duck and the `microphone` + `mediaPlayback` foreground service types.
- Reconnect: on `iceConnectionState` `failed`/`disconnected` for 10 s, the lower-id side restarts ICE (`restartIce()` + new offer). On `hello` from a peer we already have, the connection is replaced.
- Six cars = five connections per phone, about 25–32 kbps upstream per active talker only (DTX keeps silence near zero).

## 5. Data channel messages (`drivalry`)

JSON lines `{ v: 1, type, t, ... }`, each ≤ 16 KB.

| type | fields | cadence |
| --- | --- | --- |
| `pos` | `{ fixT, lat, lon, speed, heading, acc, battery }` | every 3 s while moving, 10 s while stopped; `t` is the send time and `fixT` the GPS fix time, which is what the receiver stores (the hub keeps the newest `fixT` per car, so a frame delivered twice is a no-op); the sender's phone also upserts its normal `presence` row every 30 s as today |
| `eta` | `{ toStopId?, seconds, estimated }` | whenever recomputed (Routes API with the straight-line fallback), max every 60 s |
| `voice` | `{ id, seq, count, bytes: <base64 AAC chunk, 9 KB raw / 12 KB encoded>, last, mime, durationMs }` | voice-note chat (≤ 20 s, ≤ 120 KB); the receiving phone reassembles by `id` and plays, or reads text aloud |
| `game` | `{ game, event, payload }` | passenger games; driver phones only render audio |
| `dj` | see §6 | |

Positions received are kept on the receiving phone for 30 days (`convoy_tracks` drift table: convoyId, userId, t, lat, lon) and are the recap's source. They never go to the cloud.

## 6. Convoy DJ

- Everyone's Spotify is linked locally (OAuth PKCE with the redirect `drivalry-auth://spotify-callback`, tokens in secure storage; Spotify Web API in Development Mode: the owner allowlists friends' Spotify accounts in the Spotify dashboard, docs/09 §8).
- The DJ (any member, one at a time, claimed with `dj {cmd:"claim"}` over the data channel; the lower userId wins a conflict) holds the queue and sends `dj {cmd:"play", uri, track, positionMs, atT}`: play `uri` at `positionMs` when the receiver's clock reads `atT` (`track` carries name/artist/art for the screen). Clock offset per peer is measured with `dj {cmd:"ping", t}` / `{cmd:"pong", t, rt}` (NTP-style, median of 5) and refreshed every 30 s.
- Each phone calls Spotify `PUT /me/player/play` with `position_ms = positionMs + (now - atT)`; re-sync when drift > 500 ms. Vote-to-skip is `dj {cmd:"skip-vote"}`; the DJ skips at majority.
- Spotify Jam and Apple Music SharePlay stay as deep-link buttons (`spotify:` / `music://`) when installed; no API.

## 7. ICE servers (`supabase/functions/turn`)

- The owner creates a free Metered account (20 GB TURN per month) and puts its domain and API key in `.env` as `METERED_DOMAIN` (`<app>.metered.live`) and `METERED_API_KEY`; the app fetches `https://<domain>/api/v1/turn/credentials?apiKey=…` and caches the list for 12 h. The old open credentials (`openrelayproject`) are gone. The key ships in the binary; the free plan caps the damage of extraction at 20 GB a month of relay. A broker Edge Function that keeps the key server-side was drafted and declined for now; it can be added later without changing the phone's protocol.
- Without the values the mesh uses Google's public STUN only (`stun:stun.l.google.com:19302`), so direct connections still work and relayed ones fail with the honest "direct connection failed" message (docs/03 §10).
- TURN is used only when STUN fails (default ICE behaviour). Measured use goes on the Diagnostics screen (bytes relayed per convoy, from `getStats`).

## 8. Recap

Built on each phone when the convoy ends, from: received positions (30 days), the planned route and stops (tables), members' uploaded trip summaries (`trip_summaries` for the convoy window, visible through `can_view`, which migration 0006 extends to current co-members of a convoy), expenses (totals and the settle-up are per currency; the recap's cost line shows the currency with the largest total), photos. Summaries upload after each member's drive ends, so a recap built within 24 h of the end with no summaries yet is provisional and rebuilt on the next open; after that, or as soon as summaries exist, it is stored as final. Awards: Smoothest (highest average score), Lead Foot (most speeding minutes, dishonourable), Most Stops Proposed, DJ (most tracks played), Navigator (leader). Shareable as an image sequence/video stitched on the phone; no raw positions leave the phone.

## 9. Car screens (Stage 5 hooks)

The convoy state (members, gaps, ETAs, PTT) is a Riverpod state the CarPlay/Android Auto trees read; the PTT button there drives the same mute toggle. Nothing in this protocol depends on a car screen.
