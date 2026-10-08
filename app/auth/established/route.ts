import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

// Kept so in-flight logins started with post_login_redirect_uri=/auth/established
// still land somewhere; middleware.ts now stamps new logins on any page.
export function GET() {
  return new NextResponse(null, { status: 307, headers: { Location: "/", "Cache-Control": "no-store" } });
}
