/**
 * The site's only code: serves release downloads from R2.
 *
 * Everything else is a static file, answered by the assets layer without this
 * script ever running, since only `/releases/*` is routed here first. The
 * downloads cannot be static files themselves: the zipped app is over the
 * 25 MB limit for one, so it lives in a bucket and is passed through here.
 *
 * Sparkle fetches `/releases/<file>` for an update. Range requests are
 * passed on to R2, so an interrupted download can resume.
 */
const prefix = '/releases/';

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);

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
      return new Response(body, { status: 206, headers });
    }

    headers.set('content-length', String(object.size));
    return new Response(body, { status: 200, headers });
  },
} satisfies ExportedHandler<Env>;

/** The site's own 404 page, with the status to match; served as a page, it would say 200. */
async function notFound(url: URL, env: Env): Promise<Response> {
  const page = await env.ASSETS.fetch(new URL('/404', url));
  return new Response(page.body, { status: 404, headers: page.headers });
}
