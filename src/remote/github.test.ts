import { afterEach, describe, expect, it, vi } from 'vitest';
import { bytesToBase64 } from '../crypto/base64';
import { checkRepo, normalizePath, parseRepo, readFile, RemoteError, writeFile, type GitHubTarget } from './github';

const target: GitHubTarget = { owner: 'paul', repo: 'cipher-penny-data', path: 'dir/vault.cpenny.json', token: 'tok' };

function respond(status: number, body: unknown, headers: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), { status, headers });
}

function mockFetch(...responses: Response[]) {
  const fn = vi.fn<typeof fetch>();
  for (const r of responses) fn.mockResolvedValueOnce(r);
  vi.stubGlobal('fetch', fn);
  return fn;
}

const b64 = (text: string) => bytesToBase64(new TextEncoder().encode(text));

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('input parsing', () => {
  it('parses repo names and URLs', () => {
    expect(parseRepo('paul/data')).toEqual({ owner: 'paul', repo: 'data' });
    expect(parseRepo(' https://github.com/paul/data.git ')).toEqual({ owner: 'paul', repo: 'data' });
    expect(parseRepo('https://github.com/paul/data.git/')).toEqual({ owner: 'paul', repo: 'data' });
    expect(parseRepo('paul')).toBeNull();
    expect(parseRepo('paul/data/extra')).toBeNull();
    expect(parseRepo('pa ul/data')).toBeNull();
  });

  it('normalises paths and rejects traversal', () => {
    expect(normalizePath('/a/b.json')).toBe('a/b.json');
    expect(normalizePath('a/../b.json')).toBeNull();
    expect(normalizePath('a//b.json')).toBeNull();
    expect(normalizePath('')).toBeNull();
  });
});

describe('checkRepo (F-SYNC-1)', () => {
  it('accepts a private repo and sends the token only to api.github.com', async () => {
    const fetchMock = mockFetch(respond(200, { private: true }));
    await checkRepo(target);
    const [url, init] = fetchMock.mock.calls[0]!;
    expect(url).toBe('https://api.github.com/repos/paul/cipher-penny-data');
    expect((init!.headers as Record<string, string>).Authorization).toBe('Bearer tok');
    expect(init!.credentials).toBe('omit');
  });

  it('refuses public repos', async () => {
    mockFetch(respond(200, { private: false }));
    await expect(checkRepo(target)).rejects.toMatchObject({ kind: 'public-repo' });
  });

  it('maps HTTP errors', async () => {
    mockFetch(respond(401, {}), respond(404, {}), respond(403, {}, { 'x-ratelimit-remaining': '0' }));
    await expect(checkRepo(target)).rejects.toMatchObject({ kind: 'auth' });
    await expect(checkRepo(target)).rejects.toMatchObject({ kind: 'not-found' });
    await expect(checkRepo(target)).rejects.toMatchObject({ kind: 'rate-limited' });
  });

  it('reports network failures', async () => {
    vi.stubGlobal('fetch', vi.fn<typeof fetch>().mockRejectedValue(new TypeError('Failed to fetch')));
    await expect(checkRepo(target)).rejects.toMatchObject({ kind: 'network' });
  });
});

describe('readFile / writeFile', () => {
  it('returns null for a missing file', async () => {
    mockFetch(respond(404, {}));
    expect(await readFile(target)).toBeNull();
  });

  it('decodes inline base64 with line breaks', async () => {
    const encoded = b64('{"format":"cipher-penny-vault"}');
    const fetchMock = mockFetch(
      respond(200, { type: 'file', sha: 's1', encoding: 'base64', content: `${encoded.slice(0, 10)}\n${encoded.slice(10)}` }),
    );
    expect(await readFile(target)).toEqual({ sha: 's1', text: '{"format":"cipher-penny-vault"}' });
    expect(fetchMock.mock.calls[0]![0]).toBe('https://api.github.com/repos/paul/cipher-penny-data/contents/dir/vault.cpenny.json');
  });

  it('falls back to the blob API for large files', async () => {
    const fetchMock = mockFetch(
      respond(200, { type: 'file', sha: 's2', encoding: 'none', content: '' }),
      respond(200, { content: b64('big'), encoding: 'base64' }),
    );
    expect(await readFile(target)).toEqual({ sha: 's2', text: 'big' });
    expect(fetchMock.mock.calls[1]![0]).toBe('https://api.github.com/repos/paul/cipher-penny-data/git/blobs/s2');
  });

  it('writes with the previous sha and returns the new one', async () => {
    const fetchMock = mockFetch(respond(200, { content: { sha: 'new' } }));
    expect(await writeFile(target, 'hello', 'old')).toBe('new');
    const body = JSON.parse(fetchMock.mock.calls[0]![1]!.body as string) as Record<string, string>;
    expect(fetchMock.mock.calls[0]![1]!.method).toBe('PUT');
    expect(body.sha).toBe('old');
    expect(body.content).toBe(b64('hello'));
  });

  it('maps stale writes to conflicts', async () => {
    mockFetch(respond(409, { message: 'does not match' }), respond(422, { message: '"sha" wasn\'t supplied.' }), respond(422, { message: 'path invalid' }));
    await expect(writeFile(target, 'x', 'old')).rejects.toMatchObject({ kind: 'conflict' });
    await expect(writeFile(target, 'x', null)).rejects.toMatchObject({ kind: 'conflict' });
    const err = await writeFile(target, 'x', null).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(RemoteError);
    expect(err).toMatchObject({ kind: 'unexpected' });
  });
});
