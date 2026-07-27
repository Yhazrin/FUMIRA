import { ProxyAgent, fetch as undiciFetch, type RequestInit } from "undici";

/**
 * Outbound vendor HTTP.
 *
 * Domestic (China) access is direct — do **not** set HTTP(S)_PROXY unless you
 * intentionally need one. When MINIMAX_HTTPS_PROXY / HTTPS_PROXY / HTTP_PROXY
 * is set, requests go through that proxy. Never logs credentials or Authorization.
 */
let agent: ProxyAgent | undefined;

function resolveProxyUrl(): string | undefined {
  const raw =
    process.env.MINIMAX_HTTPS_PROXY?.trim() ||
    process.env.HTTPS_PROXY?.trim() ||
    process.env.https_proxy?.trim() ||
    process.env.HTTP_PROXY?.trim() ||
    process.env.http_proxy?.trim() ||
    "";
  return raw.length > 0 ? raw : undefined;
}

function getDispatcher(): ProxyAgent | undefined {
  const proxyUrl = resolveProxyUrl();
  if (!proxyUrl) return undefined;
  if (!agent) {
    agent = new ProxyAgent(proxyUrl);
    console.info(
      JSON.stringify({
        event: "outbound_proxy_enabled",
        proxy: safeProxyDescriptor(proxyUrl),
      })
    );
  }
  return agent;
}

export function safeProxyDescriptor(proxyUrl: string): string {
  try {
    const u = new URL(proxyUrl);
    return `${u.protocol}//${u.host}`;
  } catch {
    return "invalid_proxy_url";
  }
}

export async function outboundFetch(
  url: string,
  init: RequestInit & { signal?: AbortSignal }
): Promise<Response> {
  const dispatcher = init.dispatcher ?? getDispatcher();
  const response = await undiciFetch(url, {
    ...init,
    dispatcher,
  });
  return response as unknown as Response;
}

/** Test helper to reset cached agent after env changes. */
export function resetOutboundProxyAgent(): void {
  agent = undefined;
}
