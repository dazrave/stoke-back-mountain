-- Director cam. Loaded by everyone, but dormant until someone types /director,
-- so it does nothing on the players' machines.
DirectorConfig = {
    -- Auto-follow: don't switch target more often than this, or the cut is
    -- seasick. Long enough to let a moment breathe.
    switchIntervalMs = 8000,

    -- How close two players count as "together" when finding the action.
    clusterRadius = 45.0,

    -- Start in auto-follow when you enable it (vs manual cycling).
    startInAuto = true,
}
