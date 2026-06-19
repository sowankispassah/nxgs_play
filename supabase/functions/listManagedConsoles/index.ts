import {
  corsHeaders,
  functionError,
  json,
  readBody,
  requireControllerAdmin,
  supabaseAdmin,
} from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const supabase = supabaseAdmin();
    for (const cleanupFunction of [
      "release_expired_reservations_sql",
      "release_expired_sessions_sql",
      "release_expired_manual_console_locks_sql",
    ]) {
      const { error: cleanupError } = await supabase.rpc(cleanupFunction);
      if (cleanupError)
        throw cleanupError;
    }

    const { data: consoles, error } = await supabase
      .from("consoles")
      .select("*")
      .order("added_at", { ascending: false });
    if (error)
      throw error;

    const ids = (consoles ?? []).map((console) => console.id);
    const { data: sessions, error: sessionsError } = ids.length
      ? await supabase
        .from("play_sessions")
        .select("id, console_id, status, started_at, ends_at, grace_ends_at")
        .in("console_id", ids)
        .in("status", ["pending", "active", "extended", "expired"])
        .order("created_at", { ascending: false })
      : { data: [], error: null };
    if (sessionsError)
      throw sessionsError;

    const { data: manualLocks, error: manualLocksError } = ids.length
      ? await supabase
        .from("manual_console_locks")
        .select("id, console_id, lock_type, note, expires_at, created_at, updated_at")
        .in("console_id", ids)
      : { data: [], error: null };
    if (manualLocksError)
      throw manualLocksError;

    const currentSessionByConsole = new Map<string, Record<string, unknown>>();
    const now = Date.now();
    for (const session of sessions ?? []) {
      const graceEndsAt = session.grace_ends_at ? Date.parse(session.grace_ends_at) : 0;
      if (graceEndsAt > 0 && graceEndsAt <= now)
        continue;
      if (!currentSessionByConsole.has(session.console_id))
        currentSessionByConsole.set(session.console_id, session);
    }

    const manualLockByConsole = new Map<string, Record<string, unknown>>();
    for (const manualLock of manualLocks ?? [])
      manualLockByConsole.set(manualLock.console_id, manualLock);

    return json({
      consoles: (consoles ?? []).map((console) => {
        const manualLock = manualLockByConsole.get(console.id) ?? null;
        return {
          ...console,
          current_session: currentSessionByConsole.get(console.id) ?? null,
          manual_lock: manualLock,
          effective_state: manualLock?.lock_type ?? console.state,
        };
      }),
    });
  } catch (error) {
    return functionError(error);
  }
});
