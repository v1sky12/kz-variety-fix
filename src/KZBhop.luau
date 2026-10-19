-- Compatibility entry point for existing scripts and the saved fallback motor.
-- KZBlockController owns the shared block rules and per-player bhop state.
return require(script.Parent:WaitForChild('KZBlockController'))
