"""Loopback-only, authenticated, durable named-job executor (Python stdlib).

Phone disconnects do not own process lifetime. Server restarts mark unfinished
jobs unknown, never replay them. This is not yet paired-device synchronization.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import hmac
import json
import os
from pathlib import Path
import platform
import secrets
import shutil
import sqlite3
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

PROTOCOL = "nexus-remote/1"
MAX_BODY = 16384
MAX_LOG = 1024 * 1024
TERMINAL = {"completed", "failed", "cancelled", "unknown"}


class JobError(Exception):
    def __init__(self, code: int, message: str):
        super().__init__(message)
        self.code = code


class Executor:
    def __init__(self, state: Path, token_file: Path, tasks: dict | None = None):
        self.state = state.resolve()
        self.state.mkdir(parents=True, exist_ok=True)
        self._owner_lock = (self.state / ".executor.lock").open("a+b")
        self._owner_lock.seek(0)
        if os.fstat(self._owner_lock.fileno()).st_size == 0:
            self._owner_lock.write(b"0")
            self._owner_lock.flush()
        self._owner_lock.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(self._owner_lock.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self._owner_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self._owner_lock.close()
            raise ValueError("another executor owns this state directory") from None
        self.token_file = token_file.resolve()
        self.token_file.parent.mkdir(parents=True, exist_ok=True)
        if not self.token_file.exists():
            with self.token_file.open("x", encoding="utf-8") as stream:
                stream.write(secrets.token_urlsafe(48))
            if os.name != "nt":
                self.token_file.chmod(0o600)
        if len(self.token_file.read_text(encoding="utf-8").strip()) < 32:
            raise ValueError("token file must contain at least 32 characters")
        self.db = sqlite3.connect(self.state / "jobs.sqlite3", check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.lock = threading.RLock()
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("""CREATE TABLE IF NOT EXISTS jobs (
            jobId TEXT PRIMARY KEY, requestId TEXT UNIQUE NOT NULL,
            runId TEXT NOT NULL, task TEXT NOT NULL, status TEXT NOT NULL,
            createdAt REAL NOT NULL, updatedAt REAL NOT NULL,
            exitCode INTEGER, reason TEXT)""")
        self.db.execute("UPDATE jobs SET status='unknown', reason=?, updatedAt=? "
                        "WHERE status IN ('queued','running','cancel_requested')",
                        ("executor restarted; inspect effects before any new attempt", time.time()))
        self.db.commit()
        self.tasks = {"diagnostic": {"argv": [sys.executable, "-c",
            "import platform; print('NEXUS remote diagnostic'); print(platform.system())"],
            "cwd": str(self.state), "timeout": 15, "artifacts": []}}
        for name, spec in (tasks or {}).items():
            if name == "diagnostic" or not isinstance(name, str) or not name:
                raise ValueError("invalid task name")
            if not isinstance(spec, dict) or set(spec) - {"argv", "cwd", "timeout", "artifacts"}:
                raise ValueError("invalid task configuration")
            argv = spec.get("argv")
            if not isinstance(argv, list) or not argv or any(not isinstance(s, str) or not s or "\0" in s for s in argv):
                raise ValueError("argv must be a non-empty string array")
            cwd = Path(spec.get("cwd", "")).resolve(strict=True)
            if not cwd.is_dir():
                raise ValueError("task cwd must be an existing directory")
            timeout = spec.get("timeout", 120)
            if type(timeout) is not int or not 1 <= timeout <= 3600:
                raise ValueError("invalid timeout")
            artifacts = spec.get("artifacts", [])
            if not isinstance(artifacts, list) or any(not isinstance(p, str) or Path(p).is_absolute() or ".." in Path(p).parts for p in artifacts):
                raise ValueError("artifacts must be relative paths")
            self.tasks[name] = {"argv": list(argv), "cwd": str(cwd), "timeout": timeout, "artifacts": list(artifacts)}
        self.workers = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.stop = threading.Event()

    def authorized(self, header: str) -> bool:
        # Rotation/removal revokes the old credential on the next request.
        try:
            token = self.token_file.read_text(encoding="utf-8").strip()
        except OSError:
            return False
        return len(token) >= 32 and hmac.compare_digest(header.encode(), ("Bearer " + token).encode())

    def handshake(self) -> dict:
        return {"protocolVersion": PROTOCOL, "arch": platform.machine(),
            "toolchain": [f"python-{platform.python_version()}"],
            "freeBytes": shutil.disk_usage(self.state).free, "maxConcurrency": 1,
            "tasks": sorted(self.tasks), "persistence": "sqlite",
            "restartPolicy": "unfinished_unknown_no_replay"}

    def get(self, job_id: str) -> dict:
        with self.lock:
            row = self.db.execute("SELECT * FROM jobs WHERE jobId=?", (job_id,)).fetchone()
        if row is None:
            raise JobError(404, "job not found")
        return dict(row)

    def list_jobs(self) -> list:
        with self.lock:
            return [dict(row) for row in self.db.execute("SELECT * FROM jobs ORDER BY createdAt DESC LIMIT 100")]

    def submit(self, data: dict) -> tuple[dict, bool]:
        if not isinstance(data, dict) or set(data) != {"requestId", "runId", "task"}:
            raise JobError(400, "expected requestId, runId and named task; remote commands are not accepted")
        if any(not isinstance(data[k], str) or not 1 <= len(data[k]) <= 128 or any(ord(c) < 32 for c in data[k]) for k in data):
            raise JobError(400, "invalid job identifier")
        if data["task"] not in self.tasks:
            raise JobError(400, "task is not configured on this executor")
        with self.lock:
            old = self.db.execute("SELECT * FROM jobs WHERE requestId=?", (data["requestId"],)).fetchone()
            if old:
                if old["runId"] != data["runId"] or old["task"] != data["task"]:
                    raise JobError(409, "idempotency conflict")
                return dict(old), False
            pending = self.db.execute("SELECT COUNT(*) FROM jobs WHERE status IN ('queued','running','cancel_requested')").fetchone()[0]
            if pending >= 32:
                raise JobError(429, "executor queue is full")
            now, job_id = time.time(), uuid.uuid4().hex
            self.db.execute("INSERT INTO jobs VALUES (?,?,?,?,?,?,?,?,?)", (job_id, data["requestId"], data["runId"], data["task"], "queued", now, now, None, None))
            self.db.commit()
            result = self.get(job_id)
            self.workers.submit(self._run, job_id)
        return result, True

    def _update(self, job_id: str, **fields):
        fields["updatedAt"] = time.time()
        with self.lock:
            self.db.execute("UPDATE jobs SET " + ",".join(k + "=?" for k in fields) + " WHERE jobId=?", (*fields.values(), job_id))
            self.db.commit()

    def cancel(self, job_id: str) -> dict:
        with self.lock:
            job = self.get(job_id)
            if job["status"] == "queued":
                self._update(job_id, status="cancelled", reason="cancelled before process start")
            elif job["status"] == "running":
                self._update(job_id, status="cancel_requested", reason="cancellation requested; effects are not reversed")
            return self.get(job_id)

    def _run(self, job_id: str):
        with self.lock:
            job = self.get(job_id)
            if job["status"] != "queued":
                return
            self._update(job_id, status="running")
        spec = self.tasks[job["task"]]
        process = None
        try:
            log_path = self.state / (job_id + ".log")
            with log_path.open("wb") as output:
                process = subprocess.Popen(spec["argv"], cwd=spec["cwd"], stdin=subprocess.DEVNULL,
                    stdout=output, stderr=subprocess.STDOUT, shell=False)
                start = time.monotonic()
                interrupted = None
                while process.poll() is None:
                    if self.stop.is_set() or self.get(job_id)["status"] == "cancel_requested":
                        interrupted = "cancel requested; existing effects and descendant processes require verification"
                    elif time.monotonic() - start > spec["timeout"]:
                        interrupted = "time budget exceeded; inspect effects before retry"
                    elif log_path.stat().st_size > MAX_LOG:
                        interrupted = "log budget exceeded; inspect effects before retry"
                    if interrupted:
                        process.terminate()
                        try:
                            process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=3)
                        break
                    time.sleep(0.05)
            with self.lock:
                # Serialize completion with cancel: a late cancel cannot pretend
                # that already-performed effects were rolled back.
                status = self.get(job_id)["status"]
                if interrupted or status == "cancel_requested":
                    self._update(job_id, status="unknown", exitCode=process.returncode,
                        reason=interrupted or "cancel raced with completion; inspect effects")
                else:
                    if process.returncode == 0:
                        self._snapshot_artifacts(job_id, spec)
                    self._update(job_id, status="completed" if process.returncode == 0 else "failed", exitCode=process.returncode)
        except Exception:
            if process is not None and process.poll() is None:
                process.terminate()
            self._update(job_id, status="unknown" if process else "failed", reason="executor error; inspect local diagnostics")

    def logs(self, job_id: str) -> str:
        self.get(job_id)
        path = self.state / (job_id + ".log")
        if not path.exists():
            return ""
        with path.open("rb") as stream:
            stream.seek(max(0, path.stat().st_size - MAX_LOG))
            return stream.read(MAX_LOG).decode("utf-8", errors="replace")

    def _snapshot_artifacts(self, job_id: str, spec: dict):
        root = Path(spec["cwd"]).resolve()
        target = self.state / (job_id + ".artifacts")
        target.mkdir(exist_ok=True)
        manifest = []
        for index, relative in enumerate(spec["artifacts"]):
            source = (root / relative).resolve()
            if not source.is_relative_to(root) or not source.is_file():
                raise ValueError("artifact missing or outside workspace")
            with source.open("rb") as stream:
                data = stream.read(16 * 1024 * 1024 + 1)
            if len(data) > 16 * 1024 * 1024:
                raise ValueError("artifact budget exceeded")
            (target / str(index)).write_bytes(data)
            manifest.append({"index": index, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
        (target / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    def artifact(self, job_id: str, index: int) -> tuple[bytes, str]:
        job = self.get(job_id)
        if job["status"] != "completed":
            raise JobError(409, "artifacts require a completed job")
        target = self.state / (job_id + ".artifacts")
        manifest = json.loads((target / "manifest.json").read_text(encoding="utf-8"))
        if index < 0 or index >= len(manifest):
            raise JobError(404, "artifact not found")
        data = (target / str(index)).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != manifest[index]["sha256"]:
            raise JobError(409, "artifact integrity mismatch")
        return data, digest

    def close(self):
        with self.lock:
            self.stop.set()
            self.db.execute("UPDATE jobs SET status='cancelled', reason='executor shutdown before process start', updatedAt=? WHERE status='queued'", (time.time(),))
            self.db.commit()
        self.workers.shutdown(wait=True)
        self.db.close()
        self._owner_lock.close()


class Server(ThreadingHTTPServer):
    daemon_threads = True
    def __init__(self, address, executor: Executor):
        if address[0] != "127.0.0.1":
            raise ValueError("only loopback binding is supported")
        self.executor = executor
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    server: Server
    def log_message(self, fmt, *args):
        # Do not echo credentials, requests, job output or workspace paths.
        pass

    def _respond(self, code: int, data, binary=False, digest=None):
        body = data if binary else json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/octet-stream" if binary else "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if digest:
            self.send_header("X-Content-SHA256", digest)
        self.end_headers()
        self.wfile.write(body)

    def _route(self, method: str):
        try:
            if self.headers.get("Origin") or not self.server.executor.authorized(self.headers.get("Authorization", "")):
                raise JobError(401, "authorization required")
            path = urlsplit(self.path)
            if path.query or path.fragment:
                raise JobError(400, "query parameters are not accepted")
            parts = path.path.strip("/").split("/")
            store = self.server.executor
            if method == "GET" and parts == ["handshake"]:
                return self._respond(200, store.handshake())
            if method == "GET" and parts == ["jobs"]:
                return self._respond(200, {"jobs": store.list_jobs()})
            if method == "POST" and parts == ["jobs"]:
                if self.headers.get("Transfer-Encoding"):
                    raise JobError(400, "chunked requests are not accepted")
                length = int(self.headers.get("Content-Length", "0"))
                if not 1 <= length <= MAX_BODY:
                    raise JobError(413, "request body size is invalid")
                self.connection.settimeout(5)
                body = self.rfile.read(length)
                job, created = store.submit(json.loads(body))
                return self._respond(201 if created else 200, job)
            if len(parts) >= 2 and parts[0] == "jobs":
                job_id = parts[1]
                if len(job_id) != 32 or any(c not in "0123456789abcdef" for c in job_id):
                    raise JobError(404, "job not found")
                if method == "GET" and len(parts) == 2:
                    return self._respond(200, store.get(job_id))
                if method == "POST" and parts[2:] == ["cancel"]:
                    return self._respond(200, store.cancel(job_id))
                if method == "GET" and parts[2:] == ["logs"]:
                    return self._respond(200, {"text": store.logs(job_id)})
                if method == "GET" and len(parts) == 4 and parts[2] == "artifacts":
                    data, digest = store.artifact(job_id, int(parts[3]))
                    return self._respond(200, data, binary=True, digest=digest)
            raise JobError(404, "endpoint not found")
        except JobError as error:
            self._respond(error.code, {"error": str(error)})
        except (ValueError, UnicodeError):
            self._respond(400, {"error": "invalid request"})
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            self._respond(500, {"error": "executor error"})

    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", default="local/remote-executor")
    parser.add_argument("--token-file", default="local/remote-executor/token")
    parser.add_argument("--tasks-file", help="trusted host-only JSON named task configuration; never supplied by a remote request")
    parser.add_argument("--port", type=int, default=8767)
    args = parser.parse_args()
    tasks = json.loads(Path(args.tasks_file).read_text(encoding="utf-8")) if args.tasks_file else None
    executor = Executor(Path(args.state_dir), Path(args.token_file), tasks)
    server = Server(("127.0.0.1", args.port), executor)
    print(f"NEXUS executor ready on 127.0.0.1:{server.server_port}; token stored locally, not printed", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        executor.close()


if __name__ == "__main__":
    main()
