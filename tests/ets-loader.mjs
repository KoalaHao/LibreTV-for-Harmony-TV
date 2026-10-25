import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';

// Run the real platform-independent ArkTS logic. Media service is replaced only at its kit boundary.
export async function loadEts(relative, replacements = []) {
  let source = await readFile(new URL(`../entry/src/main/ets/${relative}`, import.meta.url), 'utf8');
  for (const [from, to] of replacements) source = source.replace(from, to);
  const js = stripTypeScriptTypes(source, { mode: 'strip', sourceUrl: relative });
  return import(`data:text/javascript;base64,${Buffer.from(js).toString('base64')}`);
}
