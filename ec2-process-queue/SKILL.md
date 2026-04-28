---
name: ec2-process-queue
description: Use when the user needs to run a very large list of independent process targets across multiple AWS EC2 instances using a local master queue, remote worker-slot queues, SSM RunCommand, monitoring, retry, rebalance, and safe idle instance termination.
metadata:
  short-description: Distributed EC2 master/worker process queue
---

# EC2 Process Queue

Use this skill to build and operate a disposable EC2 worker fleet for a large queue of independent targets. The user provides the target record format and the one-target process logic; this skill supplies the queue, worker, master refill, monitor, retry, rebalance, and idle termination pattern.

## Inputs To Clarify Or Infer

- AWS profile and region.
- EC2 instance type, instance count, worker slots per instance.
- EBS size, IOPS, throughput, encryption, delete-on-termination.
- Queue record format: one-line string, TSV, or NDJSON.
- Process logic for one target.
- Whether the assistant should execute AWS actions or only provide commands.
- Success verification rule for one target.
- Retry policy and whether failed records should be automatically requeued.

## Required Safety Rules

- Use `flock` for local queue pop, remote `next` pop, and remote `next` append.
- Use atomic writes for `status`: `mktemp "${status_file}.XXXXXX"` then `mv -f`.
- Never put secrets in queue records, status, logs, or command-line arguments.
- Treat `dispatched` as "sent to EC2", not "completed".
- Treat `failed` counts as cumulative; retry success does not remove old failed lines.
- Terminate an EC2 instance only when every slot on it has `NEXT=0` and `phase=idle`.
- Rebalance only remote `next` items that have not started. Do not move active/current targets.
- Process scripts must validate output/result existence before commit/publish/write.

## Workflow

1. Read `references/workflow.md` for the detailed operating model and pitfalls.
2. Treat `skills/ec2-process-queue/scripts/` as immutable templates. Do not edit or execute them directly for a concrete job.
3. Copy scripts from `scripts/` into a job-specific working directory inside the repo.
4. Edit only the copied job scripts.
5. Implement process-specific logic in the copied `process-target.sh`.
6. Create `target_process.queue`, one target record per line.
7. Create EC2 instances and write `process-workers.instances`.
8. Generate `workers` with one line per `instance-id remote-dir`.
9. Deploy copied worker scripts to each EC2 slot using SSM.
10. Start the local master refill loop from the copied scripts.
11. Monitor with the copied `monitor-process-workers.sh`.
12. Rebalance heavy remote `next` queues if needed.
13. Collect failures and retry selected targets.
14. Terminate fully idle instances and update local worker files.

## Bundled Files

- `references/workflow.md`: full Korean operating guide.
- `scripts/process-target.sh`: minimal target processor sample.
- `scripts/process-worker.sh`: remote worker loop.
- `scripts/process-master-refill.sh`: local master refill loop.
- `scripts/monitor-process-workers.sh`: local SSM monitor.
- `scripts/ec2-bootstrap-process-workers.sh`: sample EC2 user-data bootstrap.

When the user asks for a similar distributed queue job, prefer these scripts over rewriting the pattern from scratch.
