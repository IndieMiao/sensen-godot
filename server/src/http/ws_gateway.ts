/**
 * IM 在线通道（D3 WS 网关）。客户端 WsClient 用 WebSocketPeer 直连 /v1/im/ws，握手头带
 * Authorization: Bearer <Firebase ID token>；连上后收到 {type:'hello'}，之后每条 inbox 事件推成
 * {type, seq, ...payload, event_at}——客户端按 seq 更新 last_seq，断线重连后按 last_seq 走
 * GET /v1/im/sync 补拉。这里不做离线队列，也不重发：事件已经在 user_events 里，补拉才是权威。
 *
 * 心跳：服务端每 30 s ping，两个周期没 pong 就断（手机切后台时 TCP 可能半死不活）。
 */
import fastifyWebsocket from '@fastify/websocket';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import type { UserRow } from './accounts.js';
import type { LiveHub, UserEvent } from './im.js';

type Socket = fastifyWebsocket.WebSocket;

export const WS_PATH = '/v1/im/ws';
export const WS_PING_INTERVAL_MS = 30_000;
export const WS_CLOSE_UNAUTHENTICATED = 4401;
export const WS_CLOSE_FORBIDDEN = 4403;
export const WS_CLOSE_NOT_FOUND = 4404;
export const WS_CLOSE_UNAVAILABLE = 4503;

export const eventFrame = (e: UserEvent): string => JSON.stringify({ type: e.type, seq: e.seq, ...e.payload, event_at: e.created_at });

export class SocketHub implements LiveHub {
  private sockets = new Map<string, Set<Socket>>();
  sent = 0;

  add(userId: string, socket: Socket): void {
    let set = this.sockets.get(userId);
    if (!set) { set = new Set(); this.sockets.set(userId, set); }
    set.add(socket);
  }
  remove(userId: string, socket: Socket): void {
    const set = this.sockets.get(userId);
    if (!set) return;
    set.delete(socket);
    if (set.size === 0) this.sockets.delete(userId);
  }
  connections(userId: string): number { return this.sockets.get(userId)?.size ?? 0; }
  online(): number { return this.sockets.size; }
  /** 这个人当前有没有活着的连接——离线推送据此决定发不发（D7）。 */
  has(userId: string): boolean { return (this.sockets.get(userId)?.size ?? 0) > 0; }

  publish(events: UserEvent[]): void {
    for (const e of events) {
      const set = this.sockets.get(e.user_id);
      if (!set) continue;
      const frame = eventFrame(e);
      for (const s of set) {
        if (s.readyState !== s.OPEN) continue;
        try { s.send(frame); this.sent += 1; } catch { /* 对端已断：close 事件会把它摘掉 */ }
      }
    }
  }
  /** 进程关闭：主动断开，客户端会按退避重连到新实例。 */
  closeAll(code = 1001, reason = 'server shutting down'): void {
    for (const set of this.sockets.values()) for (const s of set) { try { s.close(code, reason); } catch { /* ignore */ } }
    this.sockets.clear();
  }
}

export type Authenticate = (req: FastifyRequest) => Promise<{ user: UserRow } | { status: number; body: object }>;

export interface GatewayOptions { now: () => number; pingIntervalMs?: number; path?: string }

export async function registerImGateway(app: FastifyInstance, hub: SocketHub, authenticate: Authenticate, o: GatewayOptions): Promise<void> {
  await app.register(fastifyWebsocket, { options: { maxPayload: 64 * 1024 } });
  const interval = o.pingIntervalMs ?? WS_PING_INTERVAL_MS;
  app.get(o.path ?? WS_PATH, { websocket: true }, async (socket, req) => {
    const c = await authenticate(req);
    if (!('user' in c)) {
      const code = c.status === 401 ? WS_CLOSE_UNAUTHENTICATED : c.status === 403 ? WS_CLOSE_FORBIDDEN : c.status === 404 ? WS_CLOSE_NOT_FOUND : WS_CLOSE_UNAVAILABLE;
      socket.close(code, String((c.body as { code?: string }).code ?? 'ERROR'));
      return;
    }
    const userId = c.user.id;
    hub.add(userId, socket);
    socket.send(JSON.stringify({ type: 'hello', user_id: userId, server_time: o.now() }));
    let alive = true;
    const timer = setInterval(() => {
      if (!alive) { socket.terminate(); return; }
      alive = false;
      try { socket.ping(); } catch { socket.terminate(); }
    }, interval);
    socket.on('pong', () => { alive = true; });
    socket.on('message', (raw: unknown) => {
      // 上行只认应用层 ping（Godot 的 WebSocketPeer 不暴露控制帧）；其他一律忽略，业务都走 REST。
      alive = true;
      let msg: unknown;
      try { msg = JSON.parse(String(raw)); } catch { return; }
      if (typeof msg === 'object' && msg !== null && (msg as { type?: unknown }).type === 'ping')
        socket.send(JSON.stringify({ type: 'pong', server_time: o.now() }));
    });
    socket.on('close', () => { clearInterval(timer); hub.remove(userId, socket); });
    socket.on('error', () => { clearInterval(timer); hub.remove(userId, socket); });
  });
  app.addHook('onClose', async () => hub.closeAll());
}
