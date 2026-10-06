import { headers } from "next/headers";

export type EasyAuthUser = { name: string; email: string };

type Claim = { typ: string; val: string };

const claim = (claims: Claim[], ...types: string[]) =>
  claims.find((c) => types.includes(c.typ))?.val ?? "";

// App Service Easy Auth injects X-MS-CLIENT-PRINCIPAL (base64 JSON) on every
// authenticated request; nothing client-side (no MSAL) is needed.
export async function getUser(): Promise<EasyAuthUser | null> {
  const h = await headers();
  const raw = h.get("x-ms-client-principal");

  if (!raw) return null;

  try {
    const principal = JSON.parse(Buffer.from(raw, "base64").toString("utf8"));
    const claims: Claim[] = principal.claims ?? [];
    const email =
      h.get("x-ms-client-principal-name") ||
      claim(claims, "preferred_username", "upn", "email");

    return { name: claim(claims, "name") || email, email };
  } catch {
    return null;
  }
}
