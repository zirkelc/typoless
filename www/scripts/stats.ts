/**
 * Reads the download and update-check counters back out of Analytics Engine.
 *
 *     CLOUDFLARE_ACCOUNT_ID=… CLOUDFLARE_API_TOKEN=… pnpm run stats
 *     … pnpm run stats 30        # the last 30 days rather than 7
 *
 * The token needs one permission, Account · Account Analytics · Read, and the
 * account id is on any page of the dashboard. Nothing here writes anything.
 *
 * The rows come from the Worker, which records one per download, per resumed
 * chunk, and per update check. There is no address and nothing identifying in
 * them, so this can only ever answer "how many" and "from roughly where".
 */
import { argv, env, exit } from 'node:process';

const account = env.CLOUDFLARE_ACCOUNT_ID;
const token = env.CLOUDFLARE_API_TOKEN;
const days = Number(argv[2] ?? 7);

if (!account || !token) {
  console.error(
    'Set CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN. See the comment at the top of this file.',
  );
  exit(2);
}

/** Named in wrangler.jsonc. The preview Worker writes to a dataset of its own. */
const dataset = 'typoless_downloads';

/**
 * `blob1` is what happened, `blob2` the file or version it was about, `blob3`
 * the country, and `double1` the bytes served. `_sample_interval` is how many
 * real rows each stored row stands for once Analytics Engine starts sampling,
 * so summing it is the honest count rather than counting rows.
 */
const queries = {
  'downloads by file': `
    SELECT blob2 AS file, SUM(_sample_interval) AS downloads, ROUND(SUM(double1 * _sample_interval) / 1e9, 2) AS gigabytes
    FROM ${dataset}
    WHERE blob1 = 'download' AND timestamp > NOW() - INTERVAL '${days}' DAY
    GROUP BY file ORDER BY downloads DESC`,

  'downloads by day': `
    SELECT toDate(timestamp) AS day, SUM(_sample_interval) AS downloads
    FROM ${dataset}
    WHERE blob1 = 'download' AND timestamp > NOW() - INTERVAL '${days}' DAY
    GROUP BY day ORDER BY day`,

  'downloads by country': `
    SELECT blob3 AS country, SUM(_sample_interval) AS downloads
    FROM ${dataset}
    WHERE blob1 = 'download' AND timestamp > NOW() - INTERVAL '${days}' DAY
    GROUP BY country ORDER BY downloads DESC LIMIT 15`,

  'update checks by version': `
    SELECT blob2 AS version, SUM(_sample_interval) AS checks
    FROM ${dataset}
    WHERE blob1 = 'check' AND timestamp > NOW() - INTERVAL '${days}' DAY
    GROUP BY version ORDER BY checks DESC`,

  'resumed chunks': `
    SELECT SUM(_sample_interval) AS requests, ROUND(SUM(double1 * _sample_interval) / 1e9, 2) AS gigabytes
    FROM ${dataset}
    WHERE blob1 = 'range' AND timestamp > NOW() - INTERVAL '${days}' DAY`,
};

for (const [title, sql] of Object.entries(queries)) {
  const response = await fetch(
    `https://api.cloudflare.com/client/v4/accounts/${account}/analytics_engine/sql`,
    {
      method: 'POST',
      headers: { authorization: `Bearer ${token}` },
      body: sql,
    },
  );

  const text = await response.text();

  console.log(`\n${title} (last ${days} days)`);

  if (!response.ok) {
    console.log(`  failed: ${response.status} ${text}`);
    continue;
  }

  const { data } = JSON.parse(text) as { data: Array<Record<string, unknown>> };

  if (data.length === 0) {
    console.log('  nothing yet');
    continue;
  }

  console.table(data);
}
