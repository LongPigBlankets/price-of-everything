extends Node

## Autoload: TurnProfiler
## Turn-stage duration observability. Times each turn-manager resolution phase
## (excluding DECIDE) and the sub-steps of Production._process_production, and
## logs per-turn timings to the console + a CSV.
##
## STUB — implemented by the timing agent. Owns: turn_profiler.gd,
## turn_manager.gd (phase brackets), production.gd (sub-step brackets).
