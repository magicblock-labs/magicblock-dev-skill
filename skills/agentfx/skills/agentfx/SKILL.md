# AgentFX: Autonomous Trading Skill for MagicBlock Engine

AgentFX delivers an advanced, high-performance execution layer designed for autonomous AI agents operating within the Solana ecosystem. This skill is fully optimized for real-time market data ingestion, rapid transaction payload structuring, and strategic bot-controlled trading loops tailored for high-throughput on-chain environments.

## Core Capabilities
- **High-Frequency Ingestion:** Seamless integration with low-latency WebSocket data architecture to process token migrations and pool behaviors in millisecond intervals.
- **State-Driven Trading Loops:** Fully programable execution models utilizing customizable risk controls, including execution entry/exit thresholds, profit realization (TP), and dynamic loss mitigation (SL).
- **Compliant Infrastructure Compatibility:** Architecture engineered with standard validation paths to blend efficiently with secure multi-agent platforms and private network flows.

## Operational Endpoints

### 1. Real-Time Market Telemetry
- **Resource Path:** `/market/data`
- **Protocol:** `GET`
- **Function:** Returns immediate bonding curve metrics and pool data for specific Solana mint structures.

### 2. Payload Construction (Transaction Builder)
- **Resource Path:** `/bot/quote`
- **Protocol:** `POST`
- **Function:** Formulates precise, unsigned transaction payloads mapped directly to programmatic buy/sell parameters.

### 3. Loop Execution Control
- **Resource Path:** `/bot/start`
- **Protocol:** `POST`
- **Function:** Spawns a state-monitored trading cycle governed entirely by predefined user risk bounds.
