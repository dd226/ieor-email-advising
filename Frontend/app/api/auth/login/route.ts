import { NextRequest, NextResponse } from "next/server";
import { createHmac } from "crypto";

export async function POST(request: NextRequest) {
  const { password } = await request.json();
  const correct = process.env.ADVISOR_PASSWORD;

  if (!correct) {
    return NextResponse.json({ error: "Server misconfigured: ADVISOR_PASSWORD not set" }, { status: 500 });
  }

  if (password !== correct) {
    return NextResponse.json({ error: "Incorrect password" }, { status: 401 });
  }

  const token = createHmac("sha256", correct).update("advisor-session").digest("hex");

  const response = NextResponse.json({ ok: true });
  response.cookies.set("advisor_session", token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "strict",
    maxAge: 60 * 60 * 24 * 7, // 7 days
    path: "/",
  });
  return response;
}
