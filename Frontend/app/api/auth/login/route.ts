import { NextRequest, NextResponse } from "next/server";

// Use internal localhost URL for server-side calls — avoids nginx loopback
const BACKEND_URL = process.env.BACKEND_INTERNAL_URL ?? "http://localhost:8000";

export async function POST(request: NextRequest) {
  const { password } = await request.json();

  try {
    const res = await fetch(`${BACKEND_URL}/admin/verify-password`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
    });

    if (res.status === 401) {
      return NextResponse.json({ error: "Incorrect password" }, { status: 401 });
    }
    if (!res.ok) {
      return NextResponse.json({ error: "Auth service unavailable" }, { status: 503 });
    }

    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ error: "Auth service unavailable" }, { status: 503 });
  }
}
