import {
  isValidAutomergeUrl,
  parseAutomergeUrl,
  stringifyAutomergeUrl,
  type AutomergeUrl,
  type DocHandle,
  type Repo,
} from "@automerge/automerge-repo/slim";
import { hasHeads } from "@automerge/automerge/slim";
import { resolvePath } from "@inkandswitch/patchwork-filesystem";

const RESOLVE_TIMEOUT_MS = 20_000;

type ResolveResult = { status: number; mimeType: string; base64: string };

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

function text(status: number, message: string): ResolveResult {
  return {
    status,
    mimeType: "text/plain",
    base64: toBase64(new TextEncoder().encode(message)),
  };
}

// Port of patchwork's waitForHeads (bootloader/automerge-worker.ts), with a
// timeout in place of the handoff AbortSignal.
function waitForHeads(
  handle: DocHandle<unknown>,
  hexHeads: string[],
  timeoutMs: number,
): Promise<boolean> {
  if (hasHeads(handle.doc(), hexHeads)) return Promise.resolve(true);
  return new Promise((resolve) => {
    const cleanup = () => {
      handle.off("heads-changed", check);
      clearTimeout(timer);
    };
    const check = () => {
      if (!hasHeads(handle.doc(), hexHeads)) return;
      cleanup();
      resolve(true);
    };
    const timer = setTimeout(() => {
      cleanup();
      resolve(false);
    }, timeoutMs);
    handle.on("heads-changed", check);
    check();
  });
}

// The JS half of PatchworkSchemeHandler: patchwork's resolveAutomergeUrl with the
// service-worker/SharedWorker handoff collapsed into one native round trip.
// `raw` is the URL path after patchwork://app/ — an encoded automerge: URL first,
// then the file path inside the folder doc. Scheme handlers can't redirect, so
// a headless URL is pinned to current heads and served directly.
export function installResolver(repo: Repo) {
  window.__patchworkResolve = async (raw: string): Promise<ResolveResult> => {
    try {
      const [encoded, ...path] = raw.split("/");
      const maybeAutomergeUrl = decodeURIComponent(encoded) as AutomergeUrl;
      if (!isValidAutomergeUrl(maybeAutomergeUrl)) {
        return text(400, `invalid automerge url: ${maybeAutomergeUrl}`);
      }
      if (path.length && !path[path.length - 1]) path.pop();

      let { heads, hexHeads, documentId } =
        parseAutomergeUrl(maybeAutomergeUrl);
      const baseHandle = await repo.find(stringifyAutomergeUrl({ documentId }));

      if (!heads) {
        heads = baseHandle.heads();
        hexHeads = undefined;
      } else if (
        !(await waitForHeads(baseHandle, hexHeads ?? [], RESOLVE_TIMEOUT_MS))
      ) {
        return text(
          504,
          `heads not found for ${maybeAutomergeUrl} within ${RESOLVE_TIMEOUT_MS}ms`,
        );
      }

      const resolved = await resolvePath(
        repo,
        baseHandle.view(heads),
        path.map(decodeURIComponent),
      );
      if (!resolved) {
        return text(
          404,
          `couldn't resolve ${path.join("/")} in ${maybeAutomergeUrl}`,
        );
      }

      const bytes =
        resolved.content instanceof Uint8Array
          ? resolved.content
          : new TextEncoder().encode(String(resolved.content));
      return { status: 200, mimeType: resolved.type, base64: toBase64(bytes) };
    } catch (error) {
      return text(500, String(error));
    }
  };
}
