# Roadmap: PlanetScale Solutions Engineer

Target role: https://job-boards.greenhouse.io/planetscale/jobs/4052805009
Base salary range: $160,000 - $250,000 USD | Remote - EMEA / NA

Check off items as you complete them. Reorder freely — this is a guide, not a strict sequence.

---

## Stage 1 — Foundations (Database Fundamentals)
- [ ] Relational database theory: normalization, indexing, transactions, ACID, isolation levels
- [ ] SQL fluency: joins, subqueries, window functions, query planning / EXPLAIN
- [ ] Pick MySQL or PostgreSQL as primary focus and install/run it locally
- [ ] Break it and fix it — corrupt data, bad configs, recover from backups
- [ ] Solid Linux/CLI competence
- [ ] Python scripting basics: file parsing, API calls, small CLI tools

## Stage 2 — Production Database Operations (heaviest weight — the "5 years" bar)
- [ ] Replication: primary/replica setup, replication lag, semi-sync vs async
- [ ] High availability: failover mechanics, quorum-based systems
- [ ] Backup/restore strategies (full, incremental, point-in-time recovery)
- [ ] Performance tuning: query optimization, index strategy, slow query logs
- [ ] Connection pooling and caching layers
- [ ] Troubleshooting: locking/deadlocks, disk I/O bottlenecks, memory tuning
- [ ] Monitoring setup: Prometheus/Grafana or equivalent
- [ ] Capacity planning: sizing for workload and growth projections

## Stage 3 — Sharding & Distributed Databases
- [ ] Sharding concepts: horizontal partitioning, shard key design, resharding challenges
- [ ] Vitess architecture: VTGate, VTTablet, topology service
- [ ] Work through PlanetScale's own docs/blog on Vitess
- [ ] Compare Vitess against other distributed DB approaches (CockroachDB, Citus)

## Stage 4 — Cloud & Infrastructure
- [ ] Deep dive on one major cloud provider (AWS recommended)
- [ ] Learn their managed DB services (RDS, Cloud SQL) — the migration source point
- [ ] AWS Database Migration Service (DMS) or logical replication tools (Debezium, pg_logical)
- [ ] Kubernetes fundamentals: pods, deployments, services
- [ ] Terraform basics: provisioning databases/infra declaratively

## Stage 5 — Migration Strategy & Tooling
- [ ] Execute a full migration project (lab or personal): move a DB between hosts/providers with minimal downtime
- [ ] Learn cutover strategies: dual-write, change-data-capture, blue/green
- [ ] Build a migration automation tool (schema diff, data validation, cutover checklist)

## Stage 6 — Customer-Facing & Communication Skills
- [ ] Learn a technical discovery framework (MEDDIC/MEDDPICC)
- [ ] Build a slide deck explaining a technical architecture to a non-technical exec audience
- [ ] Design a proof-of-concept plan with defined success criteria and timeline
- [ ] Write a technical blog post or tutorial
- [ ] Give a talk (meetup, internal, or recorded) on a database topic

## Stage 7 — Portfolio & Proof (ongoing)
- [ ] Written case study of a migration you executed
- [ ] Open-source contribution or active community participation in a DB project
- [ ] GitHub repo showcasing scripting/automation work (Python/Go/JS)
- [ ] Hands-on time with PlanetScale itself (free tier) — run a real workload through it
- [ ] Be able to articulate PlanetScale's pitch and differentiation cold

---

## Notes
-
-
-
