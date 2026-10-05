import { base64ToBytes, bytesToBase64 } from '../crypto/base64';

// Talks to the GitHub REST API for sync (F-SYNC). Only ciphertext envelopes are ever sent.

const API = 'https://api.github.com';

export interface GitHubTarget {
  owner: string;
  repo: string;
  /** File path inside the repo, e.g. `vault.cpenny.json`. */
  path: string;
  token: string;
}

export interface RemoteFile {
  /** Git blob sha; required to update the file without clobbering other writers. */
  sha: string;
  text: string;
}

export type RemoteErrorKind =
  | 'network'
  | 'auth'
  | 'forbidden'
  | 'not-found'
  | 'public-repo'
  | 'conflict'
  | 'rate-limited'
  | 'unexpected';

export class RemoteError extends Error {
  constructor(
    readonly kind: RemoteErrorKind,
    message: string,
  ) {
    super(message);
    this.name = 'RemoteError';
  }
}

const NAME = /^[A-Za-z0-9_.-]+$/;

/** Accepts `owner/repo` or a github.com URL. */
export function parseRepo(input: string): { owner: string; repo: string } | null {
  const trimmed = input
    .trim()
    .replace(/^https?:\/\/github\.com\//i, '')
    .replace(/\.git$/i, '')
    .replace(/\/+$/, '');
  const [owner, repo, ...rest] = trimmed.split('/');
  if (!owner || !repo || rest.length > 0 || !NAME.test(owner) || !NAME.test(repo)) return null;
  return { owner, repo };
}

/** Normalises a file path; rejects empty segments and `..`. */
export function normalizePath(input: string): string | null {
  const segments = input.trim().replace(/^\/+/, '').split('/');
  if (segments.some((s) => s === '' || s === '.' || s === '..')) return null;
  return segments.join('/');
}

function repoUrl(t: GitHubTarget): string {
  return `${API}/repos/${encodeURIComponent(t.owner)}/${encodeURIComponent(t.repo)}`;
}

function contentsUrl(t: GitHubTarget): string {
  return `${repoUrl(t)}/contents/${t.path.split('/').map(encodeURIComponent).join('/')}`;
}

async function request(t: GitHubTarget, url: string, init: { method?: string; body?: unknown } = {}): Promise<Response> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    Authorization: `Bearer ${t.token}`,
    'X-GitHub-Api-Version': '2022-11-28',
  };
  if (init.body !== undefined) headers['Content-Type'] = 'application/json';
  try {
    return await fetch(url, {
      method: init.method ?? 'GET',
      headers,
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      cache: 'no-store',
      credentials: 'omit',
      referrerPolicy: 'no-referrer',
    });
  } catch {
    throw new RemoteError('network', '无法连接 GitHub，请检查网络');
  }
}

async function errorMessage(res: Response): Promise<string> {
  try {
    const body = (await res.json()) as { message?: unknown };
    return typeof body.message === 'string' ? body.message : '';
  } catch {
    return '';
  }
}

async function fail(res: Response, notFound: string): Promise<never> {
  if (res.status === 401) throw new RemoteError('auth', 'GitHub 令牌无效或已过期');
  if (res.status === 429 || (res.status === 403 && res.headers.get('x-ratelimit-remaining') === '0')) {
    throw new RemoteError('rate-limited', 'GitHub 请求过于频繁，请稍后再试');
  }
  if (res.status === 403) {
    throw new RemoteError('forbidden', '令牌没有这个仓库的读写权限（需要 Contents: Read and write）');
  }
  if (res.status === 404) throw new RemoteError('not-found', notFound);
  const detail = await errorMessage(res);
  throw new RemoteError('unexpected', `GitHub 返回错误 ${res.status}${detail ? `：${detail}` : ''}`);
}

function decodeText(base64: string): string {
  return new TextDecoder().decode(base64ToBytes(base64.replace(/\s/g, '')));
}

/** F-SYNC-1: the repo must exist, be reachable with the token, and be private. */
export async function checkRepo(t: GitHubTarget): Promise<void> {
  const res = await request(t, repoUrl(t));
  if (!res.ok) await fail(res, '找不到这个仓库，或令牌无权访问它');
  const repo = (await res.json()) as { private?: unknown };
  if (repo.private !== true) {
    throw new RemoteError('public-repo', '这是公开仓库。为了安全，同步只能使用私有仓库');
  }
}

/** Returns null if the file does not exist yet. */
export async function readFile(t: GitHubTarget): Promise<RemoteFile | null> {
  const res = await request(t, contentsUrl(t));
  if (res.status === 404) return null;
  if (!res.ok) await fail(res, '找不到同步文件');
  const file = (await res.json()) as { type?: unknown; sha?: unknown; encoding?: unknown; content?: unknown };
  if (file.type !== 'file' || typeof file.sha !== 'string') {
    throw new RemoteError('unexpected', '同步路径不是一个文件');
  }
  if (file.encoding === 'base64' && typeof file.content === 'string') {
    return { sha: file.sha, text: decodeText(file.content) };
  }
  // Files over 1 MB come back without inline content.
  const blobRes = await request(t, `${repoUrl(t)}/git/blobs/${encodeURIComponent(file.sha)}`);
  if (!blobRes.ok) await fail(blobRes, '找不到同步文件');
  const blob = (await blobRes.json()) as { content?: unknown };
  if (typeof blob.content !== 'string') throw new RemoteError('unexpected', '无法读取同步文件');
  return { sha: file.sha, text: decodeText(blob.content) };
}

/**
 * Creates (`sha` = null) or updates the file. Throws RemoteError('conflict') if someone
 * else changed it since `sha` was read.
 */
export async function writeFile(t: GitHubTarget, text: string, sha: string | null): Promise<string> {
  const res = await request(t, contentsUrl(t), {
    method: 'PUT',
    body: {
      message: `CipherPenny 同步 ${new Date().toISOString()}`,
      content: bytesToBase64(new TextEncoder().encode(text)),
      ...(sha ? { sha } : {}),
    },
  });
  if (res.status === 409) throw new RemoteError('conflict', '远端文件已被其他设备更新');
  if (res.status === 422) {
    // Returned when the file appeared since we read it and no sha was sent.
    const detail = await errorMessage(res);
    if (/sha/i.test(detail)) throw new RemoteError('conflict', '远端文件已被其他设备更新');
    throw new RemoteError('unexpected', `GitHub 拒绝了写入${detail ? `：${detail}` : ''}`);
  }
  if (!res.ok) await fail(res, '找不到这个仓库，或令牌无权写入');
  const body = (await res.json()) as { content?: { sha?: unknown } };
  if (typeof body.content?.sha !== 'string') throw new RemoteError('unexpected', 'GitHub 返回的数据不完整');
  return body.content.sha;
}
