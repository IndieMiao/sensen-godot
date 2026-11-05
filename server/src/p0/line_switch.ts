import type { FastifyInstance } from 'fastify';

/** 421 (preview B, 奕星 11-05): the client keeps one connection open for its commands and reads (P0Line). P0_LINE=close
 * answers every reply with `x-p0-line: close`, and each client goes back to a new request each for the rest of its
 * run: the switch on the server, should that line misbehave on some network, with no build. Anything else adds nothing. */
export function registerP0LineSwitch(app: FastifyInstance, value = process.env.P0_LINE): void {
  if (value !== 'close') return;
  app.addHook('onSend', async (_request, reply) => { reply.header('x-p0-line', 'close'); });
}
