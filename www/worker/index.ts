/**
 * The site's only code: serves release downloads from R2, and counts them.
 *
 * Everything else is a static file, answered by the assets layer without this
 * script ever running, since only the paths in `run_worker_first` are routed
 * here first. The downloads cannot be static files themselves: the zipped app
 * is over the 25 MB limit for one, so it lives in a bucket and is passed
 * through here.
 *
 * Sparkle fetches `/appcast.xml` to look for an update and `/releases/<file>`
 * to fetch one. Range requests are passed on to R2, so an interrupted download
 * can resume.
 */
const prefix = '/releases/';
const feed = '/appcast.xml';

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === feed) {
      record(env, request, { event: 'check', subject: versionOf(request) });
      return env.ASSETS.fetch(request);
    }

    if (!url.pathname.startsWith(prefix)) return env.ASSETS.fetch(request);
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', { status: 405, headers: { allow: 'GET, HEAD' } });
    }

    const key = decodeURIComponent(url.pathname.slice(prefix.length));
    if (!key || key.includes('/')) return notFound(url, env);

    const object =
      request.method === 'HEAD'
        ? await env.RELEASES.head(key)
        : await env.RELEASES.get(key, { range: request.headers, onlyIf: request.headers });

    if (!object) return notFound(url, env);

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('etag', object.httpEtag);
    headers.set('accept-ranges', 'bytes');
    /** A released file never changes under its name; a new version gets a new one. */
    headers.set('cache-control', 'public, max-age=31536000, immutable');

    /** A HEAD, or a conditional request whose condition failed, carries no body. */
    const body = 'body' in object ? (object as R2ObjectBody).body : null;
    if (!body) {
      const status = request.method === 'HEAD' ? 200 : 304;
      if (status === 200) headers.set('content-length', String(object.size));
      return new Response(null, { status, headers });
    }

    const range = object.range as { offset?: number; length?: number } | undefined;
    if (range && request.headers.has('range')) {
      const offset = range.offset ?? 0;
      const length = range.length ?? object.size - offset;
      headers.set('content-range', `bytes ${offset}-${offset + length - 1}/${object.size}`);
      headers.set('content-length', String(length));

      /**
       * Counted apart from a whole download. A resumed or chunked fetch is
       * several requests for one file, so adding them to the same total would
       * report more downloads than there were people.
       */
      record(env, request, { event: 'range', subject: key, bytes: length });
      return new Response(body, { status: 206, headers });
    }

    headers.set('content-length', String(object.size));
    record(env, request, { event: 'download', subject: key, bytes: object.size });

    return new Response(body, { status: 200, headers });
  },
} satisfies ExportedHandler<Env>;

/** The site's own 404 page, with the status to match; served as a page, it would say 200. */
async function notFound(url: URL, env: Env): Promise<Response> {
  const page = await env.ASSETS.fetch(new URL('/404', url));
  return new Response(page.body, { status: 404, headers: page.headers });
}

/**
 * One row per download or update check.
 *
 * Deliberately thin: what happened, which file or version it was about, the
 * country Cloudflare has already worked out from the address, and how many
 * bytes were served. No address is stored, nothing is set in the browser, and
 * nothing identifies a visitor or a copy of the app. What it answers is how
 * many people took the beta and which versions are still checking in, which is
 * the whole reason to have it.
 *
 * Never allowed to break a download: the binding is absent in local
 * development, and a counter that throws would take the file with it.
 */
function record(
  env: Env,
  request: Request,
  event: { event: string; subject?: string; bytes?: number },
): void {
  try {
    env.STATS?.writeDataPoint({
      blobs: [event.event, event.subject ?? 'unknown', (request.cf?.country as string) ?? 'unknown'],
      doubles: [event.bytes ?? 0],
      /** The index decides how rows are sampled when there are many, so it names the thing being counted. */
      indexes: [event.subject ?? event.event],
    });
  } catch {
    /** Counting is never worth a failed request. */
  }
}

/**
 * The version asking for the feed, from the user agent Sparkle sends, such as
 * `Typoless/0.1.0-beta Sparkle/2.8.0`.
 *
 * A browser asking for the same file reports as one, which is worth telling
 * apart: it is a person reading the feed, not a copy of the app checking in.
 */
function versionOf(request: Request): string {
  const agent = request.headers.get('user-agent') ?? '';
  const match = agent.match(/Typoless\/([^\s;]+)/);

  return match?.[1] ?? (agent.includes('Sparkle') ? 'unknown' : 'browser');
}
