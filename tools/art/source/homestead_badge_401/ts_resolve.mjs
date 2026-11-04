import { existsSync } from 'node:fs';
export async function resolve(specifier, context, nextResolve) {
  if (specifier.endsWith('.js') && (specifier.startsWith('.') || specifier.startsWith('/'))) {
    const candidate = new URL(specifier.replace(/\.js$/, '.ts'), context.parentURL);
    if (existsSync(candidate)) return nextResolve(candidate.href, context);
  }
  return nextResolve(specifier, context);
}
