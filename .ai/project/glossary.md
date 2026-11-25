# Glossary

| Term | Meaning |
|---|---|
| SoC | State of charge, estimated current charge percentage. |
| Design capacity | Nominal original battery capacity reported by hardware. |
| Full-charge capacity | Reported estimated maximum capacity now. |
| Capacity retention | Full-charge capacity divided by design capacity; an estimate, not a diagnosis. |
| IOKit | macOS framework used for battery telemetry. |
| SMC | System Management Controller; model-dependent controls require evidence. |
| BCLM | Investigational charge-limit key, not a universal supported API. |
| Hysteresis | Separate stop and resume thresholds to avoid frequent toggling. |
| Read-only fallback | Monitoring without modifying power-controller state. |
| Recovery | Verified procedure restoring safe charging behavior. |
| Service Recommended | macOS battery condition warning; not equivalent to a specific fault diagnosis. |
